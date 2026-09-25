#!/usr/bin/env bash
#
# Fetch the weights through modelkeep, coalesce TP4 -> TP1, verify, and drop
# the TP4 source. Replaces download.sh on GX10.
#
# download.sh runs snapshot_download inside the image against huggingface.co.
# Here the weights come from modelkeep (a pull-through HF mirror on the NAS),
# so the download runs on the host with HF_ENDPOINT, and only the coalesce and
# verify steps run in the image (same scripts, same arguments as download.sh).
#
# FETCH_REVISION: modelkeep holds main (ce5ff0f1), not the pinned 22f28d32.
# The two differ only in README.md; all 189 weight/config files have the same
# blobId. Asking modelkeep for 22f28d32 starts a fresh upstream pull instead.
# The files are still placed under snapshots/22f28d32, which start.sh expects.
#
# Peak disk: ~107 GB source + ~107 GB TP1 (carried files are copied, not
# hard-linked, because /hf-cache and /models are separate bind mounts).
#
set -Eeuo pipefail
cd "$(dirname "$0")/.."

: "${HF_ENDPOINT:?set HF_ENDPOINT to the modelkeep base URL}"
MODEL_REPO=0xSero/deepseek-v4-flash-0731-spark
MODEL_REVISION=22f28d32b9b29b4352eaa380ff8c2c170b2847ab
FETCH_REVISION="${FETCH_REVISION:-ce5ff0f1efb2e184aafc759d281bfae47d3a359c}"
# shellcheck disable=SC2016  # the pattern matches the literal ${IMAGE_DIGEST:-...} in start.sh
IMAGE_DIGEST="${IMAGE_DIGEST:-$(sed -n 's/^IMAGE_DIGEST="${IMAGE_DIGEST:-\(.*\)}"$/\1/p' start.sh)}"
repo_dir="hf-hub/hub/models--${MODEL_REPO//\//--}"
snapshot_host="$repo_dir/snapshots/$MODEL_REVISION"
snapshot_in_container="/hf-cache/hub/models--${MODEL_REPO//\//--}/snapshots/$MODEL_REVISION"

if [ -f data/tp1/rank-sliced-tp1-manifest.json ]; then
  echo "TP1 manifest already present — nothing to do."
  exit 0
fi

mkdir -p "$snapshot_host" data

echo ">> fetch $MODEL_REPO@$FETCH_REVISION from $HF_ENDPOINT $(date -Is)"
# hf download exits non-zero when modelkeep answers 500 for its staging lease
# even though every file arrived, so completeness is judged by the file count.
HF_ENDPOINT="$HF_ENDPOINT" HF_HUB_DISABLE_PROGRESS_BARS=1 \
  hf download "$MODEL_REPO" --revision "$FETCH_REVISION" --local-dir "$snapshot_host" \
  || echo ">> hf download exited $?; checking files"
expected="$(curl -fsS "$HF_ENDPOINT/api/models/$MODEL_REPO/revision/$FETCH_REVISION" | jq '.siblings | length')"
actual="$(find "$snapshot_host" -maxdepth 1 -type f | wc -l)"
[ "$actual" = "$expected" ] || { echo "file count $actual != $expected" >&2; exit 1; }

echo ">> coalesce $(date -Is)"
docker run --rm \
  -v "$(pwd)/hf-hub":/hf-cache \
  -v "$(pwd)/data":/models \
  -v "$(pwd)/image-patch/coalesce_rank_sliced_exl3.py":/opt/recipe/scripts/coalesce_rank_sliced_exl3.py:ro \
  --entrypoint /opt/runtime-venv/bin/python \
  "$IMAGE_DIGEST" /opt/recipe/scripts/coalesce_rank_sliced_exl3.py \
    --input-dir "$snapshot_in_container" \
    --output-dir /models/tp1 \
    --link-carried \
    --reuse-complete \
    --workers 1

echo ">> verify $(date -Is)"
docker run --rm \
  -v "$(pwd)/data":/models \
  --entrypoint /opt/runtime-venv/bin/python \
  "$IMAGE_DIGEST" /opt/recipe/scripts/verify_tp1_manifest.py /models/tp1

rm -rf "$repo_dir"
echo ">> done $(date -Is)"
