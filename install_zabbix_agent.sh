#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

LOGFILE="/var/log/zabbix_agent_install.log"
mkdir -p "$(dirname "$LOGFILE")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Zabbix Agent installer started ===" | tee -a "$LOGFILE"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Script must be run as root (current EUID=$EUID)"
  exit 1
fi

# Определяем версию Ubuntu (например, 22.04 или 24.04)
get_ubuntu_version() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" ]]; then
      echo "${VERSION_ID:-}"
      return 0
    fi
  fi
  if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -rs 2>/dev/null || true
    return 0
  fi
  echo ""
}

install_zabbix_agent() {
  local ubuntu_ver
  ubuntu_ver="$(get_ubuntu_version)"
  if [[ -z "$ubuntu_ver" ]]; then
    echo "ERROR: Cannot detect Ubuntu version" | tee -a "$LOGFILE"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detected Ubuntu version: $ubuntu_ver" | tee -a "$LOGFILE"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Removing old Zabbix repos..." | tee -a "$LOGFILE"
  rm -f /etc/apt/sources.list.d/zabbix.list
  rm -f /etc/apt/sources.list.d/zabbix-official-repo.list
  rm -f /etc/apt/sources.list.d/timeweb-zabbix.list
  rm -f /usr/share/keyrings/zabbix-archive-keyring.gpg

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting apt timeouts..." | tee -a "$LOGFILE"
  cat > /etc/apt/apt.conf.d/99timeouts <<'APTEOF'
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::http::Pipeline-Depth "0";
Acquire::http::No-Cache "true";
APTEOF

  # Устанавливаем официальный репозиторий Zabbix под текущую версию Ubuntu
  local repo_deb_url="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu${ubuntu_ver}_all.deb"
  local tmp_deb="/tmp/zabbix-release_ubuntu${ubuntu_ver}.deb"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Downloading Zabbix repo package: $repo_deb_url" | tee -a "$LOGFILE"
  if ! wget -q -O "$tmp_deb" "$repo_deb_url"; then
    echo "ERROR: Failed to download Zabbix repo package. Check if version $ubuntu_ver is supported." | tee -a "$LOGFILE"
    exit 1
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing Zabbix repo package..." | tee -a "$LOGFILE"
  dpkg -i "$tmp_deb" >> "$LOGFILE" 2>&1 || apt-get install -f -y >> "$LOGFILE" 2>&1
  rm -f "$tmp_deb"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updating packages..." | tee -a "$LOGFILE"
  apt-get update -qq --allow-releaseinfo-change -o Acquire::Retries=2 >> "$LOGFILE" 2>&1 || echo "apt-get update finished with errors, continuing..." | tee -a "$LOGFILE"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing zabbix-agent from official repo..." | tee -a "$LOGFILE"
  apt-get install -y --no-install-recommends zabbix-agent zabbix-sender sudo >> "$LOGFILE" 2>&1
}

