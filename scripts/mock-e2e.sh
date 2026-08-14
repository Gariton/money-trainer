#!/usr/bin/env bash
set -euo pipefail

api_url="${API_URL:-http://127.0.0.1:8000}"
api_token="${API_TOKEN:-local-development-token}"
task_tmp="$(mktemp -d)"

cleanup() {
  find "$task_tmp" -type f -delete
  rmdir "$task_tmp"
}
trap cleanup EXIT

# A synthetic 1x1 PNG. It contains no real currency imagery.
base64 --decode >"$task_tmp/mock.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=
PNG

annotations='[
  {"class":"jpy_1",   "x":0.02,"y":0.02,"width":0.12,"height":0.12},
  {"class":"jpy_5",   "x":0.18,"y":0.02,"width":0.12,"height":0.12},
  {"class":"jpy_10",  "x":0.34,"y":0.02,"width":0.12,"height":0.12},
  {"class":"jpy_50",  "x":0.50,"y":0.02,"width":0.12,"height":0.12},
  {"class":"jpy_100", "x":0.66,"y":0.02,"width":0.12,"height":0.12},
  {"class":"jpy_500", "x":0.82,"y":0.02,"width":0.12,"height":0.12}
]'

auth_header="Authorization: Bearer $api_token"

# Three independent capture sessions allow grouped train/validation/test splitting,
# while every split still contains all six synthetic labels.
for session_number in 1 2 3; do
  curl --fail --silent --show-error \
    -H "$auth_header" \
    -F "image=@$task_tmp/mock.png;type=image/png" \
    -F "source=camera" \
    -F "capture_session_id=mock-session-$session_number" \
    -F "review_status=reviewed" \
    -F "annotations=$annotations" \
    "$api_url/datasets/images" >/dev/null
done

job_json="$(
  curl --fail --silent --show-error \
    -H "$auth_header" \
    -H "Content-Type: application/json" \
    -d '{"mock_mode":true}' \
    "$api_url/training/jobs"
)"
job_id="$(jq -er '.id' <<<"$job_json")"
model_version="$(jq -er '.model_version' <<<"$job_json")"
echo "Queued $model_version ($job_id)"

for _ in $(seq 1 180); do
  job_json="$(curl --fail --silent --show-error -H "$auth_header" "$api_url/training/jobs/$job_id")"
  job_status="$(jq -er '.status' <<<"$job_json")"
  job_phase="$(jq -er '.phase' <<<"$job_json")"
  job_progress="$(jq -er '.progress' <<<"$job_json")"
  echo "$job_phase $job_progress%"
  if [[ "$job_status" == "completed" ]]; then
    model_id="$(jq -er '.model_id' <<<"$job_json")"
    model_json="$(
      curl --fail --silent --show-error \
        -H "$auth_header" \
        "$api_url/models/$model_id"
    )"
    completed_version="$(jq -er '.model_version' <<<"$model_json")"
    jq -e '.core_ml_available == true' <<<"$model_json" >/dev/null
    if [[ "$completed_version" != "$model_version" ]]; then
      echo "Completed model $completed_version does not match queued $model_version" >&2
      exit 1
    fi

    model_archive="$task_tmp/MoneyDetector.mlpackage.zip"
    curl --fail --silent --show-error \
      -H "$auth_header" \
      -o "$model_archive" \
      "$api_url/models/$model_id/download"
    if [[ "$(LC_ALL=C head -c 2 "$model_archive")" != "PK" ]]; then
      echo "Downloaded Core ML artifact is not a ZIP archive" >&2
      exit 1
    fi

    reports_json="$(
      curl --fail --silent --show-error \
        -H "$auth_header" \
        "$api_url/models/$model_id/reports"
    )"
    report_count="$(jq -er '.items | length' <<<"$reports_json")"
    if (( report_count < 1 )); then
      echo "Completed model has no browsable evaluation reports" >&2
      exit 1
    fi
    first_report_url="$(jq -er '.items[0].url' <<<"$reports_json")"
    curl --fail --silent --show-error \
      -H "$auth_header" \
      -o "$task_tmp/report-artifact" \
      "$api_url$first_report_url"
    if [[ ! -s "$task_tmp/report-artifact" ]]; then
      echo "Downloaded evaluation report is empty" >&2
      exit 1
    fi

    echo "Verified $completed_version: Core ML ZIP + $report_count report artifact(s)"
    jq . <<<"$model_json"
    exit 0
  fi
  if [[ "$job_status" == "failed" ]]; then
    jq -r '.error_message // "Training failed"' <<<"$job_json" >&2
    exit 1
  fi
  sleep 1
done

echo "Timed out waiting for $job_id" >&2
exit 1
