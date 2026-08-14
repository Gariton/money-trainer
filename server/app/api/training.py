from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Request, Response, status
from fastapi.responses import FileResponse
from sqlalchemy import func, select

from ..constants import JobPhase, JobStatus
from ..db_models import TrainingJob
from ..dependencies import SessionDependency, StorageDependency
from ..schemas import (
    TrainingJobClaim,
    TrainingJobCreate,
    TrainingJobList,
    TrainingJobRead,
    TrainingJobUpdate,
)
from ..services import (
    allocate_model_version,
    apply_job_update,
    build_dataset_manifest,
    current_dataset_version,
    job_read,
    validate_dataset,
)
from ..storage import StorageObjectNotFound


router = APIRouter(prefix="/training/jobs", tags=["training"])


def _get_job_or_404(db: SessionDependency, job_id: str) -> TrainingJob:
    row = db.get(TrainingJob, job_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Training job not found")
    return row


@router.post("", response_model=TrainingJobRead, status_code=status.HTTP_201_CREATED)
def create_training_job(
    request: Request,
    body: TrainingJobCreate,
    db: SessionDependency,
    storage: StorageDependency,
) -> TrainingJobRead:
    issues = validate_dataset(db, storage, request.app.state.settings)
    if issues:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail={
                "code": "dataset_validation_failed",
                "errors": [issue.model_dump(mode="json") for issue in issues],
            },
        )

    model_version, version_number = allocate_model_version(db)
    dataset_version = current_dataset_version(db)
    job_id = str(uuid.uuid4())
    # The training manifest validates that every image path is below its own parent.
    # Keep the immutable snapshot at DATA_ROOT so DATA_ROOT/images remains in scope.
    manifest_key = f"dataset-manifest-{job_id}.json"
    manifest = build_dataset_manifest(
        db, storage, dataset_version=dataset_version
    )
    storage.write_json(manifest_key, manifest)
    row = TrainingJob(
        id=job_id,
        model_version=model_version,
        version_number=version_number,
        dataset_version=dataset_version,
        dataset_manifest_key=manifest_key,
        training_config=body.training_config,
        mock_mode=body.mock_mode,
        status=JobStatus.QUEUED.value,
        phase=JobPhase.PREPARING.value,
        progress=0,
        validation_errors=[],
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception:
        db.rollback()
        storage.delete(manifest_key)
        raise
    return job_read(row)


@router.get("", response_model=TrainingJobList)
def list_training_jobs(
    db: SessionDependency,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    job_status: Annotated[JobStatus | None, Query(alias="status")] = None,
) -> TrainingJobList:
    filters = []
    if job_status is not None:
        filters.append(TrainingJob.status == job_status.value)
    total = db.scalar(select(func.count()).select_from(TrainingJob).where(*filters)) or 0
    rows = list(
        db.scalars(
            select(TrainingJob)
            .where(*filters)
            .order_by(TrainingJob.created_at.desc(), TrainingJob.id.desc())
            .limit(limit)
            .offset(offset)
        )
    )
    return TrainingJobList(
        items=[job_read(row) for row in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.post(
    "/claim",
    response_model=TrainingJobRead,
    responses={status.HTTP_204_NO_CONTENT: {"description": "No queued job"}},
)
def claim_training_job(
    body: TrainingJobClaim,
    db: SessionDependency,
) -> TrainingJobRead | Response:
    row = db.scalar(
        select(TrainingJob)
        .where(TrainingJob.status == JobStatus.QUEUED.value)
        .order_by(TrainingJob.created_at.asc(), TrainingJob.id.asc())
        .with_for_update(skip_locked=True)
        .limit(1)
    )
    if row is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    now = datetime.now(timezone.utc)
    row.status = JobStatus.RUNNING.value
    row.phase = JobPhase.VALIDATING.value
    row.progress = max(row.progress, 5)
    row.worker_id = body.worker_id
    row.claimed_at = now
    row.started_at = row.started_at or now
    row.updated_at = now
    db.commit()
    db.refresh(row)
    return job_read(row)


@router.get("/{job_id}", response_model=TrainingJobRead)
def get_training_job(job_id: str, db: SessionDependency) -> TrainingJobRead:
    return job_read(_get_job_or_404(db, job_id))


@router.get("/{job_id}/manifest", response_class=FileResponse)
def download_job_manifest(
    job_id: str,
    db: SessionDependency,
    storage: StorageDependency,
) -> FileResponse:
    row = _get_job_or_404(db, job_id)
    try:
        path = storage.local_path(row.dataset_manifest_key)
    except StorageObjectNotFound as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Manifest not found") from exc
    return FileResponse(path, media_type="application/json", filename="manifest.json")


@router.patch("/{job_id}", response_model=TrainingJobRead)
def update_training_job(
    job_id: str,
    body: TrainingJobUpdate,
    db: SessionDependency,
) -> TrainingJobRead:
    row = _get_job_or_404(db, job_id)
    if body.status == JobStatus.COMPLETED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Complete a job by registering its artifact with POST /models",
        )
    try:
        apply_job_update(
            row,
            status=body.status,
            phase=body.phase,
            progress=body.progress,
            error_message=body.error_message,
            error_message_was_set="error_message" in body.model_fields_set,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    db.commit()
    db.refresh(row)
    return job_read(row)


@router.post("/{job_id}/start", response_model=TrainingJobRead)
def start_training_job(job_id: str, db: SessionDependency) -> TrainingJobRead:
    row = _get_job_or_404(db, job_id)
    current = JobStatus(row.status)
    if current == JobStatus.QUEUED:
        return job_read(row)
    if current != JobStatus.FAILED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only a queued or failed job can be started",
        )
    # Preserve failed artifacts for debugging and allocate a fresh immutable version
    # for the retry; the training pipeline intentionally refuses to overwrite vN.
    model_version, version_number = allocate_model_version(db)
    row.model_version = model_version
    row.version_number = version_number
    row.status = JobStatus.QUEUED.value
    row.phase = JobPhase.PREPARING.value
    row.progress = 0
    row.error_message = None
    row.worker_id = None
    row.claimed_at = None
    row.started_at = None
    row.completed_at = None
    row.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(row)
    return job_read(row)


@router.delete("/{job_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_training_job(
    job_id: str,
    db: SessionDependency,
    storage: StorageDependency,
) -> Response:
    row = _get_job_or_404(db, job_id)
    if JobStatus(row.status) not in {JobStatus.QUEUED, JobStatus.FAILED}:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Running or completed jobs cannot be deleted",
        )
    manifest_key = row.dataset_manifest_key
    db.delete(row)
    db.commit()
    storage.delete(manifest_key)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
