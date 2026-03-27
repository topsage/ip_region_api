#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/ip2region.sh"

trim_cr() {
  local value="${1:-}"
  printf '%s' "${value%$'\r'}"
}

url_decode() {
  local value="${1//+/ }"
  printf '%b' "${value//%/\\x}"
}

extract_query_ip() {
  local target="$1"
  local query pair key value

  if [[ "$target" != *\?* ]]; then
    return 1
  fi

  query="${target#*\?}"
  IFS='&' read -r -a pairs <<< "$query"
  for pair in "${pairs[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    if [[ "$key" == "ip" ]]; then
      url_decode "$value"
      return 0
    fi
  done

  return 1
}

extract_json_ip() {
  local body="$1"
  printf '%s' "$body" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

send_response() {
  local status="$1"
  local body="$2"
  local length

  length="$(printf '%s' "$body" | wc -c | tr -d '[:space:]')"

  printf 'HTTP/1.1 %s\r\n' "$status"
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Content-Length: %s\r\n' "$length"
  printf 'Connection: close\r\n'
  printf '\r\n'
  printf '%s' "$body"
}

handle_lookup() {
  local ip="$1"
  local tmp_file body detail

  tmp_file="$(mktemp)"
  if body="$(lookup_ip_json "$ip" 2>"$tmp_file")"; then
    rm -f "$tmp_file"
    send_response "200 OK" "$body"
    return 0
  fi

  detail="$(tr -d '\r\n' < "$tmp_file")"
  rm -f "$tmp_file"
  body="$(error_json "$detail")"

  if [[ "$detail" == invalid\ ip\ address* || "$detail" == this\ service\ is\ using\ an\ IPv4\ xdb\ file* ]]; then
    send_response "400 Bad Request" "$body"
    return 0
  fi

  if [[ "$detail" == no\ region\ found* ]]; then
    send_response "404 Not Found" "$body"
    return 0
  fi

  send_response "500 Internal Server Error" "$body"
}

main() {
  local request_line method target http_version header_line
  local content_length body

  if ! IFS= read -r request_line; then
    send_response "400 Bad Request" "$(error_json "empty request")"
    return 0
  fi

  request_line="$(trim_cr "$request_line")"
  read -r method target http_version <<< "$request_line"
  content_length=0

  while IFS= read -r header_line; do
    header_line="$(trim_cr "$header_line")"
    [[ -z "$header_line" ]] && break
    case "${header_line%%:*}" in
      Content-Length|content-length)
        content_length="${header_line#*:}"
        content_length="${content_length//[[:space:]]/}"
        ;;
    esac
  done

  body=""
  if [[ "$content_length" =~ ^[0-9]+$ ]] && (( content_length > 0 )); then
    body="$(dd bs=1 count="$content_length" status=none 2>/dev/null)"
  fi

  case "$method $target" in
    "GET /health")
      send_response "200 OK" "$(health_json)"
      ;;
    GET\ /lookup\?*)
      if ! target_ip="$(extract_query_ip "$target")"; then
        send_response "400 Bad Request" "$(error_json "missing ip query parameter")"
        return 0
      fi
      handle_lookup "$target_ip"
      ;;
    "POST /lookup")
      target_ip="$(extract_json_ip "$body")"
      if [[ -z "$target_ip" ]]; then
        send_response "400 Bad Request" "$(error_json "missing ip in request body")"
        return 0
      fi
      handle_lookup "$target_ip"
      ;;
    *)
      send_response "404 Not Found" "$(error_json "route not found")"
      ;;
  esac
}

main "$@"
