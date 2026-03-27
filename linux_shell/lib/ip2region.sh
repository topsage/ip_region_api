#!/usr/bin/env bash

IP2REGION_SHELL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP2REGION_SHELL_ROOT="$(cd "$IP2REGION_SHELL_LIB_DIR/.." && pwd)"
IP2REGION_SHELL_DEFAULT_DB_PATH="$(cd "$IP2REGION_SHELL_ROOT/.." && pwd)/ip2region.xdb"

ip2region_db_path() {
  printf '%s\n' "${IP2REGION_XDB_PATH:-$IP2REGION_SHELL_DEFAULT_DB_PATH}"
}

ip2region_db_version() {
  printf '%s\n' "${IP2REGION_DB_VERSION:-ipv4}"
}

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

error_json() {
  printf '{"detail":"%s"}\n' "$(json_escape "$1")"
}

normalize_region_field() {
  if [[ "${1:-}" == "0" ]]; then
    printf '\n'
    return
  fi
  printf '%s\n' "${1:-}"
}

read_uints() {
  local db_path="$1"
  local offset="$2"
  local length="$3"
  od -An -v -j "$offset" -N "$length" -t u1 "$db_path" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
}

read_le16() {
  local db_path="$1"
  local offset="$2"
  local raw
  raw="$(read_uints "$db_path" "$offset" 2)"
  set -- $raw
  printf '%s\n' "$(( $1 | ($2 << 8) ))"
}

read_le32() {
  local db_path="$1"
  local offset="$2"
  local raw
  raw="$(read_uints "$db_path" "$offset" 4)"
  set -- $raw
  printf '%s\n' "$(( $1 | ($2 << 8) | ($3 << 16) | ($4 << 24) ))"
}

read_text_range() {
  local db_path="$1"
  local offset="$2"
  local length="$3"
  dd if="$db_path" bs=1 skip="$offset" count="$length" status=none 2>/dev/null
}

ensure_db_available() {
  local db_path
  db_path="$(ip2region_db_path)"
  if [[ ! -f "$db_path" ]]; then
    printf 'ip2region xdb file not found: %s\n' "$db_path" >&2
    return 1
  fi
}

parse_ipv4_ip() {
  local ip="$1"
  local a b c d extra

  if [[ "$ip" == *:* ]]; then
    printf 'this service is using an IPv4 xdb file, IPv6 is not supported\n' >&2
    return 1
  fi

  IFS=. read -r a b c d extra <<< "$ip"
  if [[ -n "${extra:-}" || -z "${a:-}" || -z "${b:-}" || -z "${c:-}" || -z "${d:-}" ]]; then
    printf 'invalid ip address `%s`\n' "$ip" >&2
    return 1
  fi

  for octet in "$a" "$b" "$c" "$d"; do
    if [[ ! "$octet" =~ ^[0-9]+$ ]] || (( octet < 0 || octet > 255 )); then
      printf 'invalid ip address `%s`\n' "$ip" >&2
      return 1
    fi
  done

  printf '%s %s %s %s %s\n' "$a" "$b" "$c" "$d" "$(( (a << 24) | (b << 16) | (c << 8) | d ))"
}

lookup_region_string() {
  local ip="$1"
  local db_path
  local parsed
  local o1 o2 o3 o4 ip_num
  local vector_offset s_ptr e_ptr
  local low high mid index_offset raw
  local start_ip end_ip data_len data_ptr
  local region

  ensure_db_available || return 1
  db_path="$(ip2region_db_path)"

  if [[ "$(ip2region_db_version)" != "ipv4" ]]; then
    printf 'unsupported ip2region version: %s\n' "$(ip2region_db_version)" >&2
    return 1
  fi

  parsed="$(parse_ipv4_ip "$ip")" || return 1
  read -r o1 o2 o3 o4 ip_num <<< "$parsed"

  vector_offset=$(( 256 + o1 * 2048 + o2 * 8 ))
  s_ptr="$(read_le32 "$db_path" "$vector_offset")"
  e_ptr="$(read_le32 "$db_path" "$(( vector_offset + 4 ))")"

  if (( s_ptr == 0 || e_ptr == 0 )); then
    printf 'no region found for ip: %s\n' "$ip" >&2
    return 1
  fi

  low=0
  high=$(( (e_ptr - s_ptr) / 14 ))
  data_len=0
  data_ptr=0

  while (( low <= high )); do
    mid=$(( (low + high) / 2 ))
    index_offset=$(( s_ptr + mid * 14 ))
    raw="$(read_uints "$db_path" "$index_offset" 14)"
    set -- $raw

    start_ip=$(( $1 | ($2 << 8) | ($3 << 16) | ($4 << 24) ))
    end_ip=$(( $5 | ($6 << 8) | ($7 << 16) | ($8 << 24) ))

    if (( ip_num < start_ip )); then
      high=$(( mid - 1 ))
      continue
    fi

    if (( ip_num > end_ip )); then
      low=$(( mid + 1 ))
      continue
    fi

    data_len=$(( $9 | (${10} << 8) ))
    data_ptr=$(( ${11} | (${12} << 8) | (${13} << 16) | (${14} << 24) ))
    break
  done

  if (( data_len == 0 || data_ptr == 0 )); then
    printf 'no region found for ip: %s\n' "$ip" >&2
    return 1
  fi

  region="$(read_text_range "$db_path" "$data_ptr" "$data_len")"
  if [[ -z "$region" ]]; then
    printf 'no region found for ip: %s\n' "$ip" >&2
    return 1
  fi

  printf '%s\n' "$region"
}

lookup_ip_json() {
  local ip="$1"
  local region
  local country province city isp country_code

  region="$(lookup_region_string "$ip")" || return 1
  IFS='|' read -r country province city isp country_code _ <<< "$region"

  country="$(normalize_region_field "$country")"
  province="$(normalize_region_field "$province")"
  city="$(normalize_region_field "$city")"
  isp="$(normalize_region_field "$isp")"
  country_code="$(normalize_region_field "$country_code")"

  printf '{"ip":"%s","country":"%s","province":"%s","city":"%s","isp":"%s","country_code":"%s","region":"%s"}\n' \
    "$(json_escape "$ip")" \
    "$(json_escape "$country")" \
    "$(json_escape "$province")" \
    "$(json_escape "$city")" \
    "$(json_escape "$isp")" \
    "$(json_escape "$country_code")" \
    "$(json_escape "$region")"
}

health_json() {
  printf '{"status":"ok","db_path":"%s","db_version":"%s"}\n' \
    "$(json_escape "$(ip2region_db_path)")" \
    "$(json_escape "$(ip2region_db_version)")"
}
