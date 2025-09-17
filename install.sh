#!/usr/bin/env bash
# indie-agent installer (v0.1.2) — supports in-place installs
set -Eeuo pipefail

# === Defaults (override via env) ===
RUN_AS="${RUN_AS:-indie}"                  # system user to run the agent
INSTALL_DOCKER="${INSTALL_DOCKER:-true}"   # install Docker if missing
TIMER_INTERVAL="${TIMER_INTERVAL:-5m}"     # systemd OnUnitActiveSec
BASE="${BASE:-/opt/indie-agent}"           # install target

ensure_root() { [[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }; }
ensure_root

# Where is the repo we're running from?
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC_AGENT="${REPO_DIR}/agent/agent.sh"
SRC_CLI="${REPO_DIR}/bin/indie-agent"
DST_AGENT="${BASE}/agent/agent.sh"
DST_CLI="/usr/local/bin/indie-agent"

same_path() { [[ "$(readlink -f "$1")" == "$(readlink -f "$2")" ]]; }

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

echo ">> Laying out directories at ${BASE}"
mkdir -p "${BASE}"/{bin,agent,systemd,examples,docs,apps} /var/lib/indie-agent/logs
chown -R "$RUN_AS":"$RUN_AS" "$BASE" /var/lib/indie-agent

echo ">> Installing agent"
if [[ -f "$SRC_AGENT" ]]; then
  if same_path "$SRC_AGENT" "$DST_AGENT"; then
    chmod 0755 "$DST_AGENT"
    echo "   (in-place) agent already at ${DST_AGENT}"
  else
    install -m 0755 -D "$SRC_AGENT" "$DST_AGENT"
  fi
else
  echo "ERROR: $SRC_AGENT not found" >&2; exit 1
fi

echo ">> Installing CLI"
if [[ -f "$SRC_CLI" ]]; then
  # Prefer a symlink so in-place updates reflect immediately
  if [[ -e "$DST_CLI" && -L "$DST_CLI" && "$(readlink -f "$DST_CLI")" == "$(readlink -f "$SRC_CLI")" ]]; then
    :
  else
    ln -sf "$SRC_CLI" "$DST_CLI" || install -m 0755 -D "$SRC_CLI" "$DST_CLI"
  fi
  chmod 0755 "$DST_CLI"
else
  echo "ERROR: $SRC_CLI not found" >&2; exit 1
fi

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
ExecStart=${DST_AGENT}
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
echo "Repo: ${REPO_DIR}"
echo "Base: ${BASE}"
echo "CLI: ${DST_CLI}  (try: indie-agent status)"
