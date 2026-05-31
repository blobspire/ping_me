#!/usr/bin/env bash
set -u

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
PID_FILE="${PING_ME_CAFFEINATE_PID_FILE:-$STATE_DIR/caffeinate.pid}"
CAFFEINATE_ARGS="${PING_ME_CAFFEINATE_ARGS:--dims}"
CAFFEINATE_TIMEOUT_SECONDS="${PING_ME_CAFFEINATE_TIMEOUT_SECONDS:-90000}"

usage() {
  cat <<'USAGE'
Usage:
  caffeinate_guard.sh start
  caffeinate_guard.sh stop
  caffeinate_guard.sh status
USAGE
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

read_pid() {
  [ -f "$PID_FILE" ] || return 1
  /bin/cat "$PID_FILE" 2>/dev/null | /usr/bin/awk 'NR == 1 { print $1 }'
}

start_guard() {
  /bin/mkdir -p "$STATE_DIR"

  existing_pid="$(read_pid || true)"
  if is_caffeinate_pid "$existing_pid"; then
    printf 'ping-me: caffeinate guard already running (pid %s).\n' "$existing_pid" >&2
    return 0
  fi

  /bin/rm -f "$PID_FILE"
  if [ ! -x /usr/bin/caffeinate ]; then
    printf 'ping-me: /usr/bin/caffeinate is unavailable.\n' >&2
    return 69
  fi

  read -r -a caffeinate_args <<< "$CAFFEINATE_ARGS"
  case "$CAFFEINATE_TIMEOUT_SECONDS" in
    ''|0) ;;
    *[!0-9]*)
      printf 'ping-me: PING_ME_CAFFEINATE_TIMEOUT_SECONDS must be a non-negative integer.\n' >&2
      return 64
      ;;
    *)
      caffeinate_args+=(-t "$CAFFEINATE_TIMEOUT_SECONDS")
      ;;
  esac
  /usr/bin/nohup /usr/bin/caffeinate "${caffeinate_args[@]}" >/dev/null 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$PID_FILE"
  printf 'ping-me: caffeinate guard started (pid %s).\n' "$pid" >&2
}

stop_guard() {
  existing_pid="$(read_pid || true)"
  if is_caffeinate_pid "$existing_pid"; then
    kill "$existing_pid" 2>/dev/null || true
    printf 'ping-me: caffeinate guard stopped (pid %s).\n' "$existing_pid" >&2
  else
    printf 'ping-me: no active caffeinate guard.\n' >&2
  fi
  /bin/rm -f "$PID_FILE"
}

status_guard() {
  existing_pid="$(read_pid || true)"
  if is_caffeinate_pid "$existing_pid"; then
    printf 'running %s\n' "$existing_pid"
  else
    printf 'stopped\n'
  fi
}

case "${1:-}" in
  start) start_guard ;;
  stop) stop_guard ;;
  status) status_guard ;;
  --help|-h|help) usage ;;
  *) usage >&2; exit 64 ;;
esac
