# Configuration


Each app is a folder in `/opt/indie-agent/apps/<name>` with an `app.json` file.


Fields:
- `repo` (string, required): Git URL (SSH or HTTPS)
- `branch` (string, default `main`)
- `image_updates` (bool, default `false`): run `docker compose pull` before deploy
- `compose_file` (string, default `docker-compose.yml`): relative to `workdir`
- `workdir` (string, default `repo`): where the repo is cloned
- `pre_hook` / `post_hook` (string): shell commands (run within `workdir`)
- `health_check` (object): `{ url, timeout, retries, interval }`
