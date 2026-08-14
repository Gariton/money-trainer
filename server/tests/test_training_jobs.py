from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from app.main import create_app
from app.worker import TrainingWorker

from .conftest import (
    ALL_CLASS_ANNOTATIONS,
    VALID_ANNOTATION,
    create_trainable_dataset,
    upload_image,
)


def test_training_requires_a_valid_dataset(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    response = client.post(
        "/training/jobs", headers=auth_headers, json={"mock_mode": True}
    )
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "dataset_validation_failed"
    assert response.json()["detail"]["errors"][0]["code"] == "empty_dataset"


def test_training_preflight_returns_structured_coverage_issues(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    upload_image(
        client,
        auth_headers,
        annotations=[VALID_ANNOTATION],
        review_status="unreviewed",
    )
    response = client.post("/training/jobs", headers=auth_headers, json={})
    assert response.status_code == 422
    issues = response.json()["detail"]["errors"]
    codes = {issue["code"] for issue in issues}
    assert "image_not_reviewed" in codes
    assert "insufficient_capture_sessions" in codes
    assert "insufficient_class_images" in codes
    assert any(issue.get("class_name") == "jpy_1" for issue in issues)


def test_training_preflight_requires_each_class_in_every_active_session_group(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    for index in range(3):
        annotations = (
            ALL_CLASS_ANNOTATIONS
            if index == 0
            else [
                annotation
                for annotation in ALL_CLASS_ANNOTATIONS
                if annotation["class"] != "jpy_500"
            ]
        )
        upload = upload_image(
            client,
            auth_headers,
            capture_session_id=f"coverage-session-{index}",
            annotations=annotations,
            review_status="reviewed",
        )
        assert upload.status_code == 201, upload.text

    response = client.post("/training/jobs", headers=auth_headers, json={})
    assert response.status_code == 422
    issues = response.json()["detail"]["errors"]
    class_issue = next(
        issue
        for issue in issues
        if issue["code"] == "insufficient_class_capture_sessions"
        and issue.get("class_name") == "jpy_500"
    )
    assert "1 capture session(s)" in class_issue["message"]
    assert "at least 3" in class_issue["message"]


def test_training_job_claim_progress_failure_and_retry(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    create_trainable_dataset(client, auth_headers)

    created = client.post(
        "/training/jobs",
        headers=auth_headers,
        json={"mock_mode": True, "training_config": {"epochs": 1}},
    )
    assert created.status_code == 201, created.text
    job = created.json()
    assert job["status"] == "queued"
    assert job["phase"] == "preparing"
    assert job["progress"] == 0
    assert job["created_at"].endswith("Z")
    assert job["model_version"] == "v1"
    assert job["dataset_version"] == "dataset-v3"
    assert Path(client.app.state.storage.local_path(job["dataset_manifest_key"])).parent == client.app.state.settings.data_root.resolve()

    manifest = client.get(
        f"/training/jobs/{job['id']}/manifest", headers=auth_headers
    )
    assert manifest.status_code == 200
    manifest_body = manifest.json()
    assert manifest_body["datasetVersion"] == "dataset-v3"
    assert Path(manifest_body["images"][0]["image_path"]).is_relative_to(
        client.app.state.settings.data_root.resolve()
    )

    claimed = client.post(
        "/training/jobs/claim",
        headers=auth_headers,
        json={"worker_id": "worker-a"},
    )
    assert claimed.status_code == 200
    assert claimed.json()["id"] == job["id"]
    assert claimed.json()["status"] == "running"
    assert claimed.json()["phase"] == "validating"
    assert claimed.json()["progress"] == 5

    none_left = client.post(
        "/training/jobs/claim",
        headers=auth_headers,
        json={"worker_id": "worker-b"},
    )
    assert none_left.status_code == 204

    progress = client.patch(
        f"/training/jobs/{job['id']}",
        headers=auth_headers,
        json={"status": "running", "phase": "training", "progress": 70},
    )
    assert progress.status_code == 200, progress.text
    assert progress.json()["progress"] == 70

    backwards = client.patch(
        f"/training/jobs/{job['id']}",
        headers=auth_headers,
        json={"phase": "validating", "progress": 75},
    )
    assert backwards.status_code == 409

    failed = client.patch(
        f"/training/jobs/{job['id']}",
        headers=auth_headers,
        json={"status": "failed", "error_message": "mock failure"},
    )
    assert failed.status_code == 200
    assert failed.json()["status"] == "failed"
    assert failed.json()["phase"] == "failed"
    assert failed.json()["error_message"] == "mock failure"
    assert failed.json()["completed_at"] is not None

    restarted = client.post(
        f"/training/jobs/{job['id']}/start", headers=auth_headers
    )
    assert restarted.status_code == 200
    assert restarted.json()["status"] == "queued"
    assert restarted.json()["model_version"] == "v2"
    assert restarted.json()["progress"] == 0
    assert restarted.json()["error_message"] is None

    listing = client.get("/training/jobs", headers=auth_headers).json()
    assert listing["total"] == 1
    assert listing["items"][0]["id"] == job["id"]


def test_job_persists_across_app_restart(
    client: TestClient, auth_headers: dict[str, str], settings
) -> None:
    create_trainable_dataset(client, auth_headers)
    created = client.post("/training/jobs", headers=auth_headers, json={})
    job_id = created.json()["id"]

    # A second process/app instance sees the same SQLite rows and filesystem artifact.
    with TestClient(create_app(settings)) as restarted_client:
        response = restarted_client.get(
            f"/training/jobs/{job_id}", headers=auth_headers
        )
        assert response.status_code == 200
        assert response.json()["status"] == "queued"


def test_worker_runs_mock_pipeline_and_persists_model(
    client: TestClient, auth_headers: dict[str, str], settings
) -> None:
    create_trainable_dataset(client, auth_headers)
    job = client.post(
        "/training/jobs",
        headers=auth_headers,
        json={"mock_mode": True, "training_config": {"epochs": 1}},
    ).json()

    class FakeMetrics:
        def to_dict(self):
            return {
                "mAP50": 0.9,
                "mAP50-95": 0.7,
                "precision": 0.8,
                "recall": 0.85,
                "perClass": {"jpy_1": {"AP": 0.7, "AP50": 0.9}},
            }

    def fake_runner(
        manifest_path,
        output_dir,
        *,
        model_version,
        progress_callback,
        **_,
    ):
        assert Path(manifest_path).is_file()
        artifact_dir = Path(output_dir) / model_version
        artifact_dir.mkdir(parents=True, exist_ok=True)
        checkpoint = artifact_dir / "best.pt"
        archive = artifact_dir / "MoneyDetector.mlpackage.zip"
        (artifact_dir / "reports").mkdir()
        checkpoint.write_bytes(b"checkpoint")
        archive.write_bytes(b"zip")
        progress_callback(SimpleNamespace(stage="training", progress=0.5))
        progress_callback(SimpleNamespace(stage="evaluating", progress=0.8))
        return SimpleNamespace(
            artifact_dir=artifact_dir,
            checkpoint_path=checkpoint,
            coreml_archive_path=archive,
            reports_dir=artifact_dir / "reports",
            metrics=FakeMetrics(),
        )

    worker = TrainingWorker(
        settings,
        database=client.app.state.database,
        storage=client.app.state.storage,
        training_runner=fake_runner,
    )
    assert worker.run_once("test-worker") is True

    completed = client.get(
        f"/training/jobs/{job['id']}", headers=auth_headers
    ).json()
    assert completed["status"] == "completed"
    assert completed["model_id"] is not None
    model = client.get(
        f"/models/{completed['model_id']}", headers=auth_headers
    ).json()
    assert model["metrics"]["map50"] == 0.9
    assert model["metrics"]["map50_95"] == 0.7
    assert model["metrics"]["per_class"]["jpy_1"]["ap"] == 0.7


def test_worker_persists_pipeline_failure(
    client: TestClient, auth_headers: dict[str, str], settings
) -> None:
    create_trainable_dataset(client, auth_headers)
    job = client.post("/training/jobs", headers=auth_headers, json={}).json()

    def failing_runner(*_, **__):
        raise RuntimeError("deterministic pipeline failure")

    worker = TrainingWorker(
        settings,
        database=client.app.state.database,
        storage=client.app.state.storage,
        training_runner=failing_runner,
    )
    assert worker.run_once("failing-worker") is True
    failed = client.get(f"/training/jobs/{job['id']}", headers=auth_headers).json()
    assert failed["status"] == "failed"
    assert failed["phase"] == "failed"
    assert failed["error_message"] == "deterministic pipeline failure"
    assert failed["completed_at"] is not None
