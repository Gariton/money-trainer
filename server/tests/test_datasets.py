from __future__ import annotations

import json

from fastapi.testclient import TestClient

from app.constants import COIN_CLASSES

from .conftest import PNG_BYTES, VALID_ANNOTATION, upload_image


def test_dataset_endpoints_and_stats(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    assert client.get("/datasets/stats").status_code == 401

    first = upload_image(
        client,
        auth_headers,
        capture_session_id="burst-001",
        annotations=[VALID_ANNOTATION],
    )
    assert first.status_code == 201, first.text
    first_body = first.json()
    assert first_body["source"] == "camera"
    assert first_body["capture_session_id"] == "burst-001"
    assert first_body["review_status"] == "reviewed"
    assert first_body["created_at"].endswith("Z")
    assert first_body["annotations"][0]["class"] == "jpy_100"
    assert first_body["image_url"].endswith(f"/{first_body['id']}/file")

    second = upload_image(
        client,
        auth_headers,
        capture_session_id="burst-001",
        source="photoLibrary",  # Compatibility alias; output stays snake_case.
    )
    assert second.status_code == 201, second.text
    assert second.json()["source"] == "photo_library"
    assert second.json()["split"] == first_body["split"]

    detail = client.get(
        f"/datasets/images/{first_body['id']}", headers=auth_headers
    )
    assert detail.status_code == 200
    assert detail.json() == first_body

    image_file = client.get(first_body["image_url"], headers=auth_headers)
    assert image_file.status_code == 200
    assert image_file.content == PNG_BYTES
    assert image_file.headers["content-type"].startswith("image/png")

    listing = client.get(
        "/datasets/images",
        params={"capture_session_id": "burst-001", "limit": 1},
        headers=auth_headers,
    )
    assert listing.status_code == 200
    assert listing.json()["total"] == 2
    assert len(listing.json()["items"]) == 1

    stats = client.get("/datasets/stats", headers=auth_headers)
    assert stats.status_code == 200
    stats_body = stats.json()
    assert stats_body["image_count"] == 2
    assert stats_body["object_count"] == 1
    assert stats_body["annotated_image_count"] == 1
    assert stats_body["unreviewed_image_count"] == 0
    assert stats_body["class_counts"] == {
        coin_class: (1 if coin_class == "jpy_100" else 0)
        for coin_class in COIN_CLASSES
    }
    assert sum(stats_body["split_counts"].values()) == 2
    assert stats_body["dataset_version"] == "dataset-v2"


def test_upload_mime_signature_size_and_filename_safety(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    unsupported = client.post(
        "/datasets/images",
        headers=auth_headers,
        files={"image": ("coin.gif", b"GIF89a", "image/gif")},
        data={"source": "camera", "capture_session_id": "session"},
    )
    assert unsupported.status_code == 415

    spoofed = client.post(
        "/datasets/images",
        headers=auth_headers,
        files={"image": ("coin.png", b"not-a-png", "image/png")},
        data={"source": "camera", "capture_session_id": "session"},
    )
    assert spoofed.status_code == 415

    oversized = upload_image(
        client,
        auth_headers,
        capture_session_id="large",
        content=b"\x89PNG\r\n\x1a\n" + b"x" * 2048,
    )
    assert oversized.status_code == 413

    traversal_name = client.post(
        "/datasets/images",
        headers=auth_headers,
        files={"image": ("../../outside.png", PNG_BYTES, "image/png")},
        data={"source": "camera", "capture_session_id": "safe-key"},
    )
    assert traversal_name.status_code == 201
    assert not (client.app.state.settings.data_root.parent / "outside.png").exists()


def test_annotation_update_validation(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    uploaded = upload_image(
        client, auth_headers, review_status="unreviewed", annotations=[]
    )
    image_id = uploaded.json()["id"]

    valid = {
        "annotations": [
            {
                "class": "jpy_50",
                "x": 0.75,
                "y": 0.75,
                "width": 0.25,
                "height": 0.25,
                "confidence": 0.91,
                "needs_review": False,
            }
        ],
        "review_status": "reviewed",
    }
    updated = client.put(
        f"/datasets/images/{image_id}/annotations",
        headers=auth_headers,
        json=valid,
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["annotations"][0]["class"] == "jpy_50"
    assert updated.json()["review_status"] == "reviewed"

    for invalid_box in (
        {"class": "jpy_50", "x": 0.8, "y": 0.1, "width": 0.3, "height": 0.2},
        {"class": "jpy_50", "x": 0.1, "y": 0.1, "width": 0, "height": 0.2},
        {"class": "usd_1", "x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2},
    ):
        response = client.put(
            f"/datasets/images/{image_id}/annotations",
            headers=auth_headers,
            json={"annotations": [invalid_box], "review_status": "reviewed"},
        )
        assert response.status_code == 422

    stats = client.get("/datasets/stats", headers=auth_headers).json()
    assert stats["dataset_version"] == "dataset-v2"
    assert stats["class_counts"]["jpy_50"] == 1


def test_invalid_upload_annotations_do_not_create_an_image(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    response = client.post(
        "/datasets/images",
        headers=auth_headers,
        files={"image": ("test.png", PNG_BYTES, "image/png")},
        data={
            "source": "camera",
            "capture_session_id": "bad-annotation",
            "annotations": json.dumps(
                [{"class": "jpy_1", "x": 0.9, "y": 0, "width": 0.2, "height": 0.2}]
            ),
        },
    )
    assert response.status_code == 422
    assert client.get("/datasets/stats", headers=auth_headers).json()["image_count"] == 0
