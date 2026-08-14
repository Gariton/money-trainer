"""Confusion-matrix and actionable failure-case artifacts."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import csv
import json
from pathlib import Path
import re
import shutil
from typing import Any, Iterable

from .metrics import ConfusionMatrix


FAILURE_CATEGORIES = {
    "false-positive": "false-positives",
    "false-negative": "false-negatives",
    "low-confidence": "low-confidence",
    "confused-class": "confused-classes",
}


@dataclass(frozen=True, slots=True)
class FailureCase:
    category: str
    image_path: Path
    image_id: str
    true_class: str | None = None
    predicted_class: str | None = None
    confidence: float | None = None
    details: str | None = None

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        value["image_path"] = str(self.image_path)
        return {key: item for key, item in value.items() if item is not None}


@dataclass(frozen=True, slots=True)
class ReportArtifacts:
    root: Path
    failure_manifest: Path
    confusion_json: Path | None
    confusion_csv: Path | None


def organize_reports(
    root: str | Path,
    *,
    failures: Iterable[FailureCase] = (),
    confusion_matrix: ConfusionMatrix | None = None,
) -> ReportArtifacts:
    report_root = Path(root).resolve()
    report_root.mkdir(parents=True, exist_ok=True)
    for directory in FAILURE_CATEGORIES.values():
        (report_root / directory).mkdir(parents=True, exist_ok=True)

    records: list[dict[str, Any]] = []
    for index, failure in enumerate(failures):
        if failure.category not in FAILURE_CATEGORIES:
            raise ValueError(f"unknown failure category: {failure.category}")
        category_dir = report_root / FAILURE_CATEGORIES[failure.category]
        if failure.category == "confused-class":
            true_name = _safe_name(failure.true_class or "unknown")
            predicted_name = _safe_name(failure.predicted_class or "unknown")
            category_dir = category_dir / f"{true_name}_as_{predicted_name}"
            category_dir.mkdir(parents=True, exist_ok=True)
        filename = f"{index:04d}-{_safe_name(failure.image_id)}{failure.image_path.suffix.lower()}"
        destination = category_dir / filename
        if failure.image_path.is_file():
            shutil.copy2(failure.image_path, destination)
            artifact_path: str | None = str(destination.relative_to(report_root))
        else:
            artifact_path = None
        record = failure.to_dict()
        record["artifact"] = artifact_path
        records.append(record)

    failure_manifest = report_root / "failure_manifest.json"
    failure_manifest.write_text(
        json.dumps(
            {"counts": _counts(records), "cases": records},
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    confusion_json: Path | None = None
    confusion_csv: Path | None = None
    if confusion_matrix is not None:
        confusion_json = report_root / "confusion_matrix.json"
        confusion_json.write_text(
            json.dumps(confusion_matrix.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        confusion_csv = report_root / "confusion_matrix.csv"
        with confusion_csv.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["actual\\predicted", *confusion_matrix.labels])
            for label, row in zip(confusion_matrix.labels, confusion_matrix.matrix, strict=True):
                writer.writerow([label, *row])

    return ReportArtifacts(
        root=report_root,
        failure_manifest=failure_manifest,
        confusion_json=confusion_json,
        confusion_csv=confusion_csv,
    )


def _safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("._-") or "unknown"


def _counts(records: list[dict[str, Any]]) -> dict[str, int]:
    return {
        category: sum(record["category"] == category for record in records)
        for category in FAILURE_CATEGORIES
    }

