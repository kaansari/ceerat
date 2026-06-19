#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$ROOT_DIR/scripts/common.sh"

KEEP_DB=false
KEEP_TYPESENSE=false

for arg in "$@"; do
  case "$arg" in
    --keep-db) KEEP_DB=true ;;
    --keep-typesense) KEEP_TYPESENSE=true ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./stop-stack.sh [--keep-db] [--keep-typesense]

Stops the local Ceerat stack.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

stop_pidfile() {
  local name="$1"
  local pid_file="$2"
  local port="$3"
  local pid=""

  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file")"
  fi

  if ! is_pid_running "$pid"; then
    pid="$(pid_for_port "$port")"
  fi

  if is_pid_running "$pid"; then
    echo "Stopping $name (pid $pid)"
    kill "$pid" || true
  else
    echo "$name is not running"
  fi

  rm -f "$pid_file"
}

ensure_dirs

stop_pidfile "customer UI" "$CUSTOMER_PID" "$CEERAT_CUSTOMER_UI_PORT"
stop_pidfile "admin UI" "$ADMIN_PID" "$CEERAT_ADMIN_UI_PORT"
stop_pidfile "web UI" "$WEB_PID" "$CEERAT_WEB_UI_PORT"
stop_pidfile "agent service" "$AGENT_PID" "$CEERAT_AGENT_PORT"
stop_pidfile "user service" "$SERVICE_PID" "$CEERAT_SERVICE_PORT"

if [[ "$KEEP_TYPESENSE" == "true" ]]; then
  echo "Typesense left running"
elif is_port_listening "$TYPESENSE_PORT"; then
  echo "Stopping Typesense"
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      (cd "$ROOT_DIR" && docker compose -f docker-compose.typesense.yml down) || true
    elif docker container inspect ceerat-typesense >/dev/null 2>&1; then
      docker stop ceerat-typesense >/dev/null || true
    else
      echo "Typesense is listening, but no managed local container was found"
    fi
  else
    echo "Docker is not running; Typesense shutdown skipped"
  fi
else
  echo "Typesense is not running"
fi

if [[ "$KEEP_DB" == "true" ]]; then
  echo "Postgres left running"
elif [[ -x "$PG_CTL" && -d "$CEERAT_PGDATA" && "$(pid_for_port "$CEERAT_DB_PORT")" != "" ]]; then
  echo "Stopping Postgres on port $CEERAT_DB_PORT"
  env LANG=C LC_ALL=C "$PG_CTL" -D "$CEERAT_PGDATA" stop
else
  echo "Postgres is not running"
fi
