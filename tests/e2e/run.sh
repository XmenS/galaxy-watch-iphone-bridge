#!/usr/bin/env bash
# Minimal smoke E2E. Hits a running API on localhost:8000.
set -euo pipefail

BASE="${GHB_BASE:-http://localhost:8000}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }

bold "→ /health"
curl -fsS "$BASE/health" | jq .

bold "→ signup"
EMAIL="e2e-$(date +%s)@example.com"
INSTALL="$(uuidgen)"
TOKENS=$(curl -fsS -X POST "$BASE/v1/auth/signup" -H "content-type: application/json" -d @- <<EOF
{ "email": "$EMAIL", "password": "supersecurepass1!", "install_id": "$INSTALL", "device_kind": "android" }
EOF
)
ACCESS=$(echo "$TOKENS" | jq -r .access_token)

bold "→ ingest"
NOW=$(date -u +%FT%TZ)
curl -fsS -X POST "$BASE/v1/sync/ingest" \
  -H "authorization: Bearer $ACCESS" \
  -H "content-type: application/json" \
  -d "{ \"source\": \"samsung-health\", \"samples\": [
    { \"client_uid\": \"e2e-uid-1\", \"source\": \"samsung-health\",
      \"type\": \"heart_rate\", \"unit\": \"bpm\", \"value\": 72,
      \"started_at\": \"$NOW\", \"ended_at\": \"$NOW\", \"metadata\": {} }
  ]}" | jq .

bold "→ samples"
curl -fsS "$BASE/v1/sync/samples?limit=10" -H "authorization: Bearer $ACCESS" | jq .

bold "✓ E2E smoke passed"
