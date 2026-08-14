from __future__ import annotations

import json
import mimetypes
import os
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from fastapi import UploadFile


class StorageError(Exception):
    """Base error for storage operations."""


class UnsafeStorageKey(StorageError):
    pass


class UploadTooLarge(StorageError):
    pass


class InvalidImageContent(StorageError):
    pass


class StorageObjectNotFound(StorageError):
    pass


@dataclass(frozen=True, slots=True)
class StoredUpload:
    key: str
    size: int


def validate_storage_key(key: str, *, allow_prefix: bool = False) -> PurePosixPath:
    if not key or "\\" in key or "\x00" in key:
        raise UnsafeStorageKey("Storage key is empty or contains forbidden characters")
    path = PurePosixPath(key)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise UnsafeStorageKey("Storage key must be a safe relative path")
    if not allow_prefix and key.endswith("/"):
        raise UnsafeStorageKey("Storage object key must name a file")
    return path


def image_signature_matches(content_type: str, header: bytes) -> bool:
    if content_type == "image/jpeg":
        return header.startswith(b"\xff\xd8\xff")
    if content_type == "image/png":
        return header.startswith(b"\x89PNG\r\n\x1a\n")
    if content_type in {"image/heic", "image/heif"}:
        if len(header) < 12 or header[4:8] != b"ftyp":
            return False
        brand = header[8:12]
        return brand in {b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1"}
    return False


class ObjectStorage(ABC):
    """Small storage boundary that can later be backed by S3-compatible storage."""

    @abstractmethod
    async def save_image_upload(
        self,
        upload: UploadFile,
        key: str,
        *,
        content_type: str,
        max_bytes: int,
    ) -> StoredUpload:
        raise NotImplementedError

    @abstractmethod
    def write_bytes(self, key: str, content: bytes) -> None:
        raise NotImplementedError

    def write_json(self, key: str, value: object) -> None:
        self.write_bytes(
            key,
            json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
        )

    @abstractmethod
    def exists(self, key: str) -> bool:
        raise NotImplementedError

    @abstractmethod
    def local_path(self, key: str) -> Path:
        """Return a local path for workers/FileResponse in the MVP filesystem backend."""
        raise NotImplementedError

    @abstractmethod
    def list_keys(self, prefix: str) -> list[str]:
        raise NotImplementedError

    @abstractmethod
    def delete(self, key: str) -> None:
        raise NotImplementedError

    @abstractmethod
    def content_type(self, key: str) -> str:
        raise NotImplementedError


class LocalObjectStorage(ObjectStorage):
    def __init__(self, root: Path) -> None:
        self.root = root.expanduser().resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / ".tmp").mkdir(parents=True, exist_ok=True)

    def _resolve(self, key: str, *, allow_prefix: bool = False) -> Path:
        relative = validate_storage_key(key, allow_prefix=allow_prefix)
        candidate = self.root.joinpath(*relative.parts).resolve()
        try:
            candidate.relative_to(self.root)
        except ValueError as exc:
            raise UnsafeStorageKey("Storage key escapes the configured data root") from exc
        return candidate

    async def save_image_upload(
        self,
        upload: UploadFile,
        key: str,
        *,
        content_type: str,
        max_bytes: int,
    ) -> StoredUpload:
        destination = self._resolve(key)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.root / ".tmp" / f"{uuid.uuid4()}.upload"
        size = 0
        header = b""
        try:
            with temporary.open("xb") as output:
                while chunk := await upload.read(64 * 1024):
                    size += len(chunk)
                    if size > max_bytes:
                        raise UploadTooLarge(
                            f"Image exceeds the {max_bytes}-byte upload limit"
                        )
                    if len(header) < 32:
                        header += chunk[: 32 - len(header)]
                    output.write(chunk)
            if size == 0:
                raise InvalidImageContent("Uploaded image is empty")
            if not image_signature_matches(content_type, header):
                raise InvalidImageContent(
                    "Uploaded bytes do not match the declared image MIME type"
                )
            os.replace(temporary, destination)
        except Exception:
            temporary.unlink(missing_ok=True)
            raise
        finally:
            await upload.close()
        return StoredUpload(key=key, size=size)

    def write_bytes(self, key: str, content: bytes) -> None:
        destination = self._resolve(key)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.root / ".tmp" / f"{uuid.uuid4()}.write"
        try:
            temporary.write_bytes(content)
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)

    def exists(self, key: str) -> bool:
        return self._resolve(key).is_file()

    def local_path(self, key: str) -> Path:
        path = self._resolve(key)
        if not path.is_file():
            raise StorageObjectNotFound(key)
        return path

    def list_keys(self, prefix: str) -> list[str]:
        directory = self._resolve(prefix, allow_prefix=True)
        if not directory.exists():
            return []
        if directory.is_file():
            return [str(directory.relative_to(self.root).as_posix())]
        return sorted(
            str(path.relative_to(self.root).as_posix())
            for path in directory.rglob("*")
            if path.is_file()
        )

    def delete(self, key: str) -> None:
        path = self._resolve(key)
        path.unlink(missing_ok=True)

    def content_type(self, key: str) -> str:
        guessed, _ = mimetypes.guess_type(key)
        return guessed or "application/octet-stream"

