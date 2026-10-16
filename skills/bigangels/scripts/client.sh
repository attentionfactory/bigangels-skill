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
