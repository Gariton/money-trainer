"""Manifest models for normalized top-left bounding boxes."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any, Iterable, Mapping
from urllib.parse import unquote, urlparse

from .constants import MANIFEST_CANDIDATES


class DatasetFormatError(ValueError):
    """Raised when a dataset manifest cannot be decoded."""


@dataclass(frozen=True, slots=True)
class Annotation:
    """A normalized box where x/y are the top-left corner, not the center."""

    class_name: str
    x: float
    y: float
    width: float
    height: float
    confidence: float | None = None

    @property
    def yolo_box(self) -> tuple[float, float, float, float]:
        return (self.x + self.width / 2, self.y + self.height / 2, self.width, self.height)

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "Annotation":
        rect = value.get("rect")
        coordinates: Mapping[str, Any] = rect if isinstance(rect, Mapping) else value
        class_name = value.get("class", value.get("class_name", value.get("denomination")))
        if class_name is None:
            raise DatasetFormatError("annotation is missing 'class'")
        try:
            confidence_raw = value.get("confidence")
            return cls(
                class_name=str(class_name),
                x=float(_required(coordinates, "x")),
                y=float(_required(coordinates, "y")),
                width=float(_required(coordinates, "width")),
                height=float(_required(coordinates, "height")),
                confidence=float(confidence_raw) if confidence_raw is not None else None,
            )
        except (TypeError, ValueError) as exc:
            raise DatasetFormatError(f"annotation coordinates must be numeric: {exc}") from exc

    def to_mapping(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "class": self.class_name,
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
        }
        if self.confidence is not None:
            value["confidence"] = self.confidence
        return value


@dataclass(frozen=True, slots=True)
class DatasetImage:
    id: str
    image_path: Path
    declared_image_path: str
    capture_session_id: str
    annotations: tuple[Annotation, ...]
    review_status: str = "unreviewed"
    source: str | None = None
    created_at: str | None = None
    model_version_used_for_pre_annotation: str | None = None

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any], root_dir: Path) -> "DatasetImage":
        image_id = value.get("id")
        if image_id is None:
            raise DatasetFormatError("image record is missing 'id'")
        declared_path = _first(
            value,
            "image",
            "image_path",
            "imagePath",
            "file_path",
            "filePath",
            "path",
            "imageURL",
            "image_url",
        )
        if declared_path is None:
            raise DatasetFormatError(f"image '{image_id}' is missing an image path")
        declared_path = str(declared_path)
        parsed = urlparse(declared_path)
        if parsed.scheme == "file":
            raw_path = Path(unquote(parsed.path))
        elif parsed.scheme:
            # Remote URLs are intentionally not fetched by the training worker.
            raw_path = Path(declared_path)
        else:
            raw_path = Path(declared_path)
        image_path = raw_path if raw_path.is_absolute() else root_dir / raw_path

        capture_session_id = _first(
            value,
            "captureSessionId",
            "captureSessionID",
            "capture_session_id",
        )
        raw_annotations = value.get("annotations", [])
        if not isinstance(raw_annotations, list):
            raise DatasetFormatError(f"image '{image_id}' annotations must be a list")
        annotations = tuple(
            Annotation.from_mapping(_mapping(annotation, "annotation"))
            for annotation in raw_annotations
        )
        return cls(
            id=str(image_id),
            image_path=image_path.resolve(strict=False),
            declared_image_path=declared_path,
            capture_session_id="" if capture_session_id is None else str(capture_session_id),
            annotations=annotations,
            review_status=str(
                _first(value, "reviewStatus", "review_status") or "unreviewed"
            ),
            source=_optional_string(_first(value, "source")),
            created_at=_optional_string(_first(value, "createdAt", "created_at")),
            model_version_used_for_pre_annotation=_optional_string(
                _first(
                    value,
                    "modelVersionUsedForPreAnnotation",
                    "model_version_used_for_pre_annotation",
                )
            ),
        )

    def to_mapping(self, *, relative_to: Path | None = None) -> dict[str, Any]:
        image_path: str
        if relative_to is not None:
            try:
                image_path = str(self.image_path.relative_to(relative_to))
            except ValueError:
                image_path = str(self.image_path)
        else:
            image_path = str(self.image_path)
        result: dict[str, Any] = {
            "id": self.id,
            "image": image_path,
            "captureSessionId": self.capture_session_id,
            "reviewStatus": self.review_status,
            "annotations": [annotation.to_mapping() for annotation in self.annotations],
        }
        if self.source is not None:
            result["source"] = self.source
        if self.created_at is not None:
            result["createdAt"] = self.created_at
        if self.model_version_used_for_pre_annotation is not None:
            result["modelVersionUsedForPreAnnotation"] = self.model_version_used_for_pre_annotation
        return result


@dataclass(frozen=True, slots=True)
class DatasetManifest:
    images: tuple[DatasetImage, ...]
    root_dir: Path
    manifest_path: Path
    dataset_version: str = "unknown"

    @classmethod
    def load(cls, path: str | Path) -> "DatasetManifest":
        supplied = Path(path).expanduser()
        if supplied.is_dir():
            manifest_path = next(
                (supplied / name for name in MANIFEST_CANDIDATES if (supplied / name).is_file()),
                None,
            )
            if manifest_path is None:
                raise DatasetFormatError(
                    f"no dataset manifest found in {supplied}; expected one of {MANIFEST_CANDIDATES}"
                )
        else:
            manifest_path = supplied
        if not manifest_path.is_file():
            raise DatasetFormatError(f"dataset manifest does not exist: {manifest_path}")
        try:
            raw = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise DatasetFormatError(f"invalid JSON in {manifest_path}: {exc}") from exc
        return cls.from_value(raw, manifest_path=manifest_path.resolve())

    @classmethod
    def from_value(cls, raw: Any, *, manifest_path: Path) -> "DatasetManifest":
        root_dir = manifest_path.parent.resolve()
        if isinstance(raw, list):
            raw_images = raw
            dataset_version = "unknown"
        elif isinstance(raw, Mapping):
            raw_images = raw.get("images")
            dataset_version = str(raw.get("datasetVersion", raw.get("dataset_version", "unknown")))
        else:
            raise DatasetFormatError("dataset manifest root must be an object or image list")
        if not isinstance(raw_images, list):
            raise DatasetFormatError("dataset manifest must contain an 'images' list")
        images = tuple(
            DatasetImage.from_mapping(_mapping(image, "image record"), root_dir)
            for image in raw_images
        )
        return cls(
            images=images,
            root_dir=root_dir,
            manifest_path=manifest_path,
            dataset_version=dataset_version,
        )

    def to_mapping(self) -> dict[str, Any]:
        return {
            "datasetVersion": self.dataset_version,
            "images": [image.to_mapping(relative_to=self.root_dir) for image in self.images],
        }

    def sessions(self) -> set[str]:
        return {image.capture_session_id for image in self.images if image.capture_session_id}

    def class_instance_counts(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for image in self.images:
            for annotation in image.annotations:
                counts[annotation.class_name] = counts.get(annotation.class_name, 0) + 1
        return counts

    def image_counts_by_class(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for image in self.images:
            for class_name in {annotation.class_name for annotation in image.annotations}:
                counts[class_name] = counts.get(class_name, 0) + 1
        return counts


def manifest_from_images(
    images: Iterable[DatasetImage],
    *,
    root_dir: Path,
    dataset_version: str = "unknown",
) -> DatasetManifest:
    """Convenience constructor for API workers that already hold image rows."""

    root = root_dir.resolve()
    return DatasetManifest(
        images=tuple(images),
        root_dir=root,
        manifest_path=root / "manifest.json",
        dataset_version=dataset_version,
    )


def _required(value: Mapping[str, Any], key: str) -> Any:
    if key not in value:
        raise DatasetFormatError(f"annotation is missing '{key}'")
    return value[key]


def _first(value: Mapping[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in value:
            return value[key]
    return None


def _optional_string(value: Any) -> str | None:
    return None if value is None else str(value)


def _mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise DatasetFormatError(f"{label} must be an object")
    return value

