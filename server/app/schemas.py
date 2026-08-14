from __future__ import annotations

import math
import re
from datetime import datetime
from typing import Any, Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .constants import (
    CoinClass,
    DatasetSplit,
    ImageSource,
    JobPhase,
    JobStatus,
    ReviewStatus,
)


class APIModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class Annotation(APIModel):
    class_name: CoinClass = Field(alias="class", serialization_alias="class")
    x: Annotated[float, Field(ge=0.0, le=1.0)]
    y: Annotated[float, Field(ge=0.0, le=1.0)]
    width: Annotated[float, Field(gt=0.0, le=1.0)]
    height: Annotated[float, Field(gt=0.0, le=1.0)]
    confidence: Annotated[float | None, Field(ge=0.0, le=1.0)] = None
    needs_review: bool = False

    @model_validator(mode="after")
    def ensure_box_is_inside_image(self) -> "Annotation":
        values = (self.x, self.y, self.width, self.height)
        if not all(math.isfinite(value) for value in values):
            raise ValueError("Bounding box coordinates must be finite")
        epsilon = 1e-9
        if self.x + self.width > 1 + epsilon or self.y + self.height > 1 + epsilon:
            raise ValueError("Bounding box must be fully inside the normalized image")
        return self


class AnnotationUpdate(APIModel):
    annotations: list[Annotation]
    review_status: ReviewStatus = ReviewStatus.REVIEWED


class DatasetImageRead(APIModel):
    id: str
    created_at: datetime
    source: ImageSource
    capture_session_id: str
    review_status: ReviewStatus
    model_version_used_for_pre_annotation: str | None
    split: DatasetSplit
    annotations: list[Annotation]
    image_url: str
    content_type: str
    file_size: int


class DatasetImageList(APIModel):
    items: list[DatasetImageRead]
    total: int
    limit: int
    offset: int


class DatasetStats(APIModel):
    image_count: int
    object_count: int
    class_counts: dict[str, int]
    split_counts: dict[str, int]
    unreviewed_image_count: int
    annotated_image_count: int
    dataset_version: str


class ValidationIssue(APIModel):
    code: str
    message: str
    image_id: str | None = None
    class_name: CoinClass | None = None


class TrainingJobCreate(APIModel):
    training_config: dict[str, Any] = Field(default_factory=dict)
    mock_mode: bool = False


class TrainingJobRead(APIModel):
    id: str
    model_version: str
    dataset_version: str
    dataset_manifest_key: str
    training_config: dict[str, Any]
    mock_mode: bool
    status: JobStatus
    phase: JobPhase
    progress: Annotated[int, Field(ge=0, le=100)]
    validation_errors: list[ValidationIssue]
    error_message: str | None
    worker_id: str | None
    created_at: datetime
    updated_at: datetime
    claimed_at: datetime | None
    started_at: datetime | None
    completed_at: datetime | None
    model_id: str | None


class TrainingJobList(APIModel):
    items: list[TrainingJobRead]
    total: int
    limit: int
    offset: int


class TrainingJobClaim(APIModel):
    worker_id: Annotated[str, Field(min_length=1, max_length=128)]


class TrainingJobUpdate(APIModel):
    status: JobStatus | None = None
    phase: JobPhase | None = None
    progress: Annotated[int | None, Field(ge=0, le=100)] = None
    error_message: Annotated[str | None, Field(max_length=10_000)] = None

    @model_validator(mode="after")
    def ensure_something_changes(self) -> "TrainingJobUpdate":
        if not self.model_fields_set:
            raise ValueError("At least one lifecycle field is required")
        return self


class ModelCreate(APIModel):
    job_id: str
    model_version: str
    dataset_version: str
    training_config: dict[str, Any] = Field(default_factory=dict)
    metrics: dict[str, Any] = Field(default_factory=dict)
    checkpoint_key: str | None = None
    core_ml_key: str
    artifact_prefix: str

    @field_validator("model_version")
    @classmethod
    def validate_model_version(cls, value: str) -> str:
        if not re.fullmatch(r"v[1-9][0-9]*", value):
            raise ValueError("model_version must match v<number>")
        return value


class ModelRead(APIModel):
    id: str
    model_version: str
    created_at: datetime
    dataset_version: str
    training_config: dict[str, Any]
    metrics: dict[str, Any]
    checkpoint_available: bool
    core_ml_available: bool
    job_id: str
    download_url: str
    reports_url: str


class ModelList(APIModel):
    items: list[ModelRead]
    total: int
    limit: int
    offset: int


class InferenceResponse(APIModel):
    model_id: str | None
    model_version: str | None
    annotations: list[Annotation]


ReportCategory = Literal[
    "false_positives", "false_negatives", "low_confidence", "confused_classes"
]


class FailureReportItem(APIModel):
    category: str
    path: str
    content_type: str
    url: str


class FailureReportList(APIModel):
    items: list[FailureReportItem]


class HealthResponse(APIModel):
    status: Literal["ok"] = "ok"
