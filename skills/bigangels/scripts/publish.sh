#!/usr/bin/env bash
# Publish a file or folder to BigAngels and print the live URL.
# A folder's .bigangels/data.json (Site Data) and .bigangels/proxy.json (proxy routes) are published too;
# problems print as warning: lines.
#
#   publish.sh <file-or-folder> [--name "Display name"] [--folder "Folder"] [--spa] [--[no-]cross-origin-isolation] [--new] [--anonymous]
#
# Re-publishing the same folder updates the same site (state lives in ~/.bigangels/sites.json).
# --cross-origin-isolation turns on COOP/COEP so SharedArrayBuffer works (threaded wasm, games);
# it stays on for later publishes until --no-cross-origin-isolation turns it off.
# --source DIR saves private source; --no-source opts out. --site SLUG --base-version ID updates a known site.
# --overwrite disables version conflict protection.
# --anonymous ignores saved/environment credentials and remembers previews separately.
# --folder files the site in a folder (created if new); --no-folder takes it out. Needs an account.
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
DEVICE="$(bigangels_publish_device_id "$STATE_DIR")"
DEVICE_HDR=(-H "X-BigAngels-Publish-Device: $DEVICE")

die() { echo "error: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required (macOS: brew install jq)"
if command -v shasum >/dev/null; then sha256() { LC_ALL=C shasum -a 256 "$1" | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null; then sha256() { LC_ALL=C sha256sum "$1" | cut -d' ' -f1; }
else die "shasum or sha256sum is required"; fi

TARGET="" NAME="" SPA="" ISOLATION="" FORCE_NEW="" ANONYMOUS="" FOLDER="" NO_FOLDER="" SOURCE="" NO_SOURCE="" OVERWRITE="" SITE="" BASE_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:-}"; [[ -n "$SITE" ]] || die "--site needs a slug"; shift 2 ;;
    --base-version) BASE_VERSION="${2:-}"; [[ -n "$BASE_VERSION" ]] || die "--base-version needs a version ID"; shift 2 ;;
    --source) SOURCE="${2:-}"; [[ -n "$SOURCE" ]] || die "--source needs a directory"; shift 2 ;;
    --no-source) NO_SOURCE=1; shift ;;
    --overwrite) OVERWRITE=1; shift ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --spa) SPA=1; shift ;;
    --folder) FOLDER="${2:-}"; [[ -n "$FOLDER" ]] || die "--folder needs a folder name"; shift 2 ;;
    --no-folder) NO_FOLDER=1; shift ;;
    --new) FORCE_NEW=1; shift ;;
    --anonymous) ANONYMOUS=1; shift ;;
    --cross-origin-isolation) ISOLATION=on; shift ;;
    --no-cross-origin-isolation) ISOLATION=off; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) [[ -z "$TARGET" ]] || die "only one file or folder can be published at a time"; TARGET="$1"; shift ;;
  esac
done
[[ -n "$TARGET" && -e "$TARGET" ]] || die "usage: publish.sh <file-or-folder> [--name NAME] [--folder FOLDER] [--spa] [--[no-]cross-origin-isolation] [--new] [--anonymous]"
[[ -n "$ANONYMOUS" ]] && STATE_FILE="$STATE_DIR/anonymous-sites.json"

if [[ -d "$TARGET" ]]; then
  ROOT="$(cd "$TARGET" && pwd)"
  FILES=()
  while IFS= read -r -d '' f; do FILES+=("${f#./}"); done < <(
    cd "$ROOT" && find . \( -name .git -o -name node_modules -o -name .bigangels \) -prune -o \
      -type f ! -name .DS_Store ! -name '.env' ! -name '.env.*' -print0 | sort -z
  )
  # .bigangels/ is local state, except the Site Data and proxy route manifests at the site root.
  if [[ -f "$ROOT/.bigangels/data.json" ]]; then FILES+=(".bigangels/data.json"); fi
  if [[ -f "$ROOT/.bigangels/proxy.json" ]]; then FILES+=(".bigangels/proxy.json"); fi
else
  ROOT="$(cd "$(dirname "$TARGET")" && pwd)"
  FILES=("$(basename "$TARGET")")
