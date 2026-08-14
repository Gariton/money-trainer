# Money Trainer iOS

開発者が iPhone 上で画像収集、アノテーション、学習 Job 操作、Core ML モデル配布、実機 Live Test、失敗例の再収集まで行う SwiftUI アプリです。deployment target は iOS 26、Swift language mode は 6、外部 runtime dependency はありません。

## 開く・実行する

生成済みの `MoneyTrainer.xcodeproj` を Xcode で開き、`MoneyTrainer` scheme を実機または iOS 26+ Simulator で実行します。プロジェクト定義の source-of-truth は `project.yml` です。ファイル追加後は次で再生成できます。

```bash
cd ios
xcodegen generate
```

初回起動後、Settings で FastAPI の Base URL と Bearer token を保存します。Token は Keychain、URL は UserDefaults に保存されます。実機から Mac 上の API へ接続する場合、`127.0.0.1` ではなく Mac の LAN IP（例 `http://192.168.1.20:8000`）を設定してください。

## Architecture

- `App`: dependency composition と iOS 26 `Tab` navigation
- `Domain`: API DTO、硬貨クラス、normalized box、metrics
- `Networking`: actor ベース API client、Bearer auth、multipart、structured errors
- `Services`: Dataset / Inference / Training / Model API boundary
- `Features`: Dataset、Capture、Annotation、Training、Models/Reports、LiveTest、Settings
- `MoneyTrainerTests`: 座標、契約 fixture、request/multipart、ViewModel、model registry、YOLO output decoder

共有 UI state は `@MainActor @Observable`、ネットワーク・filesystem・Core ML compile は actor/protocol boundary を通します。Bounding Box は内部で center-based rect として編集し、API では normalized top-left `x/y/width/height` に変換します。同じ撮影条件の leakage を避けるため、全 upload に `capture_session_id` を保持します。

## 主なフロー

1. Dataset から AVFoundation 撮影、または PhotosPicker で画像を選択（JPEGへ正規化）。同じ撮影条件ではActive capture sessionを維持し、照明・背景・場所を変えたときだけ新しいSessionを開始
2. `/inference` で pre-annotationし、モデルなし/失敗時は空の Editor を開く
3. Box の追加、選択、移動、リサイズ、削除、金種変更を行い Dataset へ保存
4. Training で server-side validation 後に Job を開始し、非終端 Job を3秒間隔で再取得
5. Models で ZIP を取得、安全に展開し、async Core ML compile/load validation 後に Activate
6. Live Test で Vision overlay、金種別個数、合計金額を表示し、誤認識 Frame を修正して Dataset へ戻す
7. Models の Failure Reports から false positive / false negative / low confidence / confused class 画像を閲覧

Live Test は Vision の `VNRecognizedObjectObservation` と、YOLO26 Core ML の `predictions` MultiArray `[1,300,6]` / `[300,6]`（`x1,y1,x2,y2,confidence,class_id`）の双方に対応します。

## Build / Test

```bash
xcodebuild \
  -project ios/MoneyTrainer.xcodeproj \
  -scheme MoneyTrainer \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing

xcodebuild \
  -project ios/MoneyTrainer.xcodeproj \
  -scheme MoneyTrainer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

カメラ入力と実モデルのフレームレート/座標は実機で確認してください。Simulator では photo import、API、Editor、Job/Model UI と unit tests を確認できます。ZIP extractor は server が生成する通常の stored/deflate entry に対応し、暗号化・data descriptor・path traversal を拒否します。
