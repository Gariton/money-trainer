"""Persistent training worker process used by the Docker vertical slice."""

from __future__ import annotations

import argparse
import json
import logging
import os
import signal
import threading
from collections.abc import Callable
from pathlib import Path
from typing import Any

from sqlalchemy import select

from .config import Settings
from .constants import JobPhase, JobStatus
from .database import Database
from .db_models import TrainingJob, TrainedModel
from .services import apply_job_update, ensure_system_state, utc_now
from .storage import LocalObjectStorage


LOGGER = logging.getLogger("money_trainer.worker")

STAGE_TO_PHASE = {
    "validating": JobPhase.VALIDATING,
    "splitting": JobPhase.TRAINING,
    "generating": JobPhase.TRAINING,
    "training": JobPhase.TRAINING,
    "evaluating": JobPhase.EVALUATING,
    "exporting_coreml": JobPhase.EXPORTING_CORE_ML,
    "validating_coreml": JobPhase.VALIDATING_CORE_ML,
    "saving_artifacts": JobPhase.VALIDATING_CORE_ML,
    "completed": JobPhase.VALIDATING_CORE_ML,
}


def _normalize_metrics(value: Any) -> dict[str, Any]:
    if hasattr(value, "to_dict"):
        value = value.to_dict()
    if not isinstance(value, dict):
        raise ValueError("Training metrics must be a mapping")
    key_map = {
        "mAP50": "map50",
        "mAP50-95": "map50_95",
        "perClass": "per_class",
        "AP": "ap",
        "AP50": "ap50",
    }
    return {
        key_map.get(str(key), str(key)): (
            _normalize_metrics(child)
            if isinstance(child, dict)
            else [
                _normalize_metrics(item) if isinstance(item, dict) else item
                for item in child
            ]
            if isinstance(child, list)
            else child
        )
        for key, child in value.items()
    }


def _normalize_training_config(value: dict[str, Any]) -> dict[str, Any]:
    if not value:
        return {}
    section_names = {
        "model",
        "training",
        "dataset",
        "augmentation",
        "evaluation",
        "export",
        "runtime",
        "classes",
    }
    if any(key in section_names for key in value):
        return value
    # The mobile UI commonly submits only epochs/batch_size/patience.
    return {"training": value}


