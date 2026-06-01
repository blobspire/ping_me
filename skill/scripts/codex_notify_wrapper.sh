#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
previous_status=0
dry_run="${PING_ME_DRY_RUN:-0}"
scope="${PING_ME_SCOPE:-}"

if [ -z "$scope" ] && [ -n "${CODEX_THREAD_ID:-}" ]; then
  scope="codex:$CODEX_THREAD_ID"
fi

if [ "$#" -gt 0 ]; then
  previous_notify="$1"
  shift
  if [ -x "$previous_notify" ]; then
    "$previous_notify" "$@" || previous_status=$?
  fi
fi

if [ -n "$scope" ] && PING_ME_CODEX_NOTIFY_HOOK=1 "$SCRIPT_DIR/ping_me_request.sh" pending --agent Codex --scope "$scope" --quiet >/dev/null 2>&1; then
  if [ "$dry_run" = "1" ]; then
    PING_ME_CODEX_NOTIFY_HOOK=1 \
      "$SCRIPT_DIR/ping_me_request.sh" complete \
        --agent Codex \
        --scope "$scope" \
        --quiet \
        --dry-run \
      >/dev/null 2>&1 || true
  else
    PING_ME_CODEX_NOTIFY_HOOK=1 \
      /usr/bin/nohup "$SCRIPT_DIR/ping_me_request.sh" complete \
        --agent Codex \
        --scope "$scope" \
        --quiet \
      >/dev/null 2>&1 &
  fi
fi

exit "$previous_status"
