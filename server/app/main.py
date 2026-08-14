from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI

from .api import datasets, inference, models, training
from .config import Settings
from .database import Database
from .dependencies import require_api_token
from .inference_engine import InferenceEngine, LazyUltralyticsInferenceEngine
from .schemas import HealthResponse
from .services import ensure_system_state
from .storage import LocalObjectStorage, ObjectStorage


def create_app(
    settings: Settings | None = None,
    *,
    database: Database | None = None,
    storage: ObjectStorage | None = None,
    inference_engine: InferenceEngine | None = None,
) -> FastAPI:
    settings = settings or Settings()
    database = database or Database(settings.database_url)
    storage = storage or LocalObjectStorage(settings.data_root)
    inference_engine = inference_engine or LazyUltralyticsInferenceEngine()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        database.create_schema()
        with database.session_factory() as db:
            ensure_system_state(db)
        yield
        database.dispose()

    app = FastAPI(
        title="Money Trainer API",
        version="0.1.0",
        description=(
            "Local-first API for Japanese coin dataset capture, asynchronous training "
            "jobs, Core ML model artifacts, and failure reports. All application "
            "endpoints use Bearer token authentication."
        ),
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.database = database
    app.state.storage = storage
    app.state.inference_engine = inference_engine

    secured = [Depends(require_api_token)]
    app.include_router(datasets.router, dependencies=secured)
    app.include_router(inference.router, dependencies=secured)
    app.include_router(training.router, dependencies=secured)
    app.include_router(models.router, dependencies=secured)

    @app.get("/health", response_model=HealthResponse, tags=["system"])
    def health() -> HealthResponse:
        return HealthResponse()

    return app


app = create_app()
