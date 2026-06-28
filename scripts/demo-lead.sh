#!/usr/bin/env bash
# DEMO helper (untracked) — fire one HMAC-signed lead at Workflow 1.
# Use during the demo recording: run it, then switch to n8n / Slack / Supabase.
set -euo pipefail
cd "$(dirname "$0")/.."

SECRET=$(grep '^WEBHOOK_HMAC_SECRET=' .env | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
BODY='{"name":"Dana Whitfield","company":"NorthPeak Logistics","email":"dana@northpeak.io","title":"VP Operations","employees":450,"message":"Budget approved for Q3 — we need to automate dispatch within 30 days. Can we start a paid pilot next week?"}'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')

echo "→ POST /webhook/lead (high-intent lead, expect score ≥ 70)"
curl -s -w "\nHTTP %{http_code}\n" -X POST http://localhost:5678/webhook/lead \
  -H "content-type: application/json" -H "x-signature: $SIG" --data "$BODY"
echo "→ Now check: n8n Executions (8 green) · Slack #autostream-alerts · Supabase llm_calls + workflow_runs"
