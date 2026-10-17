#!/usr/bin/env bash
# Shared X-BigAngels-Client detection for login.sh and publish.sh.
# Prefer BIGANGELS_CLIENT; otherwise infer from the skill install path or Cursor env.

# bigangels_detect_prefix INVOKING_SCRIPT_PATH
bigangels_detect_prefix() {
  local invoking="${1:-}"
  if [[ -n "${BIGANGELS_CLIENT:-}" ]]; then
    printf '%s' "${BIGANGELS_CLIENT%%/*}"
    return
  fi
  case "$invoking" in
    *"/.cursor/"*) printf 'cursor'; return ;;
    *"/.codex/"*) printf 'codex'; return ;;
    *"/.claude/"*) printf 'claude-code'; return ;;
  esac
  if [[ -n "${CURSOR_TRACE_ID:-}${CURSOR_AGENT:-}" || "${TERM_PROGRAM:-}" == "cursor" ]]; then
    printf 'cursor'
    return
  fi
  printf 'claude-code'
}

# bigangels_client_id INVOKING_SCRIPT_PATH ROLE
# ROLE is login-sh or publish-sh (sent as X-BigAngels-Client and CLI auth key name prefix).
bigangels_client_id() {
  local invoking="$1"
  local role="$2"
  if [[ -n "${BIGANGELS_CLIENT:-}" ]]; then
    local prefix="${BIGANGELS_CLIENT%%/*}"
    printf '%s/%s' "$prefix" "$role"
    return
  fi
  printf '%s/%s' "$(bigangels_detect_prefix "$invoking")" "$role"
}

# bigangels_publish_device_id STATE_DIR
# Stable id for tying anonymous publishes to later account recovery (stored locally, sent hashed server-side).
bigangels_publish_device_id() {
  local dir="$1"
  local file="$dir/device_id"
  if [[ -n "${BIGANGELS_PUBLISH_DEVICE:-}" ]]; then
    printf '%s' "$BIGANGELS_PUBLISH_DEVICE"
    return
  fi
  if [[ -f "$file" ]]; then
    cat "$file"
    return
  fi
  local id
  if command -v openssl >/dev/null; then id="$(openssl rand -hex 16)"
  else id="$(head -c 16 /dev/urandom | xxd -p -c 32)"; fi
  mkdir -p "$dir"
  chmod 700 "$dir"
  (umask 077 && printf '%s' "$id" >"$file")
  printf '%s' "$id"
}
