#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$ROOT_DIR/scripts/common.sh"

status_line() {
  local name="$1"
  local port="$2"
  local url="$3"
  local pid_file="${4:-}"
  local pid
  local pid_note=""

  pid="$(pid_for_port "$port")"
  if [[ -n "$pid_file" && -f "$pid_file" ]]; then
    pid_note=" pidfile=$(basename "$pid_file")"
  fi

  if [[ -n "$pid" ]]; then
    printf '%-14s running  port=%-5s pid=%-8s %s%s\n' "$name" "$port" "$pid" "$url" "$pid_note"
  else
    printf '%-14s stopped  port=%-5s %s%s\n' "$name" "$port" "$url" "$pid_note"
  fi
}

binary_line() {
  local service="$1"
  local binary_name

  binary_name="$(service_binary "$service")"
  if [[ -x "$BIN_DIR/$binary_name" ]]; then
    printf '%-14s built    %s\n' "$binary_name" "$BIN_DIR/$binary_name"
  else
    printf '%-14s missing  run: make build\n' "$binary_name"
  fi
}

printf 'Local services:\n'
status_line "Postgres" "$CEERAT_DB_PORT" "$CEERAT_DB_HOST:$CEERAT_DB_PORT"
status_line "Typesense" "$TYPESENSE_PORT" "$TYPESENSE_PROTOCOL://localhost:$TYPESENSE_PORT"
status_line "User service" "$CEERAT_SERVICE_PORT" "grpc://$USER_SERVICE_ADDR" "$SERVICE_PID"
status_line "Admin API" "$CEERAT_USER_ADMIN_PORT" "$CEERAT_ADMIN_API_BASE_URL"
status_line "Agent" "$CEERAT_AGENT_PORT" "$CEERAT_AGENT_BASE_URL" "$AGENT_PID"
status_line "Web UI" "$CEERAT_WEB_UI_PORT" "http://localhost:$CEERAT_WEB_UI_PORT" "$WEB_PID"
status_line "Admin UI" "$CEERAT_ADMIN_UI_PORT" "http://localhost:$CEERAT_ADMIN_UI_PORT" "$ADMIN_PID"
status_line "Customer UI" "$CEERAT_CUSTOMER_UI_PORT" "http://localhost:$CEERAT_CUSTOMER_UI_PORT" "$CUSTOMER_PID"

printf '\nBinaries:\n'
binary_line "user-service"
binary_line "agent-service"
binary_line "web-ui"
binary_line "admin-ui"
binary_line "customer-ui"

printf '\n'
print_log_paths
