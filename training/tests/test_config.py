from __future__ import annotations

import tempfile
from pathlib import Path
import unittest

from money_trainer.config import ConfigurationError, load_config
from money_trainer.constants import COIN_CLASSES


class ConfigTests(unittest.TestCase):
    def test_defaults_use_maintained_small_yolo_and_stable_classes(self) -> None:
        config = load_config()
        self.assertEqual(config.model.architecture, "yolo26n.pt")
        self.assertEqual(config.model.image_size, 640)
        self.assertEqual(config.classes, COIN_CLASSES)
        self.assertFalse(config.export.quantize)
        self.assertFalse(config.export.nms)

    def test_partial_yaml_is_merged_without_repeating_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "custom.yaml"
            path.write_text(
                "training:\n  epochs: 3 # quick smoke run\ndataset:\n  train: 0.6\n  validation: 0.2\n  test: 0.2\n",
                encoding="utf-8",
            )
            config = load_config(path)
        self.assertEqual(config.training.epochs, 3)
        self.assertEqual(config.training.batch_size, 16)
        self.assertEqual(config.dataset.ratios, {"train": 0.6, "validation": 0.2, "test": 0.2})

    def test_invalid_ratios_are_rejected(self) -> None:
        with self.assertRaises(ConfigurationError):
            load_config(overrides={"dataset": {"train": 0.8}})


if __name__ == "__main__":
    unittest.main()
