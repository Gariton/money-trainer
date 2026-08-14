# Money Trainer セットアップ手順

このドキュメントは、Money Trainer の開発環境を macOS 上に構築し、iOS アプリからローカルの API サーバへ接続するまでの手順をまとめたものです。

推奨構成は次のとおりです。

```text
iPhone / iOS Simulator
        |
        | HTTP + Bearer token
        v
Docker Compose: api ---- PostgreSQL
        |
        +---- worker ---- training pipeline
```

## 1. 前提

### iOS 開発に必要なもの

- macOS
- iOS 26 SDK を含む Xcode
- Apple ID（実機で実行する場合）
- Homebrew と XcodeGen

```bash
brew install xcodegen
```

### サーバに必要なもの

- Docker Desktop
- `curl`
- `jq`

ホスト上で Python の API / 学習処理を実行する場合は、Python 3.11 以上と `uv` も必要です。

## 2. サーバを Docker Compose で起動する

リポジトリのルートで実行します。

```bash
cd /Users/gariton_/dev/money-trainer
cp .env.example .env
```

`.env` の `API_TOKEN` を開発用の値へ変更します。iOS アプリにも同じ値を入力するため、空欄にはしないでください。

```dotenv
API_TOKEN=ここにローカル開発用のトークンを設定
```

ローカル開発用のランダムな値を作る例:

```bash
openssl rand -hex 24
```

API、PostgreSQL、training worker をまとめて起動します。

```bash
docker compose up --build -d
```

起動状態と API のヘルスチェックを確認します。

```bash
docker compose ps
curl http://127.0.0.1:8000/health
```

次のレスポンスが返れば API は起動しています。

```json
{"status":"ok"}
```

OpenAPI の画面は [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs) で開けます。アプリケーション API は Bearer token が必要です。

### Compose サービス

| サービス | 役割 | ホストからの接続先 |
| --- | --- | --- |
| `postgres` | Dataset、Job、Model のメタデータを保存 | Compose 内部のみ |
| `api` | FastAPI API | `http://127.0.0.1:8000` |
| `worker` | queued の Training Job を処理 | API から内部利用 |
| `api-ml` | 実モデルの pre-annotation 用 API（任意） | `http://127.0.0.1:8001` |
| `worker-gpu` | NVIDIA GPU での実学習用 worker（任意） | API から内部利用 |

画像、manifest、モデル、レポートは `money-data` volume に、DB は `postgres-data` volume に保存されます。

### 起動・停止

```bash
# ログを確認
docker compose logs -f api worker

# 停止（DB と成果物は保持）
docker compose down

# DB と画像・モデル成果物も削除する場合のみ実行
docker compose down --volumes
```

`down --volumes` を実行すると、ローカルに保存した Dataset と Model artifact は復元できません。

## 3. iOS アプリをビルドする

`project.yml` が Xcode プロジェクトの source of truth です。ファイル追加や設定変更後はプロジェクトを再生成します。

```bash
cd /Users/gariton_/dev/money-trainer/ios
xcodegen generate
open MoneyTrainer.xcodeproj
```

Xcode で次を確認します。

1. `MoneyTrainer` scheme を選択する。
2. 実機で動かす場合は、Signing & Capabilities の Team に自分の Apple ID / Team を設定する。
3. Bundle Identifier `dev.moneytrainer.app` が自分の Team で使えない場合は、`ios/project.yml` の `PRODUCT_BUNDLE_IDENTIFIER` を固有値へ変更してから `xcodegen generate` を再実行する。
4. iOS 26 以上の iPhone または Simulator を実行先にする。

カメラ撮影と Live Test は Simulator では利用できないため、実機で確認してください。初回起動時にはカメラ、写真ライブラリ、ローカルネットワークの許可を求められます。すべて許可してください。

## 4. iOS アプリからサーバへ接続する

アプリの `Settings` 画面で次を入力して `Save Configuration` を押します。その後 `Test Connection` を押して接続を確認します。

| 実行先 | Base URL |
| --- | --- |
| iOS Simulator | `http://127.0.0.1:8000` |
| Mac と同じ LAN に接続した iPhone | `http://<MacのLAN IP>:8000` |
| `api-ml` を使う場合 | 上記の末尾を `:8001` に変更 |

Mac の LAN IP は、環境に応じて次のコマンドで確認できます。

```bash
ipconfig getifaddr en0
```

Wi-Fi が `en1` など別のインターフェースの場合は、システム設定のネットワーク情報から IPv4 アドレスを確認してください。

