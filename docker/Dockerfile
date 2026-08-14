FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /opt/money-trainer
COPY server ./server
RUN pip install --no-cache-dir ./server

FROM base AS api
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# Optional real pre-annotation API. The default target deliberately omits the
# heavyweight PyTorch/Ultralytics runtime used to load YOLO checkpoints.
FROM base AS api-ml
RUN pip install --no-cache-dir "./server[ml]"
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

FROM base AS worker
COPY training ./training
RUN pip install --no-cache-dir "./training[yaml]"
CMD ["python", "-m", "app.worker"]

# Opt-in image for real YOLO/Core ML work. It is intentionally not pulled or
# built by the default Mock Mode vertical slice.
FROM worker AS worker-ml
RUN pip install --no-cache-dir "./training[ml]"
