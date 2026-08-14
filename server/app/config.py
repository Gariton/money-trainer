from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from .constants import ALLOWED_IMAGE_MIME_TYPES


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    return int(value) if value is not None else default


def _env_float(name: str, default: float) -> float:
    value = os.getenv(name)
    return float(value) if value is not None else default


@dataclass(frozen=True, slots=True)
class Settings:
    database_url: str = field(
        default_factory=lambda: os.getenv(
            "DATABASE_URL", "sqlite:///./data/money_trainer.db"
        )
    )
    data_root: Path = field(
        default_factory=lambda: Path(os.getenv("DATA_ROOT", "./data"))
    )
    api_token: str = field(
        default_factory=lambda: os.getenv("API_TOKEN", "local-development-token")
    )
    max_upload_bytes: int = field(
        default_factory=lambda: _env_int("MAX_UPLOAD_BYTES", 20 * 1024 * 1024)
    )
    split_train: float = field(
        default_factory=lambda: _env_float("DATASET_SPLIT_TRAIN", 0.70)
    )
    split_validation: float = field(
        default_factory=lambda: _env_float("DATASET_SPLIT_VALIDATION", 0.15)
    )
    split_test: float = field(
        default_factory=lambda: _env_float("DATASET_SPLIT_TEST", 0.15)
    )
    allowed_image_mime_types: frozenset[str] = field(
        default_factory=lambda: frozenset(ALLOWED_IMAGE_MIME_TYPES)
    )

    def __post_init__(self) -> None:
        if not self.api_token:
            raise ValueError("API_TOKEN must not be empty")
        if self.max_upload_bytes <= 0:
            raise ValueError("MAX_UPLOAD_BYTES must be positive")
        total = self.split_train + self.split_validation + self.split_test
        if any(
            ratio < 0
            for ratio in (self.split_train, self.split_validation, self.split_test)
        ) or abs(total - 1.0) > 1e-6:
            raise ValueError("Dataset split ratios must be non-negative and sum to 1")

