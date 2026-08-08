#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/zabbix_agent_install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Zabbix Agent installer started ==="

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Script must be run as root (current EUID=$EUID)"
  exit 1
fi

install_zabbix_agent() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updating apt and installing zabbix-agent..."
  apt-get update -y
  apt-get install -y zabbix-agent
}

configure_zabbix_agent() {
  local conf="/etc/zabbix/zabbix_agentd.conf"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Writing config to $conf ..."

  cat > "$conf" <<'CONF'
Server=103.74.94.90,127.0.0.1
StartAgents=3
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogType=system
DebugLevel=3

AllowRoot=1
User=zabbix
Timeout=30
DenyKey=system.run[*]

UserParameter=timeweb_config_version,echo 127
CONF

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Config written."
}

restart_zabbix_agent() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restarting zabbix-agent..."
  systemctl restart zabbix-agent || {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restart failed, trying enable + start..."
    systemctl enable -q zabbix-agent || true
    systemctl start zabbix-agent || true
  }
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Service status:"
  systemctl status zabbix-agent --no-pager || true
}

show_logs() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Installation log (last 200 lines of $LOGFILE) ==="
  tail -n 200 "$LOGFILE" || true
}

main() {
  install_zabbix_agent
  configure_zabbix_agent
  restart_zabbix_agent
  show_logs
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Zabbix Agent installer finished ==="
}

main "$@"