class TrainingWorker:
    def __init__(
        self,
        settings: Settings,
        *,
        database: Database | None = None,
        storage: LocalObjectStorage | None = None,
        training_runner: Callable[..., Any] | None = None,
    ) -> None:
        self.settings = settings
        self.database = database or Database(settings.database_url)
        self.storage = storage or LocalObjectStorage(settings.data_root)
        self.training_runner = training_runner

    def initialize(self) -> None:
        self.database.create_schema()
        with self.database.session_factory() as db:
            ensure_system_state(db)

    def claim_next_job(self, worker_id: str) -> str | None:
        with self.database.session_factory() as db:
            job = db.scalar(
                select(TrainingJob)
                .where(TrainingJob.status == JobStatus.QUEUED.value)
                .order_by(TrainingJob.created_at.asc(), TrainingJob.id.asc())
                .with_for_update(skip_locked=True)
                .limit(1)
            )
            if job is None:
                return None
            now = utc_now()
            job.status = JobStatus.RUNNING.value
            job.phase = JobPhase.VALIDATING.value
            job.progress = max(job.progress, 5)
            job.worker_id = worker_id
            job.claimed_at = now
            job.started_at = job.started_at or now
            job.updated_at = now
            db.commit()
            return job.id

    def _update_from_event(self, job_id: str, event: Any) -> None:
        raw_stage = getattr(event, "stage", "training")
        stage = getattr(raw_stage, "value", raw_stage)
        phase = STAGE_TO_PHASE.get(str(stage), JobPhase.TRAINING)
        raw_progress = float(getattr(event, "progress", 0.0))
        with self.database.session_factory() as db:
            job = db.get(TrainingJob, job_id)
            if job is None or JobStatus(job.status) != JobStatus.RUNNING:
                return
            progress = max(job.progress, min(99, round(raw_progress * 100)))
            try:
                apply_job_update(
                    job,
                    status=JobStatus.RUNNING,
                    phase=phase,
                    progress=progress,
                    error_message=None,
                    error_message_was_set=False,
                )
            except ValueError:
                LOGGER.debug("Ignored non-monotonic pipeline event %s", stage)
                return
            db.commit()

    def _relative_key(self, path: Path) -> str:
        resolved = path.resolve()
        try:
            return resolved.relative_to(self.storage.root).as_posix()
        except ValueError as exc:
            raise ValueError(
                f"Training artifact escaped DATA_ROOT: {resolved}"
            ) from exc

    def _runner(self) -> Callable[..., Any]:
        if self.training_runner is not None:
            return self.training_runner
        try:
            from money_trainer import run_training
        except ImportError as exc:
            raise RuntimeError(
                "The training package is not installed in the worker image"
            ) from exc
        return run_training

    def run_claimed_job(self, job_id: str) -> None:
        config_key: str | None = None
        try:
            with self.database.session_factory() as db:
                job = db.get(TrainingJob, job_id)
                if job is None or JobStatus(job.status) != JobStatus.RUNNING:
                    return
                manifest_path = self.storage.local_path(job.dataset_manifest_key)
                model_version = job.model_version
                dataset_version = job.dataset_version
                mock_mode = job.mock_mode
                config = _normalize_training_config(job.training_config)

            config_path: Path | None = None
            if config:
                config_key = f"worker-config-{job_id}.json"
                self.storage.write_bytes(
                    config_key,
                    json.dumps(config, ensure_ascii=False).encode("utf-8"),
                )
                config_path = self.storage.local_path(config_key)

            result = self._runner()(
                manifest_path,
                self.storage.root / "models",
                config_path=config_path,
                mock=mock_mode,
                model_version=model_version,
                dataset_version=dataset_version,
                progress_callback=lambda event: self._update_from_event(job_id, event),
            )

            core_ml_path = Path(result.coreml_archive_path).resolve()
            artifact_dir = Path(result.artifact_dir).resolve()
            reports_dir = Path(result.reports_dir).resolve()
            checkpoint_path = Path(result.checkpoint_path).resolve()
            if not core_ml_path.is_file():
                raise FileNotFoundError(f"Core ML archive was not produced: {core_ml_path}")
            checkpoint_key = (
                self._relative_key(checkpoint_path) if checkpoint_path.is_file() else None
            )
            core_ml_key = self._relative_key(core_ml_path)
            artifact_prefix = self._relative_key(artifact_dir)
            # Report browsing is prefix-based. Refuse a pipeline result that placed
            # reports elsewhere, ensuring every nested report is addressable through
            # `<artifact_prefix>/reports/...` without copying or absolute DB paths.
            try:
                reports_relative = reports_dir.relative_to(artifact_dir).as_posix()
            except ValueError as exc:
                raise ValueError("Training reports escaped the model artifact directory") from exc
            if reports_relative != "reports":
                raise ValueError("Training reports must be stored at <artifact>/reports")
            if not reports_dir.is_dir():
                raise FileNotFoundError(f"Training reports directory is missing: {reports_dir}")
            self._relative_key(reports_dir)
            metrics = _normalize_metrics(result.metrics)

            with self.database.session_factory() as db:
                job = db.get(TrainingJob, job_id)
                if job is None or JobStatus(job.status) != JobStatus.RUNNING:
                    return
                if job.model is not None:
                    raise RuntimeError("Training job already has a model")
                model = TrainedModel(
                    model_version=job.model_version,
                    version_number=job.version_number,
                    dataset_version=job.dataset_version,
                    training_config=job.training_config,
                    metrics=metrics,
                    checkpoint_key=checkpoint_key,
                    core_ml_key=core_ml_key,
                    artifact_prefix=artifact_prefix,
                    job=job,
                )
                apply_job_update(
                    job,
                    status=JobStatus.COMPLETED,
                    phase=JobPhase.COMPLETED,
                    progress=100,
                    error_message=None,
                    error_message_was_set=True,
                )
                db.add(model)
                db.commit()
            LOGGER.info("Completed training job %s as %s", job_id, model_version)
        except Exception as exc:
            LOGGER.exception("Training job %s failed", job_id)
            with self.database.session_factory() as db:
                job = db.get(TrainingJob, job_id)
                if job is not None and JobStatus(job.status) == JobStatus.RUNNING:
                    apply_job_update(
                        job,
                        status=JobStatus.FAILED,
                        phase=JobPhase.FAILED,
                        progress=job.progress,
                        error_message=str(exc)[:10_000],
                        error_message_was_set=True,
                    )
                    db.commit()
        finally:
            if config_key is not None:
                self.storage.delete(config_key)

    def run_once(self, worker_id: str) -> bool:
        job_id = self.claim_next_job(worker_id)
        if job_id is None:
            return False
        self.run_claimed_job(job_id)
        return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Money Trainer persistent worker")
    parser.add_argument("--once", action="store_true", help="Process at most one job")
    arguments = parser.parse_args()
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    settings = Settings()
    worker = TrainingWorker(settings)
    worker.initialize()
    worker_id = os.getenv("WORKER_ID", f"worker-{os.getpid()}")
    poll_seconds = max(0.1, float(os.getenv("WORKER_POLL_SECONDS", "2")))
    stop = threading.Event()

    def request_stop(*_: object) -> None:
        stop.set()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    try:
        if arguments.once:
            worker.run_once(worker_id)
            return
        while not stop.is_set():
            if not worker.run_once(worker_id):
                stop.wait(poll_seconds)
    finally:
        worker.database.dispose()


if __name__ == "__main__":
    main()
