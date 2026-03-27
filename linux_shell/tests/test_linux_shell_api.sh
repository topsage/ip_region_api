#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_PATH="$ROOT_DIR/lib/ip2region.sh"
HANDLER_PATH="$ROOT_DIR/bin/http_handler.sh"

source "$LIB_PATH"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'Expected: %s\n' "$expected" >&2
    printf 'Actual:   %s\n' "$actual" >&2
    fail "$message"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Did not find: %s\n' "$needle" >&2
    printf 'Within: %s\n' "$haystack" >&2
    fail "$message"
  fi
}

test_lookup_json_for_known_ip() {
  local output
  output="$(lookup_ip_json "1.1.1.1")"
  assert_contains "$output" '"country":"中国"' "country should match Python service output"
  assert_contains "$output" '"province":"香港特别行政区"' "province should match Python service output"
  assert_contains "$output" '"country_code":"CN"' "country code should match Python service output"
}

test_lookup_json_for_public_dns_ip() {
  local output
  output="$(lookup_ip_json "8.8.8.8")"
  assert_contains "$output" '"country":"United States"' "country should match Python service output"
  assert_contains "$output" '"province":"California"' "province should match Python service output"
  assert_contains "$output" '"isp":"Google LLC"' "isp should match Python service output"
}

test_rejects_ipv6_for_ipv4_database() {
  local output
  if output="$(lookup_ip_json "2409:8c54:870:1fb::1" 2>&1)"; then
    fail "ipv6 lookup should fail for the bundled IPv4 database"
  fi
  assert_contains "$output" "IPv6 is not supported" "ipv6 rejection should be explicit"
}

test_health_request() {
  local response
  response="$(
    printf 'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n' |
      "$HANDLER_PATH"
  )"
  assert_contains "$response" 'HTTP/1.1 200 OK' "health should return 200"
  assert_contains "$response" '"status":"ok"' "health body should include status"
  assert_contains "$response" '"db_version":"ipv4"' "health body should include db version"
}

test_lookup_get_request() {
  local response
  response="$(
    printf 'GET /lookup?ip=223.5.5.5 HTTP/1.1\r\nHost: localhost\r\n\r\n' |
      "$HANDLER_PATH"
  )"
  assert_contains "$response" 'HTTP/1.1 200 OK' "lookup GET should return 200"
  assert_contains "$response" '"province":"浙江省"' "lookup GET should return parsed province"
  assert_contains "$response" '"city":"杭州市"' "lookup GET should return parsed city"
}

test_lookup_post_request() {
  local payload='{"ip":"114.114.114.114"}'
  local response
  response="$(
    {
      printf 'POST /lookup HTTP/1.1\r\n'
      printf 'Host: localhost\r\n'
      printf 'Content-Type: application/json\r\n'
      printf 'Content-Length: %s\r\n' "${#payload}"
      printf '\r\n'
      printf '%s' "$payload"
    } | "$HANDLER_PATH"
  )"
  assert_contains "$response" 'HTTP/1.1 200 OK' "lookup POST should return 200"
  assert_contains "$response" '"province":"江苏省"' "lookup POST should return parsed province"
  assert_contains "$response" '"city":"南京市"' "lookup POST should return parsed city"
}

test_lookup_bad_request() {
  local response
  response="$(
    printf 'GET /lookup?ip=999.1.1.1 HTTP/1.1\r\nHost: localhost\r\n\r\n' |
      "$HANDLER_PATH"
  )"
  assert_contains "$response" 'HTTP/1.1 400 Bad Request' "invalid ip should return 400"
  assert_contains "$response" '"detail":"invalid ip address `999.1.1.1`"' "error body should explain invalid ip"
}

test_help_mentions_xdb_path_option() {
  local output
  output="$(bash "$ROOT_DIR/bin/serve.sh" --help)"
  assert_contains "$output" '--xdb-path <path>' "serve help should explain database path argument"
}

test_systemd_service_template_exists() {
  local service_path="$ROOT_DIR/systemd/ip-region-api.service"
  [[ -f "$service_path" ]] || fail "systemd service template should exist"
  assert_contains "$(cat "$service_path")" 'ExecStart=' "systemd service should define ExecStart"
  assert_contains "$(cat "$service_path")" 'IP2REGION_XDB_PATH=' "systemd service should define database path env"
}

main() {
  test_lookup_json_for_known_ip
  test_lookup_json_for_public_dns_ip
  test_rejects_ipv6_for_ipv4_database
  test_health_request
  test_lookup_get_request
  test_lookup_post_request
  test_lookup_bad_request
  test_help_mentions_xdb_path_option
  test_systemd_service_template_exists
  printf 'All shell API tests passed.\n'
}

main "$@"
