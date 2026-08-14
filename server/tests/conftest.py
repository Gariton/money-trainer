from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


TOKEN = "test-api-token"
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"money-trainer-test-image"
VALID_ANNOTATION = {
    "class": "jpy_100",
    "x": 0.1,
    "y": 0.2,
    "width": 0.3,
    "height": 0.4,
}
ALL_CLASS_ANNOTATIONS = [
    {
        "class": class_name,
        "x": index * 0.15,
        "y": 0.1,
        "width": 0.1,
        "height": 0.1,
    }
    for index, class_name in enumerate(
        ("jpy_1", "jpy_5", "jpy_10", "jpy_50", "jpy_100", "jpy_500")
    )
]


def make_settings(tmp_path: Path, *, max_upload_bytes: int = 1024) -> Settings:
    return Settings(
        database_url=f"sqlite:///{tmp_path / 'money-trainer.sqlite3'}",
        data_root=tmp_path / "data",
        api_token=TOKEN,
        max_upload_bytes=max_upload_bytes,
        split_train=0.70,
        split_validation=0.15,
        split_test=0.15,
    )


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    return make_settings(tmp_path)


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings)) as test_client:
        yield test_client


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {TOKEN}"}


def upload_image(
    client: TestClient,
    auth_headers: dict[str, str],
    *,
    capture_session_id: str = "session-a",
    annotations: list[dict[str, object]] | None = None,
    review_status: str = "reviewed",
    source: str = "camera",
    content: bytes = PNG_BYTES,
    content_type: str = "image/png",
):
    return client.post(
        "/datasets/images",
        headers=auth_headers,
        files={"image": ("test.png", content, content_type)},
        data={
            "source": source,
            "capture_session_id": capture_session_id,
            "review_status": review_status,
            "annotations": json.dumps(annotations or []),
        },
    )


def create_trainable_dataset(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    for index in range(3):
        response = upload_image(
            client,
            auth_headers,
            capture_session_id=f"trainable-session-{index}",
            annotations=ALL_CLASS_ANNOTATIONS,
            review_status="reviewed",
        )
        assert response.status_code == 201, response.text
