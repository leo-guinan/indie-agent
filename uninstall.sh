#!/usr/bin/env bash
set -euo pipefail
need_root() { [[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }; }
need_root


systemctl disable --now indie-agent.timer || true
systemctl disable --now indie-agent.service || true
rm -f /etc/systemd/system/indie-agent.timer /etc/systemd/system/indie-agent.service
systemctl daemon-reload


PURGE=${1:-}
if [[ "$PURGE" == "--purge" ]]; then
rm -rf /opt/indie-agent /var/lib/indie-agent
rm -f /usr/local/bin/indie-agent
echo "✅ Uninstalled and purged /opt/indie-agent and /var/lib/indie-agent."
else
echo "✅ Uninstalled systemd units. Data/code kept in /opt/indie-agent and /var/lib/indie-agent."
fi
