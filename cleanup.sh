#!/usr/bin/env bash

set -euo pipefail

NETDATA_CONF_DIR="/etc/netdata"
STATE_DIR="/var/lib/netdata/custom-dashboard"
CHARTS_D_CONF="$NETDATA_CONF_DIR/charts.d.conf"

log() {
  printf '[cleanup] %s\n' "$*"
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo bash "$0" "$@"
    fi
    printf '[cleanup] ERROR: Please run this script as root.\n' >&2
    exit 1
  fi
}

remove_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
  fi
}

remove_custom_files() {
  log "Removing custom chart, alert, and state files."

  remove_if_exists /usr/libexec/netdata/charts.d/custom_load.chart.sh
  remove_if_exists /usr/lib/netdata/charts.d/custom_load.chart.sh
  remove_if_exists /opt/netdata/usr/libexec/netdata/charts.d/custom_load.chart.sh
  remove_if_exists /opt/netdata/usr/lib/netdata/charts.d/custom_load.chart.sh
  remove_if_exists "$NETDATA_CONF_DIR/charts.d/custom_load.conf"
  remove_if_exists "$NETDATA_CONF_DIR/health.d/custom_cpu_alert.conf"
  remove_if_exists "$STATE_DIR"

  if [[ -f "$CHARTS_D_CONF" ]]; then
    sed -i '/^# Added by simple-monitoring\/setup\.sh$/d;/^custom_load="?yes"?$/d' "$CHARTS_D_CONF"
  fi
}

kickstart_uninstall() {
  if ! command -v curl >/dev/null 2>&1; then
    log "curl is not available, skipping kickstart-based uninstall."
    return 0
  fi

  log "Attempting Netdata uninstall through the official kickstart script."
  local kickstart
  kickstart="$(mktemp)"
  curl -fsSL https://get.netdata.cloud/kickstart.sh -o "$kickstart"
  chmod +x "$kickstart"
  DISABLE_TELEMETRY=1 sh "$kickstart" --non-interactive --uninstall || true
  rm -f "$kickstart"
}

package_manager_remove() {
  if command -v apt-get >/dev/null 2>&1; then
    log "Removing Netdata packages with apt."
    apt-get remove -y netdata netdata-plugin-chartsd || true
    apt-get purge -y netdata netdata-plugin-chartsd || true
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    log "Removing Netdata packages with dnf."
    dnf remove -y netdata netdata-plugin-chartsd || true
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    log "Removing Netdata packages with yum."
    yum remove -y netdata netdata-plugin-chartsd || true
    return 0
  fi

  if command -v zypper >/dev/null 2>&1; then
    log "Removing Netdata packages with zypper."
    zypper --non-interactive remove netdata netdata-plugin-chartsd || true
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    log "Removing Netdata packages with pacman."
    pacman -Rns --noconfirm netdata netdata-plugin-chartsd || true
    return 0
  fi
}

disable_service_if_present() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^netdata\.service'; then
    systemctl disable --now netdata || true
  fi
}

main() {
  need_root "$@"
  remove_custom_files
  disable_service_if_present
  kickstart_uninstall
  package_manager_remove
  systemctl daemon-reload || true

  cat <<'EOF'
[cleanup] Cleanup finished.
[cleanup] Netdata and the custom monitoring assets were removed when possible.
EOF
}

main "$@"
