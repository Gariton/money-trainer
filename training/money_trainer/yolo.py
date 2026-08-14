"""Generate a conventional Ultralytics/YOLO dataset tree."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
from typing import Any, Iterable

from .config import AppConfig, DatasetConfig
from .constants import CLASS_TO_INDEX, COIN_CLASSES
from .dataset import DatasetImage
from .split import DatasetSplit


@dataclass(frozen=True, slots=True)
class YoloDataset:
    root: Path
    data_yaml: Path
    generation_manifest: Path
    image_count: int
    annotation_count: int


def generate_yolo_dataset(
    split: DatasetSplit,
    output_dir: str | Path,
    config: AppConfig | DatasetConfig,
    *,
    classes: Iterable[str] = COIN_CLASSES,
) -> YoloDataset:
    output = Path(output_dir).resolve()
    if output.exists() and any(output.iterdir()):
        raise FileExistsError(f"YOLO output directory is not empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    dataset_config = config.dataset if isinstance(config, AppConfig) else config
    class_names = tuple(classes)
    class_to_index = {name: index for index, name in enumerate(class_names)}
    if class_names == COIN_CLASSES and class_to_index != CLASS_TO_INDEX:
        raise AssertionError("class index contract changed unexpectedly")

    records: list[dict[str, Any]] = []
    annotation_count = 0
    used_names: set[str] = set()
    for split_name, images in split.items():
        images_dir = output / "images" / split_name
        labels_dir = output / "labels" / split_name
        images_dir.mkdir(parents=True, exist_ok=True)
        labels_dir.mkdir(parents=True, exist_ok=True)
        for image in images:
            filename = _destination_filename(image, used_names)
            used_names.add(filename)
            destination = images_dir / filename
            _materialize_image(image.image_path, destination, dataset_config.copy_mode)
            label_path = labels_dir / f"{Path(filename).stem}.txt"
            lines: list[str] = []
            for annotation in image.annotations:
                if annotation.class_name not in class_to_index:
                    raise ValueError(f"cannot serialize unknown class {annotation.class_name!r}")
                center_x, center_y, width, height = annotation.yolo_box
                lines.append(
                    f"{class_to_index[annotation.class_name]} "
                    f"{center_x:.10f} {center_y:.10f} {width:.10f} {height:.10f}"
                )
                annotation_count += 1
            label_path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
            records.append(
                {
                    "imageId": image.id,
                    "captureSessionId": image.capture_session_id,
                    "split": split_name,
                    "source": str(image.image_path),
                    "image": str(destination.relative_to(output)),
                    "label": str(label_path.relative_to(output)),
                    "annotationCount": len(image.annotations),
                }
            )

    data_yaml = output / "data.yaml"
    data_yaml.write_text(_data_yaml(output, class_names), encoding="utf-8")
    generation_manifest = output / "generation_manifest.json"
    generation_manifest.write_text(
        json.dumps(
            {
                "coordinateConvention": "manifest x/y are normalized top-left; YOLO x/y are centers",
                "classes": list(class_names),
                "images": records,
            },
            indent=2,
            ensure_ascii=False,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return YoloDataset(
        root=output,
        data_yaml=data_yaml,
        generation_manifest=generation_manifest,
        image_count=len(records),
        annotation_count=annotation_count,
    )


def _destination_filename(image: DatasetImage, used_names: set[str]) -> str:
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", image.id).strip("._-") or "image"
    suffix = image.image_path.suffix.lower() or ".jpg"
    filename = f"{stem}{suffix}"
    if filename in used_names:
        digest = hashlib.sha256(image.id.encode()).hexdigest()[:10]
        filename = f"{stem}-{digest}{suffix}"
    return filename


def _materialize_image(source: Path, destination: Path, mode: str) -> None:
    if mode == "copy":
        shutil.copy2(source, destination)
    elif mode == "hardlink":
        os.link(source, destination)
    elif mode == "symlink":
        destination.symlink_to(os.path.relpath(source, destination.parent))
    else:
        raise ValueError(f"unsupported copy mode: {mode}")


def _data_yaml(root: Path, classes: tuple[str, ...]) -> str:
    lines = [
        f"path: {json.dumps(str(root))}",
        "train: images/train",
        "val: images/validation",
        "test: images/test",
        "names:",
    ]
    lines.extend(f"  {index}: {name}" for index, name in enumerate(classes))
    return "\n".join(lines) + "\n"

