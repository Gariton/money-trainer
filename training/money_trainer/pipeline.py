"""End-to-end validation, training, evaluation, and Core ML artifact pipeline."""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime, timezone
from enum import Enum
import json
from pathlib import Path
import re
from typing import Any, Callable

from .backend import ModelBackend, create_backend
from .config import AppConfig, RuntimeConfig, dump_yaml, load_config
from .coreml import (
    CoreMLArtifact,
    CoreMLExporter,
    CoreMLValidationResult,
    CoreMLValidator,
    create_coreml_components,
)
from .dataset import DatasetManifest
from .metrics import EvaluationMetrics
from .mock_data import create_mock_dataset
from .reports import organize_reports
from .split import DatasetSplit, split_by_capture_session
from .validation import combine_reports, validate_dataset, validate_split
from .yolo import YoloDataset, generate_yolo_dataset


class PipelineStage(str, Enum):
    VALIDATING = "validating"
    SPLITTING = "splitting"
    GENERATING = "generating"
    TRAINING = "training"
    EVALUATING = "evaluating"
    EXPORTING_COREML = "exporting_coreml"
    VALIDATING_COREML = "validating_coreml"
    SAVING_ARTIFACTS = "saving_artifacts"
    COMPLETED = "completed"


@dataclass(frozen=True, slots=True)
class PipelineEvent:
    stage: PipelineStage
    progress: float
    stage_progress: float
    message: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "stage": self.stage.value,
            "progress": self.progress,
            "stageProgress": self.stage_progress,
            "message": self.message,
        }


ProgressCallback = Callable[[PipelineEvent], None]


@dataclass(frozen=True, slots=True)
class PipelineResult:
    model_version: str
    dataset_version: str
    artifact_dir: Path
    checkpoint_path: Path
    coreml_package_path: Path
    coreml_archive_path: Path
    metrics_path: Path
    reports_dir: Path
    split_manifest_path: Path
    run_manifest_path: Path
    mock_mode: bool
    backend_name: str
    metrics: EvaluationMetrics
    coreml_validation: CoreMLValidationResult

    def to_dict(self) -> dict[str, Any]:
        return {
            "modelVersion": self.model_version,
            "datasetVersion": self.dataset_version,
            "artifactDir": str(self.artifact_dir),
            "checkpoint": str(self.checkpoint_path),
            "coreMLModel": str(self.coreml_package_path),
            "coreMLArchive": str(self.coreml_archive_path),
            "metricsPath": str(self.metrics_path),
            "reportsDir": str(self.reports_dir),
            "splitManifest": str(self.split_manifest_path),
            "runManifest": str(self.run_manifest_path),
            "mockMode": self.mock_mode,
            "backend": self.backend_name,
            "metrics": self.metrics.to_dict(),
            "coreMLValidation": self.coreml_validation.to_dict(),
        }