fi
KEY="$ROOT"; [[ -f "$TARGET" ]] && KEY="$ROOT/${FILES[0]}"
[[ ${#FILES[@]} -gt 0 ]] || die "nothing to publish in $TARGET"

# Source is private version content, never part of the served build. Only infer a project
# from a conventional build directory; do not recursively upload an arbitrary parent.
[[ -z "$SOURCE" || -z "$NO_SOURCE" ]] || die "--source and --no-source cannot be combined"
if [[ -z "$SOURCE" && -z "$NO_SOURCE" && -d "$TARGET" ]]; then
  case "$(basename "$ROOT")" in
    dist|out|build) [[ -f "$(dirname "$ROOT")/package.json" ]] && SOURCE="$(dirname "$ROOT")" ;;
  esac
fi
SOURCE_ROOT=""
SOURCE_FILES=()
if [[ -n "$SOURCE" ]]; then
  [[ -d "$SOURCE" ]] || die "source directory not found: $SOURCE"
  echo "warning: saving project source privately; secret scanning is best effort, review your source before publishing" >&2
  SOURCE_ROOT="$(cd "$SOURCE" && pwd)"
  [[ "$SOURCE_ROOT" != "$ROOT" ]] || die "source and build directories must be different"
  SOURCE_EXCLUDE=""
  case "$ROOT/" in "$SOURCE_ROOT/"*) SOURCE_EXCLUDE="./${ROOT#"$SOURCE_ROOT"/}" ;; esac
  while IFS= read -r -d '' f; do
    f="${f#./}"
    # Never traverse the output, local state, dependencies, or common secret files.
    [[ "$SOURCE_ROOT/$f" == "$ROOT/"* ]] && continue
    case "$(basename "$f" | tr '[:upper:]' '[:lower:]')" in
      .env*|.npmrc|.netrc|.pypirc|id_rsa|id_ed25519|*.pem|*.key|*.p12|*.pfx|*.keystore|*credentials*|*secret*) echo "warning: excluded sensitive source path $f" >&2; continue ;;
    esac
    # Conservative common credential patterns. This is not a complete secret scanner.
    if LC_ALL=C grep -aqE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|(sk_live_|sk-proj-|ghp_|github_pat_)[A-Za-z0-9_-]{16,}' "$SOURCE_ROOT/$f"; then
      echo "warning: excluded possible secret in source file $f" >&2; continue
    fi
    SOURCE_FILES+=("$f")
  done < <(cd "$SOURCE_ROOT" && find . \( -path "${SOURCE_EXCLUDE:-./.bigangels-no-build}" -o -name .git -o -name node_modules -o -name .bigangels -o -name .next -o -name .turbo -o -name .venv -o -name .aws -o -name .ssh -o -iname "*secret*" -o -iname "*credentials*" -o -iname ".env*" \) -prune -o -type f ! -name .DS_Store -print0 | sort -z)
fi

