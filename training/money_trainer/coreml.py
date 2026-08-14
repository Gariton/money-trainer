"""Core ML export and source-vs-export validation abstractions."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import asdict, dataclass, field
from importlib.resources import files
import json
from pathlib import Path
import platform
import shutil
from typing import Any, Iterable, Mapping, Sequence
import uuid
import zipfile

from .backend import BackendUnavailableError
from .config import AppConfig


MODEL_PACKAGE_NAME = "MoneyDetector.mlpackage"
MODEL_ARCHIVE_NAME = "MoneyDetector.mlpackage.zip"


class CoreMLExportError(RuntimeError):
    pass


class CoreMLValidationError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class CoreMLArtifact:
    package_path: Path
    archive_path: Path
    metadata_path: Path
    mock: bool
    mock_compilable: bool | None
    warnings: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class CoreMLValidationResult:
    valid: bool
    mode: str
    numerical_validation_performed: bool
    match_rate: float | None = None
    mean_confidence_delta: float | None = None
    mean_iou: float | None = None
    source_detection_count: int | None = None
    coreml_detection_count: int | None = None
    warnings: tuple[str, ...] = ()
    details: Mapping[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        return {
            "valid": value["valid"],
            "mode": value["mode"],
            "numericalValidationPerformed": value["numerical_validation_performed"],
            "matchRate": value["match_rate"],
            "meanConfidenceDelta": value["mean_confidence_delta"],
            "meanIoU": value["mean_iou"],
            "sourceDetectionCount": value["source_detection_count"],
            "coreMLDetectionCount": value["coreml_detection_count"],
            "warnings": list(value["warnings"]),
            "details": dict(value["details"]),
        }


class CoreMLExporter(ABC):
    @abstractmethod
    def export(
        self,
        checkpoint: Path,
        output_dir: Path,
        metadata: Mapping[str, Any],
        config: AppConfig,
    ) -> CoreMLArtifact:
        raise NotImplementedError


class CoreMLValidator(ABC):
    @abstractmethod
    def validate(
        self,
        checkpoint: Path,
        artifact: CoreMLArtifact,
        sample_images: Iterable[Path],
        config: AppConfig,
    ) -> CoreMLValidationResult:
        raise NotImplementedError


class MockCoreMLExporter(CoreMLExporter):
    """Create a compilable synthetic package when possible, otherwise a clear placeholder."""

    def export(
        self,
        checkpoint: Path,
        output_dir: Path,
        metadata: Mapping[str, Any],
        config: AppConfig,
    ) -> CoreMLArtifact:
        del checkpoint, config
        output_dir.mkdir(parents=True, exist_ok=True)
        package = output_dir / MODEL_PACKAGE_NAME
        if package.exists():
            raise CoreMLExportError(f"Core ML package already exists: {package}")
        warnings: list[str] = []
        # The vendored template is intentionally preferred so the default
        # Linux/arm64 Docker image has a compilable artifact without needing a
        # coremltools wheel. Dynamic generation remains a developer fallback.
        mock_compilable = _copy_vendored_mock(package, warnings)
        if not mock_compilable:
            mock_compilable = _try_create_compilable_mock(package, metadata, warnings)
        if not mock_compilable:
            _write_package_placeholder(package, metadata)
            warnings.append(
                "coremltools is unavailable or could not build a synthetic model; "
                "this package-shaped mock is downloadable but not Core ML compilable"
            )
        metadata_path = output_dir / "coreml_export.json"
        export_metadata = {
            **dict(metadata),
            "mock": True,
            "mockCompilable": mock_compilable,
            "numericalValidationExpected": False,
            "package": MODEL_PACKAGE_NAME,
            "mockOutputName": "predictions",
            "mockOutputShape": [1, 300, 6],
            "mockOutputFormat": "normalized_xyxy_confidence_class_id",
            "mockConstantDetection": [0.20, 0.20, 0.60, 0.60, 0.99, 4.0],
        }
        metadata_path.write_text(
            json.dumps(export_metadata, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        archive = output_dir / MODEL_ARCHIVE_NAME
        _zip_package(package, archive)
        return CoreMLArtifact(
            package_path=package,
            archive_path=archive,
            metadata_path=metadata_path,
            mock=True,
            mock_compilable=mock_compilable,
            warnings=tuple(warnings),
        )


class UltralyticsCoreMLExporter(CoreMLExporter):
    def export(
        self,
        checkpoint: Path,
        output_dir: Path,
        metadata: Mapping[str, Any],
        config: AppConfig,
    ) -> CoreMLArtifact:
        try:
            from ultralytics import YOLO  # type: ignore[import-not-found]
        except ImportError as exc:
            raise BackendUnavailableError(
                "Core ML export requires the optional 'ml' dependencies"
            ) from exc
        output_dir.mkdir(parents=True, exist_ok=True)
        package = output_dir / MODEL_PACKAGE_NAME
        if package.exists():
            raise CoreMLExportError(f"Core ML package already exists: {package}")
        model = YOLO(str(checkpoint))
        export_args: dict[str, Any] = {
            "format": "coreml",
            "imgsz": config.model.image_size,
            # YOLO26 is end-to-end/NMS-free. This remains configurable for a
            # future backend but defaults to false for the maintained model.
            "nms": config.export.nms,
        }
        if config.export.quantize:
            export_args["quantize"] = config.export.quantize
        exported_value = model.export(**export_args)
        exported = Path(str(exported_value)).resolve()
        if not exported.exists():
            raise CoreMLExportError(f"Ultralytics returned a missing export path: {exported}")
        if exported.is_dir():
            shutil.copytree(exported, package)
        else:
            raise CoreMLExportError(
                f"expected an .mlpackage directory from Ultralytics, got: {exported}"
            )

        warnings: list[str] = []
        _embed_metadata_if_available(package, metadata, warnings)
        metadata_path = output_dir / "coreml_export.json"
        metadata_path.write_text(
            json.dumps(
                {
                    **dict(metadata),
                    "mock": False,
                    "mockCompilable": None,
                    "quantize": config.export.quantize,
                    "nms": config.export.nms,
                    "package": MODEL_PACKAGE_NAME,
                },
                indent=2,
                sort_keys=True,
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )
        archive = output_dir / MODEL_ARCHIVE_NAME
        _zip_package(package, archive)
        return CoreMLArtifact(
            package_path=package,
            archive_path=archive,
            metadata_path=metadata_path,
            mock=False,
            mock_compilable=None,
            warnings=tuple(warnings),
        )


class MockCoreMLValidator(CoreMLValidator):
    def validate(
        self,
        checkpoint: Path,
        artifact: CoreMLArtifact,
        sample_images: Iterable[Path],
        config: AppConfig,
    ) -> CoreMLValidationResult:
        del checkpoint, sample_images, config
        manifest = artifact.package_path / "Manifest.json"
        metadata_exists = artifact.metadata_path.is_file()
        archive_exists = artifact.archive_path.is_file() and artifact.archive_path.stat().st_size > 0
        package_has_content = artifact.package_path.is_dir() and any(artifact.package_path.rglob("*"))
        valid = manifest.is_file() and metadata_exists and archive_exists and package_has_content
        warnings = list(artifact.warnings)
        if artifact.mock_compilable:
            mode = "mock-compilable-structural"
            warnings.append(
                "synthetic Mock Core ML compilation shape is valid, but detector accuracy was not validated"
            )
        else:
            mode = "mock-placeholder-structural"
            warnings.append(
                "package-shaped Mock artifact is not a Core ML protobuf; iOS compilation is expected to fail"
            )
        return CoreMLValidationResult(
            valid=valid,
            mode=mode,
            numerical_validation_performed=False,
            warnings=tuple(warnings),
            details={"mockCompilable": bool(artifact.mock_compilable)},
        )


class UltralyticsCoreMLValidator(CoreMLValidator):
    def validate(
        self,
        checkpoint: Path,
        artifact: CoreMLArtifact,
        sample_images: Iterable[Path],
        config: AppConfig,
    ) -> CoreMLValidationResult:
        structural_error = _structural_error(artifact)
        if structural_error:
            return CoreMLValidationResult(
                valid=False,
                mode="structural",
                numerical_validation_performed=False,
                warnings=(structural_error,),
            )
        if platform.system() != "Darwin":
            return CoreMLValidationResult(
                valid=True,
                mode="structural-only-non-macos",
                numerical_validation_performed=False,
                warnings=(
                    "Core ML inference validation is supported on macOS only; "
                    "run this artifact on a Mac before activation",
                ),
            )
        try:
            from ultralytics import YOLO  # type: ignore[import-not-found]
        except ImportError as exc:
            raise BackendUnavailableError(
                "Core ML numerical validation requires optional ML dependencies"
            ) from exc
        samples = [path for path in sample_images if path.is_file()][
            : config.evaluation.coreml_validation_images
        ]
        if not samples:
            return CoreMLValidationResult(
                valid=False,
                mode="numerical",
                numerical_validation_performed=False,
                warnings=("no test images available for Core ML validation",),
            )
        source_model = YOLO(str(checkpoint))
        coreml_model = YOLO(str(artifact.package_path))
        sources = [str(path) for path in samples]
        predict_args = {
            "source": sources,
            "verbose": False,
            "save": False,
            "imgsz": config.model.image_size,
            "conf": 0.001,
        }
        source_results = source_model.predict(**predict_args)
        coreml_results = coreml_model.predict(**predict_args)
        comparison = compare_detection_batches(source_results, coreml_results)
        valid = (
            comparison.match_rate >= config.evaluation.coreml_min_match_rate
            and comparison.mean_confidence_delta
            <= config.evaluation.coreml_max_mean_confidence_delta
            and comparison.mean_iou >= config.evaluation.coreml_min_mean_iou
        )
        return CoreMLValidationResult(
            valid=valid,
            mode="numerical",
            numerical_validation_performed=True,
            match_rate=comparison.match_rate,
            mean_confidence_delta=comparison.mean_confidence_delta,
            mean_iou=comparison.mean_iou,
            source_detection_count=comparison.source_detection_count,
            coreml_detection_count=comparison.coreml_detection_count,
        )


@dataclass(frozen=True, slots=True)
class DetectionComparison:
    match_rate: float
    mean_confidence_delta: float
    mean_iou: float
    source_detection_count: int
    coreml_detection_count: int


def compare_detection_batches(
    source_results: Iterable[Any],
    coreml_results: Iterable[Any],
) -> DetectionComparison:
    source_batches = [_detections(result) for result in source_results]
    coreml_batches = [_detections(result) for result in coreml_results]
    if len(source_batches) != len(coreml_batches):
        raise CoreMLValidationError("source and Core ML result batch sizes differ")
    source_count = sum(len(batch) for batch in source_batches)
    coreml_count = sum(len(batch) for batch in coreml_batches)
    matches: list[tuple[float, float]] = []
    for source_batch, coreml_batch in zip(source_batches, coreml_batches, strict=True):
        consumed: set[int] = set()
        for source_class, source_box, source_confidence in source_batch:
            candidates = [
                (index, _iou(source_box, candidate_box), candidate_confidence)
                for index, (candidate_class, candidate_box, candidate_confidence) in enumerate(coreml_batch)
                if index not in consumed and candidate_class == source_class
            ]
            if not candidates:
                continue
            index, overlap, coreml_confidence = max(candidates, key=lambda item: item[1])
            consumed.add(index)
            matches.append((overlap, abs(source_confidence - coreml_confidence)))
    denominator = max(source_count, coreml_count, 1)
    if source_count == 0 and coreml_count == 0:
        return DetectionComparison(1.0, 0.0, 1.0, 0, 0)
    return DetectionComparison(
        match_rate=len(matches) / denominator,
        mean_confidence_delta=(sum(delta for _, delta in matches) / len(matches)) if matches else 1.0,
        mean_iou=(sum(overlap for overlap, _ in matches) / len(matches)) if matches else 0.0,
        source_detection_count=source_count,
        coreml_detection_count=coreml_count,
    )


def create_coreml_components(
    *, mock_mode: bool
) -> tuple[CoreMLExporter, CoreMLValidator]:
    if mock_mode:
        return MockCoreMLExporter(), MockCoreMLValidator()
    return UltralyticsCoreMLExporter(), UltralyticsCoreMLValidator()


def _try_create_compilable_mock(
    package: Path,
    metadata: Mapping[str, Any],
    warnings: list[str],
) -> bool:
    try:
        import coremltools as ct  # type: ignore[import-not-found]
        import numpy as np  # type: ignore[import-not-found]
        from coremltools.models import datatypes  # type: ignore[import-not-found]
        from coremltools.models.neural_network import (  # type: ignore[import-not-found]
            NeuralNetworkBuilder,
        )
    except ImportError:
        return False
    try:
        builder = NeuralNetworkBuilder(
            [("image", datatypes.Array(3, 640, 640))],
            [("predictions", datatypes.Array(1, 300, 6))],
        )
        # Consume the image before producing a fixed detection tensor. Core ML
        # may compile a disconnected constant graph, but MLModel rejects that
        # graph when declaring its image input. A zero-weight inner product
        # keeps the tiny model deterministic while making the image input a
        # real part of the network and therefore Vision-loadable.
        builder.add_reduce(
            name="consume_image",
            input_name="image",
            output_name="image_mean",
            axis="CHW",
            mode="avg",
        )
        bias = np.zeros((1800,), dtype=np.float32)
        bias[:6] = [0.20, 0.20, 0.60, 0.60, 0.99, 4.0]
        builder.add_inner_product(
            name="constant_detections",
            W=np.zeros((1800, 1), dtype=np.float32),
            b=bias,
            input_channels=1,
            output_channels=1800,
            has_bias=True,
            input_name="image_mean",
            output_name="flat_predictions",
        )
        builder.add_reshape_static(
            name="shape_detections",
            input_name="flat_predictions",
            output_name="predictions",
            output_shape=(1, 300, 6),
        )
        builder.set_pre_processing_parameters(
            image_input_names=["image"],
            image_scale=1.0 / 255.0,
        )
        spec = builder.spec
        spec.description.metadata.shortDescription = (
            "Money Trainer synthetic Mock detector with one constant jpy_100 result"
        )
        for key, value in metadata.items():
            spec.description.metadata.userDefined[str(key)] = json.dumps(value, ensure_ascii=False)
        spec.description.metadata.userDefined["mock"] = "true"
        spec.description.metadata.userDefined["mock_compilable"] = "true"
        spec.description.metadata.userDefined["mock_output_name"] = "predictions"
        spec.description.metadata.userDefined["mock_output_shape"] = "[1,300,6]"
        spec.description.metadata.userDefined["mock_output_format"] = "normalized_xyxy_confidence_class_id"
        ct.models.MLModel(spec).save(str(package))
        return package.is_dir() and (package / "Manifest.json").is_file()
    except Exception as exc:
        if package.exists():
            shutil.rmtree(package)
        warnings.append(f"synthetic Core ML model generation failed: {type(exc).__name__}: {exc}")
        return False


def _copy_vendored_mock(package: Path, warnings: list[str]) -> bool:
    template = files("money_trainer").joinpath("assets", "MockMoneyDetector.mlpackage")
    try:
        if not template.is_dir():
            warnings.append("vendored Mock Core ML template is missing")
            return False

        def copy_tree(source: Any, destination: Path) -> None:
            destination.mkdir(parents=True, exist_ok=True)
            for child in source.iterdir():
                target = destination / child.name
                if child.is_dir():
                    copy_tree(child, target)
                elif child.is_file():
                    target.write_bytes(child.read_bytes())

        copy_tree(template, package)
        if not (package / "Manifest.json").is_file():
            shutil.rmtree(package)
            warnings.append("vendored Mock Core ML template has no Manifest.json")
            return False
        return True
    except Exception as exc:
        if package.exists():
            shutil.rmtree(package)
        warnings.append(f"vendored Mock Core ML copy failed: {type(exc).__name__}: {exc}")
        return False


def _write_package_placeholder(package: Path, metadata: Mapping[str, Any]) -> None:
    identifier = str(uuid.uuid5(uuid.NAMESPACE_URL, "money-trainer/mock-coreml-placeholder"))
    model_dir = package / "Data" / "com.apple.CoreML"
    model_dir.mkdir(parents=True, exist_ok=False)
    manifest = {
        "fileFormatVersion": "1.0.0",
        "rootModelIdentifier": identifier,
        "itemInfoEntries": {
            identifier: {
                "author": "com.apple.CoreML",
                "description": "NON-COMPILABLE Money Trainer Mock placeholder",
                "name": "model.mlmodel",
                "path": "com.apple.CoreML/model.mlmodel",
            }
        },
    }
    (package / "Manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (model_dir / "model.mlmodel").write_bytes(
        b"MONEY_TRAINER_NON_COMPILABLE_MOCK_PLACEHOLDER\n"
    )
    (package / "MoneyTrainerMock.json").write_text(
        json.dumps(
            {**dict(metadata), "mock": True, "mock_compilable": False},
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


def _embed_metadata_if_available(
    package: Path,
    metadata: Mapping[str, Any],
    warnings: list[str],
) -> None:
    try:
        import coremltools as ct  # type: ignore[import-not-found]
    except ImportError:
        warnings.append("coremltools metadata embedding unavailable; metadata saved as sidecar")
        return
    try:
        model = ct.models.MLModel(str(package))
        model.short_description = "Japanese yen coin detector"
        model.version = str(metadata.get("modelVersion", ""))
        for key, value in metadata.items():
            model.user_defined_metadata[str(key)] = json.dumps(value, ensure_ascii=False)
        rewritten = package.parent / ".MoneyDetector.metadata.mlpackage"
        backup = package.parent / ".MoneyDetector.pre-metadata.mlpackage"
        model.save(str(rewritten))
        package.rename(backup)
        try:
            rewritten.rename(package)
        except Exception:
            backup.rename(package)
            raise
        else:
            shutil.rmtree(backup)
    except Exception as exc:
        rewritten = package.parent / ".MoneyDetector.metadata.mlpackage"
        if rewritten.exists():
            shutil.rmtree(rewritten)
        warnings.append(f"Core ML metadata embedding failed: {type(exc).__name__}: {exc}")


def _zip_package(package: Path, archive: Path) -> None:
    # Fixed timestamps and ordering keep Mock archives byte-for-byte reproducible.
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as stream:
        for source in sorted(path for path in package.rglob("*") if path.is_file()):
            relative = Path(package.name) / source.relative_to(package)
            info = zipfile.ZipInfo(str(relative), date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            stream.writestr(info, source.read_bytes())


def _structural_error(artifact: CoreMLArtifact) -> str | None:
    if not artifact.package_path.is_dir():
        return "Core ML package directory is missing"
    if not (artifact.package_path / "Manifest.json").is_file():
        return "Core ML package Manifest.json is missing"
    if not artifact.archive_path.is_file() or artifact.archive_path.stat().st_size == 0:
        return "Core ML package archive is missing or empty"
    return None


def _detections(result: Any) -> list[tuple[int, tuple[float, float, float, float], float]]:
    boxes = getattr(result, "boxes", None)
    if boxes is None:
        return []
    box_values = _to_list(getattr(boxes, "xywhn", []))
    class_values = _to_list(getattr(boxes, "cls", []))
    confidence_values = _to_list(getattr(boxes, "conf", []))
    return [
        (int(class_name), tuple(float(value) for value in box), float(confidence))
        for class_name, box, confidence in zip(
            class_values, box_values, confidence_values, strict=True
        )
    ]


def _to_list(value: Any) -> list[Any]:
    for method_name in ("detach", "cpu"):
        method = getattr(value, method_name, None)
        if callable(method):
            value = method()
    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        value = tolist()
    return list(value)


def _iou(first: Sequence[float], second: Sequence[float]) -> float:
    def corners(box: Sequence[float]) -> tuple[float, float, float, float]:
        center_x, center_y, width, height = box
        return (
            center_x - width / 2,
            center_y - height / 2,
            center_x + width / 2,
            center_y + height / 2,
        )

    ax1, ay1, ax2, ay2 = corners(first)
    bx1, by1, bx2, by2 = corners(second)
    intersection = max(0.0, min(ax2, bx2) - max(ax1, bx1)) * max(
        0.0, min(ay2, by2) - max(ay1, by1)
    )
    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - intersection
    return intersection / union if union else 0.0
