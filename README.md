# indie-agent


Self-scheduling deploy agent for Dockerized apps on a single box. It pulls your repos on a schedule, (optionally) updates images, runs `docker compose up -d`, executes hooks, health-checks your app, and **rolls back** to the last good commit if something breaks.


- Works great with Traefik or Nginx as your TLS reverse proxy
- No orchestrator required
- Ideal for indie servers hosting multiple small apps + a Ghost blog


## Features
- 🕒 **Scheduled** updates via systemd timer (default every 5m)
- 🔁 **Idempotent** runs with a lock (no overlapping deploys)
- ✅ **Health checks** with retries + automatic **rollback**
- 📦 **Compose-native**: your repos contain `docker-compose.yml`
- 🔐 **Deploy keys**: use SSH deploy keys for private GitHub repos


## Requirements
- Ubuntu 22.04/24.04 or similar
- Docker Engine + Compose v2 plugin (`docker compose`)
- `git`, `jq`, `curl`


> Don’t have Docker yet? The installer can set it up for you.


## Quickstart


```bash
# As root on the target server
apt-get update && apt-get install -y git
cd /opt && git clone https://github.com/leo-guinan/indie-agent.git
cd indie-agent
# Optional: edit defaults at the top of install.sh
sudo bash install.sh
```
This will:

create /opt/indie-agent and /var/lib/indie-agent

install Docker (if missing), jq, curl, git

create a non-root user (default: indie) and add to docker group

set up systemd service + timer

install the indie-agent CLI wrapper to /usr/local/bin

Register your first app

Your app lives in its own repo that contains a docker-compose.yml (with reverse-proxy labels). Register it with the agent:
```
sudo indie-agent register blog \
  git@github.com:you/ghost-prod.git \
  https://blog.example.com/ghost/#/signin \
  main true

Args: <name> <git-url> <health-url> [branch=main] [image_updates=false]
```
The timer runs every 5 minutes. Force a run any time:
```
sudo indie-agent run
sudo journalctl -u indie-agent.service -n 200 -f
```


App config format (/opt/indie-agent/apps/<name>/app.json)
```
{
  "repo": "git@github.com:you/ghost-prod.git",
  "branch": "main",
  "image_updates": true,
  "compose_file": "docker-compose.yml",
  "workdir": "repo",
  "pre_hook": "",
  "post_hook": "",
  "health_check": { "url": "https://blog.example.com/ghost/#/signin", "timeout": 10, "retries": 2, "interval": 3 }
}
```

Uninstall
```
sudo bash uninstall.sh        # keeps /opt/indie-agent and /var/lib/indie-agent
sudo bash uninstall.sh --purge  # removes code and state (be careful)
```
Security

Use deploy keys (read-only) for private repos

The agent runs as a non-root user and uses flock to avoid overlap

Keep secrets in your app repo’s .env files or Docker secrets
