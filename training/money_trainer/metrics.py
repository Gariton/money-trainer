"""Stable metric schema and Ultralytics result parsing."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import math
from typing import Any, Iterable, Mapping, Sequence

from .constants import COIN_CLASSES


class MetricsParseError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class ClassMetrics:
    precision: float
    recall: float
    ap: float
    ap50: float | None = None

    def to_dict(self) -> dict[str, float]:
        result = {
            "precision": self.precision,
            "recall": self.recall,
            "AP": self.ap,
        }
        if self.ap50 is not None:
            result["AP50"] = self.ap50
        return result


@dataclass(frozen=True, slots=True)
class EvaluationMetrics:
    map50: float
    map50_95: float
    precision: float
    recall: float
    per_class: Mapping[str, ClassMetrics]

    def validate(self) -> None:
        values = [self.map50, self.map50_95, self.precision, self.recall]
        for metrics in self.per_class.values():
            values.extend([metrics.precision, metrics.recall, metrics.ap])
            if metrics.ap50 is not None:
                values.append(metrics.ap50)
        if not all(math.isfinite(value) and 0 <= value <= 1 for value in values):
            raise MetricsParseError("all evaluation metrics must be finite values between 0 and 1")

    def to_dict(self) -> dict[str, Any]:
        self.validate()
        return {
            "mAP50": self.map50,
            "mAP50-95": self.map50_95,
            "precision": self.precision,
            "recall": self.recall,
            "perClass": {
                class_name: class_metrics.to_dict()
                for class_name, class_metrics in self.per_class.items()
            },
        }

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "EvaluationMetrics":
        raw_per_class = value.get("perClass", value.get("per_class", {}))
        if not isinstance(raw_per_class, Mapping):
            raise MetricsParseError("perClass must be an object")
        per_class = {
            str(name): ClassMetrics(
                precision=_float(metrics, "precision"),
                recall=_float(metrics, "recall"),
                ap=_float(metrics, "AP", "ap", "mAP50-95"),
                ap50=_optional_float(metrics, "AP50", "ap50"),
            )
            for name, metrics in raw_per_class.items()
            if isinstance(metrics, Mapping)
        }
        result = cls(
            map50=_float(value, "mAP50", "map50"),
            map50_95=_float(value, "mAP50-95", "mAP50_95", "map50_95", "map"),
            precision=_float(value, "precision"),
            recall=_float(value, "recall"),
            per_class=per_class,
        )
        result.validate()
        return result


@dataclass(frozen=True, slots=True)
class ConfusionMatrix:
    labels: tuple[str, ...]
    matrix: tuple[tuple[float, ...], ...]

    def to_dict(self) -> dict[str, Any]:
        return {"labels": list(self.labels), "matrix": [list(row) for row in self.matrix]}


def parse_ultralytics_metrics(
    result: Any,
    *,
    class_names: Iterable[str] = COIN_CLASSES,
) -> EvaluationMetrics:
    """Parse current DetMetrics objects while tolerating dictionary fixtures."""

    names = _resolve_names(result, tuple(class_names))
    box = getattr(result, "box", None)
    if box is not None:
        precision_values = _sequence(getattr(box, "p", None))
        recall_values = _sequence(getattr(box, "r", None))
        ap_values = _sequence(getattr(box, "maps", None))
        ap50_values = _sequence(getattr(box, "ap50", None))
        per_class = _per_class_metrics(
            names,
            precision_values,
            recall_values,
            ap_values,
            ap50_values,
        )
        metrics = EvaluationMetrics(
            map50=_number(getattr(box, "map50", None), "box.map50"),
            map50_95=_number(getattr(box, "map", None), "box.map"),
            precision=_number(getattr(box, "mp", None), "box.mp"),
            recall=_number(getattr(box, "mr", None), "box.mr"),
            per_class=per_class,
        )
        metrics.validate()
        return metrics

    if isinstance(result, Mapping):
        result_dict = result.get("results_dict", result)
    else:
        result_dict = getattr(result, "results_dict", None)
    if not isinstance(result_dict, Mapping):
        raise MetricsParseError("unsupported Ultralytics metrics result")

    raw_per_class = result_dict.get("perClass", result_dict.get("per_class", {}))
    per_class: dict[str, ClassMetrics] = {}
    if isinstance(raw_per_class, Mapping):
        for name, raw_metrics in raw_per_class.items():
            if not isinstance(raw_metrics, Mapping):
                continue
            per_class[str(name)] = ClassMetrics(
                precision=_float(raw_metrics, "precision", "p"),
                recall=_float(raw_metrics, "recall", "r"),
                ap=_float(raw_metrics, "AP", "ap", "mAP50-95", "map"),
                ap50=_optional_float(raw_metrics, "AP50", "ap50", "mAP50"),
            )
    metrics = EvaluationMetrics(
        map50=_float(result_dict, "metrics/mAP50(B)", "mAP50", "map50"),
        map50_95=_float(
            result_dict,
            "metrics/mAP50-95(B)",
            "mAP50-95",
            "mAP50_95",
            "map50_95",
            "map",
        ),
        precision=_float(result_dict, "metrics/precision(B)", "precision", "mp"),
        recall=_float(result_dict, "metrics/recall(B)", "recall", "mr"),
        per_class=per_class,
    )
    metrics.validate()
    return metrics


def parse_ultralytics_confusion_matrix(
    result: Any,
    *,
    class_names: Iterable[str] = COIN_CLASSES,
) -> ConfusionMatrix | None:
    confusion = getattr(result, "confusion_matrix", None)
    raw_matrix = getattr(confusion, "matrix", None)
    if raw_matrix is None and isinstance(result, Mapping):
        raw_matrix = result.get("confusion_matrix", result.get("confusionMatrix"))
    if isinstance(raw_matrix, Mapping):
        raw_matrix = raw_matrix.get("matrix")
    rows = _matrix(raw_matrix)
    if not rows:
        return None
    base_labels = list(_resolve_names(result, tuple(class_names)))
    if len(rows) == len(base_labels) + 1:
        base_labels.append("background")
    elif len(rows) != len(base_labels):
        base_labels = [str(index) for index in range(len(rows))]
    return ConfusionMatrix(tuple(base_labels), tuple(tuple(row) for row in rows))


def deterministic_mock_metrics(
    class_names: Iterable[str] = COIN_CLASSES,
) -> EvaluationMetrics:
    per_class: dict[str, ClassMetrics] = {}
    for index, name in enumerate(class_names):
        per_class[name] = ClassMetrics(
            precision=round(0.91 + index * 0.008, 4),
            recall=round(0.89 + index * 0.009, 4),
            ap=round(0.87 + index * 0.012, 4),
            ap50=round(0.93 + index * 0.008, 4),
        )
    return EvaluationMetrics(
        map50=0.951,
        map50_95=0.902,
        precision=0.934,
        recall=0.913,
        per_class=per_class,
    )


def deterministic_mock_confusion_matrix(
    class_names: Iterable[str] = COIN_CLASSES,
) -> ConfusionMatrix:
    names = tuple(class_names) + ("background",)
    rows = []
    for row in range(len(names)):
        rows.append(tuple(float(20 + row) if row == column else 0.0 for column in range(len(names))))
    return ConfusionMatrix(names, tuple(rows))


def _resolve_names(result: Any, fallback: tuple[str, ...]) -> tuple[str, ...]:
    raw_names = getattr(result, "names", None)
    if raw_names is None and isinstance(result, Mapping):
        raw_names = result.get("names")
    if isinstance(raw_names, Mapping):
        try:
            return tuple(str(raw_names[index]) for index in sorted(raw_names, key=int))
        except (KeyError, TypeError, ValueError):
            return tuple(str(value) for _, value in sorted(raw_names.items(), key=lambda item: str(item[0])))
    if isinstance(raw_names, Sequence) and not isinstance(raw_names, (str, bytes)):
        return tuple(str(name) for name in raw_names)
    return fallback


def _per_class_metrics(
    names: tuple[str, ...],
    precision: list[float],
    recall: list[float],
    ap: list[float],
    ap50: list[float],
) -> dict[str, ClassMetrics]:
    count = min(len(names), len(precision), len(recall), len(ap))
    result: dict[str, ClassMetrics] = {}
    for index in range(count):
        result[names[index]] = ClassMetrics(
            precision=precision[index],
            recall=recall[index],
            ap=ap[index],
            ap50=ap50[index] if index < len(ap50) else None,
        )
    return result


def _sequence(value: Any) -> list[float]:
    if value is None:
        return []
    for method_name in ("detach", "cpu"):
        method = getattr(value, method_name, None)
        if callable(method):
            value = method()
    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        value = tolist()
    if isinstance(value, (int, float)):
        return [float(value)]
    if isinstance(value, Sequence):
        flattened: list[float] = []
        for item in value:
            if isinstance(item, Sequence) and not isinstance(item, (str, bytes)):
                flattened.extend(float(nested) for nested in item)
            else:
                flattened.append(float(item))
        return flattened
    return []


def _matrix(value: Any) -> list[list[float]]:
    if value is None:
        return []
    for method_name in ("detach", "cpu"):
        method = getattr(value, method_name, None)
        if callable(method):
            value = method()
    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        value = tolist()
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return []
    rows = [[float(cell) for cell in row] for row in value if isinstance(row, Sequence)]
    if rows and any(len(row) != len(rows) for row in rows):
        raise MetricsParseError("confusion matrix must be square")
    return rows


def _float(value: Mapping[str, Any], *keys: str) -> float:
    for key in keys:
        if key in value:
            return _number(value[key], key)
    raise MetricsParseError(f"missing metric; expected one of {keys}")


def _optional_float(value: Mapping[str, Any], *keys: str) -> float | None:
    for key in keys:
        if key in value:
            return _number(value[key], key)
    return None


def _number(value: Any, label: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise MetricsParseError(f"{label} must be numeric") from exc
    if not math.isfinite(result):
        raise MetricsParseError(f"{label} must be finite")
    return result

