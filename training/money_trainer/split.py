"""Deterministic capture-session grouped dataset splitting."""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
from typing import Iterable, Iterator

from .config import AppConfig, DatasetConfig
from .constants import COIN_CLASSES
from .dataset import DatasetImage, DatasetManifest


SPLIT_NAMES: tuple[str, ...] = ("train", "validation", "test")


@dataclass(frozen=True, slots=True)
class DatasetSplit:
    train: tuple[DatasetImage, ...]
    validation: tuple[DatasetImage, ...]
    test: tuple[DatasetImage, ...]

    def items(self) -> Iterator[tuple[str, tuple[DatasetImage, ...]]]:
        yield "train", self.train
        yield "validation", self.validation
        yield "test", self.test

    def __getitem__(self, name: str) -> tuple[DatasetImage, ...]:
        if name not in SPLIT_NAMES:
            raise KeyError(name)
        return getattr(self, name)

    @property
    def image_count(self) -> int:
        return sum(len(images) for _, images in self.items())

    def sessions(self, name: str) -> set[str]:
        return {image.capture_session_id for image in self[name]}

    def assert_no_leakage(self) -> None:
        owners: dict[str, str] = {}
        for split_name, images in self.items():
            for image in images:
                previous = owners.setdefault(image.capture_session_id, split_name)
                if previous != split_name:
                    raise AssertionError(
                        f"capture session {image.capture_session_id!r} leaks across "
                        f"{previous} and {split_name}"
                    )

    def to_mapping(self) -> dict[str, object]:
        result: dict[str, object] = {"strategy": "captureSessionId-grouped"}
        for split_name, images in self.items():
            result[split_name] = {
                "imageCount": len(images),
                "captureSessionIds": sorted(self.sessions(split_name)),
                "imageIds": [image.id for image in images],
            }
        return result


@dataclass(frozen=True, slots=True)
class _Group:
    session_id: str
    images: tuple[DatasetImage, ...]
    class_counts: Counter[str]
    stable_key: str


