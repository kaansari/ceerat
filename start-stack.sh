#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$ROOT_DIR/scripts/common.sh"

SKIP_BUILD=false
SKIP_TESTS=true
SKIP_DB=false
SKIP_TYPESENSE=false

for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --with-tests) SKIP_TESTS=false ;;
    --skip-db) SKIP_DB=true ;;
    --skip-typesense) SKIP_TYPESENSE=true ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./start-stack.sh [--skip-build] [--with-tests] [--skip-db] [--skip-typesense]

Starts the local Ceerat stack using the same binaries built for Render.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

start_detached() {
  local log_file="$1"
  local pid_file="$2"
  shift 2

  nohup "$@" </dev/null >>"$log_file" 2>&1 &
  echo $! >"$pid_file"
}

ensure_postgres() {
  if [[ "$SKIP_DB" == "true" ]]; then
    echo "Postgres startup skipped"
    return
  fi

  if [[ ! -x "$PG_CTL" || ! -x "$INITDB" || ! -x "$PSQL" ]]; then
    echo "PostgreSQL 14 tools were not found. Set PG_CTL, INITDB, and PSQL or install postgresql@14." >&2
    exit 1
  fi

  if [[ ! -d "$CEERAT_PGDATA" ]]; then
    echo "Initializing Postgres data directory: $CEERAT_PGDATA"
    env LANG=C LC_ALL=C "$INITDB" -D "$CEERAT_PGDATA" -U "$CEERAT_DB_USER" -A trust -E UTF8 --locale=C
  fi

  if is_port_listening "$CEERAT_DB_PORT"; then
    echo "Postgres already listening on $CEERAT_DB_HOST:$CEERAT_DB_PORT"
    return
  fi

  echo "Starting Postgres on $CEERAT_DB_HOST:$CEERAT_DB_PORT"
  env LANG=C LC_ALL=C "$PG_CTL" -D "$CEERAT_PGDATA" -l "$POSTGRES_LOG" -o "-p $CEERAT_DB_PORT" start
}

start_typesense() {
  if [[ "$SKIP_TYPESENSE" == "true" || "$TYPESENSE_DISABLED" == "true" ]]; then
    echo "Typesense startup skipped"
    return
  fi

  if is_port_listening "$TYPESENSE_PORT"; then
    echo "Typesense already listening on localhost:$TYPESENSE_PORT"
    return
  fi

  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "Docker is not running; Typesense startup skipped"
    return
  fi

  echo "Starting Typesense on localhost:$TYPESENSE_PORT"
  if docker compose version >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && docker compose --env-file typesense.env -f docker-compose.typesense.yml up -d)
  elif docker container inspect ceerat-typesense >/dev/null 2>&1; then
    docker start ceerat-typesense >/dev/null
  else
    docker run -d \
      --name ceerat-typesense \
      -p "$TYPESENSE_PORT:8108" \
      -v ceerat-typesense-data:/data \
      typesense/typesense:29.0 \
      --data-dir /data \
      --api-key="$TYPESENSE_API_KEY" \
      --enable-cors >/dev/null
  fi
}

start_service() {
  local name="$1"
  local port="$2"
  local pid_file="$3"
  local log_file="$4"
  shift 4

  if is_port_listening "$port"; then
    echo "$name already listening on port $port"
    return
  fi

  echo "Starting $name on port $port"
  start_detached "$log_file" "$pid_file" "$@"
  sleep 1
}

ensure_dirs

if [[ "$SKIP_BUILD" != "true" ]]; then
  if [[ "$SKIP_TESTS" != "true" ]]; then
    "$ROOT_DIR/scripts/render-build.sh" test
  fi
  "$ROOT_DIR/scripts/render-build.sh" all
fi

ensure_postgres
start_typesense

