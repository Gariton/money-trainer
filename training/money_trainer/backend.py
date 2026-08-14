"""Training backend abstraction and lazy Ultralytics implementation."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
import json
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence

from .augmentation import ultralytics_augmentation_args
from .config import AppConfig
from .constants import COIN_CLASSES
from .metrics import (
    ConfusionMatrix,
    EvaluationMetrics,
    deterministic_mock_confusion_matrix,
    deterministic_mock_metrics,
    parse_ultralytics_confusion_matrix,
    parse_ultralytics_metrics,
)
from .reports import FailureCase
from .yolo import YoloDataset


EpochProgress = Callable[[float], None]


class BackendUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class TrainingOutcome:
    checkpoint: Path
    backend_name: str
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class EvaluationOutcome:
    metrics: EvaluationMetrics
    confusion_matrix: ConfusionMatrix | None
    failures: tuple[FailureCase, ...] = ()
    warnings: tuple[str, ...] = ()


class ModelBackend(ABC):
    name: str

    @abstractmethod
    def train(
        self,
        dataset: YoloDataset,
        output_dir: Path,
        config: AppConfig,
        *,
        on_progress: EpochProgress | None = None,
    ) -> TrainingOutcome:
        raise NotImplementedError

    @abstractmethod
    def evaluate(
        self,
        checkpoint: Path,
        dataset: YoloDataset,
        output_dir: Path,
        config: AppConfig,
    ) -> EvaluationOutcome:
        raise NotImplementedError


class MockBackend(ModelBackend):
    """Dependency-free backend with deterministic, clearly marked artifacts."""

    name = "mock"

    def train(
        self,
        dataset: YoloDataset,
        output_dir: Path,
        config: AppConfig,
        *,
        on_progress: EpochProgress | None = None,
    ) -> TrainingOutcome:
        checkpoint_dir = output_dir / "checkpoints"
        checkpoint_dir.mkdir(parents=True, exist_ok=True)
        checkpoint = checkpoint_dir / "best.mock.pt"
        checkpoint.write_text(
            json.dumps(
                {
                    "mock": True,
                    "architecture": config.model.architecture,
                    "imageSize": config.model.image_size,
                    "datasetImageCount": dataset.image_count,
                    "datasetAnnotationCount": dataset.annotation_count,
                    "seed": config.training.seed,
                },
                sort_keys=True,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        if on_progress:
            for fraction in (0.10, 0.35, 0.70, 1.0):
                on_progress(fraction)
        return TrainingOutcome(
            checkpoint=checkpoint,
            backend_name=self.name,
            metadata={"mock": True, "deterministic": True},
        )

    def evaluate(
        self,
        checkpoint: Path,
        dataset: YoloDataset,
        output_dir: Path,
        config: AppConfig,
    ) -> EvaluationOutcome:
        del checkpoint, output_dir, config
        failures: list[FailureCase] = []
        test_images = sorted((dataset.root / "images" / "test").glob("*"))
        categories = ("false-positive", "false-negative", "low-confidence", "confused-class")
        for index, category in enumerate(categories):
            if index >= len(test_images):
                break
            image = test_images[index]
            failures.append(
                FailureCase(
                    category=category,
                    image_path=image,
                    image_id=image.stem,
                    true_class="jpy_50" if category in {"false-negative", "confused-class"} else None,
                    predicted_class="jpy_100" if category in {"false-positive", "confused-class"} else None,
                    confidence=0.42 if category in {"low-confidence", "confused-class"} else None,
                    details="deterministic mock example",
                )
            )
        return EvaluationOutcome(
            metrics=deterministic_mock_metrics(),
            confusion_matrix=deterministic_mock_confusion_matrix(),
            failures=tuple(failures),
        )


class UltralyticsBackend(ModelBackend):
    """Maintained nano YOLO backend. Imports ML dependencies only when used."""

    name = "ultralytics-yolo26"

    def train(
        self,
        dataset: YoloDataset,
        output_dir: Path,
        config: AppConfig,
        *,
        on_progress: EpochProgress | None = None,
    ) -> TrainingOutcome:
        YOLO = _load_yolo()
        model = YOLO(config.model.architecture)
        if on_progress is not None:
            total_epochs = config.training.epochs

            def epoch_callback(trainer: Any) -> None:
                epoch = int(getattr(trainer, "epoch", 0)) + 1
                on_progress(min(epoch / max(total_epochs, 1), 1.0))

            add_callback = getattr(model, "add_callback", None)
            if callable(add_callback):
                add_callback("on_train_epoch_end", epoch_callback)

        train_root = output_dir / "ultralytics"
        kwargs: dict[str, Any] = {
            "data": str(dataset.data_yaml),
            "imgsz": config.model.image_size,
            "epochs": config.training.epochs,
            "batch": config.training.batch_size,
            "patience": config.training.patience,
            "workers": config.training.workers,
            "seed": config.training.seed,
            "deterministic": config.training.deterministic,
            "device": _resolve_device(config.model.device),
            "project": str(train_root),
            "name": "train",
            "exist_ok": True,
            "plots": True,
        }
        kwargs.update(ultralytics_augmentation_args(config.augmentation))
        result = model.train(**kwargs)
        save_dir = Path(str(getattr(result, "save_dir", train_root / "train")))
        checkpoint = save_dir / "weights" / "best.pt"
        if not checkpoint.is_file():
            fallback = save_dir / "weights" / "last.pt"
            if fallback.is_file():
                checkpoint = fallback
            else:
                raise RuntimeError(f"Ultralytics did not produce a checkpoint in {save_dir}")
        if on_progress:
            on_progress(1.0)
        return TrainingOutcome(
            checkpoint=checkpoint.resolve(),
            backend_name=self.name,
            metadata={
                "architecture": config.model.architecture,
                "device": kwargs["device"],
                "ultralyticsSaveDir": str(save_dir),
            },
        )

    def evaluate(
        self,
        checkpoint: Path,
        dataset: YoloDataset,
        output_dir: Path,
        config: AppConfig,
    ) -> EvaluationOutcome:
        YOLO = _load_yolo()
        model = YOLO(str(checkpoint))
        result = model.val(
            data=str(dataset.data_yaml),
            split="test",
            imgsz=config.model.image_size,
            batch=config.training.batch_size,
            device=_resolve_device(config.model.device),
            # mAP/PR curves require the low validation floor. Deployment and
            # failure-report thresholds are applied separately below.
            conf=0.001,
            iou=config.evaluation.iou_threshold,
            project=str(output_dir / "ultralytics"),
            name="evaluation",
            exist_ok=True,
            plots=True,
        )
        metrics = parse_ultralytics_metrics(result, class_names=config.classes)
        confusion = parse_ultralytics_confusion_matrix(result, class_names=config.classes)
        warnings: list[str] = []
        try:
            failures = tuple(_extract_failure_cases(model, dataset, config))
        except Exception as exc:  # prediction API changes must not discard valid evaluation metrics
            failures = ()
            warnings.append(f"failure-case extraction failed: {type(exc).__name__}: {exc}")
        return EvaluationOutcome(
            metrics=metrics,
            confusion_matrix=confusion,
            failures=failures,
            warnings=tuple(warnings),
        )


def create_backend(*, mock_mode: bool) -> ModelBackend:
    return MockBackend() if mock_mode else UltralyticsBackend()


def _load_yolo() -> Any:
    try:
        from ultralytics import YOLO  # type: ignore[import-not-found]
    except ImportError as exc:
        raise BackendUnavailableError(
            "real training requires optional ML dependencies; install with "
            "`pip install -e '.[ml]'` from training/ or run with --mock"
        ) from exc
    return YOLO


def _resolve_device(requested: str) -> Any:
    if requested.lower() != "auto":
        return requested
    try:
        import torch  # type: ignore[import-not-found]
    except ImportError:
        return "cpu"
    if torch.cuda.is_available():
        return 0
    mps = getattr(torch.backends, "mps", None)
    if mps is not None and mps.is_available():
        return "mps"
    return "cpu"


def _extract_failure_cases(
    model: Any,
    dataset: YoloDataset,
    config: AppConfig,
) -> Iterable[FailureCase]:
    image_dir = dataset.root / "images" / "test"
    results = model.predict(
        source=str(image_dir),
        stream=True,
        save=False,
        verbose=False,
        imgsz=config.model.image_size,
        conf=0.001,
        iou=config.evaluation.iou_threshold,
        device=_resolve_device(config.model.device),
    )
    for result in results:
        image_path = Path(str(result.path))
        ground_truth = _load_yolo_labels(
            dataset.root / "labels" / "test" / f"{image_path.stem}.txt"
        )
        predictions = _prediction_rows(result)
        matched_ground_truth: set[int] = set()
        for predicted_class, predicted_box, confidence in predictions:
            best_index = -1
            best_iou = 0.0
            for gt_index, (_, gt_box) in enumerate(ground_truth):
                if gt_index in matched_ground_truth:
                    continue
                overlap = _box_iou(predicted_box, gt_box)
                if overlap > best_iou:
                    best_iou = overlap
                    best_index = gt_index
            if confidence < config.evaluation.confidence_threshold:
                yield FailureCase(
                    "low-confidence",
                    image_path,
                    image_path.stem,
                    true_class=(
                        _class_name(ground_truth[best_index][0], config.classes)
                        if best_index >= 0 and best_iou >= config.evaluation.iou_threshold
                        else None
                    ),
                    predicted_class=_class_name(predicted_class, config.classes),
                    confidence=confidence,
                    details=f"below deployment threshold; best IoU={best_iou:.4f}",
                )
                # It remains unmatched: deployment would suppress this result,
                # so an overlapping ground-truth object is also a false negative.
                continue
            if best_index >= 0 and best_iou >= config.evaluation.iou_threshold:
                matched_ground_truth.add(best_index)
                true_class = ground_truth[best_index][0]
                if predicted_class != true_class:
                    yield FailureCase(
                        "confused-class",
                        image_path,
                        image_path.stem,
                        true_class=_class_name(true_class, config.classes),
                        predicted_class=_class_name(predicted_class, config.classes),
                        confidence=confidence,
                        details=f"IoU={best_iou:.4f}",
                    )
                elif confidence < config.evaluation.low_confidence_threshold:
                    yield FailureCase(
                        "low-confidence",
                        image_path,
                        image_path.stem,
                        true_class=_class_name(true_class, config.classes),
                        predicted_class=_class_name(predicted_class, config.classes),
                        confidence=confidence,
                        details=f"IoU={best_iou:.4f}",
                    )
            else:
                yield FailureCase(
                    "false-positive",
                    image_path,
                    image_path.stem,
                    predicted_class=_class_name(predicted_class, config.classes),
                    confidence=confidence,
                )
        for gt_index, (true_class, _) in enumerate(ground_truth):
            if gt_index not in matched_ground_truth:
                yield FailureCase(
                    "false-negative",
                    image_path,
                    image_path.stem,
                    true_class=_class_name(true_class, config.classes),
                )


def _prediction_rows(result: Any) -> list[tuple[int, tuple[float, float, float, float], float]]:
    boxes = getattr(result, "boxes", None)
    if boxes is None:
        return []
    xywhn = _to_list(getattr(boxes, "xywhn", []))
    classes = _to_list(getattr(boxes, "cls", []))
    confidences = _to_list(getattr(boxes, "conf", []))
    return [
        (int(class_value), tuple(float(value) for value in box), float(confidence))
        for class_value, box, confidence in zip(classes, xywhn, confidences, strict=True)
    ]


def _load_yolo_labels(path: Path) -> list[tuple[int, tuple[float, float, float, float]]]:
    if not path.is_file():
        return []
    result = []
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) != 5:
            continue
        result.append((int(parts[0]), tuple(float(value) for value in parts[1:])))
    return result


def _box_iou(
    first: Sequence[float],
    second: Sequence[float],
) -> float:
    def corners(box: Sequence[float]) -> tuple[float, float, float, float]:
        center_x, center_y, width, height = box
        return (
            center_x - width / 2,
            center_y - height / 2,
            center_x + width / 2,
            center_y + height / 2,
        )

    first_x1, first_y1, first_x2, first_y2 = corners(first)
    second_x1, second_y1, second_x2, second_y2 = corners(second)
    intersection = max(0.0, min(first_x2, second_x2) - max(first_x1, second_x1)) * max(
        0.0, min(first_y2, second_y2) - max(first_y1, second_y1)
    )
    first_area = max(0.0, first_x2 - first_x1) * max(0.0, first_y2 - first_y1)
    second_area = max(0.0, second_x2 - second_x1) * max(0.0, second_y2 - second_y1)
    union = first_area + second_area - intersection
    return intersection / union if union > 0 else 0.0


def _to_list(value: Any) -> list[Any]:
    for method_name in ("detach", "cpu"):
        method = getattr(value, method_name, None)
        if callable(method):
            value = method()
    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        value = tolist()
    return list(value)


def _class_name(index: int, names: tuple[str, ...]) -> str:
    return names[index] if 0 <= index < len(names) else f"unknown_{index}"
