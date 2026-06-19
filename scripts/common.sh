#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
RUN_DIR="$ROOT_DIR/.run"
LOG_DIR="$ROOT_DIR/logs"
MODULE_PATHS=(
  "contracts-repo/packages/ceerat-contracts"
  "services-repo/services/ceerat-user-service"
  "apps-repo/ai/ceerat-agent-service"
  "apps-repo/apps/ceerat-web-ui"
  "apps-repo/apps/ceerat-admin-ui"
  "apps-repo/apps/ceerat-customer-ui"
)

load_env_file() {
  local file="$1"

  if [[ -f "$file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
  fi
}

load_env_file "$ROOT_DIR/.env"
load_env_file "$ROOT_DIR/typesense.env"

PG_CTL="${PG_CTL:-/usr/local/opt/postgresql@14/bin/pg_ctl}"
INITDB="${INITDB:-/usr/local/opt/postgresql@14/bin/initdb}"
PSQL="${PSQL:-/usr/local/opt/postgresql@14/bin/psql}"
if [[ ! -x "$PG_CTL" && -x "/opt/homebrew/opt/postgresql@14/bin/pg_ctl" ]]; then
  PG_CTL="/opt/homebrew/opt/postgresql@14/bin/pg_ctl"
  INITDB="/opt/homebrew/opt/postgresql@14/bin/initdb"
  PSQL="/opt/homebrew/opt/postgresql@14/bin/psql"
fi

CEERAT_PGDATA="${CEERAT_PGDATA:-$ROOT_DIR/.local/postgres-14}"
CEERAT_DB_HOST="${CEERAT_DB_HOST:-localhost}"
CEERAT_DB_PORT="${CEERAT_DB_PORT:-55434}"
CEERAT_DB_USER="${CEERAT_DB_USER:-postgres}"
CEERAT_DB_PASSWORD="${CEERAT_DB_PASSWORD:-postgres}"
CEERAT_DB_NAME="${CEERAT_DB_NAME:-postgres}"
CEERAT_SERVICE_PORT="${CEERAT_SERVICE_PORT:-50051}"
CEERAT_USER_ADMIN_PORT="${CEERAT_USER_ADMIN_PORT:-8081}"
CEERAT_AGENT_PORT="${CEERAT_AGENT_PORT:-8088}"
CEERAT_WEB_UI_PORT="${CEERAT_WEB_UI_PORT:-3000}"
CEERAT_ADMIN_UI_PORT="${CEERAT_ADMIN_UI_PORT:-3010}"
CEERAT_CUSTOMER_UI_PORT="${CEERAT_CUSTOMER_UI_PORT:-3005}"
CEERAT_ENV="${CEERAT_ENV:-development}"
CEERAT_JWT_SECRET="${CEERAT_JWT_SECRET:-dev-secret}"
JWT_AUTH_ENABLED="${JWT_AUTH_ENABLED:-true}"
USER_SERVICE_ADDR="${USER_SERVICE_ADDR:-localhost:$CEERAT_SERVICE_PORT}"
CEERAT_AGENT_BASE_URL="${CEERAT_AGENT_BASE_URL:-http://localhost:$CEERAT_AGENT_PORT}"
CEERAT_ADMIN_API_BASE_URL="${CEERAT_ADMIN_API_BASE_URL:-http://localhost:$CEERAT_USER_ADMIN_PORT}"
TYPESENSE_HOST="${TYPESENSE_HOST:-localhost}"
TYPESENSE_PORT="${TYPESENSE_PORT:-8108}"
TYPESENSE_PROTOCOL="${TYPESENSE_PROTOCOL:-http}"
TYPESENSE_API_KEY="${TYPESENSE_API_KEY:-dev_typesense_key}"
TYPESENSE_COLLECTION_JOBS="${TYPESENSE_COLLECTION_JOBS:-jobs}"
TYPESENSE_DISABLED="${TYPESENSE_DISABLED:-false}"

POSTGRES_LOG="$LOG_DIR/postgres.log"
SERVICE_LOG="$LOG_DIR/user-service.log"
AGENT_LOG="$LOG_DIR/agent-service.log"
WEB_LOG="$LOG_DIR/web-ui.log"
ADMIN_LOG="$LOG_DIR/admin-ui.log"
CUSTOMER_LOG="$LOG_DIR/customer-ui.log"
SERVICE_PID="$RUN_DIR/user-service.pid"
AGENT_PID="$RUN_DIR/agent-service.pid"
WEB_PID="$RUN_DIR/web-ui.pid"
ADMIN_PID="$RUN_DIR/admin-ui.pid"
CUSTOMER_PID="$RUN_DIR/customer-ui.pid"

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$RUN_DIR" "$LOG_DIR" "$(dirname "$CEERAT_PGDATA")"
}

is_pid_running() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

pid_for_port() {
  local port="$1"
  lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

is_port_listening() {
  [[ -n "$(pid_for_port "$1")" ]]
}

print_log_paths() {
  printf 'Logs:\n'
  printf '  Postgres:     %s\n' "$POSTGRES_LOG"
  printf '  User service: %s\n' "$SERVICE_LOG"
  printf '  Agent:        %s\n' "$AGENT_LOG"
  printf '  Web UI:       %s\n' "$WEB_LOG"
  printf '  Admin UI:     %s\n' "$ADMIN_LOG"
  printf '  Customer UI:  %s\n' "$CUSTOMER_LOG"
}

service_path() {
  case "${1:-}" in
    user-service) echo "services-repo/services/ceerat-user-service" ;;
    agent-service) echo "apps-repo/ai/ceerat-agent-service" ;;
    web-ui) echo "apps-repo/apps/ceerat-web-ui" ;;
    admin-ui) echo "apps-repo/apps/ceerat-admin-ui" ;;
    customer-ui) echo "apps-repo/apps/ceerat-customer-ui" ;;
    *)
      echo "Unknown service: ${1:-}" >&2
      echo "Expected one of: user-service agent-service web-ui admin-ui customer-ui" >&2
      return 2
      ;;
  esac
}

service_binary() {
  case "${1:-}" in
    user-service) echo "ceerat-user-service" ;;
    agent-service) echo "ceerat-agent-service" ;;
    web-ui) echo "ceerat-web-ui" ;;
    admin-ui) echo "ceerat-admin-ui" ;;
    customer-ui) echo "ceerat-customer-ui" ;;
    *)
      echo "Unknown service: ${1:-}" >&2
      return 2
      ;;
  esac
}

ensure_submodules() {
  local module_path

  for module_path in "${MODULE_PATHS[@]}"; do
    if [[ ! -f "$ROOT_DIR/$module_path/go.mod" ]]; then
      git -C "$ROOT_DIR" submodule update --init --recursive
      return
    fi
  done
}

sync_workspace() {
  local module_path

  for module_path in "${MODULE_PATHS[@]}"; do
    (cd "$ROOT_DIR/$module_path" && go mod download)
  done
}

test_workspace() {
  local module_path

  for module_path in "${MODULE_PATHS[@]}"; do
    (cd "$ROOT_DIR/$module_path" && go test ./...)
  done
}

build_service() {
  local service="$1"
  local module_path
  local binary_name

  module_path="$(service_path "$service")"
  binary_name="$(service_binary "$service")"

  mkdir -p "$BIN_DIR"
  cd "$ROOT_DIR"
  go build -o "$BIN_DIR/$binary_name" "./$module_path"
}
