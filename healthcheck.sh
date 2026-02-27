#!/usr/bin/env bash

set -u

MODE="local"
HOST=""
USER_NAME=""
SSH_PORT="22"
IDENTITY=""
SERVICE=""
CHECK_PORT=""
TIMEOUT_SECONDS="3"
JSON_OUTPUT="false"

declare -a CHECK_NAMES=()
declare -a CHECK_STATUSES=()
declare -a CHECK_MESSAGES=()

usage() {
  cat <<'EOF'
Usage:
  ./healthcheck.sh [--mode local|ssh] [--host HOST] [--user USER] [--port-ssh 22]
                       [--identity PATH] [--service NAME] [--check-port PORT]
                       [--timeout 3] [--json]
EOF
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

add_check() {
  CHECK_NAMES+=("$1")
  CHECK_STATUSES+=("$2")
  CHECK_MESSAGES+=("$3")
}

target_label() {
  if [[ "$MODE" == "local" ]]; then
    printf 'local'
    return
  fi

  if [[ -n "$USER_NAME" ]]; then
    printf '%s@%s' "$USER_NAME" "$HOST"
  else
    printf '%s' "$HOST"
  fi
}

run_cmd() {
  local cmd="$1"

  if [[ "$MODE" == "local" ]]; then
    bash -lc "$cmd"
    return $?
  fi

  local ssh_target="$HOST"
  if [[ -n "$USER_NAME" ]]; then
    ssh_target="${USER_NAME}@${HOST}"
  fi

  local -a ssh_cmd=("ssh" "-o" "BatchMode=yes" "-o" "ConnectTimeout=${TIMEOUT_SECONDS}" "-p" "$SSH_PORT")
  if [[ -n "$IDENTITY" ]]; then
    ssh_cmd+=("-i" "$IDENTITY")
  fi
  ssh_cmd+=("$ssh_target" "bash" "-lc" "$cmd")
  "${ssh_cmd[@]}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        MODE="${2:-}"
        shift 2
        ;;
      --host)
        HOST="${2:-}"
        shift 2
        ;;
      --user)
        USER_NAME="${2:-}"
        shift 2
        ;;
      --port-ssh)
        SSH_PORT="${2:-}"
        shift 2
        ;;
      --identity)
        IDENTITY="${2:-}"
        shift 2
        ;;
      --service)
        SERVICE="${2:-}"
        shift 2
        ;;
      --check-port)
        CHECK_PORT="${2:-}"
        shift 2
        ;;
      --timeout)
        TIMEOUT_SECONDS="${2:-}"
        shift 2
        ;;
      --json)
        JSON_OUTPUT="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 3
        ;;
    esac
  done

  if [[ "$MODE" != "local" && "$MODE" != "ssh" ]]; then
    echo "--mode must be local or ssh" >&2
    exit 3
  fi

  if [[ "$MODE" == "ssh" && -z "$HOST" ]]; then
    echo "--host is required in ssh mode" >&2
    exit 3
  fi

  if [[ -n "$CHECK_PORT" ]]; then
    if ! [[ "$CHECK_PORT" =~ ^[0-9]+$ ]] || (( CHECK_PORT < 1 || CHECK_PORT > 65535 )); then
      echo "--check-port must be between 1 and 65535" >&2
      exit 3
    fi
  fi

  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
    echo "--port-ssh must be between 1 and 65535" >&2
    exit 3
  fi

  if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( TIMEOUT_SECONDS < 1 )); then
    echo "--timeout must be integer >= 1" >&2
    exit 3
  fi
}

check_service_active() {
  local output rc
  output="$(run_cmd "systemctl is-active $(printf '%q' "$SERVICE") 2>&1")"
  rc=$?
  if [[ $rc -eq 0 && "$output" == "active" ]]; then
    add_check "service_active" "OK" "service '${SERVICE}' is active"
  else
    add_check "service_active" "CRITICAL" "service '${SERVICE}' is not active (${output})"
  fi
}

check_service_enabled() {
  local output rc
  output="$(run_cmd "systemctl is-enabled $(printf '%q' "$SERVICE") 2>&1")"
  rc=$?
  if [[ $rc -eq 0 && "$output" == "enabled" ]]; then
    add_check "service_enabled" "OK" "service '${SERVICE}' is enabled"
  else
    add_check "service_enabled" "WARN" "service '${SERVICE}' is not enabled (${output})"
  fi
}

