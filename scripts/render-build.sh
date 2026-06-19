#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cmd="${1:-all}"
services=(user-service agent-service web-ui admin-ui customer-ui ats-crawler)

ensure_submodules
sync_workspace

case "$cmd" in
  deps)
    ;;
  test)
    test_workspace
    ;;
  all)
    for service in "${services[@]}"; do
      build_service "$service"
    done
    ;;
  user-service|agent-service|web-ui|admin-ui|customer-ui|ats-crawler)
    build_service "$cmd"
    ;;
  *)
    echo "Usage: $0 [deps|test|all|user-service|agent-service|web-ui|admin-ui|customer-ui|ats-crawler]" >&2
    exit 2
    ;;
esac
