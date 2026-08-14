from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .constants import JobPhase, JobStatus, ReviewStatus
from .database import Base


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def uuid_string() -> str:
    return str(uuid.uuid4())


class DatasetImage(Base):
    __tablename__ = "dataset_images"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_string)
    storage_key: Mapped[str] = mapped_column(String(512), unique=True, nullable=False)
    original_filename: Mapped[str | None] = mapped_column(String(255))
    content_type: Mapped[str] = mapped_column(String(64), nullable=False)
    file_size: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False, index=True
    )
    annotations_json: Mapped[list[dict[str, Any]]] = mapped_column(
        "annotations", JSON, default=list, nullable=False
    )
    source: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    capture_session_id: Mapped[str] = mapped_column(
        String(128), nullable=False, index=True
    )
    review_status: Mapped[str] = mapped_column(
        String(32), default=ReviewStatus.UNREVIEWED.value, nullable=False, index=True
    )
    model_version_used_for_pre_annotation: Mapped[str | None] = mapped_column(
        String(64)
    )
    split: Mapped[str] = mapped_column(String(16), nullable=False, index=True)

    __table_args__ = (
        Index("ix_dataset_images_capture_session_split", "capture_session_id", "split"),
    )


class TrainingJob(Base):
    __tablename__ = "training_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_string)
    model_version: Mapped[str] = mapped_column(String(32), unique=True, nullable=False)
    version_number: Mapped[int] = mapped_column(Integer, unique=True, nullable=False)
    dataset_version: Mapped[str] = mapped_column(String(64), nullable=False)
    dataset_manifest_key: Mapped[str] = mapped_column(String(512), nullable=False)
    training_config: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    mock_mode: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    status: Mapped[str] = mapped_column(
        String(24), default=JobStatus.QUEUED.value, nullable=False, index=True
    )
    phase: Mapped[str] = mapped_column(
        String(40), default=JobPhase.PREPARING.value, nullable=False
    )
    progress: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    validation_errors: Mapped[list[dict[str, Any]]] = mapped_column(
        JSON, default=list, nullable=False
    )
    error_message: Mapped[str | None] = mapped_column(Text)
    worker_id: Mapped[str | None] = mapped_column(String(128), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now, nullable=False
    )
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    model: Mapped["TrainedModel | None"] = relationship(
        back_populates="job", uselist=False
    )


class TrainedModel(Base):
    __tablename__ = "trained_models"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uuid_string)
    model_version: Mapped[str] = mapped_column(String(32), unique=True, nullable=False)
    version_number: Mapped[int] = mapped_column(Integer, unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, nullable=False, index=True
    )
    dataset_version: Mapped[str] = mapped_column(String(64), nullable=False)
    training_config: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    metrics: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    checkpoint_key: Mapped[str | None] = mapped_column(String(512))
    core_ml_key: Mapped[str] = mapped_column(String(512), nullable=False)
    artifact_prefix: Mapped[str] = mapped_column(String(512), nullable=False)
    job_id: Mapped[str] = mapped_column(
        ForeignKey("training_jobs.id", ondelete="RESTRICT"), unique=True, nullable=False
    )

    job: Mapped[TrainingJob] = relationship(back_populates="model")


class SystemState(Base):
    __tablename__ = "system_state"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(String(255), nullable=False)
