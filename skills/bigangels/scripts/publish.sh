#!/usr/bin/env bash
# Publish a file or folder to BigAngels and print the live URL.
#
#   publish.sh <file-or-folder> [--name "Display name"] [--spa] [--new]
#
# Re-publishing the same folder updates the same site (state lives in ~/.bigangels/sites.json).
# Env: BIGANGELS_API (API origin), BIGANGELS_CLIENT (optional override, e.g. cursor/publish-sh).

set -euo pipefail

# Local development: export BIGANGELS_API=http://bigangels.localhost:8787
API="${BIGANGELS_API:-https://api.bigangels.app}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client.sh
source "$_SCRIPT_DIR/client.sh"
_INVOKING="${BASH_SOURCE[0]}"
CLIENT="$(bigangels_client_id "$_INVOKING" publish-sh)"
STATE_DIR="${BIGANGELS_HOME:-$HOME/.bigangels}"
STATE_FILE="$STATE_DIR/sites.json"

die() { echo "error: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required (macOS: brew install jq)"
if command -v shasum >/dev/null; then sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null; then sha256() { sha256sum "$1" | cut -d' ' -f1; }
else die "shasum or sha256sum is required"; fi

TARGET="" NAME="" SPA="" FORCE_NEW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --spa) SPA=1; shift ;;
    --new) FORCE_NEW=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) [[ -z "$TARGET" ]] || die "only one file or folder can be published at a time"; TARGET="$1"; shift ;;
  esac
done
[[ -n "$TARGET" && -e "$TARGET" ]] || die "usage: publish.sh <file-or-folder> [--name NAME] [--spa] [--new]"

if [[ -d "$TARGET" ]]; then
  ROOT="$(cd "$TARGET" && pwd)"
  FILES=()
  while IFS= read -r -d '' f; do FILES+=("${f#./}"); done < <(
    cd "$ROOT" && find . \( -name .git -o -name node_modules -o -name .bigangels \) -prune -o \
      -type f ! -name .DS_Store ! -name '.env' ! -name '.env.*' -print0 | sort -z
  )
else
  ROOT="$(cd "$(dirname "$TARGET")" && pwd)"
  FILES=("$(basename "$TARGET")")
fi
KEY="$ROOT"; [[ -f "$TARGET" ]] && KEY="$ROOT/${FILES[0]}"
[[ ${#FILES[@]} -gt 0 ]] || die "nothing to publish in $TARGET"

content_type() {
  case "$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')" in
    html|htm) echo "text/html; charset=utf-8" ;;   css) echo "text/css; charset=utf-8" ;;
    js|mjs) echo "text/javascript; charset=utf-8" ;; json) echo "application/json; charset=utf-8" ;;
    jsonl) echo "application/jsonl; charset=utf-8" ;;
    md) echo "text/markdown; charset=utf-8" ;;       txt) echo "text/plain; charset=utf-8" ;;
    csv) echo "text/csv; charset=utf-8" ;;           xml) echo "application/xml; charset=utf-8" ;;
    svg) echo "image/svg+xml" ;; png) echo "image/png" ;; jpg|jpeg) echo "image/jpeg" ;;
    gif) echo "image/gif" ;; webp) echo "image/webp" ;; avif) echo "image/avif" ;; ico) echo "image/x-icon" ;;
    pdf) echo "application/pdf" ;; mp4) echo "video/mp4" ;; webm) echo "video/webm" ;; mov) echo "video/quicktime" ;;
    mp3) echo "audio/mpeg" ;; wav) echo "audio/wav" ;; ogg) echo "audio/ogg" ;;
    woff) echo "font/woff" ;; woff2) echo "font/woff2" ;; ttf) echo "font/ttf" ;; otf) echo "font/otf" ;;
    wasm) echo "application/wasm" ;; zip) echo "application/zip" ;;
    *) echo "application/octet-stream" ;;
  esac
}

MANIFEST="$(
  for f in "${FILES[@]}"; do
    printf '%s\t%s\t%s\t%s\n' "$f" "$(wc -c <"$ROOT/$f" | tr -d ' ')" "$(content_type "$f")" "$(sha256 "$ROOT/$f")"
  done | jq -Rn '[inputs | split("\t") | {path: .[0], size: (.[1] | tonumber), contentType: .[2], hash: .[3]}]'
)"

mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
[[ -f "$STATE_FILE" ]] || echo '{}' >"$STATE_FILE"
SAVED="$(jq -c --arg k "$KEY" '.[$k] // empty' "$STATE_FILE")"

# Publishing requires a signed-in account (login.sh saves the key in credentials).
API_KEY="${BIGANGELS_API_KEY:-$(cat "$STATE_DIR/credentials" 2>/dev/null || true)}"
AUTH=()
[[ -n "$API_KEY" ]] && AUTH=(-H "Authorization: Bearer $API_KEY")

LOGIN_SH="$(cd "$(dirname "$0")" && pwd)/login.sh"

is_ci() { [[ -n "${GITHUB_ACTIONS:-}" || "${CI:-}" == "true" ]]; }

can_auto_browser_sign_in() {
  [[ -t 1 ]] && command -v python3 >/dev/null && ! is_ci
}

headless_sign_in_help() {
  echo "error: sign in required before publishing." >&2
  echo "  Run: $LOGIN_SH   (opens the browser; one command)" >&2
  echo "  Headless / SSH: $LOGIN_SH --email you@example.com  then verify with the code" >&2
  echo "  Or paste a key from Settings → API keys into ~/.bigangels/credentials" >&2
  echo "  Status: $LOGIN_SH --status" >&2
}

reload_credentials() {
  API_KEY="${BIGANGELS_API_KEY:-$(cat "$STATE_DIR/credentials" 2>/dev/null || true)}"
  if [[ -n "$API_KEY" ]]; then AUTH=(-H "Authorization: Bearer $API_KEY"); else AUTH=(); fi
}

auto_sign_in_or_die() {
  local reason="$1"
  if can_auto_browser_sign_in; then
    echo "$reason" >&2
    echo "Starting browser sign-in…" >&2
    BIGANGELS_CLIENT="$CLIENT" bash "$LOGIN_SH" || die "sign-in failed — run: $LOGIN_SH"
    reload_credentials
    [[ -n "$API_KEY" ]] || die "sign-in did not save credentials — run: $LOGIN_SH"
    return 0
  fi
  headless_sign_in_help
  exit 1
}

credentials_valid() {
  [[ -n "$API_KEY" ]] || return 1
  local out
  out="$(curl -sS "$API/api/v1/me" -H "Authorization: Bearer $API_KEY" -w $'\n%{http_code}')" || die "could not reach $API"
  [[ "${out##*$'\n'}" == 200 ]]
}

require_sign_in() {
  if credentials_valid; then return 0; fi
  if [[ -z "$API_KEY" ]]; then
    auto_sign_in_or_die "Sign in required before publishing."
  else
    auto_sign_in_or_die "Your saved sign-in is no longer valid."
  fi
  credentials_valid || die "sign-in did not stick — run: $LOGIN_SH"
}
require_sign_in

# call METHOD URL BODY -> sets RESPONSE and STATUS
call() {
  local out
  out="$(curl -sS -X "$1" "$2" -H "content-type: application/json" -H "X-BigAngels-Client: $CLIENT" \
    ${AUTH[@]+"${AUTH[@]}"} --data-binary "$3" -w $'\n%{http_code}')" || die "could not reach $API"
  STATUS="${out##*$'\n'}"; RESPONSE="${out%$'\n'*}"
}

BODY="$(jq -n --argjson files "$MANIFEST" --arg name "$NAME" --arg spa "$SPA" \
  '{files: $files} + (if $name != "" then {displayName: $name} else {} end) + (if $spa != "" then {spaMode: true} else {} end)')"

STATUS=""
if [[ -n "$SAVED" && -z "$FORCE_NEW" ]]; then
  SLUG="$(jq -r .slug <<<"$SAVED")"; CLAIM="$(jq -r .claimToken <<<"$SAVED")"
  CLAIM_URL="$(jq -r '.claimUrl // empty' <<<"$SAVED")"
  call PUT "$API/api/v1/publish/$SLUG" "$(jq --arg t "$CLAIM" '. + {claimToken: $t}' <<<"$BODY")"
  if [[ "$STATUS" == 404 || "$STATUS" == 410 ]]; then
    echo "previous site $SLUG is gone (expired); creating a new one" >&2
    STATUS=""
  fi
