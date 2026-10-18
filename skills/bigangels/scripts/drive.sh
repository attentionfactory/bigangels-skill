#!/usr/bin/env bash
# Keep private files in a BigAngels Drive: notes, memory, plans, context and assets that are not a website.
#
#   drive.sh drives                                   list your Drives
#   drive.sh default                                  show the default Drive ("My Drive")
#   drive.sh create "Name" [--description TEXT] [--default]
#   drive.sh ls [folder] [-r]                         files and folders (-r: every file below)
#   drive.sh put <local-file> [path] [--if-match ETAG] [--create-only]
#   drive.sh cat <path>                               print a file
#   drive.sh get <path> [local-file]                  download a file
#   drive.sh rm <path> [-r] [--if-match ETAG]         delete a file (-r: a whole folder)
#   drive.sh mv <from> <to> [--if-match ETAG]         move or rename (folders end in /)
#   drive.sh import <local-folder> [folder]           upload a folder; unchanged files are skipped
#   drive.sh export <folder> <local-folder>           download a folder
#   drive.sh link <path>                              a download link that works for 15 minutes
#   drive.sh share [--perms read|write] [--prefix folder/] [--ttl 7d] [--manage] [--label TEXT]
#   drive.sh tokens                                   list share tokens
#   drive.sh revoke <dtok_…>                          revoke a token (and every token made from it)
#   drive.sh publish [folder] [--version dv_…] [--slug SLUG] [--spa]   publish a Drive folder as a site
#   drive.sh versions                                 recent changes
#
# Every command takes --drive <id or name> (default: the default Drive).
# Credentials: BIGANGELS_DRIVE_TOKEN (a drv_live_… token someone shared with you), else
# BIGANGELS_API_KEY, else ~/.bigangels/credentials from login.sh.
# Env: BIGANGELS_API (API origin), BIGANGELS_CLIENT (optional override).

set -euo pipefail

API="${BIGANGELS_API:-https://api.bigangels.app}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=client.sh
source "$_SCRIPT_DIR/client.sh"
CLIENT="$(bigangels_client_id "${BASH_SOURCE[0]}" drive-sh)"
STATE_DIR="${BIGANGELS_HOME:-$HOME/.bigangels}"
INLINE_MAX=$((1024 * 1024))

die() { echo "error: $*" >&2; exit 1; }
command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required (macOS: brew install jq)"
if command -v shasum >/dev/null; then sha256() { LC_ALL=C shasum -a 256 "$1" | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null; then sha256() { LC_ALL=C sha256sum "$1" | cut -d' ' -f1; }
else die "shasum or sha256sum is required"; fi

TOKEN="${BIGANGELS_DRIVE_TOKEN:-${BIGANGELS_API_KEY:-$(cat "$STATE_DIR/credentials" 2>/dev/null || true)}}"
[[ -n "$TOKEN" ]] || die "not signed in. Run login.sh first, or set BIGANGELS_DRIVE_TOKEN to a token someone shared with you."
AUTH=(-H "Authorization: Bearer $TOKEN" -H "X-BigAngels-Client: $CLIENT")

[[ $# -gt 0 ]] || { sed -n '2,24p' "$0"; exit 1; }
CMD="$1"; shift
DRIVE="default" IF_MATCH="" CREATE_ONLY="" RECURSIVE="" DESCRIPTION="" MAKE_DEFAULT=""
PERMS="read" PREFIX="" TTL="" MANAGE="" LABEL="" VERSION="" SLUG="" SPA=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --drive) DRIVE="${2:?--drive needs a value}"; shift 2 ;;
    --if-match) IF_MATCH="${2:?--if-match needs an etag}"; shift 2 ;;
    --create-only) CREATE_ONLY=1; shift ;;
    -r|--recursive) RECURSIVE=1; shift ;;
    --description) DESCRIPTION="${2:-}"; shift 2 ;;
    --default) MAKE_DEFAULT=1; shift ;;
    --perms) PERMS="${2:?--perms needs read or write}"; shift 2 ;;
    --prefix) PREFIX="${2:?--prefix needs a folder}"; shift 2 ;;
    --ttl) TTL="${2:?--ttl needs a duration like 7d}"; shift 2 ;;
    --manage) MANAGE=1; shift ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --version) VERSION="${2:?--version needs a dv_ id}"; shift 2 ;;
    --slug) SLUG="${2:?--slug needs a site name}"; shift 2 ;;
    --spa) SPA=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
