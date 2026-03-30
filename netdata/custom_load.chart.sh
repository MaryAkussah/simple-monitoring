#!/usr/bin/env bash

custom_load_update_every=1
custom_load_priority=90000
custom_load_state_file="${custom_load_state_file:-/var/lib/netdata/custom-dashboard/state.env}"

custom_load_check() {
  mkdir -p -- "$(dirname -- "$custom_load_state_file")" || return 1

  if [[ ! -f "$custom_load_state_file" ]]; then
    cat >"$custom_load_state_file" <<'EOF'
active_workers=0
memory_mb=0
io_written_mb=0
phase="idle"
EOF
  fi

  return 0
}

custom_load_create() {
  cat <<EOF
CHART custom_load.synthetic '' 'Synthetic Load Test Activity' 'units' 'custom monitoring' 'custom_load.synthetic' line $custom_load_priority $custom_load_update_every
DIMENSION active_workers 'active_workers' absolute 1 1
DIMENSION memory_mb 'memory_mb' absolute 1 1
DIMENSION io_written_mb 'io_written_mb' absolute 1 1
EOF
  return 0
}

custom_load_update() {
  local microseconds="$1"
  local active_workers=0
  local memory_mb=0
  local io_written_mb=0
  local phase="idle"

  if [[ -r "$custom_load_state_file" ]]; then
    # shellcheck disable=SC1090
    . "$custom_load_state_file"
  fi

  echo "BEGIN custom_load.synthetic $microseconds"
  echo "SET active_workers = ${active_workers:-0}"
  echo "SET memory_mb = ${memory_mb:-0}"
  echo "SET io_written_mb = ${io_written_mb:-0}"
  echo "END"

  return 0
}
