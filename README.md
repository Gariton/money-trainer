# Money Trainer

日本円硬貨6金種 (`jpy_1`, `jpy_5`, `jpy_10`, `jpy_50`, `jpy_100`, `jpy_500`) のObject Detectionモデルを、iPhoneからデータ収集・アノテーション・学習・評価・Core ML配布・実機確認まで回すためのローカルファースト開発環境です。実際の硬貨画像や学習済みweightは含みません。

```text
money-trainer/
├── ios/       SwiftUI / AVFoundation / Vision / Core ML
├── server/    FastAPI / PostgreSQL / filesystem storage
└── training/  grouped split / YOLO26n / evaluation / Core ML
```

設計の詳細は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) にあります。

## Quick start: Mock vertical slice

必要なものはDocker Desktop、`curl`、`jq`です。

```bash
cp .env.example .env
# .env の API_TOKEN をローカル環境用の値へ変更
docker compose up --build -d
curl http://127.0.0.1:8000/health
API_TOKEN='<.envと同じ値>' ./scripts/mock-e2e.sh
```

スクリプトは実在通貨を含まない小さなPNGを3つの異なる`captureSessionId`で登録し、6金種のダミーBBoxを確定し、Mock Training JobがModelを登録するまでpollします。完了後はCore ML ZIPとfailure reportの取得も検証します。API仕様は [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs) で確認できます。

Defaultの`api` imageはMock vertical slice向けに軽量化されており、実Checkpointを使う
`POST /inference`ではUltralytics runtimeが必要です。real pre-annotationを試す場合は、
別portのopt-in profileを起動します。

```bash
docker compose --profile inference up -d --build api-ml
curl http://127.0.0.1:8001/health
```

`api-ml`はdefault APIと同じPostgreSQL・artifact volumeを使用し、host側は`8001`
（`API_ML_PORT`で変更可能）です。iPhoneアプリのBase URLを一時的に
`http://<MacのLAN IP>:8001`へ切り替えると、Dataset/Job/Model APIを含め同じ状態で
real pre-annotationを利用できます。default `api`は`8000`のままなのでport競合しません。

停止する場合:

```bash
docker compose down
```

DBとartifactも消す場合だけ、明示的にvolumeを削除してください。

```bash
docker compose down --volumes
```

## Architecture

- iOSアプリは撮影・Photo Library import、現在Modelでのpre-annotation、normalized BBox編集、Job監視、Model download/compile/activate、Live Test、誤認識FrameのDataset再投入を担当します。
- FastAPIはBearer token、入力検証、Dataset/Job/Modelメタデータ、artifact accessを担当します。HTTP request内でTrainingは実行しません。
- Workerは永続化された`queued` Jobをclaimし、Dataset snapshotを学習パイプラインへ渡し、結果をModel versionとして登録します。
- Trainingは全`captureSessionId` groupを壊さずに70/15/15へ分割します。画像単位random splitは行いません。
- iOSのActive capture sessionは撮影・Photo Library追加をまたいで維持され、照明・背景・場所を変えたときだけ明示的に更新します。
- 画像・modelはStorage interfaceのobject keyで扱い、MVPはfilesystem、将来はS3互換実装へ交換できます。

PostgreSQLはメタデータ、`money-data` volumeは画像、manifest、report、checkpoint、`MoneyDetector.mlpackage.zip`を保持します。

## iOS setup

iOS 26 SDKを含む安定版XcodeとXcodeGenを使用します。project設定は`ios/project.yml`がsource of truthです。

```bash
brew install xcodegen
cd ios
xcodegen generate
open MoneyTrainer.xcodeproj
```

Deployment targetはiOS 26、Swift language modeは6、iPhone/iPadの両方を対象にしています。Simulatorではカメラが使えないため、撮影・Live Testは実機で確認してください。

アプリのSettingsで次を設定します。

- Base URL: `http://<MacのLAN IP>:8000`
- API token: `.env`の`API_TOKEN`と同じ値

TokenはKeychain、Base URLはUserDefaultsへ保存します。ローカルHTTP接続は`NSAllowsLocalNetworking`だけを許可しています。MacのFirewallとiPhone/Macが同じLANにいることも確認してください。

## Server setup

Dockerを使わずAPIだけ起動する場合:

```bash
cd server
uv sync --extra test
API_TOKEN='local-token' \
DATABASE_URL='sqlite:///./data/money_trainer.db' \
DATA_ROOT='./data' \
uv run uvicorn app.main:app --reload
```

主なAPI:

- `POST /datasets/images`, `GET /datasets/stats`, image list/detail、annotation update
- `POST /inference`
- `POST /training/jobs`, Job list/detail
- `GET /models`, latest/detail/download
- `GET /models/{id}/reports` とfailure artifact download

Uploadはサイズ、MIME、magic bytesを検証し、client filenameをstorage pathに使用しません。全application routeはBearer token必須です。

## Dataset format

保存座標は画像サイズ非依存の左上原点です。

```json
{
  "class": "jpy_100",
  "x": 0.43,
  "y": 0.32,
  "width": 0.12,
  "height": 0.12
}
```

`x + width <= 1`、`y + height <= 1`を保証します。YOLO Dataset生成時だけ次へ変換します。

```text
center_x = x + width / 2
center_y = y + height / 2
```

