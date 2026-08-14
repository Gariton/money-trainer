"""Dataset and grouped-split validation."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import math
from pathlib import Path
from typing import TYPE_CHECKING, Any, Iterable

from .config import AppConfig, DatasetConfig
from .constants import COIN_CLASSES
from .dataset import DatasetManifest

if TYPE_CHECKING:
    from .split import DatasetSplit


SUPPORTED_IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".bmp",
    ".tif",
    ".tiff",
    ".webp",
}
REVIEWED_STATUSES = {"reviewed", "confirmed", "approved"}


@dataclass(frozen=True, slots=True)
class ValidationIssue:
    code: str
    message: str
    severity: str = "error"
    image_id: str | None = None
    class_name: str | None = None
    split: str | None = None
    annotation_index: int | None = None

    def to_dict(self) -> dict[str, Any]:
        return {key: value for key, value in asdict(self).items() if value is not None}


@dataclass(frozen=True, slots=True)
class ValidationReport:
    issues: tuple[ValidationIssue, ...] = ()

    @property
    def is_valid(self) -> bool:
        return not any(issue.severity == "error" for issue in self.issues)

    @property
    def errors(self) -> tuple[ValidationIssue, ...]:
        return tuple(issue for issue in self.issues if issue.severity == "error")

    @property
    def warnings(self) -> tuple[ValidationIssue, ...]:
        return tuple(issue for issue in self.issues if issue.severity == "warning")

    def raise_if_invalid(self) -> None:
        if not self.is_valid:
            raise DatasetValidationError(self)

    def to_dict(self) -> dict[str, Any]:
        return {
            "valid": self.is_valid,
            "errorCount": len(self.errors),
            "warningCount": len(self.warnings),
            "issues": [issue.to_dict() for issue in self.issues],
        }


class DatasetValidationError(ValueError):
    def __init__(self, report: ValidationReport):
        self.report = report
        preview = "; ".join(issue.message for issue in report.errors[:3])
        remaining = len(report.errors) - 3
        if remaining > 0:
            preview += f"; and {remaining} more error(s)"
        super().__init__(preview or "dataset validation failed")


def validate_dataset(
    manifest: DatasetManifest,
    config: AppConfig | DatasetConfig,
    *,
    classes: Iterable[str] = COIN_CLASSES,
) -> ValidationReport:
    dataset_config = config.dataset if isinstance(config, AppConfig) else config
    class_names = tuple(classes)
    allowed_classes = set(class_names)
    issues: list[ValidationIssue] = []
    if not manifest.images:
        issues.append(ValidationIssue("manifest_empty", "Dataset contains no images"))
        return ValidationReport(tuple(issues))

    seen_ids: set[str] = set()
    root = manifest.root_dir.resolve()
    for image in manifest.images:
        if not image.id.strip():
            issues.append(ValidationIssue("missing_image_id", "An image has an empty id"))
        elif image.id in seen_ids:
            issues.append(
                ValidationIssue(
                    "duplicate_image_id",
                    f"Duplicate image id: {image.id}",
                    image_id=image.id,
                )
            )
        seen_ids.add(image.id)
        if not image.capture_session_id.strip():
            issues.append(
                ValidationIssue(
                    "missing_capture_session_id",
                    "captureSessionId is required",
                    image_id=image.id,
                )
            )
        try:
            image.image_path.relative_to(root)
        except ValueError:
            issues.append(
                ValidationIssue(
                    "image_path_outside_dataset",
                    "Image path must stay inside the dataset directory",
                    image_id=image.id,
                )
            )
        if not image.image_path.exists():
            issues.append(
                ValidationIssue(
                    "image_not_found",
                    f"Image file does not exist: {image.declared_image_path}",
                    image_id=image.id,
                )
            )
        elif not image.image_path.is_file():
            issues.append(
                ValidationIssue(
                    "image_not_file",
                    f"Image path is not a file: {image.declared_image_path}",
                    image_id=image.id,
                )
            )
        if image.image_path.suffix.lower() not in SUPPORTED_IMAGE_EXTENSIONS:
            issues.append(
                ValidationIssue(
                    "unsupported_image_type",
                    f"Unsupported image extension: {image.image_path.suffix or '(none)'}",
                    image_id=image.id,
                )
            )
        if dataset_config.require_reviewed and image.review_status.lower() not in REVIEWED_STATUSES:
            issues.append(
                ValidationIssue(
                    "image_not_reviewed",
                    f"Image '{image.id}' has not been reviewed",
                    image_id=image.id,
                )
            )
        for annotation_index, annotation in enumerate(image.annotations):
            context = {
                "image_id": image.id,
                "class_name": annotation.class_name,
                "annotation_index": annotation_index,
            }
            if annotation.class_name not in allowed_classes:
                issues.append(
                    ValidationIssue(
                        "unknown_class",
                        f"Unknown class '{annotation.class_name}'",
                        **context,
                    )
                )
            if annotation.confidence is not None and (
                not math.isfinite(annotation.confidence)
                or annotation.confidence < 0
                or annotation.confidence > 1
            ):
                issues.append(
                    ValidationIssue(
                        "confidence_out_of_range",
                        "Annotation confidence must be finite and between 0 and 1",
                        **context,
                    )
                )
            coordinates = (
                annotation.x,
                annotation.y,
                annotation.width,
                annotation.height,
            )
            if not all(math.isfinite(value) for value in coordinates):
                issues.append(
                    ValidationIssue(
                        "bbox_not_finite",
                        "Bounding box values must be finite",
                        **context,
                    )
                )
                continue
            if annotation.width <= 0 or annotation.height <= 0:
                issues.append(
                    ValidationIssue(
                        "bbox_invalid_size",
                        "Bounding box width and height must be greater than zero",
                        **context,
                    )
                )
            if (
                annotation.x < 0
                or annotation.y < 0
                or annotation.x + annotation.width > 1
                or annotation.y + annotation.height > 1
            ):
                issues.append(
                    ValidationIssue(
                        "bbox_out_of_bounds",
                        "Bounding box extends outside normalized image bounds",
                        **context,
                    )
                )

    image_counts = manifest.image_counts_by_class()
    instance_counts = manifest.class_instance_counts()
    for class_name in class_names:
        image_count = image_counts.get(class_name, 0)
        if image_count < dataset_config.minimum_images_per_class:
            issues.append(
                ValidationIssue(
                    "insufficient_class_images",
                    (
                        f"{class_name} has {image_count} image(s); "
                        f"at least {dataset_config.minimum_images_per_class} required"
                    ),
                    class_name=class_name,
                )
            )
        instance_count = instance_counts.get(class_name, 0)
        if instance_count < dataset_config.minimum_instances_per_class:
            issues.append(
                ValidationIssue(
                    "insufficient_class_instances",
                    (
                        f"{class_name} has {instance_count} instance(s); "
                        f"at least {dataset_config.minimum_instances_per_class} required"
                    ),
                    class_name=class_name,
                )
            )

    active_splits = sum(ratio > 0 for ratio in dataset_config.ratios.values())
    session_count = len(manifest.sessions())
    if session_count < active_splits:
        issues.append(
            ValidationIssue(
                "insufficient_capture_sessions",
                f"{session_count} capture session(s) cannot populate {active_splits} active splits",
            )
        )
    return ValidationReport(tuple(issues))


def validate_split(
    split: "DatasetSplit",
    config: AppConfig | DatasetConfig,
    *,
    classes: Iterable[str] = COIN_CLASSES,
) -> ValidationReport:
    dataset_config = config.dataset if isinstance(config, AppConfig) else config
    class_names = tuple(classes)
    issues: list[ValidationIssue] = []
    session_owners: dict[str, str] = {}
    for split_name, images in split.items():
        if dataset_config.ratios[split_name] > 0 and not images:
            issues.append(
                ValidationIssue(
                    "empty_split",
                    f"{split_name} split contains no images",
                    split=split_name,
                )
            )
        for image in images:
            previous = session_owners.setdefault(image.capture_session_id, split_name)
            if previous != split_name:
                issues.append(
                    ValidationIssue(
                        "capture_session_leakage",
                        (
                            f"captureSessionId '{image.capture_session_id}' appears in "
                            f"both {previous} and {split_name}"
                        ),
                        image_id=image.id,
                        split=split_name,
                    )
                )
        if dataset_config.require_all_classes_in_each_split and dataset_config.ratios[split_name] > 0:
            present = {
                annotation.class_name
                for image in images
                for annotation in image.annotations
            }
            for class_name in class_names:
                if class_name not in present:
                    issues.append(
                        ValidationIssue(
                            "class_missing_from_split",
                            f"{class_name} is missing from the {split_name} split",
                            class_name=class_name,
                            split=split_name,
                        )
                    )
    return ValidationReport(tuple(issues))


def combine_reports(*reports: ValidationReport) -> ValidationReport:
    return ValidationReport(tuple(issue for report in reports for issue in report.issues))