fi
if [[ -z "$STATUS" ]]; then
  call POST "$API/api/v1/publish" "$BODY"
  CLAIM="$(jq -r '.claimToken // empty' <<<"$RESPONSE" 2>/dev/null || true)"
  CLAIM_URL="$(jq -r '.claimUrl // empty' <<<"$RESPONSE" 2>/dev/null || true)"
fi
[[ "$STATUS" == 401 ]] && die "sign in required or your saved key is invalid. Run login.sh again."
[[ "$STATUS" =~ ^2 ]] || die "publish failed ($STATUS): $(jq -r '.error // .' <<<"$RESPONSE" 2>/dev/null || echo "$RESPONSE")"

SLUG="$(jq -r .slug <<<"$RESPONSE")"
VERSION="$(jq -r .upload.versionId <<<"$RESPONSE")"
FINALIZE="$(jq -r .upload.finalizeUrl <<<"$RESPONSE")"
TOTAL="$(jq '.upload.uploads | length' <<<"$RESPONSE")"
SKIPPED="$(jq '.upload.skipped | length' <<<"$RESPONSE")"

N=0
while IFS=$'\t' read -r path url ctype; do
  N=$((N + 1))
  printf '\ruploading %d/%d' "$N" "$TOTAL" >&2
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$url" -H "Content-Type: $ctype" --data-binary @"$ROOT/$path")" \
    || die "upload failed for $path"
  [[ "$code" =~ ^2 ]] || die "upload failed for $path ($code)"
done < <(jq -r '.upload.uploads[] | [.path, .url, .headers["Content-Type"]] | @tsv' <<<"$RESPONSE")
[[ "$TOTAL" -gt 0 ]] && echo >&2

call POST "$FINALIZE" "$(jq -n --arg v "$VERSION" '{versionId: $v}')"
[[ "$STATUS" =~ ^2 ]] || die "finalize failed ($STATUS): $(jq -r '.error // .message // .' <<<"$RESPONSE" 2>/dev/null || echo "$RESPONSE")"

LIVE="$(jq -r '.live // empty' <<<"$RESPONSE")"
[[ "$LIVE" == "true" ]] || die "finalize did not mark the site live — do not share a URL yet"
STATE="$(jq -r '.publishStatus.state // empty' <<<"$RESPONSE")"
[[ "$STATE" == "live" ]] || die "finalize response missing publishStatus.state=live"
URL="$(jq -r .siteUrl <<<"$RESPONSE")"
[[ -n "$URL" && "$URL" != "null" ]] || die "finalize succeeded but no siteUrl was returned"

RESP_API="$(jq -r '.apiOrigin // empty' <<<"$RESPONSE")"
if [[ -n "$RESP_API" && "$RESP_API" != "$API" ]]; then
  die "API mismatch: you called $API but finalize returned apiOrigin $RESP_API — set BIGANGELS_API to match the environment you want"
fi
serve_code="$(curl -sS -o /dev/null -w '%{http_code}' "$URL" || true)"
[[ "$serve_code" =~ ^2 ]] || die "site is not reachable at $URL ($serve_code). If BIGANGELS_API points at localhost or an old host, production links will not work."
EXPIRES="$(jq -r '.publishStatus.expiresAt // empty' <<<"$RESPONSE")"
TMP="$(mktemp)"
jq --arg k "$KEY" --arg slug "$SLUG" --arg claim "${CLAIM:-}" --arg claimUrl "${CLAIM_URL:-}" --arg url "$URL" --arg exp "$EXPIRES" \
  '.[$k] = {slug: $slug, claimToken: $claim, claimUrl: $claimUrl, siteUrl: $url, expiresAt: $exp}' "$STATE_FILE" >"$TMP" \
  && mv "$TMP" "$STATE_FILE"
chmod 600 "$STATE_FILE"

echo "published: $URL"
echo "files: $TOTAL uploaded, $SKIPPED unchanged"
if [[ -n "$EXPIRES" ]]; then
  echo "expires: $EXPIRES (anonymous site)"
  [[ -n "${CLAIM_URL:-}" ]] && echo "keep it: $CLAIM_URL"
fi
exit 0
