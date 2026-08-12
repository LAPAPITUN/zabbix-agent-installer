# Zabbix Agent Installer

One-shot installer for Ubuntu. Installs `zabbix-agent`, writes `zabbix_agentd.conf`, opens port `10050/tcp`, restarts the service, and saves a full log.

## Usage

```bash
curl -fsSL https://raw.githubusercontent.com/LAPAPITUN/zabbix-agent-installer/master/install_zabbix_agent.sh | sudo bash
```

For non-interactive runs:

```bash
curl -fsSL https://raw.githubusercontent.com/LAPAPITUN/zabbix-agent-installer/master/install_zabbix_agent.sh | sudo ZBX_SERVER=1.2.3.4 INSTALL_WG=y bash
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
ServerActive=<SERVER_ADDRESS>
Hostname=<HOSTNAME>
StartAgents=3
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogType=system
DebugLevel=3

AllowRoot=1
EnableRemoteCommands=1
User=zabbix
Timeout=30

AllowKey=system.run[*]
```

`<SERVER_ADDRESS>` — address of the primary Zabbix server, asked during install or passed via `ZBX_SERVER` env var.

## Supported Ubuntu versions

- `noble` — Zabbix 7.0
- `jammy` — Zabbix 7.0
- `oracular` — Zabbix 7.0
- other — fallback to Zabbix 7.0 for `noble`

## Log

After the run:

```bash
less /var/log/zabbix_agent_install.log
```

## Notes

- Requires root.
- If restart fails, script attempts enable + start and prints `systemctl status`.
