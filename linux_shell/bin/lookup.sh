#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/ip2region.sh"

usage() {
  cat <<'EOF'
Usage:
  ./bin/lookup.sh [--xdb-path <path>] <ip>

Environment:
  IP2REGION_XDB_PATH   Override the xdb file path
  IP2REGION_DB_VERSION Database version, default: ipv4
EOF
}

parse_args() {
  LOOKUP_IP=""

  while (($# > 0)); do
    case "$1" in
      --xdb-path)
        export IP2REGION_XDB_PATH="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        LOOKUP_IP="$1"
        shift
        ;;
    esac
  done
}

main() {
  local ip
  local error_output

  parse_args "$@"
  ip="${LOOKUP_IP:-}"

  if [[ -z "$ip" ]]; then
    usage
    return 0
  fi

  if ! error_output="$(lookup_ip_json "$ip" 2>&1)"; then
    printf '%s\n' "$error_output" >&2
    return 1
  fi

  printf '%s\n' "$error_output"
}

main "$@"
