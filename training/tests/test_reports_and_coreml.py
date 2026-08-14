from __future__ import annotations

from types import SimpleNamespace
import json
import tempfile
from pathlib import Path
import unittest

from money_trainer.coreml import compare_detection_batches
from money_trainer.metrics import deterministic_mock_confusion_matrix
from money_trainer.reports import FailureCase, organize_reports


class ReportAndCoreMLTests(unittest.TestCase):
    def test_confused_class_artifact_uses_actual_as_predicted_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "case.jpg"
            image.write_bytes(b"test")
            artifacts = organize_reports(
                root / "reports",
                failures=(
                    FailureCase(
                        "confused-class",
                        image,
                        "case-1",
                        true_class="jpy_50",
                        predicted_class="jpy_100",
                        confidence=0.8,
                    ),
                ),
                confusion_matrix=deterministic_mock_confusion_matrix(),
            )
            copied = artifacts.root / "confused-classes" / "jpy_50_as_jpy_100"
            self.assertEqual(len(list(copied.glob("*.jpg"))), 1)
            manifest = json.loads(artifacts.failure_manifest.read_text(encoding="utf-8"))
            self.assertEqual(manifest["counts"]["confused-class"], 1)
            self.assertTrue(artifacts.confusion_csv and artifacts.confusion_csv.is_file())

    def test_detection_comparison_matches_class_boxes_and_confidence(self) -> None:
        def result(box, confidence):
            return SimpleNamespace(
                boxes=SimpleNamespace(xywhn=[box], cls=[4], conf=[confidence])
            )

        comparison = compare_detection_batches(
            [result([0.5, 0.5, 0.2, 0.2], 0.90)],
            [result([0.505, 0.5, 0.2, 0.2], 0.88)],
        )
        self.assertEqual(comparison.match_rate, 1.0)
        self.assertGreater(comparison.mean_iou, 0.9)
        self.assertAlmostEqual(comparison.mean_confidence_delta, 0.02)


if __name__ == "__main__":
    unittest.main()

