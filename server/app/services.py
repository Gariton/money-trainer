from __future__ import annotations

import hashlib
import uuid
from collections import Counter
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .config import Settings
from .constants import (
    COIN_CLASSES,
    JOB_PHASE_ORDER,
    DatasetSplit,
    JobPhase,
    JobStatus,
    ReviewStatus,
)
from .db_models import DatasetImage, SystemState, TrainingJob, TrainedModel
from .schemas import (
    Annotation,
    DatasetImageRead,
    DatasetStats,
    ModelRead,
    TrainingJobRead,
    ValidationIssue,
)
from .storage import ObjectStorage


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(value: datetime | None) -> datetime | None:
    """Normalize SQLite's naive DateTime values to the UTC API contract."""
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def assign_capture_session_split(
    capture_session_id: str, settings: Settings
) -> DatasetSplit:
    digest = hashlib.sha256(capture_session_id.encode("utf-8")).digest()
    point = int.from_bytes(digest[:8], "big") / 2**64
    if point < settings.split_train:
        return DatasetSplit.TRAIN
    if point < settings.split_train + settings.split_validation:
        return DatasetSplit.VALIDATION
    return DatasetSplit.TEST


def split_for_session(
    db: Session, capture_session_id: str, settings: Settings
) -> DatasetSplit:
    existing = db.scalar(
        select(DatasetImage.split)
        .where(DatasetImage.capture_session_id == capture_session_id)
        .limit(1)
    )
    if existing is not None:
        return DatasetSplit(existing)
    return assign_capture_session_split(capture_session_id, settings)


def annotations_to_json(annotations: list[Annotation]) -> list[dict[str, Any]]:
    return [
        annotation.model_dump(by_alias=True, mode="json", exclude_none=True)
        for annotation in annotations
    ]


def image_read(image: DatasetImage) -> DatasetImageRead:
    return DatasetImageRead(
        id=image.id,
        created_at=as_utc(image.created_at),
        source=image.source,
        capture_session_id=image.capture_session_id,
        review_status=image.review_status,
        model_version_used_for_pre_annotation=image.model_version_used_for_pre_annotation,
        split=image.split,
        annotations=[Annotation.model_validate(item) for item in image.annotations_json],
        image_url=f"/datasets/images/{image.id}/file",
        content_type=image.content_type,
        file_size=image.file_size,
    )


def model_read(model: TrainedModel, storage: ObjectStorage) -> ModelRead:
    return ModelRead(
        id=model.id,
        model_version=model.model_version,
        created_at=as_utc(model.created_at),
        dataset_version=model.dataset_version,
        training_config=model.training_config,
        metrics=model.metrics,
        checkpoint_available=bool(
            model.checkpoint_key and storage.exists(model.checkpoint_key)
        ),
        core_ml_available=storage.exists(model.core_ml_key),
        job_id=model.job_id,
        download_url=f"/models/{model.id}/download",
        reports_url=f"/models/{model.id}/reports",
    )


def job_read(job: TrainingJob) -> TrainingJobRead:
    return TrainingJobRead(
        id=job.id,
        model_version=job.model_version,
        dataset_version=job.dataset_version,
        dataset_manifest_key=job.dataset_manifest_key,
        training_config=job.training_config,
        mock_mode=job.mock_mode,
        status=job.status,
        phase=job.phase,
        progress=job.progress,
        validation_errors=[
            ValidationIssue.model_validate(issue) for issue in job.validation_errors
        ],
        error_message=job.error_message,
        worker_id=job.worker_id,
        created_at=as_utc(job.created_at),
        updated_at=as_utc(job.updated_at),
        claimed_at=as_utc(job.claimed_at),
        started_at=as_utc(job.started_at),
        completed_at=as_utc(job.completed_at),
        model_id=job.model.id if job.model is not None else None,
    )


def ensure_system_state(db: Session) -> None:
    defaults = {"dataset_revision": "0", "model_version_counter": "0"}
    changed = False
    for key, value in defaults.items():
        if db.get(SystemState, key) is None:
            db.add(SystemState(key=key, value=value))
            changed = True
    if changed:
        db.commit()