- `Base URL`: API の URL。末尾に `/docs` や `/health` は付けない。
- `Bearer token`: ルートの `.env` に設定した `API_TOKEN` と同じ値。

Token は iOS の Keychain、Base URL は UserDefaults に保存されます。ソースコードに token を書く必要はありません。

### iPhone 接続時の注意

- iPhone と Mac を同じ LAN に接続する。
- iPhone から `127.0.0.1` や `localhost` を指定しない。これは iPhone 自身を指す。
- Docker の API がホストの `8000` ポートで公開されていることを確認する。
- macOS Firewall が Docker Desktop の受信を遮断していないことを確認する。
- アプリのローカルネットワーク権限を許可する。

API が Mac 上で動作しているかを確認する場合:

```bash
curl http://127.0.0.1:8000/health
```

## Apache で FQDN / HTTPS 経由にする

Apache のリバースプロキシ設定テンプレートを [deploy/apache/money-trainer.conf](../deploy/apache/money-trainer.conf) に用意しています。これは、Docker の API を `127.0.0.1:8000` で公開し、Apache を `:80` / `:443` の入口にする構成です。

1. 設定ファイル上部の `Define MONEY_TRAINER_FQDN` を、ローカル DNS に登録した実際の FQDN へ変更する。
2. `Define MONEY_TRAINER_CERT_DIR` を証明書ディレクトリへ変更する。証明書ファイルは `<FQDN>.crt`、秘密鍵は `<FQDN>.key` として配置する。
3. Apache の `mod_ssl`、`mod_proxy`、`mod_proxy_http`、`mod_headers` を有効にする。
4. VirtualHost を有効化し、設定を検証して reload する。

Debian / Ubuntu の例:

```bash
sudo cp deploy/apache/money-trainer.conf /etc/apache2/sites-available/money-trainer.conf
sudo a2enmod ssl proxy proxy_http headers
sudo a2ensite money-trainer.conf
sudo apachectl configtest
sudo systemctl reload apache2
```

疎通確認:

```bash
curl https://api.example.local/health
```

iOS の Base URL は次のように変更します。

```text
https://api.example.local
```

証明書の SAN に FQDN が含まれている必要があります。ローカル CA や自己署名証明書を使う場合は、iPhone に CA 証明書をインストールして信頼させてください。証明書が信頼されていない場合、ATS の設定を追加しても HTTPS 接続は失敗します。

## 5. 最初の動作確認

サーバ単体の API 接続を確認した後、Mock vertical slice を実行します。これは実際の硬貨画像を使わず、3 つの capture session、6 金種のダミー annotation、Mock Training Job、Core ML ZIP、failure report の取得まで確認します。

```bash
API_TOKEN="$(sed -n 's/^API_TOKEN=//p' .env)" ./scripts/mock-e2e.sh
```

成功すると、Job の完了と Core ML ZIP / report artifact の検証結果が表示されます。iOS アプリでは次の順に確認します。

1. `Settings` → `Test Connection`
2. `Dataset` → 画像の撮影または Photo Library からの追加
3. Annotation Editor → Bounding Box と金種を確定
4. `Training` → Mock Mode の Job を開始
5. `Models` → 完成した Model の download / activate
6. `Live Test` → 実機カメラで確認

## 6. 実モデルを使う場合

### 実 pre-annotation API

デフォルトの `api` image は軽量な Mock vertical slice 用で、Ultralytics runtime を含みません。実際の checkpoint を使った `/inference` を試す場合は、別 profile の API を起動します。

```bash
docker compose --profile inference up --build -d api-ml
curl http://127.0.0.1:8001/health
```

iOS の Base URL を `http://<MacのLAN IP>:8001` に変更します。`api-ml` は `api` と同じ PostgreSQL / `money-data` を使うため、Dataset、Job、Model の状態は共有されます。

### 実学習

- Apple Silicon Mac: Docker の Linux container より、macOS ホスト上の training 環境で実行する方法を推奨します。MPS と macOS の Core ML validation を利用できます。
- NVIDIA Linux host: `worker` を停止してから GPU profile を起動します。

```bash
docker compose stop worker
docker compose up --build -d postgres api
docker compose --profile gpu up --build -d worker-gpu
```

同じ queue を `worker` と `worker-gpu` が同時に処理しないようにしてください。Ultralytics / Core ML Tools の license と配布条件は、実運用前に確認してください。

## 7. Docker を使わずに API と worker を起動する場合