# Keep in sync with apps/edge/src/lib/files.ts. Files are uploaded byte for byte and never
# recompressed: Build.wasm.br is sent as application/wasm and served with Content-Encoding: br.
content_type() {
  local name ext
  name="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    *.wasm.br|*.wasm.gz|*.js.br|*.js.gz|*.mjs.br|*.mjs.gz|*.cjs.br|*.cjs.gz|*.json.br|*.json.gz|*.map.br|*.map.gz|\
    *.data.br|*.data.gz|*.pck.br|*.pck.gz|*.mem.br|*.mem.gz|*.bin.br|*.bin.gz|*.glb.br|*.glb.gz|*.gltf.br|*.gltf.gz|\
    *.css.br|*.css.gz|*.svg.br|*.svg.gz|*.txt.br|*.txt.gz|*.xml.br|*.xml.gz|\
    *.wat.br|*.wat.gz)
      name="${name%.*}" ;;
  esac
  ext="${name##*.}"
  case "$ext" in
    html|htm) echo "text/html; charset=utf-8" ;;   css) echo "text/css; charset=utf-8" ;;
    js|mjs|cjs) echo "text/javascript; charset=utf-8" ;;
    json|map) echo "application/json; charset=utf-8" ;;
    jsonl) echo "application/jsonl; charset=utf-8" ;;
    webmanifest) echo "application/manifest+json; charset=utf-8" ;;
    md) echo "text/markdown; charset=utf-8" ;;       txt|wat) echo "text/plain; charset=utf-8" ;;
    csv) echo "text/csv; charset=utf-8" ;;           tsv) echo "text/tab-separated-values; charset=utf-8" ;;
    xml) echo "application/xml; charset=utf-8" ;;    yaml|yml) echo "text/yaml; charset=utf-8" ;;
    py) echo "text/x-python; charset=utf-8" ;;
    svg) echo "image/svg+xml" ;; png) echo "image/png" ;; apng) echo "image/apng" ;; jpg|jpeg) echo "image/jpeg" ;;
    gif) echo "image/gif" ;; webp) echo "image/webp" ;; avif) echo "image/avif" ;; jxl) echo "image/jxl" ;;
    bmp) echo "image/bmp" ;; tif|tiff) echo "image/tiff" ;; ico) echo "image/x-icon" ;;
    ktx) echo "image/ktx" ;; ktx2) echo "image/ktx2" ;; dds) echo "image/vnd-ms.dds" ;; hdr) echo "image/vnd.radiance" ;;
    pdf) echo "application/pdf" ;;
    mp4|m4v) echo "video/mp4" ;; webm) echo "video/webm" ;; ogv) echo "video/ogg" ;; mov) echo "video/quicktime" ;;
    m3u8) echo "application/vnd.apple.mpegurl" ;;
    mp3) echo "audio/mpeg" ;; m4a) echo "audio/mp4" ;; aac) echo "audio/aac" ;; wav) echo "audio/wav" ;;
    ogg|oga|opus) echo "audio/ogg" ;; weba) echo "audio/webm" ;; flac) echo "audio/flac" ;; mid|midi) echo "audio/midi" ;;
    woff) echo "font/woff" ;; woff2) echo "font/woff2" ;; ttf) echo "font/ttf" ;; otf) echo "font/otf" ;;
    wasm) echo "application/wasm" ;;
    glb) echo "model/gltf-binary" ;; gltf) echo "model/gltf+json" ;;
    obj) echo "model/obj" ;; mtl) echo "model/mtl" ;; stl) echo "model/stl" ;; usdz) echo "model/vnd.usdz+zip" ;;
    zip|whl) echo "application/zip" ;; tar) echo "application/x-tar" ;; gz|tgz) echo "application/gzip" ;;
    br) echo "application/x-brotli" ;; zst) echo "application/zstd" ;;
    *) echo "application/octet-stream" ;;  # .data .pck .unityweb .bin .basis .mem
  esac
}

MANIFEST="$(
  { for f in "${FILES[@]}"; do
    hash="$(sha256 "$ROOT/$f")" || exit 1
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || exit 1
    printf '%s\t%s\t%s\t%s\n' "$f" "$(wc -c <"$ROOT/$f" | tr -d ' ')" "$(content_type "$f")" "$hash"
  done
  for f in ${SOURCE_FILES[@]+"${SOURCE_FILES[@]}"}; do
    hash="$(sha256 "$SOURCE_ROOT/$f")" || exit 1
    printf '%s\t%s\t%s\t%s\n' ".bigangels/source/$f" "$(wc -c <"$SOURCE_ROOT/$f" | tr -d ' ')" "$(content_type "$f")" "$hash"
  done; } | jq -Rn '[inputs | split("\t") | {path: .[0], size: (.[1] | tonumber), contentType: .[2], hash: .[3]}]'
)"

mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
[[ -f "$STATE_FILE" ]] || echo '{}' >"$STATE_FILE"
SAVED="$(jq -c --arg k "$KEY" '.[$k] // empty' "$STATE_FILE")"

# With no key, publish a public six-hour preview. Explicit anonymous mode never reads credentials.
API_KEY=""
if [[ -z "$ANONYMOUS" ]]; then
  API_KEY="${BIGANGELS_API_KEY:-$(cat "$STATE_DIR/credentials" 2>/dev/null || true)}"
fi
AUTH=()
[[ -n "$API_KEY" ]] && AUTH=(-H "Authorization: Bearer $API_KEY")

credentials_valid() {
  [[ -n "$API_KEY" ]] || return 1
  local out
  out="$(curl -sS "$API/api/v1/me" -H "Authorization: Bearer $API_KEY" -w $'\n%{http_code}')" || die "could not reach $API"
  case "${out##*$'\n'}" in
    200) return 0 ;;
    401) return 1 ;;
    *) die "could not check sign-in; retry without replacing credentials" ;;
  esac
}

