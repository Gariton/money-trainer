"""Stable Japanese-yen class definitions shared by every training stage."""

from __future__ import annotations

COIN_CLASSES: tuple[str, ...] = (
    "jpy_1",
    "jpy_5",
    "jpy_10",
    "jpy_50",
    "jpy_100",
    "jpy_500",
)

# Readable compatibility aliases for callers that prefer generic terminology.
CLASSES = COIN_CLASSES
CLASS_NAMES = COIN_CLASSES

CLASS_TO_INDEX: dict[str, int] = {name: index for index, name in enumerate(COIN_CLASSES)}
INDEX_TO_CLASS: dict[int, str] = {index: name for name, index in CLASS_TO_INDEX.items()}

DISPLAY_NAMES: dict[str, str] = {
    "jpy_1": "1円",
    "jpy_5": "5円",
    "jpy_10": "10円",
    "jpy_50": "50円",
    "jpy_100": "100円",
    "jpy_500": "500円",
}

DEFAULT_CONFIG_NAME = "default_config.yaml"
MANIFEST_CANDIDATES: tuple[str, ...] = ("manifest.json", "dataset.json", "images.json")
