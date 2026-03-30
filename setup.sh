#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NETDATA_CONF_DIR="/etc/netdata"
NETDATA_HEALTH_DIR="$NETDATA_CONF_DIR/health.d"
NETDATA_CHARTS_CONF_DIR="$NETDATA_CONF_DIR/charts.d"
STATE_DIR="/var/lib/netdata/custom-dashboard"
STATE_FILE="$STATE_DIR/state.env"
CHART_NAME="custom_load"

log() {
  printf '[setup] %s\n' "$*"
}

fail() {
  printf '[setup] ERROR: %s\n' "$*" >&2
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

download_kickstart() {
  local tmpfile
  tmpfile="$(mktemp)"
  curl -fsSL https://get.netdata.cloud/kickstart.sh -o "$tmpfile"
  chmod +x "$tmpfile"
  printf '%s\n' "$tmpfile"
}

install_netdata() {
  local kickstart
  kickstart="$(download_kickstart)"

  log "Installing Netdata with the official kickstart script."
  DISABLE_TELEMETRY=1 sh "$kickstart" \
    --non-interactive \
    --release-channel stable \
    --no-updates
  rm -f "$kickstart"
}

install_chartsd_package() {
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing charts.d support with apt."
    apt-get update
    apt-get install -y netdata-plugin-chartsd
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    log "Installing charts.d support with dnf."
    dnf install -y netdata-plugin-chartsd
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    log "Installing charts.d support with yum."
    yum install -y netdata-plugin-chartsd
    return 0
  fi

  if command -v zypper >/dev/null 2>&1; then
    log "Installing charts.d support with zypper."
    zypper --non-interactive install netdata-plugin-chartsd
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    log "Installing charts.d support with pacman."
    pacman -Sy --noconfirm netdata-plugin-chartsd
    return 0
  fi

  fail "Unable to install netdata-plugin-chartsd automatically on this distribution."
}

find_chartsd_plugin() {
  local candidate
  for candidate in \
    /usr/libexec/netdata/plugins.d/charts.d.plugin \
    /usr/lib/netdata/plugins.d/charts.d.plugin \
    /opt/netdata/usr/libexec/netdata/plugins.d/charts.d.plugin \
    /opt/netdata/usr/lib/netdata/plugins.d/charts.d.plugin
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_netdata() {
  if command -v netdata >/dev/null 2>&1 || systemctl list-unit-files 2>/dev/null | grep -q '^netdata\.service'; then
    log "Netdata is already installed. Reusing the existing installation."
  else
    install_netdata
  fi
}

ensure_chartsd() {
  local plugin_path
  if plugin_path="$(find_chartsd_plugin)"; then
    printf '%s\n' "$plugin_path"
    return 0
  fi

  install_chartsd_package

  if plugin_path="$(find_chartsd_plugin)"; then
    printf '%s\n' "$plugin_path"
    return 0
  fi

  fail "charts.d.plugin was not found after installation."
}

ensure_global_chartsd_config() {
  local config_file="$NETDATA_CONF_DIR/charts.d.conf"
  mkdir -p "$NETDATA_CONF_DIR"
  touch "$config_file"

  if ! grep -Eq '^custom_load="?yes"?$' "$config_file"; then
    cat >>"$config_file" <<'EOF'

# Added by simple-monitoring/setup.sh
custom_load=yes
EOF
  fi
}

install_custom_files() {
  local plugin_path="$1"
  local netdata_lib_dir
  local charts_scripts_dir

  netdata_lib_dir="$(cd -- "$(dirname -- "$plugin_path")/.." && pwd)"
  charts_scripts_dir="$netdata_lib_dir/charts.d"

  mkdir -p "$charts_scripts_dir" "$NETDATA_CHARTS_CONF_DIR" "$NETDATA_HEALTH_DIR" "$STATE_DIR"

  install -m 0755 "$PROJECT_DIR/netdata/custom_load.chart.sh" "$charts_scripts_dir/custom_load.chart.sh"
  install -m 0644 "$PROJECT_DIR/netdata/custom_load.conf" "$NETDATA_CHARTS_CONF_DIR/custom_load.conf"
  install -m 0644 "$PROJECT_DIR/netdata/custom_cpu_alert.conf" "$NETDATA_HEALTH_DIR/custom_cpu_alert.conf"

  cat >"$STATE_FILE" <<'EOF'
active_workers=0
memory_mb=0
io_written_mb=0
phase="idle"
EOF
  chmod 0644 "$STATE_FILE"
  chmod 0755 "$STATE_DIR"

  ensure_global_chartsd_config
}

restart_netdata() {
  log "Restarting Netdata."
  systemctl enable --now netdata
  systemctl restart netdata

  if command -v netdatacli >/dev/null 2>&1; then
    netdatacli reload-health >/dev/null 2>&1 || true
  fi
}

show_summary() {
  local host_hint
  host_hint="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -z "${host_hint:-}" ]]; then
    host_hint="localhost"
  fi

  cat <<EOF

Netdata is ready.

Dashboard URL:
  http://$host_hint:19999

Custom additions:
  - Chart: custom_load.synthetic
  - Alert: custom_cpu_usage_high

Next step:
  sudo ./test_dashboard.sh
EOF
}

main() {
  need_root "$@"
  require_cmd bash
  require_cmd curl
  require_cmd systemctl

  ensure_netdata
  install_custom_files "$(ensure_chartsd)"
  restart_netdata
  show_summary
}

main "$@"