これは SQLite を使う開発用構成です。API と worker は同じ `DATABASE_URL`、`DATA_ROOT`、`API_TOKEN` を使用してください。

### API

```bash
cd /Users/gariton_/dev/money-trainer/server
uv sync --extra test
API_TOKEN='local-token' DATABASE_URL='sqlite:///./data/money_trainer.db' DATA_ROOT='./data' uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

`--host 0.0.0.0` は、実機 iPhone から Mac の LAN IP 経由で接続するために必要です。API だけを起動した場合、Training Job を処理する worker は別途起動してください。

### worker

API 用の virtual environment に training package もインストールします。

```bash
cd /Users/gariton_/dev/money-trainer/server
uv pip install -e '../training[yaml]'
```

別ターミナルで、API と同じ環境変数を設定して worker を起動します。

```bash
cd /Users/gariton_/dev/money-trainer/server
API_TOKEN='local-token' DATABASE_URL='sqlite:///./data/money_trainer.db' DATA_ROOT='./data' uv run python -m app.worker
```

worker は queued の Job を定期的に取得します。Job が `queued` のまま進まない場合は、worker のログと `DATA_ROOT` が API と一致しているかを確認してください。

## 8. 主要な環境変数

### Docker Compose（ルート `.env`）

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `API_TOKEN` | `local-development-token` | iOS、API、worker で共有する Bearer token |
| `API_PORT` | `8000` | 軽量 API のホスト公開ポート |
| `API_ML_PORT` | `8001` | `api-ml` のホスト公開ポート |
| `MAX_UPLOAD_BYTES` | `20971520` | 画像 1 枚あたりの最大 upload サイズ（20 MiB） |
| `WORKER_POLL_SECONDS` | `2` | worker の queue polling 間隔 |
| `POSTGRES_USER` | `money_trainer` | PostgreSQL ユーザー |
| `POSTGRES_PASSWORD` | `money_trainer` | PostgreSQL パスワード |
| `POSTGRES_DB` | `money_trainer` | PostgreSQL DB 名 |

### API / worker を直接起動する場合

| 変数 | 用途 |
| --- | --- |
| `DATABASE_URL` | SQLAlchemy の DB URL。開発用 SQLite は `sqlite:///./data/money_trainer.db` |
| `DATA_ROOT` | 画像、manifest、モデル、レポートを保存するルート |
| `API_TOKEN` | API 認証 token。iOS と一致させる |
| `DATASET_SPLIT_TRAIN` | train split の比率。既定値 `0.70` |
| `DATASET_SPLIT_VALIDATION` | validation split の比率。既定値 `0.15` |
| `DATASET_SPLIT_TEST` | test split の比率。既定値 `0.15` |
| `WORKER_ID` | worker の識別子。未設定時はプロセス ID から生成 |

split の 3 比率の合計は 1 でなければなりません。

## 9. よくある問題

### iPhone から API に接続できない

Base URL が `127.0.0.1` になっていないか、Mac の LAN IP と `8000` ポートを指定しているかを確認します。次に、同じ LAN、macOS Firewall、iOS のローカルネットワーク権限を確認します。

### `401 Unauthorized` になる

iOS Settings の token と `.env` の `API_TOKEN` が完全に一致しているかを確認します。空白や改行を含めないでください。

### Training Job が `queued` のままになる

worker が起動しているか確認します。

```bash
docker compose logs -f worker
```

Docker を使わない構成では、API と同じ DB / `DATA_ROOT` を指定した `python -m app.worker` が別ターミナルで動いていることを確認します。

### Training 開始時に `422` になる

Training 前の validation が失敗しています。すべての画像を review 済みにし、`captureSessionId` を設定してください。train / validation / test を埋めるため、少なくとも 3 つの独立した capture session が必要です。6 金種が各 split に登場するデータ構成も必要です。

### 実 pre-annotation が `503` になる

`api-ml` が起動していること、実モデルに checkpoint が登録されていること、Ultralytics runtime がインストールされていることを確認します。Mock Model は精度モデルではないため、Mock Mode では annotation は空になります。

### Xcode でファイルや設定が反映されない

`ios/project.yml` を変更した後に `cd ios && xcodegen generate` を実行し、Xcode でプロジェクトを開き直してください。

## 関連ドキュメント

- [アーキテクチャ](ARCHITECTURE.md)
- [iOS README](../ios/README.md)
- [Server README](../server/README.md)
- [Training README](../training/README.md)