start_service "user service" "$CEERAT_SERVICE_PORT" "$SERVICE_PID" "$SERVICE_LOG" env \
  PORT="$CEERAT_SERVICE_PORT" \
  DB_HOST="$CEERAT_DB_HOST" \
  DB_PORT="$CEERAT_DB_PORT" \
  DB_USER="$CEERAT_DB_USER" \
  DB_PASSWORD="$CEERAT_DB_PASSWORD" \
  DB_NAME="$CEERAT_DB_NAME" \
  JWT_SECRET="$CEERAT_JWT_SECRET" \
  JWT_AUTH_ENABLED="$JWT_AUTH_ENABLED" \
  CEERAT_USER_ADMIN_PORT="$CEERAT_USER_ADMIN_PORT" \
  CEERAT_ENV="$CEERAT_ENV" \
  INITIAL_ADMIN_EMAIL="${INITIAL_ADMIN_EMAIL:-admin@local}" \
  INITIAL_ADMIN_PASSWORD="${INITIAL_ADMIN_PASSWORD:-admin}" \
  INITIAL_ADMIN_NAME="${INITIAL_ADMIN_NAME:-Local Admin}" \
  TYPESENSE_HOST="$TYPESENSE_HOST" \
  TYPESENSE_PORT="$TYPESENSE_PORT" \
  TYPESENSE_PROTOCOL="$TYPESENSE_PROTOCOL" \
  TYPESENSE_API_KEY="$TYPESENSE_API_KEY" \
  TYPESENSE_COLLECTION_JOBS="$TYPESENSE_COLLECTION_JOBS" \
  TYPESENSE_DISABLED="$TYPESENSE_DISABLED" \
  "$BIN_DIR/ceerat-user-service"

start_service "agent service" "$CEERAT_AGENT_PORT" "$AGENT_PID" "$AGENT_LOG" env \
  PORT="$CEERAT_AGENT_PORT" \
  USER_SERVICE_ADDR="$USER_SERVICE_ADDR" \
  CEERAT_USER_SERVICE_ADDR="$USER_SERVICE_ADDR" \
  OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
  OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1-mini}" \
  "$BIN_DIR/ceerat-agent-service"

start_service "web UI" "$CEERAT_WEB_UI_PORT" "$WEB_PID" "$WEB_LOG" env \
  CEERAT_WEB_UI_PORT="$CEERAT_WEB_UI_PORT" \
  CEERAT_API_BASE_URL="$USER_SERVICE_ADDR" \
  CEERAT_AGENT_BASE_URL="$CEERAT_AGENT_BASE_URL" \
  CEERAT_WEB_UI_ROOT="$ROOT_DIR/apps-repo/apps/ceerat-web-ui" \
  CEERAT_ENV="$CEERAT_ENV" \
  "$BIN_DIR/ceerat-web-ui"

start_service "admin UI" "$CEERAT_ADMIN_UI_PORT" "$ADMIN_PID" "$ADMIN_LOG" env \
  CEERAT_ADMIN_UI_PORT="$CEERAT_ADMIN_UI_PORT" \
  CEERAT_API_BASE_URL="$USER_SERVICE_ADDR" \
  CEERAT_ADMIN_API_BASE_URL="$CEERAT_ADMIN_API_BASE_URL" \
  CEERAT_ADMIN_UI_ROOT="$ROOT_DIR/apps-repo/apps/ceerat-admin-ui" \
  CEERAT_ENV="$CEERAT_ENV" \
  "$BIN_DIR/ceerat-admin-ui"

start_service "customer UI" "$CEERAT_CUSTOMER_UI_PORT" "$CUSTOMER_PID" "$CUSTOMER_LOG" env \
  PORT="$CEERAT_CUSTOMER_UI_PORT" \
  CEERAT_API_BASE_URL="$USER_SERVICE_ADDR" \
  CEERAT_AGENT_BASE_URL="$CEERAT_AGENT_BASE_URL" \
  CEERAT_CUSTOMER_UI_ROOT="$ROOT_DIR/apps-repo/apps/ceerat-customer-ui" \
  CEERAT_ENV="$CEERAT_ENV" \
  "$BIN_DIR/ceerat-customer-ui"

"$ROOT_DIR/status.sh"
