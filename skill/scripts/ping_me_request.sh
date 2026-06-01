#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="${PING_ME_CONFIG:-}"
if [ -z "$CONFIG_FILE" ]; then
  if [ -f "$HOME/.config/ping-me/ping-me.env" ]; then
    CONFIG_FILE="$HOME/.config/ping-me/ping-me.env"
  elif [ -f "$HOME/.codex/ping-me.env" ]; then
    CONFIG_FILE="$HOME/.codex/ping-me.env"
  fi
fi
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

STATE_DIR="${PING_ME_STATE_DIR:-$HOME/.local/state/ping-me}"
REQUEST_DIR="$STATE_DIR/requests"
action="${1:-}"
agent_name=""
message=""
message_explicit=0
status="success"
status_explicit=0
request_id=""
request_scope=""
scope_explicit=0
quiet=0
dry_run=0

usage() {
  cat <<'USAGE'
Usage:
  ping_me_request.sh arm [options]
  ping_me_request.sh mark [options]
  ping_me_request.sh pending [options]
  ping_me_request.sh complete [options]
  ping_me_request.sh cancel [options]
  ping_me_request.sh list

Options:
  --agent NAME       Agent label, e.g. Codex or Claude.
  --message TEXT     Completion notification body.
  --status STATUS    success, failure, or blocked.
  --id ID            Complete or cancel a specific request.
  --scope SCOPE      Scope requests to a session or task id.
  --quiet            Suppress "nothing to do" messages.
  --dry-run          Do not send notifications; useful for tests.
  --help             Show this help.
USAGE
}

die() {
  printf 'ping-me: %s\n' "$*" >&2
  exit 64
}

case "$action" in
  arm|mark|pending|complete|cancel|list|status) shift ;;
  --help|-h|help|'') usage; exit 0 ;;
  *) die "unknown action: $action" ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)
      [ "$#" -ge 2 ] || die "--agent requires a value"
      agent_name="$2"
      shift 2
      ;;
    --message)
      [ "$#" -ge 2 ] || die "--message requires a value"
      message="$2"
      message_explicit=1
      shift 2
      ;;
    --status)
      [ "$#" -ge 2 ] || die "--status requires a value"
      status="$2"
      status_explicit=1
      shift 2
      ;;
    --id)
      [ "$#" -ge 2 ] || die "--id requires a value"
      request_id="$2"
      shift 2
      ;;
    --scope)
      [ "$#" -ge 2 ] || die "--scope requires a value"
      request_scope="$2"
      scope_explicit=1
      shift 2
      ;;
    --quiet)
      quiet=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$status" in
  success|failure|blocked) ;;
  *) die "--status must be success, failure, or blocked" ;;
esac

safe_agent() {
  printf '%s\n' "${1:-Codex}" | /usr/bin/tr -cd '[:alnum:]_.-'
}

safe_scope() {
  printf '%s\n' "$1" | /usr/bin/tr -cd '[:alnum:]_.:-'
}

current_scope() {
  if [ "$scope_explicit" -eq 1 ]; then
    safe_scope "$request_scope"
    return 0
  fi
  if [ -n "${PING_ME_SCOPE:-}" ]; then
    safe_scope "$PING_ME_SCOPE"
    return 0
  fi
  case "$(printf '%s\n' "${agent_name:-Codex}" | /usr/bin/tr '[:upper:]' '[:lower:]')" in
    codex)
      if [ -n "${CODEX_THREAD_ID:-}" ]; then
        safe_scope "codex:$CODEX_THREAD_ID"
      fi
      ;;
  esac
}

new_id() {
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  if [ -r /dev/urandom ]; then
    suffix="$(/usr/bin/od -An -N4 -tx1 /dev/urandom 2>/dev/null | /usr/bin/tr -d ' \n')"
  else
    suffix="$$"
  fi
  printf '%s-%s-%s\n' "$stamp" "$$" "${suffix:-manual}"
}

