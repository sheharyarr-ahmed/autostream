#!/usr/bin/env bash
# AutoStream preflight checks
# Validates env keys + connectivity before `docker compose up`.
# Exits non-zero on any failure so a CI runner can gate deploys on it.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YEL='\033[1;33m'
RST='\033[0m'

fail=0

pass() { printf "${GREEN}✓${RST} %s\n" "$1"; }
warn() { printf "${YEL}!${RST} %s\n" "$1"; }
err()  { printf "${RED}✗${RST} %s\n" "$1"; fail=1; }

# 1. .env exists
if [[ ! -f .env ]]; then
  err ".env not found — run: cp .env.example .env"
  exit 1
fi
pass ".env present"

# Load .env into the current shell (ignoring comments/blanks)
set -a
# shellcheck disable=SC1091
source .env
set +a

# 2. All keys from .env.example present in .env (non-empty)
required_keys=$(grep -E '^[A-Z_]+=' .env.example | cut -d= -f1)
for key in $required_keys; do
  val="${!key:-}"
  if [[ -z "$val" ]]; then
    err "$key is empty in .env"
  fi
done
[[ $fail -eq 0 ]] && pass "all .env.example keys present"

# 3. Encryption key length
if [[ ${#N8N_ENCRYPTION_KEY} -lt 32 ]]; then
  err "N8N_ENCRYPTION_KEY must be >= 32 chars (currently ${#N8N_ENCRYPTION_KEY})"
else
  pass "N8N_ENCRYPTION_KEY length OK"
fi

# 4. docker compose config parses
if docker compose config >/dev/null 2>&1; then
  pass "docker compose config valid"
else
  err "docker compose config failed"
fi

# 5. Anthropic API reachable
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    https://api.anthropic.com/v1/models || echo "000")
  if [[ "$status" == "200" ]]; then
    pass "Anthropic API reachable (200)"
  else
    err "Anthropic API check failed (HTTP $status)"
  fi
fi

# 6. Supabase reachable (REST root returns 200 with apikey)
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    "$SUPABASE_URL/rest/v1/" || echo "000")
  if [[ "$status" =~ ^(200|404)$ ]]; then
    pass "Supabase REST reachable ($status)"
  else
    err "Supabase check failed (HTTP $status)"
  fi
fi

# 7. Slack webhook accepts test POST (uses a no-op payload that Slack treats as invalid → expect 400)
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d '{}' "$SLACK_WEBHOOK_URL" || echo "000")
  # Slack returns 400 "invalid_payload" for {} but the endpoint is alive.
  if [[ "$status" =~ ^(200|400)$ ]]; then
    pass "Slack webhook endpoint alive ($status)"
  else
    err "Slack webhook unreachable (HTTP $status)"
  fi
fi

echo ""
if [[ $fail -eq 0 ]]; then
  printf "${GREEN}all preflight checks passed${RST}\n"
  exit 0
else
  printf "${RED}preflight failed — fix the items above before running docker compose up${RST}\n"
  exit 1
fi
