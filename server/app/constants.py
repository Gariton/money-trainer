from __future__ import annotations

from enum import StrEnum


class CoinClass(StrEnum):
    JPY_1 = "jpy_1"
    JPY_5 = "jpy_5"
    JPY_10 = "jpy_10"
    JPY_50 = "jpy_50"
    JPY_100 = "jpy_100"
    JPY_500 = "jpy_500"


COIN_CLASSES = tuple(member.value for member in CoinClass)


class ImageSource(StrEnum):
    CAMERA = "camera"
    PHOTO_LIBRARY = "photo_library"
    LIVE_TEST = "live_test"


class ReviewStatus(StrEnum):
    UNREVIEWED = "unreviewed"
    NEEDS_REVIEW = "needs_review"
    REVIEWED = "reviewed"


class DatasetSplit(StrEnum):
    TRAIN = "train"
    VALIDATION = "validation"
    TEST = "test"


class JobStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class JobPhase(StrEnum):
    PREPARING = "preparing"
    UPLOADING = "uploading"
    VALIDATING = "validating"
    TRAINING = "training"
    EVALUATING = "evaluating"
    EXPORTING_CORE_ML = "exporting_core_ml"
    VALIDATING_CORE_ML = "validating_core_ml"
    COMPLETED = "completed"
    FAILED = "failed"


JOB_PHASE_ORDER = {
    JobPhase.PREPARING: 0,
    JobPhase.UPLOADING: 1,
    JobPhase.VALIDATING: 2,
    JobPhase.TRAINING: 3,
    JobPhase.EVALUATING: 4,
    JobPhase.EXPORTING_CORE_ML: 5,
    JobPhase.VALIDATING_CORE_ML: 6,
    JobPhase.COMPLETED: 7,
    JobPhase.FAILED: 7,
}


ALLOWED_IMAGE_MIME_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
}
