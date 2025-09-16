# Security Notes


- Use **read-only deploy keys** for private repos (GitHub: Settings → Deploy keys).
- The agent runs as a non-root user. Only Docker group membership is needed.
- Keep secrets in app `.env` files (Compose automatically loads `.env`).
- Locking: the agent uses `flock` to prevent overlapping runs.
