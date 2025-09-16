# Health Checks


Provide a fast HTTP endpoint (e.g., `/healthz`) that returns `200`.
Configure in `app.json` → `health_check.url`, `timeout`, `retries`, and `interval`.
If checks fail after deploy, the agent resets to the last good commit and retries once.
