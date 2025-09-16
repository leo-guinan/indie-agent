#!/usr/bin/env bash
}


rollback(){
local app="$1"; local last_good="$2"; local compose_file="$3"; local workdir="$4"
if [[ -n "$last_good" ]]; then
git reset --hard "$last_good"
else
log "$app: no last_good; leaving current commit"
fi
docker compose -f "$compose_file" up -d
}


deploy_app(){
local app="$1"; local appdir="$2"; local repo="$3"; local branch="$4"; local image_updates="$5"
local compose_file="$6"; local workdir="$7"; local pre_hook="$8"; local post_hook="$9"
local hc_url="${10}"; local hc_timeout="${11}"; local hc_retries="${12}"; local hc_interval="${13}"


mkdir -p "$workdir"
if [[ ! -d "$workdir/.git" ]]; then
git clone --branch "$branch" --depth 1 "$repo" "$workdir"
fi
pushd "$workdir" >/dev/null


local last_good_file="$STATE_DIR/${app}.last_good"
local last_good="$(cat "$last_good_file" 2>/dev/null || true)"
local before="$(git rev-parse HEAD)"


git fetch --depth 1 origin "$branch"
git reset --hard "origin/$branch"


[[ -n "$pre_hook" ]] && bash -lc "$pre_hook" || true


[[ "$image_updates" == "true" ]] && docker compose -f "$compose_file" pull || true
docker compose -f "$compose_file" up -d


if health_check "$hc_url" "$hc_timeout" "$hc_retries" "$hc_interval"; then
log "$app: OK"
git rev-parse HEAD > "$last_good_file"
else
log "$app: UNHEALTHY, rolling back"
rollback "$app" "$last_good" "$compose_file" "$workdir"
if ! health_check "$hc_url" "$hc_timeout" 1 "$hc_interval"; then
log "$app: rollback did not restore health"
fi
fi


popd >/dev/null
}


shopt -s nullglob
for conf in "$APPS_DIR"/*/app.json; do
appdir="$(dirname "$conf")"; app="$(basename "$appdir")"
repo="$(jq -r '.repo // empty' "$conf")" || repo=""
branch="$(jq -r '.branch // "main"' "$conf")"
image_updates="$(jq -r '.image_updates // false' "$conf")"
compose_file="$(jq -r '.compose_file // "docker-compose.yml"' "$conf")"
workrel="$(jq -r '.workdir // "repo"' "$conf")"
pre_hook="$(jq -r '.pre_hook // empty' "$conf")"
post_hook="$(jq -r '.post_hook // empty' "$conf")" # reserved; can be used after compose up
hc_url="$(jq -r '.health_check.url // empty' "$conf")"
hc_timeout="$(jq -r '.health_check.timeout // 10' "$conf")"
hc_retries="$(jq -r '.health_check.retries // 2' "$conf")"
hc_interval="$(jq -r '.health_check.interval // 3' "$conf")"


[[ -z "$repo" ]] && { log "Skipping $app: no repo"; continue; }


workdir="$appdir/$workrel"
compose_path="$workdir/$compose_file"
if [[ ! -f "$compose_path" ]]; then
# Repo may not be cloned yet; set path anyway; deploy_app will clone
:
fi


log "Deploying $app"
deploy_app "$app" "$appdir" "$repo" "$branch" "$image_updates" "$compose_path" "$workdir" "$pre_hook" "$post_hook" "$hc_url" "$hc_timeout" "$hc_retries" "$hc_interval" || true
done
