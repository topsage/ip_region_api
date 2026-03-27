#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HANDLER_PATH="$ROOT_DIR/bin/http_handler.sh"

HOST="127.0.0.1"
PORT="8011"

usage() {
  cat <<'EOF'
Usage:
  ./bin/serve.sh [--host <host>] [--port <port>] [--xdb-path <path>]

Environment:
  IP2REGION_XDB_PATH   Override the xdb file path
  IP2REGION_DB_VERSION Database version, default: ipv4
EOF
}

detect_nc_command() {
  if command -v ncat >/dev/null 2>&1; then
    printf 'ncat\n'
    return 0
  fi

  if command -v nc >/dev/null 2>&1; then
    printf 'nc\n'
    return 0
  fi

  if command -v netcat >/dev/null 2>&1; then
    printf 'netcat\n'
    return 0
  fi

  return 1
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --host)
        HOST="${2:-}"
        shift 2
        ;;
      --port)
        PORT="${2:-}"
        shift 2
        ;;
      --xdb-path)
        export IP2REGION_XDB_PATH="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        exit 1
        ;;
    esac
  done
}

main() {
  local nc_bin help_output tmp_dir response_pipe

  parse_args "$@"

  if ! nc_bin="$(detect_nc_command)"; then
    printf 'netcat is required to run the shell API server\n' >&2
    exit 1
  fi

  printf 'Starting shell IP Region API on http://%s:%s\n' "$HOST" "$PORT" >&2
  printf 'Database: %s\n' "${IP2REGION_XDB_PATH:-$ROOT_DIR/../ip2region.xdb}" >&2

  if [[ "$nc_bin" == "ncat" ]]; then
    exec ncat --listen "$HOST" "$PORT" --keep-open --sh-exec "$HANDLER_PATH"
  fi

  help_output="$("$nc_bin" -h 2>&1 || true)"
  tmp_dir="$(mktemp -d)"
  response_pipe="$tmp_dir/response.pipe"
  mkfifo "$response_pipe"
  trap 'rm -rf "$tmp_dir"' EXIT

  if [[ "$help_output" == *OpenBSD* ]]; then
    while true; do
      cat "$response_pipe" | "$nc_bin" -l "$HOST" "$PORT" | "$HANDLER_PATH" > "$response_pipe"
    done
  fi

  while true; do
    cat "$response_pipe" | "$nc_bin" -l -p "$PORT" -s "$HOST" | "$HANDLER_PATH" > "$response_pipe"
  done
}

main "$@"
