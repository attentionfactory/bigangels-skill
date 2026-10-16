#!/usr/bin/env bash
# Sign in to BigAngels from the terminal, so published sites are permanent.
#
#   login.sh                  open the browser (default on macOS/Linux with a display)
#   login.sh --browser        same as login.sh with no arguments
#   login.sh --email <email>          email a 6-digit code (headless / SSH fallback)
#   login.sh --email <email> <code>   verify the code and save an API key
#   login.sh <email>          same as --email (legacy)
#   login.sh <email> <code>   verify (legacy)
#   login.sh --status         show who is signed in
#   login.sh --logout         forget the saved key
#
# Env: BIGANGELS_API, BIGANGELS_APP, BIGANGELS_CLIENT, BIGANGELS_HOME (same as publish.sh).
# Client id defaults from skill path (~/.cursor → cursor, ~/.codex → codex, ~/.claude → claude-code).
#
# Exit codes: 0 success (signed in / signed out / --status ok); 1 error or usage;
#   email flow with no code yet exits 0 (code sent — run again with the code).

set -euo pipefail

# Local development: export BIGANGELS_API=http://bigangels.localhost:8787 BIGANGELS_APP=http://localhost:3000
API="${BIGANGELS_API:-https://api.bigangels.app}"
APP="${BIGANGELS_APP:-}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client.sh
source "$_SCRIPT_DIR/client.sh"
_INVOKING="${BASH_SOURCE[0]}"
CLIENT="$(bigangels_client_id "$_INVOKING" login-sh)"
STATE_DIR="${BIGANGELS_HOME:-$HOME/.bigangels}"
CREDENTIALS="$STATE_DIR/credentials"
STATE_FILE="$STATE_DIR/sites.json"
KEY_NAME="${CLIENT%%/*}"

die() { echo "error: $*" >&2; exit 1; }
command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required (macOS: brew install jq)"

app_origin() {
  if [[ -n "$APP" ]]; then printf '%s' "$APP"; return; fi
  case "$API" in
    *localhost*|*127.0.0.1*) printf '%s' "http://localhost:3000" ;;
    *) printf '%s' "https://bigangels.app" ;;
  esac
}

# post PATH BODY [API_KEY] -> sets RESPONSE and STATUS
post() {
  local out auth=()
  [[ -n "${3:-}" ]] && auth=(-H "Authorization: Bearer $3")
  out="$(curl -sS -X POST "$API$1" -H "content-type: application/json" -H "X-BigAngels-Client: $CLIENT" \
    ${auth[@]+"${auth[@]}"} --data-binary "$2" -w $'\n%{http_code}')" || die "could not reach $API"
  STATUS="${out##*$'\n'}"; RESPONSE="${out%$'\n'*}"
}
error_of() { jq -r '.error // empty' <<<"$RESPONSE" 2>/dev/null || echo "$RESPONSE"; }

claim_local_sites() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  local kept=0
  while IFS=$'\t' read -r path token; do
    post /api/v1/claim "$(jq -n --arg t "$token" '{claimToken: $t}')" "$key"
    if [[ "$STATUS" =~ ^2 ]]; then
      kept=$((kept + 1))
      TMP="$(mktemp)"
      jq --arg p "$path" '.[$p].expiresAt = "" | .[$p].claimUrl = ""' "$STATE_FILE" >"$TMP" && mv "$TMP" "$STATE_FILE"
    fi
  done < <(jq -r 'to_entries[] | select(.value.claimToken != "" and .value.expiresAt != "") | [.key, .value.claimToken] | @tsv' "$STATE_FILE")
  chmod 600 "$STATE_FILE"
  [[ $kept -gt 0 ]] && echo "kept $kept earlier site(s) — they no longer expire"
}

save_api_key() {
  local key="$1"
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  (umask 077 && printf '%s' "$key" >"$CREDENTIALS")
  local me
  me="$(curl -sS "$API/api/v1/me" -H "Authorization: Bearer $key" -w $'\n%{http_code}')" || die "could not reach $API"
  [[ "${me##*$'\n'}" == 200 ]] || die "sign-in did not stick — try again"
  echo "signed in as $(jq -r .user.email <<<"${me%$'\n'*}")"
  claim_local_sites "$key"
}

open_browser() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 && return
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 && return
  fi
  echo "open this link in your browser:"
  echo "$url"
}

