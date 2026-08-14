from __future__ import annotations

import json
import tempfile
from pathlib import Path
import unittest
import zipfile

from money_trainer.config import load_config
from money_trainer.coreml import MockCoreMLExporter, MockCoreMLValidator
from money_trainer.pipeline import PipelineStage, TrainingPipeline


class CoreMLExportTests(unittest.TestCase):
    def test_mock_export_is_downloadable_and_transparent_about_compilability(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkpoint = root / "best.mock.pt"
            checkpoint.write_text("mock", encoding="utf-8")
            config = load_config(overrides={"runtime": {"mock_mode": True}})
            artifact = MockCoreMLExporter().export(
                checkpoint,
                root / "artifact",
                {
                    "modelVersion": "v1",
                    "classes": list(config.classes),
                    "trainingDate": "2026-08-14T00:00:00Z",
                    "datasetVersion": "mock-v1",
                },
                config,
            )
            metadata = json.loads(artifact.metadata_path.read_text(encoding="utf-8"))
            self.assertTrue(artifact.package_path.is_dir())
            self.assertTrue(artifact.mock_compilable)
            self.assertTrue((artifact.package_path / "Manifest.json").is_file())
            self.assertEqual(metadata["mockCompilable"], artifact.mock_compilable)
            self.assertEqual(metadata["mockOutputShape"], [1, 300, 6])
            with zipfile.ZipFile(artifact.archive_path) as archive:
                self.assertIn("MoneyDetector.mlpackage/Manifest.json", archive.namelist())
            second = MockCoreMLExporter().export(
                checkpoint,
                root / "artifact-2",
                {
                    "modelVersion": "v1",
                    "classes": list(config.classes),
                    "trainingDate": "2026-08-14T00:00:00Z",
                    "datasetVersion": "mock-v1",
                },
                config,
            )
            self.assertEqual(
                artifact.archive_path.read_bytes(), second.archive_path.read_bytes()
            )
            result = MockCoreMLValidator().validate(checkpoint, artifact, [], config)
            self.assertTrue(result.valid)
            self.assertFalse(result.numerical_validation_performed)
            self.assertIn("mock", result.mode)

    def test_complete_mock_pipeline_writes_versioned_contract_and_progress(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = load_config(overrides={"runtime": {"mock_mode": True}})
            events = []
            result = TrainingPipeline(config).run(
                root / "missing-dataset",
                root / "models",
                model_version="v7",
                dataset_version="dataset-7",
                progress_callback=events.append,
            )
            self.assertEqual(result.model_version, "v7")
            self.assertEqual(result.dataset_version, "dataset-7")
            self.assertTrue(result.coreml_package_path.is_dir())
            self.assertTrue(result.coreml_archive_path.is_file())
            self.assertTrue(result.metrics_path.is_file())
            self.assertTrue((result.reports_dir / "confusion_matrix.json").is_file())
            self.assertTrue((result.reports_dir / "failure_manifest.json").is_file())
            self.assertTrue((result.artifact_dir / "yolo_dataset" / "data.yaml").is_file())
            self.assertEqual(events[-1].stage, PipelineStage.COMPLETED)
            self.assertEqual(events[-1].progress, 1.0)
            self.assertEqual(result.metrics.to_dict()["mAP50"], 0.951)
            model_record = json.loads(result.run_manifest_path.read_text(encoding="utf-8"))
            self.assertTrue(model_record["mockMode"])
            self.assertFalse(model_record["coreMLValidation"]["numericalValidationPerformed"])


if __name__ == "__main__":
    unittest.main()
