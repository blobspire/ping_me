#!/usr/bin/env bash
# Claude Code Stop hook: completes an armed ping for THIS session when Claude
# stops, so the notification is delivered even if the model never reaches the
# explicit complete step. It must stay fast, silent, and ALWAYS exit 0 so it can
# never block Claude from stopping. Completion is claim-locked, so if the model
# also ran an explicit complete, only one notification is sent.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dry_run="${PING_ME_DRY_RUN:-0}"

# Read the Stop hook payload from stdin and pull out the session id.
payload="$(/bin/cat 2>/dev/null | /usr/bin/tr -d '\n' 2>/dev/null || true)"
session_id="$(printf '%s' "$payload" | /usr/bin/sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$session_id" ] || exit 0

scope="claude:$session_id"

# Act only when this session has an armed Claude ping. This is a cheap pending
# check on every other turn.
if "$SCRIPT_DIR/ping_me_request.sh" pending --agent Claude --scope "$scope" --quiet >/dev/null 2>&1; then
  if [ "$dry_run" = "1" ]; then
    "$SCRIPT_DIR/ping_me_request.sh" complete --agent Claude --scope "$scope" --quiet --dry-run || true
  else
    "$SCRIPT_DIR/ping_me_request.sh" complete --agent Claude --scope "$scope" --quiet --background >/dev/null 2>&1 || true
  fi
fi

exit 0
