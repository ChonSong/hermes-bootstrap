#!/bin/bash
set -e

HERMES_BOOTSTRAP_DIR="${HOME}/hermes-bootstrap"
HERMES_SYNC_DIR="${HOME}/hermes-sync"
HERMES_DIR="${HOME}/.hermes"
WORKSPACE_DIR="${HOME}/workspace"
PASSPHRASE="${PASSPHRASE:-dawnofdoyle}"

echo "==> Hermes bootstrap"
echo ""

# GitHub PAT (required)
if [[ -z "${GITHUB_TOKEN}" ]]; then
    echo "Error: GITHUB_TOKEN environment variable not set."
    echo ""
    echo "  Usage:  GITHUB_TOKEN=ghp_xxx curl -fsSL .../setup.sh | bash"
    echo "  Or:     export GITHUB_TOKEN=ghp_xxx  # then run the curl command"
    echo ""
    echo "  Create a PAT at: https://github.com/settings/tokens"
    echo "  Required scope: repo (full) — for private repos hermes-sync, hermes-webui"
    exit 1
fi
export GITHUB_TOKEN
AUTH_BASE="https://${GITHUB_TOKEN}@github.com"

# Package manager
if command -v apt-get &>/dev/null; then PKG_MGR="apt-get"
elif command -v dnf &>/dev/null; then PKG_MGR="dnf"
elif command -v pacman &>/dev/null; then PKG_MGR="pacman"
else echo "Unsupported distro"; exit 1; fi

echo "==> Installing dependencies..."
case "$PKG_MGR" in
    apt-get) sudo apt-get update && sudo apt-get install -y docker.io docker-compose git python3-cryptography curl rsync ;;
    dnf)     sudo dnf install -y docker docker-compose git python3-cryptography curl rsync ;;
    pacman)  sudo pacman -Syu --noconfirm docker docker-compose git python3-cryptography curl rsync ;;
esac

# Git credential helper — needed for pulls after clones
git config --global credential.helper "store"

# Clone hermes-bootstrap (this repo — public)
if [[ -d "$HERMES_BOOTSTRAP_DIR/.git" ]]; then
    echo "==> Updating hermes-bootstrap..."
    git -C "$HERMES_BOOTSTRAP_DIR" pull
else
    echo "==> Cloning hermes-bootstrap..."
    git clone "https://github.com/ChonSong/hermes-bootstrap.git" "$HERMES_BOOTSTRAP_DIR"
fi

# Clone hermes-sync (private)
if [[ -d "$HERMES_SYNC_DIR/.git" ]]; then
    echo "==> Updating hermes-sync..."
    git -C "$HERMES_SYNC_DIR" pull
else
    echo "==> Cloning hermes-sync..."
    git clone "${AUTH_BASE}/ChonSong/hermes-sync.git" "$HERMES_SYNC_DIR"
fi

# Clone hermes-agent (public fork of NousResearch)
HERMES_AGENT_DIR="$(dirname "$HERMES_SYNC_DIR")/hermes-agent"
if [[ -d "$HERMES_AGENT_DIR/.git" ]]; then
    echo "==> Updating hermes-agent..."
    git -C "$HERMES_AGENT_DIR" pull
else
    echo "==> Cloning hermes-agent..."
    git clone "${AUTH_BASE}/ChonSong/hermes-agent.git" "$HERMES_AGENT_DIR" || \
    git clone "https://github.com/NousResearch/hermes-agent.git" "$HERMES_AGENT_DIR"
fi

# Clone hermes-webui (private)
HERMES_WEBUI_DIR="$(dirname "$HERMES_SYNC_DIR")/hermes-webui"
if [[ -d "$HERMES_WEBUI_DIR/.git" ]]; then
    echo "==> Updating hermes-webui..."
    git -C "$HERMES_WEBUI_DIR" pull
else
    echo "==> Cloning hermes-webui..."
    git clone "${AUTH_BASE}/ChonSong/hermes-webui.git" "$HERMES_WEBUI_DIR"
fi

# Init hermes dir git repo (for backup cron)
if [[ ! -d "$HERMES_DIR/.git" ]]; then
    echo "==> Initializing $HERMES_DIR..."
    mkdir -p "$HERMES_DIR"
    git -C "$HERMES_DIR" init
    git -C "$HERMES_DIR" remote add origin "${AUTH_BASE}/ChonSong/hermes-sync.git"
fi

# Restore secrets
if [[ -f "${HERMES_SYNC_DIR}/secrets.age" ]]; then
    echo "==> Restoring secrets..."
    mkdir -p "$HERMES_DIR"
    python3 - <<'PYEOF'
import base64, os
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

passphrase = os.environ.get("PASSPHRASE", "dawnofdoyle")
salt = b"hermes-sync-salt-v1"
kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=480000)
key = base64.urlsafe_b64encode(kdf.derive(passphrase.encode()))

with open("secrets.age", "rb") as f:
    token = f.read()
f2 = Fernet(key)
decrypted = f2.decrypt(token)
with open(".env", "wb") as out:
    out.write(decrypted)
for line in decrypted.decode().splitlines():
    if line.startswith("RCLONE_CONFIG_BASE64="):
        b64 = line.split("=", 1)[1].strip()
        rclone_conf = base64.b64decode(b64).decode()
        os.makedirs(".hermes/rclone_config", exist_ok=True)
        with open(".hermes/rclone_config/rclone.conf", "w") as f:
            f.write(rclone_conf)
        print("  Rclone config restored.")
        break
print("  Secrets restored.")
PYEOF
fi

# Sync files
echo "==> Syncing files..."
mkdir -p "${HERMES_DIR}/skills" "${WORKSPACE_DIR}"
rsync -av --delete "${HERMES_SYNC_DIR}/config/"   "${HERMES_DIR}/"
rsync -av --delete "${HERMES_SYNC_DIR}/skills/"   "${HERMES_DIR}/skills/"
rsync -av "${HERMES_SYNC_DIR}/memory/"            "${HERMES_DIR}/memories/"
rsync -av "${HERMES_SYNC_DIR}/SOUL.md"            "${HERMES_DIR}/"
rsync -av --delete "${HERMES_SYNC_DIR}/workspace/" "${WORKSPACE_DIR}/"

# Start containers
echo "==> Starting Hermes gateway + dashboard..."
export HERMES_AGENT_DIR
docker compose -f "${HERMES_SYNC_DIR}/docker/docker-compose.yml" up -d --build

echo "==> Starting hermes-webui..."
docker compose -f "${HERMES_WEBUI_DIR}/docker-compose.yml" up -d --build

# Wait for gateway
echo "==> Waiting for gateway..."
max_wait=120
elapsed=0
while true; do
    status=$(docker inspect --format='{{.State.Health.Status}}' hermes 2>/dev/null || echo "none")
    if [[ "$status" == "healthy" ]]; then
        echo "  Gateway healthy!"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    if [[ $elapsed -ge $max_wait ]]; then
        echo "  Warning: health check timed out (status: $status)"
        break
    fi
done

echo ""
echo "Done!"
echo "  WebUI:  http://localhost:8787"
echo "  TUI:    docker exec hermes /opt/hermes/.venv/bin/hermes --tui"
echo "  Logs:   docker logs hermes -f"
