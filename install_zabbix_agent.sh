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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding official Zabbix repo..."
  apt-get update -y
  apt-get install -y curl gnupg
  curl -fsSL https://repo.zabbix.com/zabbix-official-repo.key | gpg --dearmor -o /usr/share/keyrings/zabbix-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/zabbix-archive-keyring.gpg] http://repo.zabbix.com/zabbix/$(lsb_release -cs)/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/zabbix.list
  echo "deb-src [signed-by=/usr/share/keyrings/zabbix-archive-keyring.gpg] http://repo.zabbix.com/zabbix/$(lsb_release -cs)/ $(lsb_release -cs) main" >> /etc/apt/sources.list.d/zabbix.list
  apt-get update -y
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing zabbix-agent..."
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

open_zabbix_port() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Opening port 10050/tcp for Zabbix..."
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 10050/tcp comment 'Zabbix Agent' || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=10050/tcp || true
    firewall-cmd --reload || true
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Port 10050/tcp open step done."
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
  open_zabbix_port
  restart_zabbix_agent
  show_logs
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Zabbix Agent installer finished ==="
}

main "$@"
