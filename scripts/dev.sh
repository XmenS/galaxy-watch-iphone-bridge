#!/usr/bin/env bash
# Convenience wrapper to bring up dev stack + tail API logs.
set -euo pipefail
cd "$(dirname "$0")/.."
make install
make dev &
PID=$!
trap "kill $PID 2>/dev/null || true" EXIT
sleep 5
docker compose -f infrastructure/docker/docker-compose.yml logs -f api
