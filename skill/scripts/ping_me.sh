#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${PING_ME_CONFIG:-$HOME/.codex/ping-me.env}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

DEFAULT_TITLE="Codex done"
title="$DEFAULT_TITLE"
message=""
status="success"
transport="${PING_ME_TRANSPORT:-auto}"
min_idle_seconds="${PING_ME_MIN_IDLE_SECONDS:-120}"
force=0
dry_run=0
wait_pid=""
command_status=""
caffeinate=0
caffeinate_pid=""
stop_caffeinate_after=0
command_args=()

usage() {
  cat <<'USAGE'
Usage:
  ping_me.sh [options]
  ping_me.sh [options] -- command [args...]

Options:
  --title TEXT          Notification title.
  --message TEXT        Notification body.
  --status STATUS       success, failure, blocked, or neutral.
  --transport NAME      auto, pushover, ntfy, imessage, or macos.
  --min-idle SECONDS    Suppress unless Mac has been idle this long.
  --pid PID             Wait for PID to exit, then notify.
  --caffeinate          Keep Mac awake while waiting for PID or command.
  --caffeinate-stop     Stop the ping-me caffeinate guard after notifying.
  --force               Notify even if the Mac appears active.
  --dry-run             Print what would happen without sending.
  --help                Show this help.
USAGE
}

die() {
  printf 'ping-me: %s\n' "$*" >&2
  exit 64
}

is_caffeinate_pid() {
  pid="$1"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  case "$(/bin/ps -p "$pid" -o args= 2>/dev/null)" in
    *"/caffeinate"*) return 0 ;;
    *) return 1 ;;
  esac
}

stop_local_caffeinate() {
  if is_caffeinate_pid "$caffeinate_pid"; then
    kill "$caffeinate_pid" 2>/dev/null || true
  fi
}

start_local_caffeinate() {
  [ "$caffeinate" -eq 1 ] || return 0

  if [ "$dry_run" -eq 1 ]; then
    printf 'ping-me dry-run: would start caffeinate with args: %s\n' "${PING_ME_CAFFEINATE_ARGS:--dims}" >&2
    return 0
  fi

  if [ ! -x /usr/bin/caffeinate ]; then
    printf 'ping-me: /usr/bin/caffeinate is unavailable; continuing without wake guard.\n' >&2
    return 0
  fi

  read -r -a caffeinate_args <<< "${PING_ME_CAFFEINATE_ARGS:--dims}"
  /usr/bin/caffeinate "${caffeinate_args[@]}" >/dev/null 2>&1 &
  caffeinate_pid=$!
  trap stop_local_caffeinate EXIT INT TERM
  printf 'ping-me: caffeinate started (pid %s).\n' "$caffeinate_pid" >&2
}

stop_caffeinate_guard() {
  [ "$stop_caffeinate_after" -eq 1 ] || return 0
  if [ -x "$SCRIPT_DIR/caffeinate_guard.sh" ]; then
    "$SCRIPT_DIR/caffeinate_guard.sh" stop >&2 || true
  else
    printf 'ping-me: caffeinate guard script not found; cannot stop guard.\n' >&2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --title)
      [ "$#" -ge 2 ] || die "--title requires a value"
      title="$2"
      shift 2
      ;;
    --message)
      [ "$#" -ge 2 ] || die "--message requires a value"
      message="$2"
      shift 2
      ;;
    --status)
      [ "$#" -ge 2 ] || die "--status requires a value"
      status="$2"
      shift 2
      ;;
    --transport)
      [ "$#" -ge 2 ] || die "--transport requires a value"
      transport="$2"
      shift 2
      ;;
    --min-idle)
      [ "$#" -ge 2 ] || die "--min-idle requires a value"
      min_idle_seconds="$2"
      shift 2
      ;;
    --pid|--wait-pid)
      [ "$#" -ge 2 ] || die "--pid requires a value"
      wait_pid="$2"
      shift 2
      ;;
    --caffeinate)
      caffeinate=1
      shift
      ;;
    --caffeinate-stop|--stop-caffeinate)
      stop_caffeinate_after=1
      shift
      ;;
    --force)
      force=1
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
    --)
      shift
      [ "$#" -gt 0 ] || die "-- requires a command"
      command_args=("$@")
      break
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$status" in
  success|failure|blocked|neutral) ;;
  *) die "--status must be success, failure, blocked, or neutral" ;;