def split_by_capture_session(
    source: DatasetManifest | Iterable[DatasetImage],
    config: AppConfig | DatasetConfig,
    *,
    seed: int | None = None,
) -> DatasetSplit:
    """Split whole capture sessions with a deterministic balancing heuristic.

    The objective balances image counts first and per-class object counts second.
    Exact ratios are impossible when a capture session is large, but leakage is
    impossible because a group is assigned atomically.
    """

    images = tuple(source.images if isinstance(source, DatasetManifest) else source)
    dataset_config = config.dataset if isinstance(config, AppConfig) else config
    selected_seed = config.training.seed if isinstance(config, AppConfig) and seed is None else seed
    selected_seed = 42 if selected_seed is None else selected_seed

    grouped: dict[str, list[DatasetImage]] = defaultdict(list)
    for image in images:
        # Missing IDs are invalid, but keeping them independent avoids introducing
        # accidental leakage if a caller inspects a pre-validation split.
        key = image.capture_session_id or f"__missing__:{image.id}"
        grouped[key].append(image)

    groups: list[_Group] = []
    total_class_counts: Counter[str] = Counter()
    for session_id, group_images in grouped.items():
        class_counts = Counter(
            annotation.class_name
            for image in group_images
            for annotation in image.annotations
        )
        total_class_counts.update(class_counts)
        stable_key = hashlib.sha256(f"{selected_seed}:{session_id}".encode()).hexdigest()
        groups.append(
            _Group(
                session_id=session_id,
                images=tuple(group_images),
                class_counts=class_counts,
                stable_key=stable_key,
            )
        )

    # Large and class-diverse groups are allocated first; the hash gives seeded,
    # platform-independent ordering for otherwise equal groups.
    groups.sort(
        key=lambda group: (
            -len(group.images),
            -len(group.class_counts),
            -sum(group.class_counts.values()),
            group.stable_key,
        )
    )
    active_names = [name for name in SPLIT_NAMES if dataset_config.ratios[name] > 0]
    target_images = {
        name: len(images) * dataset_config.ratios[name] for name in SPLIT_NAMES
    }
    target_classes = {
        name: {
            class_name: count * dataset_config.ratios[name]
            for class_name, count in total_class_counts.items()
        }
        for name in SPLIT_NAMES
    }
    assignments: dict[str, list[DatasetImage]] = {name: [] for name in SPLIT_NAMES}
    current_images = Counter({name: 0 for name in SPLIT_NAMES})
    current_classes: dict[str, Counter[str]] = {
        name: Counter() for name in SPLIT_NAMES
    }

    remaining_groups = list(groups)
    if dataset_config.require_all_classes_in_each_split:
        # Reserve coverage before ratio balancing. Without this phase, a small
        # dataset can miss a class in validation/test even when one complete
        # session per class and split exists.
        coverage_order = sorted(
            active_names,
            key=lambda name: (dataset_config.ratios[name], active_names.index(name)),
        )
        for split_name in coverage_order:
            missing = set(COIN_CLASSES)
            while missing:
                availability = Counter(
                    class_name
                    for group in remaining_groups
                    for class_name in group.class_counts
                    if class_name in missing
                )
                candidates = [
                    group for group in remaining_groups if missing.intersection(group.class_counts)
                ]
                if not candidates:
                    break
                selected_group = min(
                    candidates,
                    key=lambda group: (
                        -sum(
                            1.0 / max(availability[class_name], 1)
                            for class_name in missing.intersection(group.class_counts)
                        ),
                        -len(missing.intersection(group.class_counts)),
                        len(group.images),
                        group.stable_key,
                    ),
                )
                _assign_group(
                    split_name,
                    selected_group,
                    assignments,
                    current_images,
                    current_classes,
                )
                remaining_groups.remove(selected_group)
                missing.difference_update(selected_group.class_counts)

    for index, group in enumerate(remaining_groups):
        empty_names = [name for name in active_names if current_images[name] == 0]
        groups_remaining_including_current = len(remaining_groups) - index
        candidates = active_names
        if empty_names and groups_remaining_including_current <= len(empty_names):
            candidates = empty_names
        selected = min(
            candidates,
            key=lambda name: (
                _assignment_delta(
                    name,
                    group,
                    current_images,
                    current_classes,
                    target_images,
                    target_classes,
                ),
                active_names.index(name),
            ),
        )
        _assign_group(
            selected,
            group,
            assignments,
            current_images,
            current_classes,
        )

    result = DatasetSplit(
        train=tuple(sorted(assignments["train"], key=lambda image: image.id)),
        validation=tuple(sorted(assignments["validation"], key=lambda image: image.id)),
        test=tuple(sorted(assignments["test"], key=lambda image: image.id)),
    )
    result.assert_no_leakage()
    return result


def _assignment_delta(
    split_name: str,
    group: _Group,
    current_images: Counter[str],
    current_classes: dict[str, Counter[str]],
    target_images: dict[str, float],
    target_classes: dict[str, dict[str, float]],
) -> float:
    target_image_count = max(target_images[split_name], 1.0)
    before_images = current_images[split_name]
    after_images = before_images + len(group.images)
    image_delta = (
        ((after_images - target_images[split_name]) ** 2)
        - ((before_images - target_images[split_name]) ** 2)
    ) / target_image_count

    class_delta = 0.0
    for class_name, added_count in group.class_counts.items():
        target = target_classes[split_name].get(class_name, 0.0)
        before = current_classes[split_name][class_name]
        after = before + added_count
        class_delta += (((after - target) ** 2) - ((before - target) ** 2)) / max(target, 1.0)
    return image_delta + 0.25 * class_delta


def _assign_group(
    split_name: str,
    group: _Group,
    assignments: dict[str, list[DatasetImage]],
    current_images: Counter[str],
    current_classes: dict[str, Counter[str]],
) -> None:
    assignments[split_name].extend(group.images)
    current_images[split_name] += len(group.images)
    current_classes[split_name].update(group.class_counts)