check_load() {
  local cmd output rc
  cmd='cpu=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 1); load=$(cut -d" " -f1 /proc/loadavg 2>/dev/null || echo 0); printf "%s %s\n" "$cpu" "$load"'
  output="$(run_cmd "$cmd" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    add_check "load_average" "WARN" "cannot read load info (${output})"
    return
  fi

  local cpu load warn_thresh crit_thresh
  cpu="$(awk '{print $1}' <<<"$output")"
  load="$(awk '{print $2}' <<<"$output")"
  if [[ -z "$cpu" || -z "$load" ]]; then
    add_check "load_average" "WARN" "unexpected load output (${output})"
    return
  fi

  warn_thresh="$(awk -v c="$cpu" 'BEGIN {printf "%.2f", c*1.5}')"
  crit_thresh="$(awk -v c="$cpu" 'BEGIN {printf "%.2f", c*2.0}')"

  if awk -v l="$load" -v c="$crit_thresh" 'BEGIN{exit !(l>=c)}'; then
    add_check "load_average" "CRITICAL" "load=${load} cpu=${cpu} (critical >= ${crit_thresh})"
  elif awk -v l="$load" -v w="$warn_thresh" 'BEGIN{exit !(l>=w)}'; then
    add_check "load_average" "WARN" "load=${load} cpu=${cpu} (warning >= ${warn_thresh})"
  else
    add_check "load_average" "OK" "load=${load} cpu=${cpu}"
  fi
}

check_disk_usage() {
  local output rc
  output="$(run_cmd "df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,\"\",\$5); print \$5}'" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 || -z "$output" || ! "$output" =~ ^[0-9]+$ ]]; then
    add_check "disk_usage_root" "WARN" "cannot read disk usage (${output})"
    return
  fi

  local pct="$output"
  if (( pct >= 90 )); then
    add_check "disk_usage_root" "CRITICAL" "disk / usage ${pct}%"
  elif (( pct >= 80 )); then
    add_check "disk_usage_root" "WARN" "disk / usage ${pct}%"
  else
    add_check "disk_usage_root" "OK" "disk / usage ${pct}%"
  fi
}

check_inode_usage() {
  local output rc
  output="$(run_cmd "df -Pi / 2>/dev/null | awk 'NR==2 {gsub(/%/,\"\",\$5); print \$5}'" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 || -z "$output" || ! "$output" =~ ^[0-9]+$ ]]; then
    add_check "inode_usage_root" "WARN" "cannot read inode usage (${output})"
    return
  fi

  local pct="$output"
  if (( pct >= 90 )); then
    add_check "inode_usage_root" "CRITICAL" "inode / usage ${pct}%"
  elif (( pct >= 80 )); then
    add_check "inode_usage_root" "WARN" "inode / usage ${pct}%"
  else
    add_check "inode_usage_root" "OK" "inode / usage ${pct}%"
  fi
}

check_memory_available() {
  local cmd output rc
  cmd='free -m 2>/dev/null | awk "/^Mem:/ {if (\$7 ~ /^[0-9]+$/) {print \$2 \" \" \$7} else {print \$2 \" \" \$4}}"'
  output="$(run_cmd "$cmd" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 || -z "$output" ]]; then
    add_check "memory_available" "WARN" "cannot read memory info (${output})"
    return
  fi

  local total available pct
  total="$(awk '{print $1}' <<<"$output")"
  available="$(awk '{print $2}' <<<"$output")"
  if [[ -z "$total" || -z "$available" || ! "$total" =~ ^[0-9]+$ || ! "$available" =~ ^[0-9]+$ || "$total" -eq 0 ]]; then
    add_check "memory_available" "WARN" "unexpected memory output (${output})"
    return
  fi

  pct="$(awk -v a="$available" -v t="$total" 'BEGIN {printf "%.1f", (a*100)/t}')"
  if awk -v p="$pct" 'BEGIN{exit !(p<8.0)}'; then
    add_check "memory_available" "CRITICAL" "available memory ${pct}%"
  elif awk -v p="$pct" 'BEGIN{exit !(p<15.0)}'; then
    add_check "memory_available" "WARN" "available memory ${pct}%"
  else
    add_check "memory_available" "OK" "available memory ${pct}%"
  fi
}

