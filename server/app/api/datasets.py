from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.responses import FileResponse
from pydantic import TypeAdapter, ValidationError
from sqlalchemy import func, select

from ..config import Settings
from ..constants import (
    ALLOWED_IMAGE_MIME_TYPES,
    DatasetSplit,
    ImageSource,
    ReviewStatus,
)
from ..db_models import DatasetImage
from ..dependencies import SessionDependency, StorageDependency
from ..schemas import (
    Annotation,
    AnnotationUpdate,
    DatasetImageList,
    DatasetImageRead,
    DatasetStats,
)
from ..services import (
    annotations_to_json,
    bump_dataset_revision,
    dataset_stats,
    image_read,
    split_for_session,
)
from ..storage import InvalidImageContent, StorageObjectNotFound, UploadTooLarge


router = APIRouter(prefix="/datasets", tags=["datasets"])
annotation_list_adapter = TypeAdapter(list[Annotation])


def _parse_annotations(raw: str) -> list[Annotation]:
    try:
        return annotation_list_adapter.validate_json(raw)
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail={
                "code": "invalid_annotations",
                "errors": json.loads(exc.json(include_url=False)),
            },
        ) from exc


def _parse_source(raw: str) -> ImageSource:
    aliases = {"photoLibrary": "photo_library", "liveTest": "live_test"}
    try:
        return ImageSource(aliases.get(raw, raw))
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="source must be camera, photo_library, or live_test",
        ) from exc


def _parse_review_status(raw: str) -> ReviewStatus:
    aliases = {"needsReview": "needs_review"}
    try:
        return ReviewStatus(aliases.get(raw, raw))
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="review_status must be unreviewed, needs_review, or reviewed",
        ) from exc


@router.post(
    "/images",
    response_model=DatasetImageRead,
    status_code=status.HTTP_201_CREATED,
)
async def upload_dataset_image(
    request: Request,
    image: Annotated[UploadFile, File(description="JPEG or PNG image")],
    source: Annotated[str, Form()],
    capture_session_id: Annotated[str, Form(min_length=1, max_length=128)],
    review_status: Annotated[str, Form()] = ReviewStatus.UNREVIEWED.value,
    annotations: Annotated[str, Form()] = "[]",
    model_version_used_for_pre_annotation: Annotated[
        str | None, Form(max_length=64)
    ] = None,
    *,
    db: SessionDependency,
    storage: StorageDependency,
) -> DatasetImageRead:
    settings: Settings = request.app.state.settings
    content_type = (image.content_type or "").lower()
    if content_type not in settings.allowed_image_mime_types:
        await image.close()
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Unsupported image MIME type",
        )
    parsed_source = _parse_source(source)
    parsed_review_status = _parse_review_status(review_status)
    parsed_annotations = _parse_annotations(annotations)
    capture_session_id = capture_session_id.strip()
    if not capture_session_id:
        await image.close()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="capture_session_id must not be blank",
        )

    image_id = str(uuid.uuid4())
    extension = ALLOWED_IMAGE_MIME_TYPES[content_type]
    storage_key = f"images/{image_id}{extension}"
    try:
        stored = await storage.save_image_upload(
            image,
            storage_key,
            content_type=content_type,
            max_bytes=settings.max_upload_bytes,
        )
    except UploadTooLarge as exc:
        raise HTTPException(status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail=str(exc)) from exc
    except InvalidImageContent as exc:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail=str(exc)) from exc

    original_name = (image.filename or "").replace("\\", "/").split("/")[-1]
    row = DatasetImage(
        id=image_id,
        storage_key=stored.key,
        original_filename=Path(original_name).name[:255] or None,
        content_type=content_type,
        file_size=stored.size,
        annotations_json=annotations_to_json(parsed_annotations),
        source=parsed_source.value,
        capture_session_id=capture_session_id,
        review_status=parsed_review_status.value,
        model_version_used_for_pre_annotation=model_version_used_for_pre_annotation,
        split=split_for_session(db, capture_session_id, settings).value,
    )
    try:
        db.add(row)
        bump_dataset_revision(db)
        db.commit()
        db.refresh(row)
    except Exception:
        db.rollback()
        storage.delete(storage_key)
        raise
    return image_read(row)


@router.get("/stats", response_model=DatasetStats)
def get_dataset_stats(db: SessionDependency) -> DatasetStats:
    return dataset_stats(db)


@router.get("/images", response_model=DatasetImageList)
def list_dataset_images(
    db: SessionDependency,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    source: ImageSource | None = None,
    review_status: ReviewStatus | None = None,
    split: DatasetSplit | None = None,
    capture_session_id: Annotated[str | None, Query(max_length=128)] = None,
) -> DatasetImageList:
    filters = []
    if source is not None:
        filters.append(DatasetImage.source == source.value)
    if review_status is not None:
        filters.append(DatasetImage.review_status == review_status.value)
    if split is not None:
        filters.append(DatasetImage.split == split.value)
    if capture_session_id is not None:
        filters.append(DatasetImage.capture_session_id == capture_session_id)
    total = db.scalar(select(func.count()).select_from(DatasetImage).where(*filters)) or 0
    rows = list(
        db.scalars(
            select(DatasetImage)
            .where(*filters)
            .order_by(DatasetImage.created_at.desc(), DatasetImage.id.desc())
            .limit(limit)
            .offset(offset)
        )
    )
    return DatasetImageList(
        items=[image_read(row) for row in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


def _get_image_or_404(db: SessionDependency, image_id: str) -> DatasetImage:
    row = db.get(DatasetImage, image_id)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dataset image not found")
    return row


@router.get("/images/{image_id}", response_model=DatasetImageRead)
def get_dataset_image(image_id: str, db: SessionDependency) -> DatasetImageRead:
    return image_read(_get_image_or_404(db, image_id))


@router.get("/images/{image_id}/file", response_class=FileResponse)
def download_dataset_image(
    image_id: str, db: SessionDependency, storage: StorageDependency
) -> FileResponse:
    row = _get_image_or_404(db, image_id)
    try:
        path = storage.local_path(row.storage_key)
    except StorageObjectNotFound as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Image file not found") from exc
    return FileResponse(path, media_type=row.content_type, filename=row.original_filename)


@router.put("/images/{image_id}/annotations", response_model=DatasetImageRead)
def update_dataset_annotations(
    image_id: str,
    body: AnnotationUpdate,
    db: SessionDependency,
) -> DatasetImageRead:
    row = _get_image_or_404(db, image_id)
    row.annotations_json = annotations_to_json(body.annotations)
    row.review_status = body.review_status.value
    bump_dataset_revision(db)
    db.commit()
    db.refresh(row)
    return image_read(row)
