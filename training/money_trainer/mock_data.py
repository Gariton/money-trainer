"""Tiny deterministic non-coin dataset for dependency-free vertical-slice tests."""

from __future__ import annotations

import base64
import json
from pathlib import Path

from .constants import COIN_CLASSES


# A valid 1x1 transparent PNG. It deliberately contains no coin imagery.
_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/"
    "RAXitwAAAABJRU5ErkJggg=="
)


def create_mock_dataset(root: str | Path, *, session_count: int = 20) -> Path:
    destination = Path(root).resolve()
    if destination.exists() and any(destination.iterdir()):
        raise FileExistsError(f"mock dataset directory is not empty: {destination}")
    images_dir = destination / "images"
    images_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for index in range(session_count):
        filename = f"mock-{index:03d}.png"
        (images_dir / filename).write_bytes(_PNG)
        annotations = [
            {
                "class": class_name,
                "x": round(0.025 + class_index * 0.16, 6),
                "y": round(0.15 + (index % 3) * 0.20, 6),
                "width": 0.10,
                "height": 0.10,
            }
            for class_index, class_name in enumerate(COIN_CLASSES)
        ]
        records.append(
            {
                "id": f"mock-{index:03d}",
                "image": f"images/{filename}",
                "source": "mock",
                "captureSessionId": f"mock-session-{index:03d}",
                "reviewStatus": "reviewed",
                "annotations": annotations,
            }
        )
    manifest = destination / "manifest.json"
    manifest.write_text(
        json.dumps(
            {"datasetVersion": "mock-v1", "mock": True, "images": records},
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return manifest