check_port_listening() {
  local cmd output rc
  cmd="ss -lnt 2>/dev/null | awk 'NR>1 {print \$4}' | grep -E '(^|:|\\])${CHECK_PORT}$' -q"
  output="$(run_cmd "$cmd" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    add_check "port_listening" "OK" "port ${CHECK_PORT} is listening"
  else
    add_check "port_listening" "CRITICAL" "port ${CHECK_PORT} is not listening"
  fi
}

check_tcp_connect() {
  local cmd output rc
  cmd="if command -v timeout >/dev/null 2>&1; then timeout ${TIMEOUT_SECONDS}s bash -c '</dev/tcp/127.0.0.1/${CHECK_PORT}' >/dev/null 2>&1; else exit 125; fi"
  output="$(run_cmd "$cmd" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    add_check "tcp_connect" "OK" "tcp connect 127.0.0.1:${CHECK_PORT} succeeded"
  elif [[ $rc -eq 125 ]]; then
    add_check "tcp_connect" "WARN" "timeout utility not found, check skipped"
  else
    add_check "tcp_connect" "CRITICAL" "tcp connect 127.0.0.1:${CHECK_PORT} failed"
  fi
}

compute_overall_status() {
  local has_warn="false"
  local has_critical="false"
  local status
  for status in "${CHECK_STATUSES[@]}"; do
    if [[ "$status" == "CRITICAL" ]]; then
      has_critical="true"
    elif [[ "$status" == "WARN" ]]; then
      has_warn="true"
    fi
  done

  if [[ "$has_critical" == "true" ]]; then
    printf 'CRITICAL'
  elif [[ "$has_warn" == "true" ]]; then
    printf 'WARN'
  else
    printf 'OK'
  fi
}

print_text() {
  local i
  local target
  local service_label
  target="$(target_label)"
  service_label="${SERVICE:-not-set}"
  echo "target=${target} mode=${MODE} service=${service_label}"
  for ((i=0; i<${#CHECK_NAMES[@]}; i++)); do
    printf '[%s] %s: %s\n' "${CHECK_STATUSES[$i]}" "${CHECK_NAMES[$i]}" "${CHECK_MESSAGES[$i]}"
  done
}

print_json() {
  local overall status_lc i
  overall="$(compute_overall_status)"
  case "$overall" in
    OK) status_lc="ok" ;;
    WARN) status_lc="warn" ;;
    *) status_lc="critical" ;;
  esac

  printf '{'
  printf '"status":"%s",' "$status_lc"
  printf '"target":"%s",' "$(json_escape "$(target_label)")"
  printf '"service":"%s",' "$(json_escape "$SERVICE")"
  printf '"timestamp":"%s",' "$(date -Is)"
  printf '"checks":['
  for ((i=0; i<${#CHECK_NAMES[@]}; i++)); do
    local comma=""
    local status_value="${CHECK_STATUSES[$i]}"
    if (( i > 0 )); then
      comma=","
    fi
    printf '%s{"name":"%s","status":"%s","message":"%s"}' \
      "$comma" \
      "$(json_escape "${CHECK_NAMES[$i]}")" \
      "$(json_escape "$status_value")" \
      "$(json_escape "${CHECK_MESSAGES[$i]}")"
  done
  printf ']}\n'
}

main() {
  parse_args "$@"

  if [[ "$MODE" == "ssh" ]]; then
    if ! run_cmd "true" >/dev/null 2>&1; then
      if [[ "$JSON_OUTPUT" == "true" ]]; then
        printf '{"status":"critical","target":"%s","service":"%s","timestamp":"%s","checks":[{"name":"ssh_connectivity","status":"CRITICAL","message":"ssh connection failed"}]}\n' \
          "$(json_escape "$(target_label)")" \
          "$(json_escape "$SERVICE")" \
          "$(date -Is)"
      else
        echo "target=$(target_label) mode=${MODE} service=${SERVICE:-not-set}"
        echo "[CRITICAL] ssh_connectivity: ssh connection failed"
      fi
      exit 2
    fi
  fi

  if [[ -n "$SERVICE" ]]; then
    check_service_active
    check_service_enabled
  fi
  check_load
  check_disk_usage
  check_inode_usage
  check_memory_available
  if [[ -n "$CHECK_PORT" ]]; then
    check_port_listening
    check_tcp_connect
  fi

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    print_json
  else
    print_text
  fi

  case "$(compute_overall_status)" in
    OK) exit 0 ;;
    WARN) exit 1 ;;
    CRITICAL) exit 2 ;;
    *) exit 3 ;;
  esac
}

main "$@"
