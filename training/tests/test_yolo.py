from __future__ import annotations

import json
import tempfile
from pathlib import Path
import unittest

from money_trainer.config import load_config
from money_trainer.dataset import DatasetManifest
from money_trainer.mock_data import create_mock_dataset
from money_trainer.split import split_by_capture_session
from money_trainer.yolo import generate_yolo_dataset


class YoloGenerationTests(unittest.TestCase):
    def test_generates_labels_and_converts_top_left_to_center(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = DatasetManifest.load(create_mock_dataset(root / "source"))
            config = load_config()
            split = split_by_capture_session(manifest, config)
            generated = generate_yolo_dataset(split, root / "yolo", config)
            record = json.loads(generated.generation_manifest.read_text(encoding="utf-8"))["images"][0]
            line = (generated.root / record["label"]).read_text(encoding="utf-8").splitlines()[0]
            class_index, center_x, center_y, width, height = line.split()
            source_image = next(image for image in manifest.images if image.id == record["imageId"])
            source_box = source_image.annotations[0]
            self.assertEqual(int(class_index), 0)
            self.assertAlmostEqual(float(center_x), source_box.x + source_box.width / 2)
            self.assertAlmostEqual(float(center_y), source_box.y + source_box.height / 2)
            self.assertAlmostEqual(float(width), source_box.width)
            self.assertAlmostEqual(float(height), source_box.height)
            self.assertEqual(generated.image_count, 20)
            self.assertEqual(generated.annotation_count, 120)
            data_yaml = generated.data_yaml.read_text(encoding="utf-8")
            self.assertIn("val: images/validation", data_yaml)
            self.assertIn("0: jpy_1", data_yaml)
            self.assertIn("5: jpy_500", data_yaml)


if __name__ == "__main__":
    unittest.main()

