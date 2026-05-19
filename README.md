# Hermes Bootstrap

One-command install for the full Hermes stack on any Linux machine.

## What it installs

- **hermes-agent** -- autonomous AI agent with memory, skills, cron
- **hermes-webui** -- browser chat interface (localhost:8787)
- **hermes-sync** (private) -- config, skills, memories, workspace

## One-liner

```bash
GITHUB_TOKEN=ghp_your_token_here curl -fsSL https://raw.githubusercontent.com/ChonSong/hermes-bootstrap/main/setup.sh | bash
```

Get your token at https://github.com/settings/tokens — needs **repo** (full) scope for private repos.

## After install

| Service | URL |
|---------|-----|
| WebUI | http://localhost:8787 |
| TUI | docker exec hermes /opt/hermes/.venv/bin/hermes --tui |
| Logs | docker logs hermes -f |
