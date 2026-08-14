from __future__ import annotations

from types import SimpleNamespace
import unittest

from money_trainer.constants import COIN_CLASSES
from money_trainer.metrics import (
    MetricsParseError,
    parse_ultralytics_confusion_matrix,
    parse_ultralytics_metrics,
)


class MetricsTests(unittest.TestCase):
    def test_parses_ultralytics_object_metrics(self) -> None:
        box = SimpleNamespace(
            mp=0.90,
            mr=0.80,
            map50=0.95,
            map=0.72,
            p=[0.80] * 6,
            r=[0.70] * 6,
            maps=[0.60] * 6,
            ap50=[0.90] * 6,
        )
        result = SimpleNamespace(box=box, names={index: name for index, name in enumerate(COIN_CLASSES)})
        metrics = parse_ultralytics_metrics(result)
        self.assertEqual(metrics.map50, 0.95)
        self.assertEqual(metrics.map50_95, 0.72)
        self.assertEqual(metrics.per_class["jpy_100"].ap, 0.60)
        self.assertEqual(metrics.to_dict()["perClass"]["jpy_1"]["AP50"], 0.90)

    def test_parses_flat_results_dict(self) -> None:
        metrics = parse_ultralytics_metrics(
            {
                "metrics/precision(B)": 0.8,
                "metrics/recall(B)": 0.7,
                "metrics/mAP50(B)": 0.9,
                "metrics/mAP50-95(B)": 0.6,
            }
        )
        self.assertEqual(metrics.precision, 0.8)
        self.assertEqual(metrics.per_class, {})

    def test_out_of_range_metric_is_rejected(self) -> None:
        with self.assertRaises(MetricsParseError):
            parse_ultralytics_metrics(
                {"precision": 1.2, "recall": 0.7, "mAP50": 0.9, "mAP50-95": 0.6}
            )

    def test_confusion_matrix_gets_background_label(self) -> None:
        matrix = [[1 if row == column else 0 for column in range(7)] for row in range(7)]
        result = SimpleNamespace(
            confusion_matrix=SimpleNamespace(matrix=matrix),
            names={index: name for index, name in enumerate(COIN_CLASSES)},
        )
        parsed = parse_ultralytics_confusion_matrix(result)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.labels[-1], "background")


if __name__ == "__main__":
    unittest.main()

