#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="/var/lib/netdata/custom-dashboard"
STATE_FILE="$STATE_DIR/state.env"
TMP_ROOT="/tmp/netdata-load-test"
DASHBOARD_URL="${DASHBOARD_URL:-http://127.0.0.1:19999}"
DURATION_SECONDS="${DURATION_SECONDS:-60}"
CPU_WORKERS="${CPU_WORKERS:-}"
IO_FILE="$TMP_ROOT/io-test.bin"
MEMORY_FILE=""
IO_WRITTEN_MB=0
MEMORY_MB=0
PHASE="idle"
CPU_PIDS=()

log() {
  printf '[test] %s\n' "$*"
}

fail() {
  printf '[test] ERROR: %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo bash "$0" "$@"
    fi
    fail "Please run this script as root."
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

detect_cpu_workers() {
  if [[ -n "$CPU_WORKERS" ]]; then
    printf '%s\n' "$CPU_WORKERS"
    return 0
  fi

  if command -v nproc >/dev/null 2>&1; then
    nproc
    return 0
  fi

  printf '2\n'
}

reset_state() {
  cat >"$STATE_FILE" <<'EOF'
active_workers=0
memory_mb=0
io_written_mb=0
phase="idle"
EOF
}

write_state() {
  local workers="$1"
  cat >"$STATE_FILE" <<EOF
active_workers=$workers
memory_mb=$MEMORY_MB
io_written_mb=$IO_WRITTEN_MB
phase="$PHASE"
EOF
}

cleanup() {
  set +e

  for pid in "${CPU_PIDS[@]:-}"; do
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  if [[ -n "$MEMORY_FILE" && -e "$MEMORY_FILE" ]]; then
    rm -f "$MEMORY_FILE"
  fi

  rm -f "$IO_FILE"
  rmdir "$TMP_ROOT" 2>/dev/null || true
  reset_state
}

trap cleanup EXIT

verify_dashboard() {
  curl -fsS "$DASHBOARD_URL/api/v1/info" >/dev/null
  curl -fsS "$DASHBOARD_URL/api/v1/charts" | grep -q 'custom_load.synthetic'
  curl -fsS "$DASHBOARD_URL/api/v1/alarms?all" | grep -q 'custom_cpu_usage_high'
  log "Netdata API, custom chart, and custom alert are reachable at $DASHBOARD_URL."
}

allocate_memory() {
  local mem_total_kb
  local target_mb

  mem_total_kb="$(awk '/MemTotal/ { print $2 }' /proc/meminfo)"
  target_mb=$(( mem_total_kb / 4096 ))

  if (( target_mb < 64 )); then
    target_mb=64
  fi

  if (( target_mb > 512 )); then
    target_mb=512
  fi

  if [[ -d /dev/shm && -w /dev/shm ]]; then
    MEMORY_FILE="/dev/shm/netdata-memory-load.bin"
  else
    MEMORY_FILE="$TMP_ROOT/netdata-memory-load.bin"
  fi

  MEMORY_MB="$target_mb"
  PHASE="memory"
  log "Allocating roughly ${MEMORY_MB}MB of memory-backed storage."
  dd if=/dev/zero of="$MEMORY_FILE" bs=1M count="$MEMORY_MB" status=none
}

start_cpu_load() {
  local workers="$1"
  local i

  PHASE="cpu"
  log "Starting $workers CPU worker(s)."
  for (( i = 0; i < workers; i++ )); do
    yes > /dev/null &
    CPU_PIDS+=("$!")
  done

  write_state "$workers"
}

run_io_load() {
  local workers="$1"
  local deadline
  local chunk_mb=128

  PHASE="disk"
  deadline=$(( SECONDS + DURATION_SECONDS ))
  log "Generating disk I/O for ${DURATION_SECONDS}s."

  while (( SECONDS < deadline )); do
    dd if=/dev/zero of="$IO_FILE" bs=4M count=32 conv=fdatasync status=none
    IO_WRITTEN_MB=$(( IO_WRITTEN_MB + chunk_mb ))
    write_state "$workers"
  done
}

show_dashboard_hint() {
  cat <<EOF

Open the dashboard while the load test is running:
  $DASHBOARD_URL

Suggested charts:
  system.cpu
  system.ram
  disk.io
  custom_load.synthetic

EOF
}

main() {
  local workers

  need_root "$@"
  require_cmd bash
  require_cmd curl
  require_cmd dd
  require_cmd awk

  [[ -d "$STATE_DIR" ]] || fail "State directory $STATE_DIR does not exist. Run ./setup.sh first."

  mkdir -p "$TMP_ROOT"
  reset_state
  verify_dashboard

  workers="$(detect_cpu_workers)"
  allocate_memory
  start_cpu_load "$workers"
  show_dashboard_hint
  run_io_load "$workers"

  PHASE="complete"
  write_state "$workers"
  log "Load test completed. Inspect the CPU, RAM, disk, and custom_load charts for the captured activity."
}

main "$@"