browser_sign_in() {
  command -v python3 >/dev/null || die "python3 is required for browser sign-in (or use: login.sh --email you@example.com)"
  local state port redirect out_file listener_pid origin auth_url encoded
  state="$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p -c 32)"
  port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  redirect="http://127.0.0.1:${port}/callback"
  out_file="$(mktemp)"
  trap 'rm -f "$out_file"; kill "$listener_pid" 2>/dev/null || true' RETURN

  python3 - "$state" "$out_file" "$port" <<'PY' &
import sys, urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

STATE, OUT, PORT = sys.argv[1:4]

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/callback":
            self.send_error(404)
            return
        q = urllib.parse.parse_qs(parsed.query, strict_parsing=False)
        if q.get("state", [""])[0] != STATE:
            self.send_error(400)
            return
        key = q.get("api_key", [""])[0]
        if not key.startswith("ba_live_"):
            self.send_error(400)
            return
        with open(OUT, "w", encoding="utf-8") as f:
            f.write(key)
        body = b"<!DOCTYPE html><html lang=en><meta charset=utf-8><title>Signed in</title><body><p>Signed in. You can close this tab and return to your terminal.</p></body></html>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self.server.shutdown()

HTTPServer(("127.0.0.1", int(PORT)), Handler).serve_forever()
PY
  listener_pid=$!

  origin="$(app_origin)"
  encoded="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$redirect")"
  auth_url="${origin}/dashboard/cli-auth?state=${state}&redirect_uri=${encoded}&client=${KEY_NAME}"

  echo "Opening your browser to sign in…"
  open_browser "$auth_url"
  echo "Waiting for sign-in (up to 2 minutes). Use login.sh --email for headless SSH."

  local i key
  for i in $(seq 1 120); do
    if [[ -s "$out_file" ]]; then
      key="$(cat "$out_file")"
      kill "$listener_pid" 2>/dev/null || true
      wait "$listener_pid" 2>/dev/null || true
      save_api_key "$key"
      return 0
    fi
    if ! kill -0 "$listener_pid" 2>/dev/null; then
      die "sign-in was interrupted — run login.sh again"
    fi
    sleep 1
  done
  kill "$listener_pid" 2>/dev/null || true
  die "timed out waiting for browser sign-in — run login.sh again"
}

email_sign_in() {
  local email="$1" code="${2:-}"
  if [[ -z "$code" ]]; then
    post /api/v1/auth/request-code "$(jq -n --arg e "$email" '{email: $e}')"
    [[ "$STATUS" =~ ^2 ]] || die "$(error_of)"
    echo "sent a 6-digit code to $email — ask the user for it, then run: login.sh --email $email <code>"
    DEV_CODE="$(jq -r '.devCode // empty' <<<"$RESPONSE")"
    [[ -n "$DEV_CODE" ]] && echo "dev code: $DEV_CODE"
    return 0
  fi

  post /api/v1/auth/verify-code "$(jq -n --arg e "$email" --arg c "$code" --arg k "$KEY_NAME" '{email: $e, code: $c, keyName: $k}')"
  [[ "$STATUS" =~ ^2 ]] || die "$(error_of)"
  save_api_key "$(jq -r .apiKey <<<"$RESPONSE")"
}

case "${1:-}" in
  ""|-h|--help)
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,14p' "$0"; exit 0
    fi
    browser_sign_in
    exit 0
    ;;
  --browser) browser_sign_in; exit 0 ;;
  --status)
    [[ -f "$CREDENTIALS" ]] || { echo "not signed in"; exit 1; }
    out="$(curl -sS "$API/api/v1/me" -H "Authorization: Bearer $(cat "$CREDENTIALS")" -w $'\n%{http_code}')" || die "could not reach $API"
    [[ "${out##*$'\n'}" == 200 ]] || { echo "saved sign-in is no longer valid; sign in again"; exit 1; }
    jq -r '"signed in as \(.user.email) · \(.usage.sites) sites"' <<<"${out%$'\n'*}"
    exit 0
    ;;
  --logout) rm -f "$CREDENTIALS"; echo "signed out on this computer"; exit 0 ;;
  --email)
    shift
    [[ $# -ge 1 ]] || die "usage: login.sh --email you@example.com [code]"
    email_sign_in "$1" "${2:-}"
    exit 0
    ;;
esac

[[ "$1" == *@* ]] || die "usage: login.sh [--browser | --email <email> [code] | --status | --logout]"
email_sign_in "$1" "${2:-}"