maybe_sign_in() {
  if credentials_valid; then return 0; fi
  if [[ -n "$API_KEY" ]]; then
    echo "saved sign-in is no longer valid — publishing without an account (offline after 6 hours)" >&2
    API_KEY=""
    AUTH=()
  fi
  return 0
}
maybe_sign_in

# call METHOD URL BODY -> sets RESPONSE and STATUS
call() {
  local out
  out="$(curl -sS -X "$1" "$2" -H "content-type: application/json" -H "X-BigAngels-Client: $CLIENT" \
    "${DEVICE_HDR[@]}" ${AUTH[@]+"${AUTH[@]}"} --data-binary "$3" -w $'\n%{http_code}')" || die "could not reach $API"
  STATUS="${out##*$'\n'}"; RESPONSE="${out%$'\n'*}"
}

BODY="$(jq -n --argjson files "$MANIFEST" --arg name "$NAME" --arg spa "$SPA" --arg iso "$ISOLATION" \
  --arg folder "$FOLDER" --arg nofolder "$NO_FOLDER" \
  '{files: $files} + (if $name != "" then {displayName: $name} else {} end) + (if $spa != "" then {spaMode: true} else {} end)
   + (if $iso == "" then {} else {crossOriginIsolation: ($iso == "on")} end)
   + (if $folder != "" then {folder: $folder} elif $nofolder != "" then {folder: null} else {} end)')"

STATUS=""
if [[ -n "$SITE" ]]; then
  [[ "$SITE" =~ ^[a-z0-9-]+$ ]] || die "--site must be a site slug"
  [[ -n "$API_KEY" ]] || die "--site requires an account key"
  [[ -z "$FORCE_NEW" ]] || die "--site and --new cannot be combined"
  if [[ -z "$BASE_VERSION" && -z "$OVERWRITE" ]]; then die "--site requires --base-version from the version you read, or --overwrite"; fi
  SAVED="$(jq -n --arg slug "$SITE" --arg version "$BASE_VERSION" '{slug:$slug, versionId:$version, claimToken:""}')"
fi
if [[ -n "$SAVED" && -z "$FORCE_NEW" ]]; then
  SLUG="$(jq -r .slug <<<"$SAVED")"; CLAIM="$(jq -r .claimToken <<<"$SAVED")"
  CLAIM_URL="$(jq -r '.claimUrl // empty' <<<"$SAVED")"
  BASE="$(jq -r '.versionId // empty' <<<"$SAVED")"
  UPDATE_BODY="$(jq --arg t "$CLAIM" --arg base "$BASE" --arg overwrite "$OVERWRITE" '. + {claimToken: $t} + (if $base != "" and $overwrite == "" then {baseVersionId: $base} else {} end)' <<<"$BODY")"
  call PUT "$API/api/v1/publish/$SLUG" "$UPDATE_BODY"
  if [[ "$STATUS" == 404 || "$STATUS" == 410 ]]; then
    [[ -z "$SITE" ]] || die "site $SLUG not found or expired"
    echo "previous site $SLUG is gone (expired); creating a new one" >&2
    STATUS=""
  elif [[ "$STATUS" == 401 && -n "$ANONYMOUS" ]]; then
    echo "previous preview is now account-owned; creating a new anonymous preview" >&2
    STATUS=""
  fi
fi
if [[ -z "$STATUS" ]]; then
  call POST "$API/api/v1/publish" "$BODY"
  CLAIM="$(jq -r '.claimToken // empty' <<<"$RESPONSE" 2>/dev/null || true)"
  CLAIM_URL="$(jq -r '.claimUrl // empty' <<<"$RESPONSE" 2>/dev/null || true)"
