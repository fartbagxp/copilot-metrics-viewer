#!/usr/bin/env bash
# Shared helpers for the scripts in this directory. Source, don't execute:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Returns 0 only when copilot-metrics-viewer itself answers at $1.
#
# A bare reachability probe (`curl -sf "$HOST/api/health"`) is not enough:
# -f only fails on HTTP >= 400, so an unrelated server holding the same port
# and answering with a 302 to its own login page looks like success. We
# therefore require a 200 whose body carries this app's health payload.
app_is_healthy() {
  local host="$1" response code body
  response=$(curl -s -m 5 -w '\n%{http_code}' "$host/api/health" 2>/dev/null) || return 1
  code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  [ "$code" = "200" ] || return 1
  case "$body" in
    *'"status":"healthy"'*|*'"status": "healthy"'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0 if *something* answers HTTP at $1, whether or not it is our app.
# Used to tell "nothing is running" apart from "the port is taken by someone
# else", which need very different remedies.
host_responds() {
  curl -s -m 5 -o /dev/null "$1/api/health" 2>/dev/null
}

# Prints a diagnosis for a failed health check against $1.
report_unhealthy_host() {
  local host="$1"
  if host_responds "$host"; then
    echo "Error: something is listening at $host, but it is not copilot-metrics-viewer."
    echo "       GET $host/api/health did not return this app's health payload."
    echo ""
    echo "Stop whatever owns that port, or run against a different one, e.g.:"
    echo "  PORT=3001 ./scripts/run_all.sh http://localhost:3001"
  else
    echo "Error: server is not responding at $host"
  fi
}
