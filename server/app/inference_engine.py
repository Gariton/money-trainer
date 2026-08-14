from __future__ import annotations

import threading
from pathlib import Path
from typing import Any, Protocol

from .constants import COIN_CLASSES
from .db_models import TrainedModel
from .schemas import Annotation
from .storage import ObjectStorage, StorageObjectNotFound


class InferenceRuntimeUnavailable(RuntimeError):
    pass


class InferenceEngine(Protocol):
    def predict(
        self,
        image_path: Path,
        model: TrainedModel,
        storage: ObjectStorage,
    ) -> list[Annotation]: ...


class LazyUltralyticsInferenceEngine:
    """Optional real detector adapter; Ultralytics is imported on first use only."""

    def __init__(self, *, needs_review_threshold: float = 0.5) -> None:
        self.needs_review_threshold = needs_review_threshold
        self._lock = threading.Lock()
        self._cached_key: tuple[str, int] | None = None
        self._cached_detector: Any = None

    def _detector_for(self, checkpoint_key: str, storage: ObjectStorage) -> Any:
        try:
            checkpoint_path = storage.local_path(checkpoint_key)
        except StorageObjectNotFound as exc:
            raise InferenceRuntimeUnavailable("Model checkpoint is missing") from exc
        cache_key = (checkpoint_key, checkpoint_path.stat().st_mtime_ns)
        with self._lock:
            if cache_key == self._cached_key:
                return self._cached_detector
            try:
                from ultralytics import YOLO
            except ImportError as exc:
                raise InferenceRuntimeUnavailable(
                    "Real inference requires the optional Ultralytics runtime"
                ) from exc
            try:
                detector = YOLO(str(checkpoint_path))
            except Exception as exc:
                raise InferenceRuntimeUnavailable(
                    "The latest checkpoint could not be loaded for inference"
                ) from exc
            self._cached_key = cache_key
            self._cached_detector = detector
            return detector

    def predict(
        self,
        image_path: Path,
        model: TrainedModel,
        storage: ObjectStorage,
    ) -> list[Annotation]:
        if not model.checkpoint_key:
            return []
        detector = self._detector_for(model.checkpoint_key, storage)
        try:
            results = detector.predict(source=str(image_path), verbose=False)
        except Exception as exc:
            raise InferenceRuntimeUnavailable("Ultralytics inference failed") from exc
        annotations: list[Annotation] = []
        for result in results:
            boxes = getattr(result, "boxes", None)
            if boxes is None:
                continue
            xywhn = boxes.xywhn.detach().cpu().tolist()
            class_indexes = boxes.cls.detach().cpu().tolist()
            confidences = boxes.conf.detach().cpu().tolist()
            names = getattr(result, "names", getattr(detector, "names", {}))
            for values, class_index, confidence in zip(
                xywhn, class_indexes, confidences, strict=True
            ):
                center_x, center_y, width, height = (float(value) for value in values)
                index = int(class_index)
                class_name = (
                    names.get(index)
                    if isinstance(names, dict)
                    else names[index]
                    if 0 <= index < len(names)
                    else None
                )
                if class_name not in COIN_CLASSES:
                    # Stable class order is a safe fallback for checkpoints lacking names.
                    class_name = COIN_CLASSES[index] if 0 <= index < len(COIN_CLASSES) else None
                if class_name is None:
                    continue
                x = max(0.0, min(1.0, center_x - width / 2))
                y = max(0.0, min(1.0, center_y - height / 2))
                right = max(0.0, min(1.0, center_x + width / 2))
                bottom = max(0.0, min(1.0, center_y + height / 2))
                width = right - x
                height = bottom - y
                if width <= 0 or height <= 0:
                    continue
                annotations.append(
                    Annotation(
                        **{
                            "class": class_name,
                            "x": x,
                            "y": y,
                            "width": width,
                            "height": height,
                            "confidence": float(confidence),
                            "needs_review": float(confidence)
                            < self.needs_review_threshold,
                        }
                    )
                )
        return annotations
