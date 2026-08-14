from __future__ import annotations

from pathlib import PurePosixPath
from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, HTTPException, Query, status
from fastapi.responses import FileResponse
from sqlalchemy import func, select

from ..constants import JobStatus
from ..db_models import TrainingJob, TrainedModel
from ..dependencies import SessionDependency, StorageDependency
from ..schemas import (
    FailureReportItem,
    FailureReportList,
    ModelCreate,
    ModelList,
    ModelRead,
)
from ..services import apply_job_update, model_read
from ..storage import (
    StorageObjectNotFound,
    UnsafeStorageKey,
    validate_storage_key,
)


router = APIRouter(prefix="/models", tags=["models"])


def _get_model_or_404(db: SessionDependency, model_id: str) -> TrainedModel:
    row = db.get(TrainedModel, model_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Model not found")
    return row


def _ensure_key_is_within_prefix(key: str, prefix: str) -> None:
    key_path = validate_storage_key(key)
    prefix_path = validate_storage_key(prefix, allow_prefix=True)
    try:
        key_path.relative_to(prefix_path)
    except ValueError as exc:
        raise UnsafeStorageKey("Artifact key must be inside artifact_prefix") from exc


@router.post("", response_model=ModelRead, status_code=status.HTTP_201_CREATED)
def register_model(
    body: ModelCreate,
    db: SessionDependency,
    storage: StorageDependency,
) -> ModelRead:
    job = db.get(TrainingJob, body.job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Training job not found")
    if job.model is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Training job already has a registered model",
        )
    if JobStatus(job.status) != JobStatus.RUNNING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Model can only be registered for a running training job",
        )
    if body.model_version != job.model_version or body.dataset_version != job.dataset_version:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Model and training job versions do not match",
        )
    try:
        validate_storage_key(body.artifact_prefix, allow_prefix=True)
        _ensure_key_is_within_prefix(body.core_ml_key, body.artifact_prefix)
        if body.checkpoint_key:
            _ensure_key_is_within_prefix(body.checkpoint_key, body.artifact_prefix)
    except UnsafeStorageKey as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    if not storage.exists(body.core_ml_key):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Core ML artifact does not exist",
        )
    if body.checkpoint_key and not storage.exists(body.checkpoint_key):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Checkpoint artifact does not exist",
        )

    model = TrainedModel(
        model_version=body.model_version,
        version_number=job.version_number,
        dataset_version=body.dataset_version,
        training_config=body.training_config,
        metrics=body.metrics,
        checkpoint_key=body.checkpoint_key,
        core_ml_key=body.core_ml_key,
        artifact_prefix=body.artifact_prefix.rstrip("/"),
        job=job,
    )
    apply_job_update(
        job,
        status=JobStatus.COMPLETED,
        phase=None,
        progress=100,
        error_message=None,
        error_message_was_set=False,
    )
    db.add(model)
    db.commit()
    db.refresh(model)
    return model_read(model, storage)


@router.get("", response_model=ModelList)
def list_models(
    db: SessionDependency,
    storage: StorageDependency,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> ModelList:
    total = db.scalar(select(func.count()).select_from(TrainedModel)) or 0
    rows = list(
        db.scalars(
            select(TrainedModel)
            .order_by(TrainedModel.version_number.desc())
            .limit(limit)
            .offset(offset)
        )
    )
    return ModelList(
        items=[model_read(row, storage) for row in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/latest", response_model=ModelRead)
def get_latest_model(
    db: SessionDependency, storage: StorageDependency
) -> ModelRead:
    row = db.scalar(
        select(TrainedModel).order_by(TrainedModel.version_number.desc()).limit(1)
    )
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No model is available")
    return model_read(row, storage)


@router.get("/{model_id}", response_model=ModelRead)
def get_model(
    model_id: str, db: SessionDependency, storage: StorageDependency
) -> ModelRead:
    return model_read(_get_model_or_404(db, model_id), storage)


@router.get("/{model_id}/download", response_class=FileResponse)
def download_model(
    model_id: str, db: SessionDependency, storage: StorageDependency
) -> FileResponse:
    row = _get_model_or_404(db, model_id)
    try:
        path = storage.local_path(row.core_ml_key)
    except StorageObjectNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Core ML artifact not found"
        ) from exc
    return FileResponse(
        path,
        media_type="application/zip",
        filename=f"MoneyDetector-{row.model_version}.mlpackage.zip",
    )


@router.get("/{model_id}/reports", response_model=FailureReportList)
def list_failure_reports(
    model_id: str, db: SessionDependency, storage: StorageDependency
) -> FailureReportList:
    row = _get_model_or_404(db, model_id)
    report_prefix = f"{row.artifact_prefix}/reports"
    items: list[FailureReportItem] = []
    for key in storage.list_keys(report_prefix):
        relative = PurePosixPath(key).relative_to(PurePosixPath(report_prefix)).as_posix()
        first_part = PurePosixPath(relative).parts[0] if relative else "other"
        items.append(
            FailureReportItem(
                category=first_part.replace("-", "_"),
                path=relative,
                content_type=storage.content_type(key),
                url=f"/models/{row.id}/reports/{quote(relative, safe='/')}",
            )
        )
    return FailureReportList(items=items)


@router.get("/{model_id}/reports/{report_path:path}", response_class=FileResponse)
def download_failure_report(
    model_id: str,
    report_path: str,
    db: SessionDependency,
    storage: StorageDependency,
) -> FileResponse:
    row = _get_model_or_404(db, model_id)
    try:
        safe_relative = validate_storage_key(report_path).as_posix()
        key = f"{row.artifact_prefix}/reports/{safe_relative}"
        _ensure_key_is_within_prefix(key, f"{row.artifact_prefix}/reports")
        path = storage.local_path(key)
    except UnsafeStorageKey as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except StorageObjectNotFound as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found") from exc
    return FileResponse(path, media_type=storage.content_type(key), filename=path.name)
