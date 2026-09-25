#!/usr/bin/env bash
#
# Foreground entry point for a process supervisor such as llama-swap.
#
#   cmd:     gx10/serve.sh <port>
#   cmdStop: gx10/start.sh stop
#
# start.sh runs `docker compose up -d` and returns, but a supervisor needs a
# process that lives as long as the server. This starts the container on the
# given port, then follows its logs in the foreground; `compose logs -f`
# returns once the container stops, so this exits when the server does.
#
set -Eeuo pipefail
cd "$(dirname "$0")/.."

export SERVING_PORT="${1:?usage: gx10/serve.sh <port>}"
./gx10/start.sh --no-wait
exec docker compose -f compose.yml logs -f --no-log-prefix