def _counter_row(db: Session, key: str) -> SystemState:
    row = db.scalar(
        select(SystemState).where(SystemState.key == key).with_for_update()
    )
    if row is None:
        row = SystemState(key=key, value="0")
        db.add(row)
        db.flush()
    return row


def bump_dataset_revision(db: Session) -> int:
    row = _counter_row(db, "dataset_revision")
    revision = int(row.value) + 1
    row.value = str(revision)
    db.flush()
    return revision


def current_dataset_version(db: Session) -> str:
    row = db.get(SystemState, "dataset_revision")
    return f"dataset-v{int(row.value) if row else 0}"


def allocate_model_version(db: Session) -> tuple[str, int]:
    row = _counter_row(db, "model_version_counter")
    number = int(row.value) + 1
    row.value = str(number)
    db.flush()
    return f"v{number}", number


def dataset_stats(db: Session) -> DatasetStats:
    images = list(db.scalars(select(DatasetImage)))
    class_counts: Counter[str] = Counter()
    split_counts: Counter[str] = Counter()
    object_count = 0
    unreviewed_count = 0
    annotated_count = 0
    for image in images:
        split_counts[image.split] += 1
        if image.review_status != ReviewStatus.REVIEWED.value:
            unreviewed_count += 1
        if image.annotations_json:
            annotated_count += 1
        object_count += len(image.annotations_json)
        class_counts.update(item["class"] for item in image.annotations_json)
    return DatasetStats(
        image_count=len(images),
        object_count=object_count,
        class_counts={name: class_counts[name] for name in COIN_CLASSES},
        split_counts={name.value: split_counts[name.value] for name in DatasetSplit},
        unreviewed_image_count=unreviewed_count,
        annotated_image_count=annotated_count,
        dataset_version=current_dataset_version(db),
    )


def validate_dataset(
    db: Session, storage: ObjectStorage, settings: Settings
) -> list[ValidationIssue]:
    images = list(db.scalars(select(DatasetImage).order_by(DatasetImage.created_at)))
    issues: list[ValidationIssue] = []
    if not images:
        return [
            ValidationIssue(
                code="empty_dataset",
                message="Dataset must contain at least one image before training",
            )
        ]
    object_count = 0
    image_counts: Counter[str] = Counter()
    instance_counts: Counter[str] = Counter()
    class_sessions: dict[str, set[str]] = {
        class_name: set() for class_name in COIN_CLASSES
    }
    sessions: dict[str, set[str]] = {}
    for image in images:
        object_count += len(image.annotations_json)
        sessions.setdefault(image.capture_session_id, set()).add(image.split)
        if image.review_status != ReviewStatus.REVIEWED.value:
            issues.append(
                ValidationIssue(
                    code="image_not_reviewed",
                    message="Every dataset image must be reviewed before training",
                    image_id=image.id,
                )
            )
        if not storage.exists(image.storage_key):
            issues.append(
                ValidationIssue(
                    code="image_file_missing",
                    message="Stored image file is missing",
                    image_id=image.id,
                )
            )
        # Revalidate legacy/externally-imported rows at the job boundary.
        image_classes: set[str] = set()
        for raw_annotation in image.annotations_json:
            try:
                annotation = Annotation.model_validate(raw_annotation)
                image_classes.add(annotation.class_name.value)
                instance_counts[annotation.class_name.value] += 1
            except ValueError:
                issues.append(
                    ValidationIssue(
                        code="invalid_annotation",
                        message="Bounding box is invalid or outside the image",
                        image_id=image.id,
                    )
                )
        image_counts.update(image_classes)
        for class_name in image_classes:
            class_sessions[class_name].add(image.capture_session_id)
    if object_count == 0:
        issues.append(
            ValidationIssue(
                code="empty_annotations",
                message="Dataset must contain at least one bounding box before training",
            )
        )
    for capture_session_id, splits in sessions.items():
        if len(splits) > 1:
            issues.append(
                ValidationIssue(
                    code="capture_session_leakage",
                    message=(
                        f"Capture session {capture_session_id!r} appears in multiple splits"
                    ),
                )
            )
    active_splits = sum(
        ratio > 0
        for ratio in (
            settings.split_train,
            settings.split_validation,
            settings.split_test,
        )
    )
    if len(sessions) < active_splits:
        issues.append(
            ValidationIssue(
                code="insufficient_capture_sessions",
                message=(
                    f"Dataset has {len(sessions)} capture session(s); at least "
                    f"{active_splits} are required for active splits"
                ),
            )
        )
    for class_name in COIN_CLASSES:
        if image_counts[class_name] == 0:
            issues.append(
                ValidationIssue(
                    code="insufficient_class_images",
                    message=f"{class_name} must appear in at least one image",
                    class_name=class_name,
                )
            )
        if instance_counts[class_name] == 0:
            issues.append(
                ValidationIssue(
                    code="insufficient_class_instances",
                    message=f"{class_name} must have at least one bounding box",
                    class_name=class_name,
                )
            )
        if len(class_sessions[class_name]) < active_splits:
            issues.append(
                ValidationIssue(
                    code="insufficient_class_capture_sessions",
                    message=(
                        f"{class_name} appears in {len(class_sessions[class_name])} "
                        f"capture session(s); at least {active_splits} are required "
                        "to populate all active splits"
                    ),
                    class_name=class_name,
                )
            )
    return issues


