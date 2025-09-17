#!/usr/bin/env bash
# Setup Traefik (DNS-01 via Cloudflare)
set -euo pipefail

# Defaults (env override supported)
ACME_EMAIL="${ACME_EMAIL:-}"
CF_TOKEN="${CLOUDFLARE_DNS_API_TOKEN:-${CF_TOKEN:-}}"
BASE="${BASE:-/opt/traefik}"
RESOLVER="${RESOLVER:-le}"
MIGRATE_FROM="${MIGRATE_FROM:-/opt/ghost-host/traefik}"
FORCE="${FORCE:-false}"

# Parse flags: --flag value OR --flag=value
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)            ACME_EMAIL="${2:-}"; shift 2;;
    --email=*)          ACME_EMAIL="${1#*=}"; shift 1;;
    --cf-token)         CF_TOKEN="${2:-}"; shift 2;;
    --cf-token=*)       CF_TOKEN="${1#*=}"; shift 1;;
    --base)             BASE="${2:-}"; shift 2;;
    --base=*)           BASE="${1#*=}"; shift 1;;
    --resolver)         RESOLVER="${2:-}"; shift 2;;
    --resolver=*)       RESOLVER="${1#*=}"; shift 1;;
    --migrate-from)     MIGRATE_FROM="${2:-}"; shift 2;;
    --migrate-from=*)   MIGRATE_FROM="${1#*=}"; shift 1;;
    --force)            FORCE=true; shift 1;;
    -h|--help)          sed -n '1,80p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

[[ -n "$ACME_EMAIL" ]] || { echo "--email is required"; exit 1; }
[[ -n "$CF_TOKEN"   ]] || { echo "--cf-token is required"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need docker
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 required"; exit 1; }

mkdir -p "$BASE/letsencrypt"
chmod 700 "$BASE/letsencrypt"

# .env (contains sensitive token)
ENV_FILE="$BASE/.env"
cat >"$ENV_FILE" <<EOF
ACME_EMAIL=$ACME_EMAIL
CLOUDFLARE_DNS_API_TOKEN=$CF_TOKEN
EOF
chmod 600 "$ENV_FILE"

# compose
COMPOSE_FILE="$BASE/docker-compose.yml"
cat >"$COMPOSE_FILE" <<YAML
services:
  traefik:
    image: traefik:v3.5
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entryPoints.web.address=:80
      - --entryPoints.websecure.address=:443
      - --certificatesresolvers.${RESOLVER}.acme.email=\${ACME_EMAIL}
      - --certificatesresolvers.${RESOLVER}.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.${RESOLVER}.acme.dnschallenge.provider=cloudflare
    env_file:
      - .env
    environment:
      - TZ=UTC
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
YAML

ACME_STORE="$BASE/letsencrypt/acme.json"
[[ -f "$ACME_STORE" ]] || touch "$ACME_STORE"
chmod 600 "$ACME_STORE"

# Migrate old acme.json if present
if [[ -f "$MIGRATE_FROM/letsencrypt/acme.json" ]]; then
  if [[ ! -s "$ACME_STORE" || "$FORCE" == "true" ]]; then
    cp -f "$MIGRATE_FROM/letsencrypt/acme.json" "$ACME_STORE"
    chmod 600 "$ACME_STORE"
    echo "Migrated acme.json from $MIGRATE_FROM"
  else
    echo "acme.json exists at $ACME_STORE; skipping migration (use --force to overwrite)"
  fi
fi

# Restart traefik cleanly if already running
if docker ps --format '{{.Names}}' | grep -qx traefik; then
  docker stop traefik >/dev/null || true
  docker rm traefik >/dev/null || true
fi

pushd "$BASE" >/dev/null
docker compose --env-file .env up -d
popd >/dev/null

echo "✅ Traefik up at $BASE using DNS-01 (resolver: $RESOLVER)."
echo "Check logs: docker logs traefik --since=5m | egrep -i 'acme|lego|certificate'"