class TrainingPipeline:
    def __init__(
        self,
        config: AppConfig,
        *,
        backend: ModelBackend | None = None,
        exporter: CoreMLExporter | None = None,
        validator: CoreMLValidator | None = None,
    ) -> None:
        self.config = config
        self.backend = backend or create_backend(mock_mode=config.runtime.mock_mode)
        default_exporter, default_validator = create_coreml_components(
            mock_mode=config.runtime.mock_mode
        )
        self.exporter = exporter or default_exporter
        self.validator = validator or default_validator

    def run(
        self,
        dataset_path: str | Path,
        output_dir: str | Path,
        *,
        model_version: str = "v1",
        dataset_version: str | None = None,
        progress_callback: ProgressCallback | None = None,
    ) -> PipelineResult:
        _validate_version(model_version)
        artifact_root = Path(output_dir).expanduser().resolve() / model_version
        if artifact_root.exists() and any(artifact_root.iterdir()):
            raise FileExistsError(f"model artifact directory is not empty: {artifact_root}")
        artifact_root.mkdir(parents=True, exist_ok=True)
        (artifact_root / "training_config.yaml").write_text(
            dump_yaml(self.config.to_dict()), encoding="utf-8"
        )

        supplied_dataset = Path(dataset_path).expanduser()
        if not supplied_dataset.exists() and self.config.runtime.mock_mode:
            manifest_path = create_mock_dataset(artifact_root / "mock_dataset")
        else:
            manifest_path = supplied_dataset
        manifest = DatasetManifest.load(manifest_path)
        effective_dataset_version = dataset_version or manifest.dataset_version

        self._emit(
            progress_callback,
            PipelineStage.VALIDATING,
            0.02,
            0.0,
            "Validating dataset records and normalized boxes",
        )
        dataset_report = validate_dataset(manifest, self.config, classes=self.config.classes)
        validation_path = artifact_root / "dataset_validation.json"
        validation_path.write_text(
            json.dumps(dataset_report.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        dataset_report.raise_if_invalid()
        self._emit(
            progress_callback,
            PipelineStage.SPLITTING,
            0.08,
            0.0,
            "Assigning complete capture sessions to train/validation/test",
        )
        split = split_by_capture_session(manifest, self.config)
        split_report = validate_split(split, self.config, classes=self.config.classes)
        combined_report = combine_reports(dataset_report, split_report)
        validation_path.write_text(
            json.dumps(combined_report.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        combined_report.raise_if_invalid()
        split_manifest_path = artifact_root / "splits.json"
        split_manifest_path.write_text(
            json.dumps(split.to_mapping(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self._emit(
            progress_callback,
            PipelineStage.GENERATING,
            0.12,
            0.0,
            "Generating YOLO image and label directories",
        )
        yolo_dataset = generate_yolo_dataset(
            split,
            artifact_root / "yolo_dataset",
            self.config,
            classes=self.config.classes,
        )
        self._emit(
            progress_callback,
            PipelineStage.TRAINING,
            0.18,
            0.0,
            f"Training with {self.backend.name}",
        )

        def epoch_progress(fraction: float) -> None:
            bounded = max(0.0, min(fraction, 1.0))
            self._emit(
                progress_callback,
                PipelineStage.TRAINING,
                0.18 + bounded * 0.56,
                bounded,
                f"Training {bounded:.0%}",
            )

        training = self.backend.train(
            yolo_dataset,
            artifact_root,
            self.config,
            on_progress=epoch_progress,
        )
        self._emit(
            progress_callback,
            PipelineStage.EVALUATING,
            0.76,
            0.0,
            "Evaluating the selected best checkpoint on the test split",
        )
        evaluation = self.backend.evaluate(
            training.checkpoint,
            yolo_dataset,
            artifact_root,
            self.config,
        )
        metrics_path = artifact_root / "metrics.json"
        metrics_path.write_text(
            json.dumps(evaluation.metrics.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        report_artifacts = organize_reports(
            artifact_root / "reports",
            failures=evaluation.failures,
            confusion_matrix=evaluation.confusion_matrix,
        )
        self._emit(
            progress_callback,
            PipelineStage.EXPORTING_COREML,
            0.84,
            0.0,
            "Exporting MoneyDetector.mlpackage",
        )
        created_at = datetime.now(timezone.utc).isoformat()
        export_metadata = {
            "modelVersion": model_version,
            "classes": list(self.config.classes),
            "trainingDate": created_at,
            "datasetVersion": effective_dataset_version,
        }
        coreml_artifact = self.exporter.export(
            training.checkpoint,
            artifact_root,
            export_metadata,
            self.config,
        )
        self._emit(
            progress_callback,
            PipelineStage.VALIDATING_COREML,
            0.93,
            0.0,
            "Validating Core ML structure and numerical fidelity when supported",
        )
        test_images = sorted((yolo_dataset.root / "images" / "test").glob("*"))
        coreml_validation = self.validator.validate(
            training.checkpoint,
            coreml_artifact,
            test_images,
            self.config,
        )
        coreml_validation_path = artifact_root / "coreml_validation.json"
        coreml_validation_path.write_text(
            json.dumps(coreml_validation.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if not coreml_validation.valid:
            raise RuntimeError(
                "Core ML validation failed; see " + str(coreml_validation_path)
            )
        self._emit(
            progress_callback,
            PipelineStage.SAVING_ARTIFACTS,
            0.98,
            0.0,
            "Saving version manifest",
        )
        run_manifest_path = artifact_root / "model.json"
        run_manifest = {
            "modelVersion": model_version,
            "createdAt": created_at,
            "datasetVersion": effective_dataset_version,
            "trainingConfig": self.config.to_dict(),
            "metrics": evaluation.metrics.to_dict(),
            "checkpoint": str(training.checkpoint),
            "coreMLModel": str(coreml_artifact.package_path),
            "coreMLArchive": str(coreml_artifact.archive_path),
            "coreMLValidation": coreml_validation.to_dict(),
            "reports": str(report_artifacts.root),
            "splitManifest": str(split_manifest_path),
            "backend": training.backend_name,
            "mockMode": self.config.runtime.mock_mode,
            "warnings": [
                *evaluation.warnings,
                *coreml_artifact.warnings,
                *coreml_validation.warnings,
            ],
        }
        run_manifest_path.write_text(
            json.dumps(run_manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        result = PipelineResult(
            model_version=model_version,
            dataset_version=effective_dataset_version,
            artifact_dir=artifact_root,
            checkpoint_path=training.checkpoint,
            coreml_package_path=coreml_artifact.package_path,
            coreml_archive_path=coreml_artifact.archive_path,
            metrics_path=metrics_path,
            reports_dir=report_artifacts.root,
            split_manifest_path=split_manifest_path,
            run_manifest_path=run_manifest_path,
            mock_mode=self.config.runtime.mock_mode,
            backend_name=training.backend_name,
            metrics=evaluation.metrics,
            coreml_validation=coreml_validation,
        )
        self._emit(
            progress_callback,
            PipelineStage.COMPLETED,
            1.0,
            1.0,
            "Training pipeline completed",
        )
        return result

    @staticmethod
    def _emit(
        callback: ProgressCallback | None,
        stage: PipelineStage,
        progress: float,
        stage_progress: float,
        message: str,
    ) -> None:
        if callback is not None:
            callback(
                PipelineEvent(
                    stage=stage,
                    progress=max(0.0, min(progress, 1.0)),
                    stage_progress=max(0.0, min(stage_progress, 1.0)),
                    message=message,
                )
            )


def run_training(
    dataset_path: str | Path,
    output_dir: str | Path,
    *,
    config_path: str | Path | None = None,
    mock: bool | None = None,
    model_version: str = "v1",
    dataset_version: str | None = None,
    progress_callback: ProgressCallback | None = None,
) -> PipelineResult:
    """Server-worker friendly one-call API."""

    config = load_config(config_path)
    if mock is not None:
        config = replace(config, runtime=RuntimeConfig(mock_mode=mock))
    return TrainingPipeline(config).run(
        dataset_path,
        output_dir,
        model_version=model_version,
        dataset_version=dataset_version,
        progress_callback=progress_callback,
    )


def _validate_version(value: str) -> None:
    if not value or value in {".", ".."} or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value):
        raise ValueError("model_version must be a safe path component")

