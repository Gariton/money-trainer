# Money Trainer architecture

Money Trainer is a local-first developer system with three independently testable components.

```text
iPhone (SwiftUI / AVFoundation / Vision)
                  |
                  | JSON + multipart, bearer token
                  v
FastAPI ---- PostgreSQL metadata
   |               |
   |               +---- queued job state / metrics / model versions
   v
Storage abstraction (images, manifests, reports, model archives)
   ^
   |
Training worker ---- money_trainer pipeline ---- YOLO26n / Core ML
```

## Ownership boundaries

- `ios/` owns capture, review, annotation editing, job monitoring, downloaded-model activation, and live testing. Bounding boxes are normalized before crossing the API boundary.
- `server/` owns authentication, validation, metadata persistence, storage paths, job coordination, and artifact downloads. HTTP handlers never run training synchronously.
- `training/` owns grouped dataset splitting, YOLO dataset generation, backend execution, evaluation, failure reports, Core ML export, and cross-runtime validation.

The worker connects the latter two components. It atomically claims one queued job, exports an immutable dataset manifest, invokes the pipeline, then registers the resulting metrics and model archive. A failed process leaves a durable failed job with a user-visible reason. A restarted worker can continue claiming later queued jobs.

## Data leakage boundary

`captureSessionId` is required on every image. Split assignment hashes and balances whole capture-session groups; an individual group can never appear in more than one of train, validation, and test. The generated split manifest is stored with every model so the decision can be audited.

## Model contract

The default real backend is the maintained Ultralytics `yolo26n.pt` detection model at 640-pixel input. Backend imports are lazy, so API and Mock Mode do not require PyTorch, Ultralytics, or Core ML Tools. The iPhone consumes a versioned `MoneyDetector.mlpackage.zip`; it extracts, compiles, and activates the package without replacing the previous working version until compilation succeeds.

## Storage evolution

Database rows store object keys relative to a `Storage` interface, never arbitrary client paths. The MVP filesystem implementation applies safe generated names under one configured root. An S3-compatible implementation can replace it without changing route or training contracts.

