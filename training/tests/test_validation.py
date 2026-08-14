from __future__ import annotations

import json
import math
import tempfile
from pathlib import Path
import unittest

from money_trainer.config import load_config
from money_trainer.dataset import DatasetManifest
from money_trainer.mock_data import create_mock_dataset
from money_trainer.validation import validate_dataset


class DatasetValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "dataset"
        self.manifest_path = create_mock_dataset(self.root)
        self.config = load_config(overrides={"runtime": {"mock_mode": True}})

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_valid_dataset(self) -> None:
        report = validate_dataset(DatasetManifest.load(self.manifest_path), self.config)
        self.assertTrue(report.is_valid, report.to_dict())

    def test_top_left_box_must_remain_inside_image(self) -> None:
        value = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        value["images"][0]["annotations"][0].update(x=0.95, width=0.10)
        self.manifest_path.write_text(json.dumps(value), encoding="utf-8")
        report = validate_dataset(DatasetManifest.load(self.manifest_path), self.config)
        codes = {issue.code for issue in report.issues}
        self.assertIn("bbox_out_of_bounds", codes)

    def test_non_finite_zero_size_unknown_class_and_session_are_reported(self) -> None:
        value = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        image = value["images"][0]
        image["captureSessionId"] = ""
        image["annotations"][0]["x"] = math.nan
        image["annotations"][1]["width"] = 0
        image["annotations"][2]["class"] = "usd_quarter"
        image["annotations"][3]["confidence"] = 1.1
        self.manifest_path.write_text(json.dumps(value, allow_nan=True), encoding="utf-8")
        report = validate_dataset(DatasetManifest.load(self.manifest_path), self.config)
        codes = {issue.code for issue in report.issues}
        self.assertTrue(
            {
                "missing_capture_session_id",
                "bbox_not_finite",
                "bbox_invalid_size",
                "unknown_class",
                "confidence_out_of_range",
            }
            <= codes
        )

    def test_unreviewed_and_missing_image_are_reported(self) -> None:
        value = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        value["images"][0]["reviewStatus"] = "needs_review"
        value["images"][1]["image"] = "images/no-such.png"
        self.manifest_path.write_text(json.dumps(value), encoding="utf-8")
        report = validate_dataset(DatasetManifest.load(self.manifest_path), self.config)
        codes = {issue.code for issue in report.issues}
        self.assertIn("image_not_reviewed", codes)
        self.assertIn("image_not_found", codes)


if __name__ == "__main__":
    unittest.main()
