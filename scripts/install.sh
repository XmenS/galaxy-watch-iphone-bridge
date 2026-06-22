#!/usr/bin/env bash
# Galaxy Health Bridge — one-line installer.
# Usage: curl -fsSL https://raw.githubusercontent.com/galaxy-health-bridge/galaxy-health-bridge/main/scripts/install.sh | bash
set -euo pipefail

REPO="${GHB_REPO:-galaxy-health-bridge/galaxy-health-bridge}"
INSTALL_DIR="${GHB_HOME:-$HOME/.galaxy-health-bridge}"
VERSION="${GHB_VERSION:-latest}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
err()  { printf "\033[31m%s\033[0m\n" "$*" >&2; exit 1; }

bold "→ Galaxy Health Bridge installer"

command -v docker >/dev/null || err "Docker required. https://docs.docker.com/engine/install/"
docker compose version >/dev/null 2>&1 || err "Docker Compose v2 required."

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

bold "→ Fetching compose stack ($VERSION)"
curl -fsSL "https://raw.githubusercontent.com/$REPO/$VERSION/infrastructure/docker/docker-compose.yml" -o docker-compose.yml
curl -fsSL "https://raw.githubusercontent.com/$REPO/$VERSION/infrastructure/docker/Caddyfile" -o Caddyfile

if [ ! -f .env ]; then
  bold "→ Generating .env"
  : "${POSTGRES_PASSWORD:=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)}"
  : "${JWT_SECRET:=$(openssl rand -base64 48 | tr -d '/+=')}"
  : "${ENCRYPTION_KEY:=$(openssl rand -hex 32)}"
  cat > .env <<EOF
POSTGRES_USER=ghb
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=ghb
PUBLIC_URL=${PUBLIC_URL:-http://localhost:8000}
PUBLIC_DOMAIN=${PUBLIC_DOMAIN:-localhost}
JWT_SECRET=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
E2E_REQUIRED=${E2E_REQUIRED:-false}
EOF
  chmod 600 .env
fi

bold "→ Pulling images"
docker compose pull --quiet

bold "→ Starting stack"
docker compose up -d

bold "→ Running database migrations"
docker compose run --rm migrate || true

bold "✓ Galaxy Health Bridge is running"
echo "API:      $(grep PUBLIC_URL .env | cut -d= -f2)"
echo "Docs:     $(grep PUBLIC_URL .env | cut -d= -f2)/docs"
echo "Data:     $INSTALL_DIR"
echo "Logs:     cd $INSTALL_DIR && docker compose logs -f"