read_first_line() {
  file="$1"
  [ -f "$file" ] || return 1
  /usr/bin/awk 'NR == 1 { print; exit }' "$file"
}

completion_mode() {
  scope="$(current_scope)"
  case "${agent_name:-Codex}:${PING_ME_CODEX_NOTIFY_HOOK:-0}:$scope" in
    Codex:1:?*|codex:1:?*) printf 'hook' ;;
    *) printf 'manual' ;;
  esac
}

request_path_for_id() {
  id="$1"
  [ -n "$id" ] || return 1
  case "$id" in
    *[!A-Za-z0-9_.:-]*) return 1 ;;
  esac
  printf '%s/%s\n' "$REQUEST_DIR" "$id"
}

latest_request_path() {
  filter_agent="$(safe_agent "${agent_name:-}")"
  filter_scope="$(current_scope)"
  latest=""
  for dir in "$REQUEST_DIR"/*; do
    [ -d "$dir" ] || continue
    if [ -n "$filter_agent" ]; then
      dir_agent="$(read_first_line "$dir/agent" 2>/dev/null || true)"
      [ "$dir_agent" = "$filter_agent" ] || continue
    fi
    dir_scope="$(read_first_line "$dir/scope" 2>/dev/null || true)"
    if [ -n "$filter_scope" ]; then
      [ "$dir_scope" = "$filter_scope" ] || continue
    elif [ -n "$dir_scope" ]; then
      continue
    fi
    latest="$dir"
  done
  [ -n "$latest" ] || return 1
  printf '%s\n' "$latest"
}

find_request_path() {
  if [ -n "$request_id" ]; then
    path="$(request_path_for_id "$request_id" || true)"
    [ -n "${path:-}" ] && [ -d "$path" ] || return 1
    printf '%s\n' "$path"
    return 0
  fi
  latest_request_path
}

has_requests() {
  for dir in "$REQUEST_DIR"/*; do
    [ -d "$dir" ] && return 0
  done
  return 1
}

has_matching_request() {
  path="$(find_request_path || true)"
  [ -n "${path:-}" ]
}

remove_matching_requests() {
  filter_agent="$1"
  filter_scope="$2"
  for dir in "$REQUEST_DIR"/*; do
    [ -d "$dir" ] || continue
    dir_agent="$(read_first_line "$dir/agent" 2>/dev/null || true)"
    [ "$dir_agent" = "$filter_agent" ] || continue
    dir_scope="$(read_first_line "$dir/scope" 2>/dev/null || true)"
    if [ -n "$filter_scope" ]; then
      [ "$dir_scope" = "$filter_scope" ] || continue
    elif [ -n "$dir_scope" ]; then
      continue
    fi
    /bin/rm -rf "$dir"
  done
}

stop_guard_if_idle() {
  has_requests && return 0
  if [ -x "$SCRIPT_DIR/caffeinate_guard.sh" ]; then
    PING_ME_STATE_DIR="$STATE_DIR" "$SCRIPT_DIR/caffeinate_guard.sh" stop >&2 || true
  fi
}

arm_request() {
  agent_name="$(safe_agent "${agent_name:-Codex}")"
  [ -n "$message" ] || message="The requested task finished."

  if [ "$dry_run" -eq 1 ]; then
    printf 'ping-me dry-run: would arm agent=%s completion=%s\n' "$agent_name" "$(completion_mode)"
    return 0
  fi

  umask 077
  /bin/mkdir -p "$REQUEST_DIR"
  scope="$(current_scope)"
  remove_matching_requests "$agent_name" "$scope"
  id="${request_id:-$(new_id)}"
  request_path="$(request_path_for_id "$id")" || die "invalid request id"
  tmp_path="$request_path.tmp.$$"
  /bin/rm -rf "$tmp_path"
  /bin/mkdir "$tmp_path" || exit 1
  printf '%s\n' "$agent_name" > "$tmp_path/agent"
  if [ -n "$scope" ]; then
    printf '%s\n' "$scope" > "$tmp_path/scope"
  fi
  printf '%s\n' "$message" > "$tmp_path/message"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$tmp_path/created_at"
  printf 'success\n' > "$tmp_path/status"
  /bin/mv "$tmp_path" "$request_path"

  if [ -x "$SCRIPT_DIR/caffeinate_guard.sh" ]; then
    PING_ME_STATE_DIR="$STATE_DIR" "$SCRIPT_DIR/caffeinate_guard.sh" start >&2 || true
  fi

  printf 'ping-me armed id=%s completion=%s\n' "$id" "$(completion_mode)"
}

mark_request() {
  path="$(find_request_path || true)"
  if [ -z "${path:-}" ]; then
    [ "$quiet" -eq 1 ] || printf 'ping-me: no armed request; nothing to mark.\n' >&2
    return 0
  fi

  printf '%s\n' "$status" > "$path/status"
  if [ "$message_explicit" -eq 1 ]; then
    printf '%s\n' "$message" > "$path/message"
  fi

  [ "$quiet" -eq 1 ] || printf 'ping-me: marked %s as %s\n' "$(/usr/bin/basename "$path")" "$status"
}

pending_request() {
  if has_matching_request; then
    [ "$quiet" -eq 1 ] || printf 'pending\n'
    return 0
  fi
  [ "$quiet" -eq 1 ] || printf 'none\n'
  return 1
}

complete_request() {
  path="$(find_request_path || true)"
  if [ -z "${path:-}" ]; then
    [ "$quiet" -eq 1 ] || printf 'ping-me: no armed request; nothing to complete.\n' >&2
    return 0
  fi

  stored_agent="$(read_first_line "$path/agent" 2>/dev/null || true)"
  [ -n "$agent_name" ] || agent_name="${stored_agent:-Codex}"
  agent_name="$(safe_agent "$agent_name")"

  if [ "$message_explicit" -eq 0 ]; then
    message="$(/bin/cat "$path/message" 2>/dev/null || true)"
  fi
  [ -n "$message" ] || message="The requested task finished."

  if [ "$status_explicit" -eq 0 ]; then
    status="$(read_first_line "$path/status" 2>/dev/null || true)"
    case "$status" in
      success|failure|blocked) ;;
      *) status="success" ;;
    esac
  fi

  args=(--force --agent "$agent_name" --status "$status" --message "$message")
  if [ "$dry_run" -eq 1 ]; then
    args+=(--dry-run)
  fi

  "$SCRIPT_DIR/ping_me.sh" "${args[@]}"
  notify_status=$?
  if [ "$notify_status" -eq 0 ]; then
    /bin/rm -rf "$path"
    stop_guard_if_idle
  fi
  return "$notify_status"
}

cancel_request() {
  path="$(find_request_path || true)"
  if [ -z "${path:-}" ]; then
    [ "$quiet" -eq 1 ] || printf 'ping-me: no armed request; nothing to cancel.\n' >&2
    return 0
  fi
  /bin/rm -rf "$path"
  stop_guard_if_idle
  printf 'ping-me: canceled %s\n' "$(/usr/bin/basename "$path")"
}

list_requests() {
  for dir in "$REQUEST_DIR"/*; do
    [ -d "$dir" ] || continue
    id="$(/usr/bin/basename "$dir")"
    req_agent="$(read_first_line "$dir/agent" 2>/dev/null || true)"
    req_scope="$(read_first_line "$dir/scope" 2>/dev/null || true)"
    created_at="$(read_first_line "$dir/created_at" 2>/dev/null || true)"
    printf '%s\t%s\t%s\t%s\n' "$id" "${req_agent:-unknown}" "${req_scope:-unscoped}" "${created_at:-unknown}"
  done
}

case "$action" in
  arm) arm_request ;;
  mark) mark_request ;;
  pending) pending_request ;;
  complete) complete_request ;;
  cancel) cancel_request ;;
  list|status) list_requests ;;
esac
