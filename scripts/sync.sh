#!/usr/bin/env bash
# Triggers a bulk sync of the last 28 days of Copilot metrics.
# Reads scope and org/enterprise from .env if present.
# Usage: ./scripts/sync.sh [host]
#   host defaults to http://localhost:3000

set -euo pipefail

HOST="${1:-http://localhost:3000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

# Load .env then .env.local (local overrides base), pulling only the vars we need
SCOPE="" GITHUB_ORG="" GITHUB_ENT=""
for envfile in .env .env.local; do
  if [ -f "$envfile" ]; then
    val=$(grep -E '^NUXT_PUBLIC_SCOPE=' "$envfile" | tail -1 | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
    if [ -n "$val" ]; then SCOPE="$val"; fi
    val=$(grep -E '^NUXT_PUBLIC_GITHUB_ORG=' "$envfile" | tail -1 | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
    if [ -n "$val" ]; then GITHUB_ORG="$val"; fi
    val=$(grep -E '^NUXT_PUBLIC_GITHUB_ENT=' "$envfile" | tail -1 | cut -d= -f2 | tr -d '"' | tr -d "'" || true)
    if [ -n "$val" ]; then GITHUB_ENT="$val"; fi
  fi
done

SCOPE="${SCOPE:-organization}"
GITHUB_ORG="${GITHUB_ORG:-}"
GITHUB_ENT="${GITHUB_ENT:-}"

# Pick identifier based on scope
if [ "$SCOPE" = "enterprise" ]; then
  IDENTIFIER="${GITHUB_ENT}"
  ID_PARAM="githubEnt=$IDENTIFIER"
else
  IDENTIFIER="${GITHUB_ORG}"
  ID_PARAM="githubOrg=$IDENTIFIER"
fi

if [ -z "$IDENTIFIER" ]; then
  echo "Error: could not determine org/enterprise from .env"
  exit 1
fi

# Check the server is reachable
if ! app_is_healthy "$HOST"; then
  report_unhealthy_host "$HOST"
  exit 1
fi

echo "Syncing last 28 days for $SCOPE:$IDENTIFIER ..."
RESPONSE=$(curl -s -X POST "$HOST/api/admin/sync?action=sync-last-28&scope=$SCOPE&$ID_PARAM")
echo "$RESPONSE"

# Surface errors clearly. Parsing (rather than grepping for '"success":false')
# means a response that is not this endpoint's JSON at all — an HTML error page,
# a login redirect — fails loudly instead of passing as a successful sync.
if ! printf '%s' "$RESPONSE" | node -e "
const chunks = [];
process.stdin.on('data', d => chunks.push(d));
process.stdin.on('end', () => {
  let d;
  try {
    d = JSON.parse(chunks.join(''));
  } catch {
    console.error('');
    console.error('Error: sync response was not valid JSON — see the response above');
    process.exit(1);
  }
  if (d.success !== true) {
    const errors = Array.isArray(d.errors) ? d.errors : [];
    console.error('');
    console.error('Error: sync reported failure' + (errors.length ? ' (' + errors.length + ' error(s))' : ''));
    for (const e of errors) console.error('  ' + e.date + ': ' + e.error);
    process.exit(1);
  }
  console.log('');
  console.log('Sync OK: ' + d.savedDays + ' saved, ' + d.skippedDays + ' skipped, of ' + d.totalDays + ' day(s).');
});
"; then
  exit 1
fi
