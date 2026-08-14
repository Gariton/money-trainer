from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, File, HTTPException, Request, UploadFile, status
from sqlalchemy import select
from starlette.concurrency import run_in_threadpool

from ..config import Settings
from ..constants import ALLOWED_IMAGE_MIME_TYPES
from ..db_models import TrainedModel
from ..dependencies import SessionDependency, StorageDependency
from ..inference_engine import InferenceEngine, InferenceRuntimeUnavailable
from ..schemas import InferenceResponse
from ..storage import InvalidImageContent, UploadTooLarge


router = APIRouter(tags=["inference"])


@router.post("/inference", response_model=InferenceResponse)
async def run_inference(
    request: Request,
    image: Annotated[UploadFile, File(description="Image to annotate")],
    db: SessionDependency,
    storage: StorageDependency,
) -> InferenceResponse:
    """Validate an inference upload and return a mock-safe prediction envelope.

    Actual detector execution is intentionally behind the training/model runtime
    boundary. The MVP response is empty when no runtime detector is configured, which
    lets the annotation editor open normally before the first model exists.
    """

    settings: Settings = request.app.state.settings
    content_type = (image.content_type or "").lower()
    if content_type not in settings.allowed_image_mime_types:
        await image.close()
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported image MIME type",
        )
    key = f"inference/{uuid.uuid4()}{ALLOWED_IMAGE_MIME_TYPES[content_type]}"
    stored = False
    try:
        await storage.save_image_upload(
            image,
            key,
            content_type=content_type,
            max_bytes=settings.max_upload_bytes,
        )
        stored = True
    except UploadTooLarge as exc:
        raise HTTPException(status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail=str(exc)) from exc
    except InvalidImageContent as exc:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail=str(exc)) from exc
    try:
        latest = db.scalar(
            select(TrainedModel).order_by(TrainedModel.version_number.desc()).limit(1)
        )
        if latest is None or latest.job.mock_mode or latest.checkpoint_key is None:
            annotations = []
        else:
            engine: InferenceEngine = request.app.state.inference_engine
            try:
                annotations = await run_in_threadpool(
                    engine.predict, storage.local_path(key), latest, storage
                )
            except InferenceRuntimeUnavailable as exc:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail={"code": "inference_runtime_unavailable", "message": str(exc)},
                ) from exc
        return InferenceResponse(
            model_id=latest.id if latest else None,
            model_version=latest.model_version if latest else None,
            annotations=annotations,
        )
    finally:
        if stored:
            storage.delete(key)
