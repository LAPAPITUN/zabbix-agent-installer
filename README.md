# Zabbix Agent Installer

One-shot installer for Ubuntu. Installs `zabbix-agent`, writes `zabbix_agentd.conf`, opens port `10050/tcp`, restarts the service, and saves a full log.

## Usage

```bash
curl -fsSL https://raw.githubusercontent.com/LAPAPITUN/zabbix-agent-installer/master/install_zabbix_agent.sh | sudo bash
```

## What it does

- adds official Zabbix repo
- installs `zabbix-agent`
- opens port `10050/tcp` (`ufw` / `firewalld`)
- writes `/etc/zabbix/zabbix_agentd.conf`
- restarts `zabbix-agent`
- writes full output log to `/var/log/zabbix_agent_install.log`

## Config written

```ini
Server=<SERVER_ADDRESS>,127.0.0.1
StartAgents=3
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogType=system
DebugLevel=3

AllowRoot=1
User=zabbix
Timeout=30
DenyKey=system.run[*]

UserParameter=timeweb_config_version,echo 127
```

`<SERVER_ADDRESS>` — адрес основного Zabbix-сервера, который запрашивается у пользователя во время установки. По умолчанию используется `103.74.94.90`.

## Supported Ubuntu versions

- `noble` / `resolute` — Zabbix 7.0
- остальные — Zabbix 6.4

## Log

After the run:

```bash
less /var/log/zabbix_agent_install.log
```

## Notes

- Requires root.
- If restart fails, script attempts enable + start and prints `systemctl status`.
