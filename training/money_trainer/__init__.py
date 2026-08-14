"""Money Trainer model-training package.

Heavy ML libraries are intentionally not imported here. The public API can be
used by the server worker and by tests without PyTorch, Ultralytics, or
coremltools being installed.
"""

from .config import AppConfig, load_config
from .constants import CLASS_NAMES, CLASS_TO_INDEX, CLASSES, COIN_CLASSES, DISPLAY_NAMES
from .dataset import Annotation, DatasetImage, DatasetManifest
from .pipeline import (
    PipelineEvent,
    PipelineResult,
    PipelineStage,
    TrainingPipeline,
    run_training,
)
from .validation import DatasetValidationError, ValidationIssue, ValidationReport

__all__ = [
    "Annotation",
    "AppConfig",
    "CLASS_TO_INDEX",
    "CLASS_NAMES",
    "CLASSES",
    "COIN_CLASSES",
    "DISPLAY_NAMES",
    "DatasetImage",
    "DatasetManifest",
    "DatasetValidationError",
    "PipelineResult",
    "PipelineStage",
    "PipelineEvent",
    "TrainingPipeline",
    "ValidationIssue",
    "ValidationReport",
    "load_config",
    "run_training",
]
