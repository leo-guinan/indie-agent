## install.sh
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
fi
ARCH=$(dpkg --print-architecture)
. /etc/os-release
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
>/etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
fi


# docker group membership
getent group docker >/dev/null || groupadd docker
usermod -aG docker "$RUN_AS"


# Layout
BASE=/opt/indie-agent
STATE=/var/lib/indie-agent
mkdir -p "$BASE"/bin "$BASE"/agent "$BASE"/systemd "$BASE"/examples "$BASE"/docs "$STATE"/logs
chown -R "$RUN_AS":"$RUN_AS" "$BASE" "$STATE"


# Install files from repo checkout
cp -f agent/agent.sh "$BASE"/agent/agent.sh
cp -f bin/indie-agent /usr/local/bin/indie-agent
chmod +x "$BASE"/agent/agent.sh /usr/local/bin/indie-agent


# Systemd units
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


systemctl daemon-reload
systemctl enable --now indie-agent.timer


echo "✅ Installed. Runs as ${RUN_AS}. Timer interval: ${TIMER_INTERVAL}."
echo "Apps dir: ${BASE}/apps | State: ${STATE}"
echo "CLI: indie-agent (run/status/logs/register)"