arg() { echo "${ARGS[$1]:-}"; }
TMPS=()
cleanup() { [[ ${#TMPS[@]} -eq 0 ]] || rm -f "${TMPS[@]}"; }
trap cleanup EXIT

# call METHOD PATH [curl args…] -> sets BODY and STATUS. PATH is under /api/v1.
call() {
  local method="$1" path="$2" out; shift 2
  out="$(curl -sS -X "$method" "$API/api/v1$path" "${AUTH[@]}" "$@" -w $'\n%{http_code}')" || die "could not reach $API"
  STATUS="${out##*$'\n'}"; BODY="${out%$'\n'*}"
}
json_call() { call "$1" "$2" -H 'content-type: application/json' --data-binary "$3"; }
ok_or_die() { # what
  [[ "$STATUS" =~ ^2 ]] && return 0
  local code msg
  code="$(jq -r '.code // empty' <<<"$BODY" 2>/dev/null || true)"
  msg="$(jq -r '.error // empty' <<<"$BODY" 2>/dev/null || true)"
  if [[ "$STATUS" == 412 ]]; then
    die "$1: ${msg:-precondition failed} ($code). Someone changed it first: read it again, then retry with the new --if-match."
  fi
  die "$1 failed ($STATUS${code:+ $code}): ${msg:-$BODY}"
}
enc_path() { jq -rn --arg p "$1" '$p | split("/") | map(@uri) | join("/")'; }
strip_slash() { local p="${1#./}"; p="${p#/}"; echo "$p"; }

# Resolve --drive: "default", a drv_… id, or a Drive's name.
DRIVE_ID=""
drive_id() {
  if [[ -n "$DRIVE_ID" ]]; then echo "$DRIVE_ID"; return; fi
  if [[ "$DRIVE" == default || "$DRIVE" == drv_* ]]; then DRIVE_ID="$DRIVE"
  else
    call GET /drives; ok_or_die "listing Drives"
    DRIVE_ID="$(jq -r --arg n "$DRIVE" '[.drives[] | select(.name == $n)][0].id // empty' <<<"$BODY")"
    [[ -n "$DRIVE_ID" ]] || die "no Drive named \"$DRIVE\". See: drive.sh drives"
  fi
  echo "$DRIVE_ID"
}

# list_all FOLDER -> every file below FOLDER as TSV: path, size, sha256, etag
list_all() {
  local id cursor="" q
  id="$(drive_id)"
  while :; do
    q="prefix=$(jq -rn --arg p "$1" '$p|@uri')&limit=1000"
    [[ -n "$cursor" ]] && q="$q&cursor=$(jq -rn --arg c "$cursor" '$c|@uri')"
    call GET "/drives/$id/files?$q"; ok_or_die "listing files"
    jq -r '.files[] | [.path, .size, .sha256, .etag] | @tsv' <<<"$BODY"
    cursor="$(jq -r '.nextCursor // empty' <<<"$BODY")"
    [[ -n "$cursor" ]] || break
  done
}

# stage LOCAL PATH [IF_MATCH] [CREATE_ONLY] -> prints the uploadId once the bytes are uploaded
stage() {
  local file="$1" path="$2" size hash req url
  size="$(wc -c <"$file" | tr -d ' ')"; hash="$(sha256 "$file")"
  req="$(jq -nc --arg p "$path" --argjson s "$size" --arg h "$hash" --arg m "${3:-}" --arg c "${4:-}" \
    '{path: $p, size: $s, sha256: $h} + (if $m != "" then {ifMatch: $m} else {} end) + (if $c != "" then {ifNoneMatch: "*"} else {} end)')"
  json_call POST "/drives/$(drive_id)/files/uploads" "$req"; ok_or_die "preparing $path"
  if [[ "$(jq -r .uploadRequired <<<"$BODY")" == true ]]; then
    url="$(jq -r .url <<<"$BODY")"
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$url" -H "Content-Type: $(jq -r '.headers["Content-Type"]' <<<"$BODY")" \
      --data-binary @"$file")" || die "upload failed for $path"
    [[ "$code" =~ ^2 ]] || die "upload failed for $path ($code)"
  fi
  jq -r .uploadId <<<"$BODY"
}

# Resolve the Drive once, so a Drive given by name is looked up a single time.
case "$CMD" in drives|create|-h|--help) ;; *) DRIVE_ID="$(drive_id)" ;; esac

print_written() { jq -r '.files[] | "saved: \(.path)  (\(.size) bytes, etag \(.etag))"' <<<"$BODY"; echo "version: $(jq -r .versionId <<<"$BODY")"; }

case "$CMD" in
  drives)
    call GET /drives; ok_or_die "listing Drives"
    jq -r '.drives[] | "\(.id)\t\(.name)\(if .isDefault then " (default)" else "" end)\t\(.fileCount) files\t\(.totalBytes) bytes"' <<<"$BODY"
    jq -r 'if .usage then "storage: \(.usage.usedBytes) of \(.usage.storageBytes) bytes used (\(.usage.plan) plan)" else empty end' <<<"$BODY"
    ;;
  default)
    call GET "/drives/$(drive_id)"; ok_or_die "reading the Drive"
    jq -r '.drive | "id: \(.id)\nname: \(.name)\nfiles: \(.fileCount)\nbytes: \(.totalBytes)\nversion: \(.headVersionId // "none yet")\ndashboard: \(.dashboardUrl)"' <<<"$BODY"
    ;;
  create)
    name="$(arg 0)"; [[ -n "$name" ]] || die "usage: drive.sh create \"Name\""
    json_call POST /drives "$(jq -nc --arg n "$name" --arg d "$DESCRIPTION" --arg def "$MAKE_DEFAULT" \
      '{name: $n} + (if $d != "" then {description: $d} else {} end) + (if $def != "" then {isDefault: true} else {} end)')"
    ok_or_die "creating the Drive"
    jq -r '.drive | "created: \(.id)  \(.name)"' <<<"$BODY"
    ;;
  ls)
    folder="$(strip_slash "$(arg 0)")"; [[ -n "$folder" && "$folder" != */ ]] && folder="$folder/"
    if [[ -n "$RECURSIVE" ]]; then
      list_all "$folder" | awk -F'\t' '{ printf "%10s  %s\n", $2, $1 }'
    else
      call GET "/drives/$(drive_id)/files?delimiter=/&limit=1000&prefix=$(jq -rn --arg p "$folder" '$p|@uri')"; ok_or_die "listing files"
      jq -r '(.folders[] | "\(.path)  (\(.fileCount) files)"), (.files[] | "\(.path)  \(.size) bytes  etag \(.etag)")' <<<"$BODY"
      [[ "$(jq -r '.nextCursor // empty' <<<"$BODY")" == "" ]] || echo "(more: use ls -r)"
    fi
    ;;
  put)
    file="$(arg 0)"; [[ -f "$file" ]] || die "usage: drive.sh put <local-file> [path]"
    path="$(strip_slash "$(arg 1)")"; [[ -z "$path" ]] && path="$(basename "$file")"
    [[ "$path" == */ ]] && path="$path$(basename "$file")"
    size="$(wc -c <"$file" | tr -d ' ')"
    if (( size <= INLINE_MAX )); then
      headers=()
      [[ -n "$IF_MATCH" ]] && headers+=(-H "If-Match: \"$IF_MATCH\"")
      [[ -n "$CREATE_ONLY" ]] && headers+=(-H "If-None-Match: *")
      # No Content-Type: the server picks one from the file extension.
      call PUT "/drives/$(drive_id)/files/$(enc_path "$path")" ${headers[@]+"${headers[@]}"} \
        -H "Content-Type:" --data-binary @"$file"
    else
      upload="$(stage "$file" "$path" "$IF_MATCH" "$CREATE_ONLY")" || exit 1
      json_call POST "/drives/$(drive_id)/files/finalize" "$(jq -nc --arg u "$upload" '{uploadId: $u}')"
    fi
    ok_or_die "saving $path"; print_written
    ;;
  cat|get)
    path="$(strip_slash "$(arg 0)")"; [[ -n "$path" ]] || die "usage: drive.sh $CMD <path>"
    out="-"; [[ "$CMD" == get ]] && { out="$(arg 1)"; [[ -n "$out" ]] || out="$(basename "$path")"; }
    tmp="$(mktemp)"; TMPS+=("$tmp")
    code="$(curl -sS -o "$tmp" -w '%{http_code}' "$API/api/v1/drives/$(drive_id)/files/$(enc_path "$path")" "${AUTH[@]}")" || die "could not reach $API"
    if ! [[ "$code" =~ ^2 ]]; then BODY="$(cat "$tmp")"; STATUS="$code"; rm -f "$tmp"; ok_or_die "reading $path"; fi
    if [[ "$out" == "-" ]]; then cat "$tmp"; rm -f "$tmp"; else mkdir -p "$(dirname "$out")"; mv "$tmp" "$out"; echo "downloaded: $out"; fi
    ;;
  rm)
    path="$(strip_slash "$(arg 0)")"; [[ -n "$path" ]] || die "usage: drive.sh rm <path> [-r]"
    headers=(); [[ -n "$IF_MATCH" ]] && headers+=(-H "If-Match: \"$IF_MATCH\"")
    q=""; [[ -n "$RECURSIVE" ]] && { path="${path%/}"; q="?recursive=1"; }
    call DELETE "/drives/$(drive_id)/files/$(enc_path "$path")$q" ${headers[@]+"${headers[@]}"}
    ok_or_die "deleting $path"
    jq -r '.deletedPaths[] | "deleted: \(.)"' <<<"$BODY"
    ;;
  mv)
    from="$(strip_slash "$(arg 0)")"; to="$(strip_slash "$(arg 1)")"
    [[ -n "$from" && -n "$to" ]] || die "usage: drive.sh mv <from> <to>"
    json_call POST "/drives/$(drive_id)/files/move" "$(jq -nc --arg f "$from" --arg t "$to" --arg m "$IF_MATCH" \
      '{from: $f, to: $t} + (if $m != "" then {ifMatch: $m} else {} end)')"
    ok_or_die "moving $from"; print_written
    ;;
  import)
    src="$(arg 0)"; [[ -d "$src" ]] || die "usage: drive.sh import <local-folder> [folder]"
    src="$(cd "$src" && pwd)"
    dest="$(strip_slash "$(arg 1)")"; [[ -n "$dest" && "$dest" != */ ]] && dest="$dest/"
    # path<TAB>sha256 of what the Drive already holds, to skip unchanged files (no bash 4 needed).
    remote="$(mktemp)"; TMPS+=("$remote")
    list_all "$dest" | awk -F'\t' '{ print $1 "\t" $3 }' >"$remote"
    ops=() skipped=0 count=0
    flush() {
      [[ ${#ops[@]} -gt 0 ]] || return 0
      json_call PATCH "/drives/$(drive_id)/files" "$(printf '%s\n' "${ops[@]}" | jq -sc '{ops: .}')"
      ok_or_die "saving files"
      count=$((count + ${#ops[@]})); ops=()
    }
    while IFS= read -r -d '' f; do
      rel="${f#./}"; path="$dest$rel"
      if grep -qxF "$path"$'\t'"$(sha256 "$src/$rel")" "$remote"; then skipped=$((skipped + 1)); continue; fi
      echo "uploading: $rel" >&2
      upload="$(stage "$src/$rel" "$path")" || exit 1
      ops+=("$(jq -nc --arg p "$path" --arg u "$upload" '{op: "write", path: $p, uploadId: $u}')")
      [[ ${#ops[@]} -lt 50 ]] || flush
    done < <(cd "$src" && find . \( -name .git -o -name node_modules \) -prune -o -type f ! -name .DS_Store ! -name '.env' ! -name '.env.*' -print0 | sort -z)
    flush
    echo "imported: $count files into ${dest:-the top level}, $skipped unchanged"
    [[ $count -gt 0 ]] && echo "version: $(jq -r .versionId <<<"$BODY")"
    ;;
  export)
    folder="$(strip_slash "$(arg 0)")"; out="$(arg 1)"
    [[ -n "$out" ]] || die "usage: drive.sh export <folder> <local-folder>"
    [[ -n "$folder" && "$folder" != */ ]] && folder="$folder/"
    mkdir -p "$out"; n=0
    while IFS=$'\t' read -r p _ _ _; do
      [[ -n "$p" ]] || continue
      rel="${p#"$folder"}"; mkdir -p "$out/$(dirname "$rel")"
      code="$(curl -sS -o "$out/$rel" -w '%{http_code}' "$API/api/v1/drives/$(drive_id)/files/$(enc_path "$p")" "${AUTH[@]}")" || die "could not reach $API"
      [[ "$code" =~ ^2 ]] || die "download failed for $p ($code)"
      n=$((n + 1))
    done < <(list_all "$folder")
    echo "exported: $n files to $out"
    ;;
  link)
    path="$(strip_slash "$(arg 0)")"; [[ -n "$path" ]] || die "usage: drive.sh link <path>"
    json_call POST "/drives/$(drive_id)/files/download-url" "$(jq -nc --arg p "$path" '{path: $p}')"
    ok_or_die "making a link for $path"
    jq -r '"link: \(.url)\nexpires: \(.expiresAt)"' <<<"$BODY"
    ;;
  share)
    [[ "$PERMS" == read || "$PERMS" == write ]] || die "--perms must be read or write"
    json_call POST "/drives/$(drive_id)/tokens" "$(jq -nc --arg p "$PERMS" --arg x "$PREFIX" --arg t "$TTL" --arg m "$MANAGE" --arg l "$LABEL" \
      '{perms: $p} + (if $x != "" then {pathPrefix: $x} else {} end) + (if $t != "" then {ttl: $t} else {} end)
       + (if $m != "" then {manageTokens: true} else {} end) + (if $l != "" then {label: $l} else {} end)')"
    ok_or_die "creating a share token"
    jq -r '"token: \(.token)\nid: \(.tokenInfo.id)\naccess: \(.tokenInfo.perms)\(if .tokenInfo.pathPrefix then " in " + .tokenInfo.pathPrefix else " (whole Drive)" end)\nexpires: \(.tokenInfo.expiresAt // "never")\ndrive: \(.drive.id)\napi: \(.apiOrigin)"' <<<"$BODY"
    echo "note: shown once. The other agent sets BIGANGELS_DRIVE_TOKEN=<token> and uses drive.sh as usual."
    ;;
  tokens)
    call GET "/drives/$(drive_id)/tokens"; ok_or_die "listing tokens"
    jq -r '.tokens[] | "\(.id)\t\(.perms)\t\(.pathPrefix // "/")\t\(.status)\texpires \(.expiresAt // "never")\t\(.label // "")"' <<<"$BODY"
    ;;
  revoke)
    id="$(arg 0)"; [[ "$id" == dtok_* ]] || die "usage: drive.sh revoke <dtok_…>"
    call DELETE "/drives/$(drive_id)/tokens/$id"; ok_or_die "revoking $id"
    echo "revoked: $id ($(jq -r .revoked <<<"$BODY") token(s), effective now)"
    ;;
  publish)
    folder="$(strip_slash "$(arg 0)")"
    json_call POST /publish "$(jq -nc --arg d "$(drive_id)" --arg p "$folder" --arg v "$VERSION" --arg s "$SLUG" --arg spa "$SPA" \
      '{fromDrive: ({driveId: $d} + (if $p != "" then {prefix: $p} else {} end) + (if $v != "" then {version: $v} else {} end)
        + (if $s != "" then {slug: $s} else {} end))} + (if $spa != "" then {spaMode: true} else {} end)')"
    ok_or_die "publishing"
    jq -r '"published: \(.siteUrl)\nfiles: \(.filesCount) (\(.copiedFiles) copied)\nfrom: \(.driveId) at \(.driveVersionId)"' <<<"$BODY"
    ;;
  versions)
    call GET "/drives/$(drive_id)/versions?limit=20"; ok_or_die "listing versions"
    jq -r '.versions[] | "\(.number)\t\(.id)\t\(.createdAt)\t\(.by.type)\t\([.ops[] | "\(.op) \(.path // (.from + " -> " + .to))"] | join(", "))"' <<<"$BODY"
    ;;
  *) die "unknown command: $CMD (see drive.sh --help)" ;;
esac
