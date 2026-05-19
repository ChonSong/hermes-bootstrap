# Hermes Bootstrap

One-command install for the full Hermes stack on any Linux machine.

## What it installs

- **hermes-agent** -- autonomous AI agent with memory, skills, cron
- **hermes-webui** -- browser chat interface (localhost:8787)
- **hermes-sync** (private) -- config, skills, memories, workspace

## One-liner

    curl -fsSL https://raw.githubusercontent.com/ChonSong/hermes-bootstrap/main/setup.sh | bash

You will be prompted for a GitHub PAT (classic, repo scope needed).

## After install

| Service | URL |
|---------|-----|
| WebUI | http://localhost:8787 |
| TUI | docker exec hermes /opt/hermes/.venv/bin/hermes --tui |
| Logs | docker logs hermes -f |
