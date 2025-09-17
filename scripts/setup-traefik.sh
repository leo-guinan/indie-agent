#!/usr/bin/env bash


[[ -n "$ACME_EMAIL" ]] || { echo "--email is required" >&2; exit 1; }
[[ -n "$CF_TOKEN" ]] || { echo "--cf-token is required" >&2; exit 1; }


mkdir -p "$BASE/letsencrypt"
chmod 700 "$BASE/letsencrypt"


# .env with sensitive token
ENV_FILE="$BASE/.env"
cat >"$ENV_FILE" <<EOF
ACME_EMAIL=${ACME_EMAIL}
CLOUDFLARE_DNS_API_TOKEN=${CF_TOKEN}
EOF
chmod 600 "$ENV_FILE"


# docker-compose.yml
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
- --certificatesresolvers.${RESOLVER}.acme.email=
- --certificatesresolvers.${RESOLVER}.acme.storage=/letsencrypt/acme.json
- --certificatesresolvers.${RESOLVER}.acme.dnschallenge.provider=cloudflare
environment:
- TZ=UTC
- ACME_EMAIL=
- CLOUDFLARE_DNS_API_TOKEN=
env_file:
- .env
volumes:
- /var/run/docker.sock:/var/run/docker.sock:ro
- ./letsencrypt:/letsencrypt
YAML


# acme storage
ACME_STORE="$BASE/letsencrypt/acme.json"
if [[ ! -f "$ACME_STORE" ]]; then
touch "$ACME_STORE"
fi
chmod 600 "$ACME_STORE"


# Optional migration from old path
if [[ -d "$MIGRATE_FROM/letsencrypt" && -f "$MIGRATE_FROM/letsencrypt/acme.json" ]]; then
if [[ ! -s "$ACME_STORE" || "$FORCE" == true ]]; then
echo "Migrating existing acme.json from $MIGRATE_FROM" >&2
cp -f "$MIGRATE_FROM/letsencrypt/acme.json" "$ACME_STORE"
chmod 600 "$ACME_STORE"
else
echo "acme.json already exists at $ACME_STORE; skipping migration (use --force to overwrite)" >&2
fi
fi


# If an older traefik is running, stop it (optional)
if docker ps --format '{{.Names}}' | grep -qx 'traefik'; then
echo "Stopping existing traefik container…" >&2
docker stop traefik >/dev/null || true
docker rm traefik >/dev/null || true
fi


# Bring up Traefik
pushd "$BASE" >/dev/null
export COMPOSE_IGNORE_ORPHANS=true
DOCKER_DEFAULT_PLATFORM=${DOCKER_DEFAULT_PLATFORM:-} docker compose --env-file .env up -d
popd >/dev/null


echo
echo "✅ Traefik up with DNS-01 (Cloudflare). Base: $BASE"
echo "- Resolver name: $RESOLVER"
echo "- ACME email: $ACME_EMAIL"
echo "- Env file: $ENV_FILE (600)"
echo "- ACME store: $ACME_STORE (600)"
echo
cat <<'TIP'
Next steps:
1) Point your app/router labels at this resolver (example):
- traefik.http.routers.myapp.entrypoints=websecure
- traefik.http.routers.myapp.tls.certresolver=le
2) Keep your Cloudflare DNS record proxied (orange). DNS-01 works with the proxy on.
3) Check logs for ACME events:
docker logs traefik --since=5m | egrep -i 'acme|lego|challenge|certificate'
TIP
