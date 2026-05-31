#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
previous_status=0
dry_run_args=()

if [ "${PING_ME_DRY_RUN:-0}" = "1" ]; then
  dry_run_args=(--dry-run)
fi

if [ "$#" -gt 0 ]; then
  previous_notify="$1"
  shift
  if [ -x "$previous_notify" ]; then
    "$previous_notify" "$@" || previous_status=$?
  fi
fi

PING_ME_CODEX_NOTIFY_HOOK=1 \
"$SCRIPT_DIR/ping_me_request.sh" complete \
    --agent Codex \
    --quiet \
    "${dry_run_args[@]}" \
  >/dev/null 2>&1 || true

exit "$previous_status"