fi
[[ "$STATUS" == 401 ]] && die "authentication failed. Use --anonymous for a new public 6-hour preview, or sign in with login.sh to update an account-owned site."
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
  local_file="$ROOT/$path"
  if [[ "$path" == .bigangels/source/* && -n "$SOURCE_ROOT" ]]; then local_file="$SOURCE_ROOT/${path#.bigangels/source/}"; fi
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$url" -H "Content-Type: $ctype" --data-binary @"$local_file")" \
    || die "upload failed for $path"
  [[ "$code" =~ ^2 ]] || die "upload failed for $path ($code)"
done < <(jq -r '.upload.uploads[] | [.path, .url, .headers["Content-Type"]] | @tsv' <<<"$RESPONSE")
[[ "$TOTAL" -gt 0 ]] && echo >&2

FINALIZE_BODY="$(jq -n --arg v "$VERSION" --arg t "${CLAIM:-}" '{versionId: $v} + (if $t != "" then {claimToken: $t} else {} end)')"
call POST "$FINALIZE" "$FINALIZE_BODY"
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
EXPIRES="$(jq -r '.publishStatus.expiresAt // empty' <<<"$RESPONSE")"
TMP="$(mktemp)"
jq --arg k "$KEY" --arg slug "$SLUG" --arg claim "${CLAIM:-}" --arg claimUrl "${CLAIM_URL:-}" --arg url "$URL" --arg exp "$EXPIRES" --arg version "$VERSION" \
  '.[$k] = {slug: $slug, claimToken: $claim, claimUrl: $claimUrl, siteUrl: $url, expiresAt: $exp, versionId: $version}' "$STATE_FILE" >"$TMP" \
  && mv "$TMP" "$STATE_FILE"
chmod 600 "$STATE_FILE"

serve_body="$(curl -sS -w $'\n%{http_code}' "$URL" || true)"
serve_code="${serve_body##*$'\n'}"
PROTECTED=""
INVITE_ONLY=""
# A password-protected or invite-only site answers 401 until a visitor gets in. That still means it's live.
serve_gate="$(jq -r '.code // empty' <<<"${serve_body%$'\n'*}" 2>/dev/null || true)"
if [[ "$serve_code" == 401 && "$serve_gate" == password_required ]]; then
  PROTECTED=1
elif [[ "$serve_code" == 401 && "$serve_gate" == access_required ]]; then
  INVITE_ONLY=1
elif ! [[ "$serve_code" =~ ^2 ]]; then
  die "site is not reachable at $URL ($serve_code). If BIGANGELS_API points at localhost or an old host, production links will not work."
fi

echo "published: $URL"
echo "files: $TOTAL uploaded, $SKIPPED unchanged"
if [[ -n "$SOURCE_ROOT" ]]; then echo "source: saved privately (secret scanning is best effort; review exclusions)"; fi
VANITY="$(jq -r '.vanityUrl // empty' <<<"$RESPONSE")"
if [[ -n "$VANITY" ]]; then echo "also at: $VANITY"; fi
FOLDER_NAME="$(jq -r '.folder.name // empty' <<<"$RESPONSE")"
if [[ -n "$FOLDER_NAME" ]]; then echo "folder: $FOLDER_NAME"; fi
if [[ -n "$PROTECTED" ]]; then echo "password: on (visitors enter the site password first; it was not changed)"; fi
if [[ -n "$INVITE_ONLY" ]]; then echo "access: specific people (visitors confirm an invited email first; the list was not changed)"; fi
SITE_DATA="$(jq -r 'if .siteData then (if .siteData.enabled then "on (" + (.siteData.collections | join(", ")) + ")" else "off" end) else empty end' <<<"$RESPONSE")"
if [[ -n "$SITE_DATA" ]]; then echo "site data: $SITE_DATA"; fi
# Proxy routes (.bigangels/proxy.json). Keys stay on the server as variables; see SKILL.md.
PROXY="$(jq -r 'if .proxy then (if .proxy.enabled then "on (" + (.proxy.routes | join(", ")) + ")" else "off" end) else empty end' <<<"$RESPONSE")"
if [[ -n "$PROXY" ]]; then echo "proxy routes: $PROXY"; fi
while IFS= read -r warning; do
  if [[ -n "$warning" ]]; then echo "warning: $warning"; fi
done < <(jq -r '.warnings[]? // empty' <<<"$RESPONSE")
if [[ -n "$EXPIRES" ]]; then
  echo "offline in: 6 hours; claim within 7 days to bring it back (expires: $EXPIRES)"
  [[ -n "${CLAIM_URL:-}" ]] && echo "keep it: $CLAIM_URL"
  echo "tip: sign in with login.sh and open keep it: — otherwise this site goes offline, then is deleted after 7 days"
fi
exit 0
