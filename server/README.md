# Money Trainer server

The FastAPI service is the control plane for dataset images, asynchronous training
jobs, and versioned Core ML artifacts. PostgreSQL stores metadata while an
`ObjectStorage` boundary stores images, immutable job manifests, models, and reports.
The included backend uses the local filesystem and can later be replaced by an
S3-compatible implementation.

## Run locally

```bash
cd server
python -m venv .venv
. .venv/bin/activate
pip install -e '.[test]'
API_TOKEN=development-token uvicorn app.main:app --reload
```

SQLite is the default. Set `DATABASE_URL` to a SQLAlchemy PostgreSQL URL and set
`DATA_ROOT` to the shared API/training-worker artifact directory for Docker.
Interactive OpenAPI documentation is available at `/docs`. Send the configured token
as `Authorization: Bearer <token>` to application endpoints.

## Worker protocol

1. `POST /training/jobs/claim` with `{"worker_id":"worker-1"}` claims one queued job.
2. Download `GET /training/jobs/{id}/manifest` or read `dataset_manifest_key` from the
   shared data root.
3. Update phase/progress with `PATCH /training/jobs/{id}`.
4. Write artifacts under the shared data root and call `POST /models`; successful
   registration atomically completes the job.

The Core ML download contract is always a ZIP containing
`MoneyDetector.mlpackage`, including in mock mode.

`POST /inference` returns an empty annotation list before a real model is available
and for Mock Mode artifacts. For a real checkpoint it lazily uses the optional
Ultralytics runtime in a worker thread. If that runtime is absent or the checkpoint
cannot be loaded, the endpoint returns `503 inference_runtime_unavailable` rather
than silently pretending the model found no coins.

Install the real inference adapter with `pip install -e '.[ml]'`; the default API
image intentionally stays lightweight for Mock Mode.

## Tests

```bash
cd server
pytest
```
