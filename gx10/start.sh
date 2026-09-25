#!/usr/bin/env bash
#
# start.sh with GX10 defaults. Arguments pass through (./gx10/start.sh stop, ...).
#
# SERVING_PORT: otelcol-contrib on GX10 already listens on 127.0.0.1:8888 for
#   its own metrics, so the upstream default fails with EADDRINUSE.
# SERVING_HOST: the port has no auth in front of it; keep it on loopback.
# GPU_MEMORY_UTILIZATION: upstream's 0.94 assumes a DGX Spark reporting
#   121.63 GiB. GX10 reports 119.63 GiB (122500 MiB), so 0.94 leaves 6.01 GiB
#   for KV against the 7.44 GiB a 384k request needs.
#   vLLM refuses to start unless the free memory it sees at startup covers the
#   whole budget, and on a headless GX10 that is 114.22 GiB. 0.953 (114.01 GiB,
#   8.05 GiB of KV) fits with only 0.21 GiB to spare and did fail once at
#   113.98 GiB with the desktop still running. 0.95 (113.65 GiB) keeps ~0.57 GiB
#   of slack and still leaves ~7.7 GiB of KV for the 384k context.
#
set -Eeuo pipefail
cd "$(dirname "$0")/.."

export SERVING_HOST="${SERVING_HOST:-127.0.0.1}"
export SERVING_PORT="${SERVING_PORT:-8889}"
export GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.95}"

exec ./start.sh "$@"
