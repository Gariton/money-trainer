from __future__ import annotations

import io
import zipfile

from fastapi.testclient import TestClient

from app.schemas import Annotation

from .conftest import PNG_BYTES, create_trainable_dataset


def _zip_artifact() -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr("MoneyDetector.mlpackage/Manifest.json", "{}")
    return output.getvalue()


def _running_job(
    client: TestClient, auth_headers: dict[str, str], *, mock_mode: bool = True
) -> dict:
    create_trainable_dataset(client, auth_headers)
    job = client.post(
        "/training/jobs", headers=auth_headers, json={"mock_mode": mock_mode}
    ).json()
    claimed = client.post(
        "/training/jobs/claim",
        headers=auth_headers,
        json={"worker_id": "model-test-worker"},
    )
    assert claimed.status_code == 200
    return job


def test_models_latest_detail_download_and_reports(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    assert client.get("/models/latest", headers=auth_headers).status_code == 404
    job = _running_job(client, auth_headers)
    storage = client.app.state.storage
    prefix = f"models/{job['model_version']}"
    core_ml_key = f"{prefix}/MoneyDetector.mlpackage.zip"
    checkpoint_key = f"{prefix}/best.pt"
    artifact_bytes = _zip_artifact()
    storage.write_bytes(core_ml_key, artifact_bytes)
    storage.write_bytes(checkpoint_key, b"mock-checkpoint")
    storage.write_bytes(
        f"{prefix}/reports/false-positives/example.png", PNG_BYTES
    )

    created = client.post(
        "/models",
        headers=auth_headers,
        json={
            "job_id": job["id"],
            "model_version": job["model_version"],
            "dataset_version": job["dataset_version"],
            "training_config": {"epochs": 1},
            "metrics": {
                "map50": 0.982,
                "map50_95": 0.8,
                "precision": 0.987,
                "recall": 0.978,
                "per_class": {"jpy_100": {"precision": 1, "recall": 1, "ap": 1}},
            },
            "checkpoint_key": checkpoint_key,
            "core_ml_key": core_ml_key,
            "artifact_prefix": prefix,
        },
    )
    assert created.status_code == 201, created.text
    model = created.json()
    assert model["model_version"] == "v1"
    assert model["core_ml_available"] is True
    assert model["checkpoint_available"] is True
    assert model["metrics"]["map50"] == 0.982

    job_after = client.get(
        f"/training/jobs/{job['id']}", headers=auth_headers
    ).json()
    assert job_after["status"] == "completed"
    assert job_after["phase"] == "completed"
    assert job_after["progress"] == 100
    assert job_after["model_id"] == model["id"]

    listing = client.get("/models", headers=auth_headers)
    assert listing.status_code == 200
    assert listing.json()["total"] == 1
    assert listing.json()["items"][0]["id"] == model["id"]

    latest = client.get("/models/latest", headers=auth_headers)
    detail = client.get(f"/models/{model['id']}", headers=auth_headers)
    assert latest.json() == detail.json() == model

    download = client.get(model["download_url"], headers=auth_headers)
    assert download.status_code == 200
    assert download.headers["content-type"].startswith("application/zip")
    assert "MoneyDetector-v1.mlpackage.zip" in download.headers["content-disposition"]
    assert download.content == artifact_bytes

    reports = client.get(model["reports_url"], headers=auth_headers)
    assert reports.status_code == 200
    assert reports.json()["items"][0]["category"] == "false_positives"
    report = client.get(reports.json()["items"][0]["url"], headers=auth_headers)
    assert report.status_code == 200
    assert report.content == PNG_BYTES


def test_model_registration_rejects_unsafe_or_missing_artifacts(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    job = _running_job(client, auth_headers)
    base = {
        "job_id": job["id"],
        "model_version": job["model_version"],
        "dataset_version": job["dataset_version"],
        "core_ml_key": "outside/model.zip",
        "artifact_prefix": "models/v1",
    }
    unsafe = client.post("/models", headers=auth_headers, json=base)
    assert unsafe.status_code == 400

    missing = client.post(
        "/models",
        headers=auth_headers,
        json={**base, "core_ml_key": "models/v1/missing.zip"},
    )
    assert missing.status_code == 422


def test_inference_is_mock_safe_without_a_model(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    response = client.post(
        "/inference",
        headers=auth_headers,
        files={"image": ("frame.png", PNG_BYTES, "image/png")},
    )
    assert response.status_code == 200, response.text
    assert response.json() == {
        "model_id": None,
        "model_version": None,
        "annotations": [],
    }


def test_inference_uses_injected_engine_for_a_real_model(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    job = _running_job(client, auth_headers, mock_mode=False)
    storage = client.app.state.storage
    prefix = "models/v1"
    storage.write_bytes(f"{prefix}/MoneyDetector.mlpackage.zip", b"zip")
    storage.write_bytes(f"{prefix}/best.pt", b"checkpoint")
    registered = client.post(
        "/models",
        headers=auth_headers,
        json={
            "job_id": job["id"],
            "model_version": "v1",
            "dataset_version": job["dataset_version"],
            "core_ml_key": f"{prefix}/MoneyDetector.mlpackage.zip",
            "checkpoint_key": f"{prefix}/best.pt",
            "artifact_prefix": prefix,
        },
    )
    assert registered.status_code == 201, registered.text

    class FakeEngine:
        def predict(self, image_path, model, object_storage):
            assert image_path.is_file()
            assert model.id == registered.json()["id"]
            assert object_storage is storage
            return [
                Annotation(
                    **{
                        "class": "jpy_500",
                        "x": 0.1,
                        "y": 0.2,
                        "width": 0.3,
                        "height": 0.4,
                        "confidence": 0.95,
                    }
                )
            ]

    client.app.state.inference_engine = FakeEngine()
    response = client.post(
        "/inference",
        headers=auth_headers,
        files={"image": ("frame.png", PNG_BYTES, "image/png")},
    )
    assert response.status_code == 200, response.text
    assert response.json()["model_version"] == "v1"
    assert response.json()["annotations"][0]["class"] == "jpy_500"
    assert response.json()["annotations"][0]["x"] == 0.1
