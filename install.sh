#!/usr/bin/env bash
# indie-agent installer (v0.1.1)
set -Eeuo pipefail

# === Defaults (override via env) ===
RUN_AS="${RUN_AS:-indie}"            # system user to run the agent
INSTALL_DOCKER="${INSTALL_DOCKER:-true}"  # install Docker if missing
TIMER_INTERVAL="${TIMER_INTERVAL:-5m}"    # OnUnitActiveSec value for the timer

ensure_root() { if [[ $EUID -ne 0 ]]; then echo "Run as root" >&2; exit 1; fi; }
ensure_root

echo ">> Installing base deps"
apt-get update -y
apt-get install -y jq curl git ca-certificates gnupg

echo ">> Ensuring user '${RUN_AS}' exists"
if ! id -u "$RUN_AS" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$RUN_AS"
  usermod -aG sudo "$RUN_AS"
fi

echo ">> Installing Docker (if requested or missing)"
if [[ "$INSTALL_DOCKER" == "true" ]] || ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  ARCH="$(dpkg --print-architecture)"
  . /etc/os-release
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

echo ">> Docker group membership"
getent group docker >/dev/null || groupadd docker
usermod -aG docker "$RUN_AS"

echo ">> Laying out directories"
BASE="/opt/indie-agent"
STATE="/var/lib/indie-agent"
mkdir -p "$BASE"/{bin,agent,systemd,examples,docs,apps} "$STATE/logs"
chown -R "$RUN_AS":"$RUN_AS" "$BASE" "$STATE"

echo ">> Installing agent + CLI from repo checkout"
# Expect these files to exist in the repo:
#   agent/agent.sh
#   bin/indie-agent
install -m 0755 agent/agent.sh "$BASE/agent/agent.sh"
install -m 0755 bin/indie-agent /usr/local/bin/indie-agent

echo ">> Writing systemd units"
cat > /etc/systemd/system/indie-agent.service <<EOF
[Unit]
Description=Indie deploy agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=${RUN_AS}
Group=${RUN_AS}
WorkingDirectory=${BASE}
ExecStart=${BASE}/agent/agent.sh
Nice=10
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
EOF

cat > /etc/systemd/system/indie-agent.timer <<EOF
[Unit]
Description=Run the deploy agent on a schedule

[Timer]
OnBootSec=2m
OnUnitActiveSec=${TIMER_INTERVAL}
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo ">> Enabling timer"
systemctl daemon-reload
systemctl enable --now indie-agent.timer

echo "✅ Installed. Runs as ${RUN_AS}. Timer interval: ${TIMER_INTERVAL}."
echo "Apps dir: ${BASE}/apps   |   State: ${STATE}"
echo "CLI: indie-agent  (run | status | logs [app] | register ...)"