configure_zabbix_agent() {
  local conf="/etc/zabbix/zabbix_agentd.conf"

  local server=""
  printf "Введите IP Zabbix Server: " > /dev/tty 2>/dev/null || true
  read -r server < /dev/tty 2>/dev/null || server=""
  server="${server:-}"

  local hostname
  hostname="$(hostname -f 2>/dev/null || hostname)"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Writing config to $conf ..." | tee -a "$LOGFILE"

  cat > "$conf" <<CONF
Server=${server:-127.0.0.1},127.0.0.1
ServerActive=${server:-127.0.0.1}
Hostname=${hostname}
StartAgents=3
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogType=system
DebugLevel=3

AllowRoot=1
EnableRemoteCommands=1
User=zabbix
Timeout=30

AllowKey=system.run[*]
CONF

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Config written." | tee -a "$LOGFILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hostname: ${hostname}" | tee -a "$LOGFILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server: ${server:-127.0.0.1}" | tee -a "$LOGFILE"

  usermod -aG docker zabbix 2>/dev/null || true

  local install_wg=""
  printf "Установить скрипты мониторинга WireGuard (wg-v2-peer-*)? (y/N): " > /dev/tty 2>/dev/null || true
  read -r install_wg < /dev/tty 2>/dev/null || install_wg=""

  if [[ "${install_wg:-}" =~ ^[Yy]$ ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing WG scripts..." | tee -a "$LOGFILE"
    mkdir -p /usr/local/bin

    cat > /usr/local/bin/wg-v2-peer-discovery.sh <<'WGEOF'
#!/bin/bash
docker exec wg-easy cat /etc/wireguard/wg0.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
out=[]
for c in d.get('clients',{}).values():
    if not c.get('enabled', False):
        continue
    out.append({'{#PEER_IP}': c.get('address','').split('/')[0], '{#PEER_NAME}': c.get('name','unknown')})
print(json.dumps({'data':out}))
"
WGEOF

    cat > /usr/local/bin/wg-v2-peer-age.sh <<'WGEOF'
#!/bin/bash
PEER_IP="$1"
docker exec wg-easy wg show wg0 dump | awk -F'\t' -v ip="$PEER_IP/32" '$4==ip {print int(systime()-$5)}'
WGEOF

    cat > /usr/local/bin/wg-v2-peer-traffic.sh <<'WGEOF'
#!/bin/bash
PEER_IP="$1"
docker exec wg-easy wg show wg0 dump | awk -F'\t' -v ip="$PEER_IP/32" '$4==ip {print $6+$7}'
WGEOF

    chmod +x /usr/local/bin/wg-v2-peer-*.sh
    chown zabbix:zabbix /usr/local/bin/wg-v2-peer-*.sh

    cat > /etc/zabbix/zabbix_agentd.d/wg-peer.conf <<'CONFEOF'
UserParameter=wg.peer.discovery,sudo -u zabbix /usr/local/bin/wg-v2-peer-discovery.sh
UserParameter=wg.peer.age[*],sudo -u zabbix /usr/local/bin/wg-v2-peer-age.sh $1
UserParameter=wg.peer.traffic[*],sudo -u zabbix /usr/local/bin/wg-v2-peer-traffic.sh $1
CONFEOF

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WG scripts installed." | tee -a "$LOGFILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WG scripts skipped." | tee -a "$LOGFILE"
  fi
}

open_zabbix_port() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Opening port 10050/tcp for Zabbix..." | tee -a "$LOGFILE"
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 10050/tcp comment 'Zabbix Agent' >> "$LOGFILE" 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=10050/tcp >> "$LOGFILE" 2>&1 || true
    firewall-cmd --reload >> "$LOGFILE" 2>&1 || true
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Port 10050/tcp open step done." | tee -a "$LOGFILE"
}

restart_zabbix_agent() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restarting zabbix-agent..." | tee -a "$LOGFILE"
  systemctl enable --now zabbix-agent >> "$LOGFILE" 2>&1 || systemctl restart zabbix-agent >> "$LOGFILE" 2>&1 || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Service status:" | tee -a "$LOGFILE"
  systemctl is-active zabbix-agent | tee -a "$LOGFILE" || true
}

show_logs() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Installation log (last 200 lines) ===" | tee -a "$LOGFILE"
  tail -n 200 "$LOGFILE" 2>/dev/null | tee -a "$LOGFILE" || true
}

# Показывает Hostname из файла конфига агента
show_hostname_from_config() {
  local conf="/etc/zabbix/zabbix_agentd.conf"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Hostname from config ($conf) ===" | tee -a "$LOGFILE"
  if [[ -f "$conf" ]]; then
    local hn
    hn="$(grep -E '^[[:space:]]*Hostname[[:space:]]*=' "$conf" | tail -n1 | sed -E 's/^[[:space:]]*Hostname[[:space:]]*=[[:space:]]*//')"
    echo "Hostname=${hn:-<not set>}" | tee -a "$LOGFILE"
  else
    echo "Config file $conf not found" | tee -a "$LOGFILE"
  fi
}

main() {
  install_zabbix_agent
  configure_zabbix_agent
  open_zabbix_port
  restart_zabbix_agent
  show_logs

  # Вывод Hostname из конфига
  show_hostname_from_config

  # Через 30 секунд — повторный перезапуск агента
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting 30 seconds before second restart..." | tee -a "$LOGFILE"
  sleep 30
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Second restart of zabbix-agent..." | tee -a "$LOGFILE"
  restart_zabbix_agent

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Zabbix Agent installer finished ===" | tee -a "$LOGFILE"
}

main "$@"