def build_dataset_manifest(
    db: Session,
    storage: ObjectStorage,
    *,
    dataset_version: str,
) -> dict[str, Any]:
    images = list(db.scalars(select(DatasetImage).order_by(DatasetImage.created_at)))
    return {
        "datasetVersion": dataset_version,
        "images": [
            {
                "id": image.id,
                "image": image.storage_key,
                "image_path": str(storage.local_path(image.storage_key)),
                "captureSessionId": image.capture_session_id,
                "reviewStatus": image.review_status,
                "source": image.source,
                "split": image.split,
                "annotations": image.annotations_json,
            }
            for image in images
        ],
    }


def apply_job_update(
    job: TrainingJob,
    *,
    status: JobStatus | None,
    phase: JobPhase | None,
    progress: int | None,
    error_message: str | None,
    error_message_was_set: bool,
) -> None:
    current_status = JobStatus(job.status)
    target_status = status or current_status
    allowed = {
        JobStatus.QUEUED: {JobStatus.QUEUED, JobStatus.RUNNING, JobStatus.FAILED},
        JobStatus.RUNNING: {
            JobStatus.RUNNING,
            JobStatus.COMPLETED,
            JobStatus.FAILED,
        },
        JobStatus.COMPLETED: {JobStatus.COMPLETED},
        JobStatus.FAILED: {JobStatus.FAILED},
    }
    if target_status not in allowed[current_status]:
        raise ValueError(
            f"Invalid training job transition: {current_status.value} -> {target_status.value}"
        )

    target_phase = phase or JobPhase(job.phase)
    if current_status == JobStatus.RUNNING and target_status == JobStatus.RUNNING:
        current_phase = JobPhase(job.phase)
        if JOB_PHASE_ORDER[target_phase] < JOB_PHASE_ORDER[current_phase]:
            raise ValueError("Training phase cannot move backwards")
    if target_status == JobStatus.COMPLETED:
        target_phase = JobPhase.COMPLETED
        progress = 100
    elif target_status == JobStatus.FAILED:
        target_phase = JobPhase.FAILED
    elif target_status == JobStatus.RUNNING and target_phase in {
        JobPhase.PREPARING,
        JobPhase.COMPLETED,
        JobPhase.FAILED,
    }:
        raise ValueError("Running jobs require an active worker phase")

    if progress is not None and target_status == JobStatus.RUNNING and progress < job.progress:
        raise ValueError("Training progress cannot decrease")

    now = utc_now()
    if current_status == JobStatus.QUEUED and target_status == JobStatus.RUNNING:
        job.started_at = job.started_at or now
    if target_status in {JobStatus.COMPLETED, JobStatus.FAILED}:
        job.completed_at = now
    job.status = target_status.value
    job.phase = target_phase.value
    if progress is not None:
        job.progress = progress
    if error_message_was_set:
        job.error_message = error_message
    job.updated_at = now
