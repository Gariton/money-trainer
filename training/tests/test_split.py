from __future__ import annotations

import tempfile
from pathlib import Path
import unittest

from money_trainer.config import load_config
from money_trainer.constants import COIN_CLASSES
from money_trainer.dataset import Annotation, DatasetImage, DatasetManifest
from money_trainer.mock_data import create_mock_dataset
from money_trainer.split import DatasetSplit, split_by_capture_session
from money_trainer.validation import validate_split


class SplitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        manifest_path = create_mock_dataset(Path(self.temporary.name) / "dataset")
        self.manifest = DatasetManifest.load(manifest_path)
        self.config = load_config()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_split_is_deterministic_and_has_no_capture_session_leakage(self) -> None:
        first = split_by_capture_session(self.manifest, self.config)
        second = split_by_capture_session(self.manifest, self.config)
        self.assertEqual(first.to_mapping(), second.to_mapping())
        first.assert_no_leakage()
        all_sessions = [session for name, _ in first.items() for session in first.sessions(name)]
        self.assertEqual(len(all_sessions), len(set(all_sessions)))
        self.assertEqual(first.image_count, len(self.manifest.images))
        self.assertTrue(validate_split(first, self.config).is_valid)

    def test_images_from_same_session_are_atomic(self) -> None:
        images = list(self.manifest.images)
        first = images[0]
        second = images[1]
        object.__setattr__(second, "capture_session_id", first.capture_session_id)
        split = split_by_capture_session(images, self.config)
        owners = [name for name, group in split.items() if first in group or second in group]
        self.assertEqual(owners, [owners[0]])
        owner = owners[0]
        self.assertIn(first, split[owner])
        self.assertIn(second, split[owner])

    def test_split_validator_detects_manual_leakage(self) -> None:
        image = self.manifest.images[0]
        invalid = DatasetSplit(train=(image,), validation=(), test=(image,))
        report = validate_split(invalid, self.config)
        self.assertIn("capture_session_leakage", {issue.code for issue in report.issues})

    def test_class_coverage_is_reserved_when_feasible(self) -> None:
        images = [
            DatasetImage(
                id=f"{class_name}-{index}",
                image_path=Path(self.temporary.name) / f"{class_name}-{index}.jpg",
                declared_image_path=f"{class_name}-{index}.jpg",
                capture_session_id=f"{class_name}-session-{index}",
                annotations=(Annotation(class_name, 0.1, 0.1, 0.2, 0.2),),
                review_status="reviewed",
            )
            for class_name in COIN_CLASSES
            for index in range(3)
        ]
        split = split_by_capture_session(images, self.config)
        self.assertTrue(validate_split(split, self.config).is_valid)
        for split_name, split_images in split.items():
            present = {
                annotation.class_name
                for image in split_images
                for annotation in image.annotations
            }
            self.assertEqual(present, set(COIN_CLASSES), split_name)


if __name__ == "__main__":
    unittest.main()