画像recordは`id`, image key, `createdAt`, annotations, `source`, `captureSessionId`, `reviewStatus`, pre-annotationに使ったModel versionを保持します。Training開始時のmanifestはimmutable snapshotです。

## Training

依存なしMock Modeは、Dataset pathを省略するとダミーDatasetも生成します。

```bash
cd training
uv sync --extra yaml --extra test
uv run python -m money_trainer train --mock --output artifacts
```

実Dataset manifestを指定する例:

```bash
uv run python -m money_trainer train \
  --mock \
  --dataset /absolute/path/to/manifest.json \
  --output /absolute/path/to/artifacts \
  --model-version v1 \
  --dataset-version dataset-v1
```

処理順はDataset validation、grouped split、YOLO Dataset生成、training、test evaluation、best checkpoint、failure extraction、Core ML export、Core ML validation、version manifest保存です。進捗はstderrへJSON Lines、最終resultはstdoutへJSONで出力します。

設定は [training/money_trainer/default_config.yaml](training/money_trainer/default_config.yaml) を基準に、`--config`で別YAMLを指定できます。分割比、epochs、batch size、patience、augmentation、閾値、export設定はコードへ固定していません。

### Real YOLO training

実学習用dependencyを追加して`--real`を指定します。

```bash
cd training
uv sync --extra yaml --extra ml
uv run python -m money_trainer train \
  --real \
  --dataset /absolute/path/to/manifest.json \
  --output /absolute/path/to/artifacts \
  --model-version v1
```

default backendは小型の`yolo26n.pt`、inputは640、deviceは`CUDA -> MPS -> CPU`の順に自動選択します。rotationを中心に、brightness/contrast/exposure/blur/noise/scale/crop/perspective/shadowを現実的な範囲へ制限しています。

UltralyticsにはAGPL-3.0とEnterprise licenseの選択肢があります。配布・商用利用前にプロジェクトの利用形態とlicense条件を確認してください。

## GPU setup

defaultの`worker`はMock/CPU向けです。NVIDIA Container Toolkitが設定済みのLinux hostでは、通常workerを起動せずGPU profileを選びます。

```bash
docker compose up --build -d postgres api
docker compose --profile gpu up --build -d worker-gpu
```

すでにdefault workerを起動した場合は、同じqueueを競合させないため先に停止します。

```bash
docker compose stop worker
```

Apple Silicon Macで実学習する場合は、Docker Linux containerよりhost上の`uv run ... --real`を推奨します。これによりMPSとmacOS上のCore ML validationを使用できます。

## Evaluation and artifacts

Model versionごとに次を保存します。

```text
artifacts/vN/
├── checkpoints/
├── metrics.json
├── splits.json
├── reports/
│   ├── false-positives/
│   ├── false-negatives/
│   ├── low-confidence/
│   ├── confused-classes/
│   └── confusion_matrix.{json,csv}
├── MoneyDetector.mlpackage/
├── MoneyDetector.mlpackage.zip
├── coreml_validation.json
└── model.json
```

MetricsはmAP50、mAP50-95、precision、recallと金種別precision/recall/AP/AP50です。実Core ML validationはmacOSでPyTorch出力とのmatch rate、confidence差、IoUを比較します。Linuxでは構造検証のみになり、その事実をartifactへ記録します。

## Model deployment

iOSのModels画面でversionを選ぶと、archiveをdownloadし、安全に展開し、`MLModel.compileModel(at:)`で非同期compileします。load検証に成功した場合だけactive modelを切り替えるため、失敗時は直前のmodelが維持されます。過去versionも端末内registryから再activateできます。

Live TestはVisionのlegacy NMS outputとYOLO26 end-to-end `(1, 300, 6)` outputを扱い、BBox、confidence、金種別個数、合計金額を表示します。Correctionは現在Frameと修正済みBBoxをAnnotation Editorへ送り、確定後にDatasetへ追加します。

## Tests

```bash
cd server && uv run pytest
cd ../training && uv run pytest
cd ../ios && xcodegen generate
xcodebuild test \
  -project MoneyTrainer.xcodeproj \
  -scheme MoneyTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Server testsはDataset API、annotation/security validation、Job lifecycle、Model API、Storage/path safety、capture-session splitを対象にします。Training testsはvalidation、grouped split/leakage、YOLO生成、metrics、reports、Core ML comparison/Mock pipelineを対象にします。iOS testsは座標変換、JSON/API request、ViewModel、model archive/registry、YOLO26 output decodingを対象にします。

## Troubleshooting

### iPhoneからAPIへ接続できない

`127.0.0.1`はiPhone自身です。SettingsへMacのLAN IPを設定し、Macのport 8000、Firewall、同一LANを確認してください。

### Training開始が422になる

Training前validationが失敗しています。Responseの`detail.errors`には、未review画像、金種不足、BBox範囲外、画像file欠落、capture session不足などが入ります。最低3つの独立したcapture sessionを用意し、各金種が3 sessionすべてに登場するようにしてください。

### Core ML numerical validationがskipされる

Core ML runtime比較はmacOSで実行してください。Linux workerはexportと構造検証はできますが、Core ML inferenceの数値比較は行いません。

### Apple Silicon Dockerでreal ML imageをbuildできない

PyTorch/Core ML ToolsのLinux arm64 wheel対応に依存します。Mac hostの`uv`環境を使うか、NVIDIA Linux hostでGPU profileを使用してください。Mock vertical sliceにはML dependencyは不要です。
