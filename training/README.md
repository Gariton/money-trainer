# Money Trainer training pipeline

This directory is an installable, server-worker friendly Python package. It
validates a reviewed dataset, performs a deterministic capture-session grouped
split, generates YOLO labels, trains/evaluates a small maintained YOLO26 model,
exports Core ML, validates the export, and writes versioned artifacts.

## Install and run

Dependency-free Mock Mode (Python 3.11+):

```bash
cd training
python -m money_trainer train --mock --model-version v1
```

If the default `./dataset` path does not exist, Mock Mode creates a tiny
non-coin PNG dataset inside the version artifact. It produces deterministic
metrics and the same artifact contract as real training.

Real training:

```bash
cd training
python -m pip install -e '.[ml,yaml]'
python -m money_trainer train \
  --real \
  --dataset /data/manifest.json \
  --output /data/models \
  --model-version v14
```

`yolo26n.pt` at image size 640 is the default. The ML extra deliberately pins
Ultralytics to `>=8.4.104,<8.5`, the maintained YOLO26-compatible release line,
and keeps all heavy imports lazy. CUDA is preferred, Apple MPS is the next
fallback, then CPU. Review the Ultralytics license before distribution.

The container entrypoint is `python -m money_trainer`; a server-owned worker can
instead install this package and call `run_training(...)` directly.

The supplied Dockerfile defaults to the small Mock-capable image. Build the real
ML variant with `docker build --build-arg INSTALL_ML=1 training/`. For NVIDIA
training, use a CUDA/PyTorch-compatible base or install the matching CUDA wheel;
the runtime will select CUDA automatically when PyTorch reports it available.

## Manifest contract

Place `manifest.json` at the dataset root when image storage keys are relative:

```json
{
  "datasetVersion": "dataset-14",
  "images": [
    {
      "id": "image-1",
      "image": "images/image-1.jpg",
      "captureSessionId": "capture-session-1",
      "reviewStatus": "reviewed",
      "annotations": [
        {"class": "jpy_100", "x": 0.2, "y": 0.3, "width": 0.1, "height": 0.1}
      ]
    }
  ]
}
```

Manifest `x` and `y` are the normalized **top-left corner**. Width and height
are normalized. The generator converts these to YOLO center coordinates. All
paths must resolve inside the manifest directory; this makes a manifest at
`DATA_ROOT/manifest.json` with `image: images/...` the recommended server
layout. Both common camelCase and snake_case field aliases are accepted.

Validation rejects missing files/sessions, duplicate IDs, unreviewed images,
unknown classes, non-finite/zero/out-of-bounds boxes, insufficient class data,
empty splits, missing classes in a split, and any capture-session leakage.

## Configuration

The bundled [`money_trainer/default_config.yaml`](money_trainer/default_config.yaml)
contains every parameter. A partial YAML file passed with `--config` is merged
over these defaults. The class order is stable and intentionally cannot be
changed:

`jpy_1, jpy_5, jpy_10, jpy_50, jpy_100, jpy_500`.

Rotation, brightness, contrast/exposure, scale/crop, perspective, and flipping
map to maintained Ultralytics controls. The optional Albumentations adapter also
implements conservative blur, noise, and shadow transforms for custom/offline
loaders. Quantization is off by default so PyTorch/Core ML fidelity can be
measured before an INT8 rollout. YOLO26 is NMS-free, so export NMS is also off.

## Worker API

```python
from money_trainer import run_training

result = run_training(
    "/data/manifest.json",
    "/data/models",
    mock=False,
    model_version="v14",
    dataset_version="dataset-14",
    progress_callback=lambda event: persist(event.to_dict()),
)
```

The callback receives overall and stage progress. `PipelineResult` exposes the
checkpoint, package directory, downloadable ZIP, metrics/report/split paths,
backend name, Mock flag, structured metrics, and Core ML validation result.

Each `/data/models/v14` directory contains:

```text
training_config.yaml
dataset_validation.json
splits.json
yolo_dataset/
checkpoints/ or ultralytics/
metrics.json
reports/
  confusion_matrix.json
  confusion_matrix.csv
  failure_manifest.json
  false-positives/
  false-negatives/
  low-confidence/
  confused-classes/<actual>_as_<predicted>/
MoneyDetector.mlpackage/
MoneyDetector.mlpackage.zip
coreml_export.json
coreml_validation.json
model.json
```

## Core ML platform constraints and Mock semantics

Current Ultralytics Core ML export runs on macOS or x86 Linux. Core ML inference
and numerical validation run on macOS only. On macOS the validator compares
class-matched boxes, IoU, confidence delta, and detection match rate between the
PyTorch checkpoint and `.mlpackage`. A Linux export is explicitly recorded as
`structural-only-non-macos` and must be validated on a Mac before activation.

Mock Mode ships a tiny, compile-tested synthetic image-input `.mlpackage`, so
the default dependency-free/Docker path can complete download and Core ML
compilation without a `coremltools` wheel. Its `predictions` MLMultiArray has shape
`[1, 300, 6]`, uses normalized `[x1,y1,x2,y2,confidence,class_id]` rows, and
emits one constant `jpy_100` result so the Vision/decoder path can be exercised.
It is still not an accuracy model, and per-run metadata is written to the
sidecar because the vendored package is immutable. If the packaged template is
unexpectedly missing or corrupt, Mock Mode tries to regenerate it with
coremltools and finally falls back to a transparent package-shaped placeholder.
`coreml_export.json` always records `mockCompilable`, while
`coreml_validation.json` makes clear that detector fidelity was not validated.
iOS should keep the previously active model if any compilation fails.

Run tests with:

```bash
cd training
python -m pytest
```
