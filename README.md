# Zabbix Agent Installer

One-shot installer for Ubuntu. Installs `zabbix-agent`, writes a fixed `zabbix_agentd.conf`, restarts the service, and saves a full log.

## Usage

```bash
curl -fsSL https://raw.githubusercontent.com/LAPAPITUN/zabbix-agent-installer/main/install_zabbix_agent.sh -o install_zabbix_agent.sh
chmod +x install_zabbix_agent.sh
sudo ./install_zabbix_agent.sh
```

## What it does

- installs `zabbix-agent`
- overwrites `/etc/zabbix/zabbix_agentd.conf`
- restarts `zabbix-agent`
- writes full output log to `/var/log/zabbix_agent_install.log`

## Config written

```ini
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
```

## Log

After the run, log is available at:

```bash
less /var/log/zabbix_agent_install.log
```

## Notes

- Requires root.
- If restart fails, script attempts enable + start and prints `systemctl status`.
