#!/usr/bin/env bash
# Sign in to BigAngels from the terminal, so published sites are permanent.
#
#   login.sh <email>          email a 6-digit code
#   login.sh <email> <code>   verify it, save an API key, and keep every site published from this computer
#   login.sh --status         show who is signed in
#   login.sh --logout         forget the saved key
#
# Env: BIGANGELS_API, BIGANGELS_CLIENT, BIGANGELS_HOME (same as publish.sh).

set -euo pipefail

# Local development: export BIGANGELS_API=http://bigangels.localhost:8787
API="${BIGANGELS_API:-https://api.bigangels.app}"
CLIENT="${BIGANGELS_CLIENT:-claude-code/login-sh}"
STATE_DIR="${BIGANGELS_HOME:-$HOME/.bigangels}"
CREDENTIALS="$STATE_DIR/credentials"
STATE_FILE="$STATE_DIR/sites.json"

die() { echo "error: $*" >&2; exit 1; }
command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required (macOS: brew install jq)"

# post PATH BODY [API_KEY] -> sets RESPONSE and STATUS
post() {
  local out auth=()
  [[ -n "${3:-}" ]] && auth=(-H "Authorization: Bearer $3")
  out="$(curl -sS -X POST "$API$1" -H "content-type: application/json" -H "X-BigAngels-Client: $CLIENT" \
    ${auth[@]+"${auth[@]}"} --data-binary "$2" -w $'\n%{http_code}')" || die "could not reach $API"
  STATUS="${out##*$'\n'}"; RESPONSE="${out%$'\n'*}"
}
error_of() { jq -r '.error // empty' <<<"$RESPONSE" 2>/dev/null || echo "$RESPONSE"; }

case "${1:-}" in
  ""|-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  --status)
    [[ -f "$CREDENTIALS" ]] || { echo "not signed in"; exit 0; }
    out="$(curl -sS "$API/api/v1/me" -H "Authorization: Bearer $(cat "$CREDENTIALS")" -w $'\n%{http_code}')" || die "could not reach $API"
    [[ "${out##*$'\n'}" == 200 ]] || { echo "saved sign-in is no longer valid; sign in again"; exit 0; }
    jq -r '"signed in as \(.user.email) · \(.usage.sites) sites"' <<<"${out%$'\n'*}"
    exit 0 ;;
  --logout) rm -f "$CREDENTIALS"; echo "signed out on this computer"; exit 0 ;;
esac

EMAIL="$1"
CODE="${2:-}"

if [[ -z "$CODE" ]]; then
  post /api/v1/auth/request-code "$(jq -n --arg e "$EMAIL" '{email: $e}')"
  [[ "$STATUS" =~ ^2 ]] || die "$(error_of)"
  echo "sent a 6-digit code to $EMAIL — ask the user for it, then run: login.sh $EMAIL <code>"
  DEV_CODE="$(jq -r '.devCode // empty' <<<"$RESPONSE")"
  [[ -n "$DEV_CODE" ]] && echo "dev code: $DEV_CODE"
  exit 0
fi

post /api/v1/auth/verify-code "$(jq -n --arg e "$EMAIL" --arg c "$CODE" --arg k "${CLIENT%%/*}" '{email: $e, code: $c, keyName: $k}')"
[[ "$STATUS" =~ ^2 ]] || die "$(error_of)"
KEY="$(jq -r .apiKey <<<"$RESPONSE")"

mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
(umask 077 && printf '%s' "$KEY" >"$CREDENTIALS")
echo "signed in as $(jq -r .user.email <<<"$RESPONSE")"

# Sites published anonymously from this computer become permanent and show up in the dashboard.
[[ -f "$STATE_FILE" ]] || exit 0
kept=0
while IFS=$'\t' read -r path token; do
  post /api/v1/claim "$(jq -n --arg t "$token" '{claimToken: $t}')" "$KEY"
  if [[ "$STATUS" =~ ^2 ]]; then
    kept=$((kept + 1))
    TMP="$(mktemp)"
    jq --arg p "$path" '.[$p].expiresAt = "" | .[$p].claimUrl = ""' "$STATE_FILE" >"$TMP" && mv "$TMP" "$STATE_FILE"
  fi
done < <(jq -r 'to_entries[] | select(.value.claimToken != "" and .value.expiresAt != "") | [.key, .value.claimToken] | @tsv' "$STATE_FILE")
chmod 600 "$STATE_FILE"
[[ $kept -gt 0 ]] && echo "kept $kept earlier site(s) — they no longer expire"
exit 0