esac

case "$transport" in
  auto|pushover|ntfy|imessage|macos) ;;
  *) die "--transport must be auto, pushover, ntfy, imessage, or macos" ;;
esac

case "$min_idle_seconds" in
  ''|*[!0-9]*) die "--min-idle must be a non-negative integer" ;;
esac

if [ -n "$wait_pid" ] && [ "${#command_args[@]}" -gt 0 ]; then
  die "use --pid or -- command, not both"
fi

start_local_caffeinate

if [ -n "$wait_pid" ]; then
  case "$wait_pid" in
    ''|*[!0-9]*) die "--pid must be a positive integer" ;;
  esac
  while kill -0 "$wait_pid" 2>/dev/null; do
    sleep 5
  done
fi

if [ "${#command_args[@]}" -gt 0 ]; then
  "${command_args[@]}"
  command_status=$?
  if [ "$command_status" -eq 0 ]; then
    status="success"
  else
    status="failure"
  fi
  if [ -z "$message" ]; then
    message="Command finished with exit status $command_status."
  fi
fi

if [ -z "$message" ]; then
  message="Task finished at $(date '+%Y-%m-%d %H:%M:%S')."
fi

if [ "$title" = "$DEFAULT_TITLE" ]; then
  case "$status" in
    success) title="Codex done" ;;
    failure) title="Codex failure" ;;
    blocked) title="Codex blocked" ;;
  esac
fi

idle_seconds() {
  /usr/sbin/ioreg -c IOHIDSystem 2>/dev/null | /usr/bin/awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }'
}

screen_locked() {
  /usr/sbin/ioreg -n Root -d1 2>/dev/null | /usr/bin/grep -q 'CGSSessionScreenIsLocked.*Yes'
}

should_notify() {
  if [ "$force" -eq 1 ]; then
    return 0
  fi

  if screen_locked; then
    return 0
  fi

  idle="$(idle_seconds)"
  if [ -z "$idle" ]; then
    printf 'ping-me: could not read Mac idle time; notifying anyway.\n' >&2
    return 0
  fi

  if [ "$idle" -lt "$min_idle_seconds" ]; then
    printf 'ping-me: skipped; Mac appears active (idle %ss < %ss).\n' "$idle" "$min_idle_seconds" >&2
    return 1
  fi

  return 0
}

dry_note() {
  printf 'ping-me dry-run: transport=%s title=%s message=%s\n' "$1" "$title" "$message"
}

notify_pushover() {
  [ -n "${PING_ME_PUSHOVER_USER_KEY:-}" ] || return 78
  [ -n "${PING_ME_PUSHOVER_API_TOKEN:-}" ] || return 78

  if [ "$dry_run" -eq 1 ]; then
    dry_note "pushover"
    return 0
  fi

  args=(-fsS --retry 2 --max-time 10 \
    -X POST "https://api.pushover.net/1/messages.json" \
    --form-string "token=$PING_ME_PUSHOVER_API_TOKEN" \
    --form-string "user=$PING_ME_PUSHOVER_USER_KEY" \
    --form-string "title=$title" \
    --form-string "message=$message" \
    --form-string "priority=${PING_ME_PUSHOVER_PRIORITY:-0}")
  if [ -n "${PING_ME_PUSHOVER_SOUND:-}" ]; then
    args+=(--form-string "sound=$PING_ME_PUSHOVER_SOUND")
  fi

  /usr/bin/curl "${args[@]}" >/dev/null
}

