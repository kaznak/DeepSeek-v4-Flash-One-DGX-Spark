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
# The container belongs to dockerd, not to this process tree, so a signal to
# this script does not reach it. When systemd stops the supervisor it sends
# SIGTERM to every process in the unit's cgroup at once; this script dies
# first, the supervisor sees its upstream already gone and never runs
# cmdStop, and the container keeps its ~114 GiB. Stop it here on TERM/INT.
#
set -Eeuo pipefail
cd "$(dirname "$0")/.."

export SERVING_PORT="${1:?usage: gx10/serve.sh <port>}"
./gx10/start.sh --no-wait

docker compose -f compose.yml logs -f --no-log-prefix &
logs_pid=$!

stop_server() {
  trap - TERM INT
  kill "$logs_pid" 2>/dev/null || true
  ./gx10/start.sh stop
  exit 143
}
trap stop_server TERM INT

wait "$logs_pid"