notify_ntfy() {
  url="${PING_ME_NTFY_URL:-}"
  if [ -z "$url" ] && [ -n "${PING_ME_NTFY_TOPIC:-}" ]; then
    url="https://ntfy.sh/$PING_ME_NTFY_TOPIC"
  fi
  [ -n "$url" ] || return 78

  if [ "$dry_run" -eq 1 ]; then
    dry_note "ntfy"
    printf 'ping-me dry-run: url=%s\n' "$url"
    return 0
  fi

  if [ -n "${PING_ME_NTFY_TOKEN:-}" ]; then
    /usr/bin/curl -fsS --retry 2 --max-time 10 \
      -H "Authorization: Bearer $PING_ME_NTFY_TOKEN" \
      -H "Title: $title" \
      -H "Priority: ${PING_ME_NTFY_PRIORITY:-default}" \
      -H "Tags: ${PING_ME_NTFY_TAGS:-white_check_mark}" \
      -d "$message" \
      "$url" \
      >/dev/null
  else
    /usr/bin/curl -fsS --retry 2 --max-time 10 \
      -H "Title: $title" \
      -H "Priority: ${PING_ME_NTFY_PRIORITY:-default}" \
      -H "Tags: ${PING_ME_NTFY_TAGS:-white_check_mark}" \
      -d "$message" \
      "$url" \
      >/dev/null
  fi
}

notify_imessage() {
  [ -n "${PING_ME_IMESSAGE_TARGET:-}" ] || return 78

  if [ "$dry_run" -eq 1 ]; then
    dry_note "imessage"
    printf 'ping-me dry-run: target=%s\n' "$PING_ME_IMESSAGE_TARGET"
    return 0
  fi

  /usr/bin/osascript - "$PING_ME_IMESSAGE_TARGET" "$title: $message" <<'APPLESCRIPT'
on run argv
  set targetBuddy to item 1 of argv
  set bodyText to item 2 of argv
  tell application "Messages"
    set targetService to 1st service whose service type = iMessage
    send bodyText to buddy targetBuddy of targetService
  end tell
end run
APPLESCRIPT
}

notify_macos() {
  if [ "$dry_run" -eq 1 ]; then
    dry_note "macos"
    return 0
  fi

  /usr/bin/osascript - "$title" "$message" <<'APPLESCRIPT'
on run argv
  set titleText to item 1 of argv
  set bodyText to item 2 of argv
  display notification bodyText with title titleText
end run
APPLESCRIPT
}

notify_auto() {
  if [ -n "${PING_ME_PUSHOVER_USER_KEY:-}" ] && [ -n "${PING_ME_PUSHOVER_API_TOKEN:-}" ]; then
    notify_pushover
    return $?
  fi

  if [ -n "${PING_ME_NTFY_TOPIC:-}" ] || [ -n "${PING_ME_NTFY_URL:-}" ]; then
    notify_ntfy
    return $?
  fi

  if [ -n "${PING_ME_IMESSAGE_TARGET:-}" ]; then
    notify_imessage
    return $?
  fi

  printf 'ping-me: no watch push transport configured; using macOS notification fallback.\n' >&2
  notify_macos
}

if should_notify; then
  case "$transport" in
    auto) notify_auto; notify_status=$? ;;
    pushover) notify_pushover; notify_status=$? ;;
    ntfy) notify_ntfy; notify_status=$? ;;
    imessage) notify_imessage; notify_status=$? ;;
    macos) notify_macos; notify_status=$? ;;
  esac
else
  notify_status=0
fi

if [ "$notify_status" -eq 78 ]; then
  printf 'ping-me: transport "%s" is not configured in %s.\n' "$transport" "$CONFIG_FILE" >&2
fi

stop_caffeinate_guard

if [ -n "$command_status" ]; then
  exit "$command_status"
fi

exit "$notify_status"
