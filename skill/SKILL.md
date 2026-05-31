---
name: ping-me
description: Use only when the user directly asks Codex to notify them when the current Codex task, command, or long-running process finishes, such as a standalone "ping me", "notify me when done", or a separate imperative clause like "run tests, then ping me". Do not use when pinging, alerts, notifications, connectivity, or "ping me" are part of the app/product behavior being discussed or implemented.
metadata:
  short-description: Explicit completion pings for long tasks
---

# Ping Me

Use this skill as a one-shot completion ping for the current task only. Do not notify for future unrelated tasks unless the user asks again.

## Trigger Guard

Use this skill only when the user is directly instructing Codex to send a completion notification for Codex's current work.

Valid examples:

- `ping me`
- `notify me when done`
- `run the tests, then ping me`
- `please send me a watch notification after this finishes`

Do not use this skill when notification language is part of the user's product requirements, code behavior, documentation, tests, or examples. For example, do not trigger for: `I'm building a walkie talkie app and I want it to ping me when I lose connection.`

If the intent is ambiguous, do not use the skill.

## Workflow

1. As soon as the ping request is received, arm the request:

```bash
"$HOME/.codex/skills/ping-me/scripts/ping_me_request.sh" arm \
  --agent Codex \
  --message "The requested task finished."
```

2. Finish the user's actual task. Do not let the notification workflow replace or shorten the requested work.
3. If the arm command printed `completion=manual`, complete the armed request at the end:

```bash
"$HOME/.codex/skills/ping-me/scripts/ping_me_request.sh" complete \
  --agent Codex \
  --status success
```

If the arm command printed `completion=hook`, do not send a manual notification; the Codex notify hook owns completion. If the task fails or becomes blocked in hook mode, mark the armed request before ending:

```bash
"$HOME/.codex/skills/ping-me/scripts/ping_me_request.sh" mark \
  --agent Codex \
  --status failure \
  --message "The requested task failed."
```

Use `--status failure` when the task failed and `--status blocked` when Codex cannot continue without user input or an external change. Keep notification text short and do not include secrets, command output, file contents, tokens, or large logs.

Default notification titles by status:

- `success`: `Codex done`
- `failure`: `Codex failure`
- `blocked`: `Codex blocked`

Do not pass `--title` unless the user explicitly asks for custom title text.

The request script starts the caffeinate guard while armed and stops it after the final armed request completes.

For a single long shell command, the wrapper can manage caffeinate and notification in one process:

```bash
"$HOME/.codex/skills/ping-me/scripts/ping_me.sh" \
  --force \
  --caffeinate \
  --agent Codex \
  -- make test
```

## Active Laptop Suppression

The script loads `~/.codex/ping-me.env` if present, checks macOS HID idle time, and skips the notification when the Mac has been idle for less than `PING_ME_MIN_IDLE_SECONDS` unless `--force` is passed.

For this skill, pass `--force`; explicit "ping me" requests should notify even if the user touched the laptop recently. The idle threshold is only for direct/manual script use where `--force` is not passed.

Defaults:

- Minimum idle time: 120 seconds
- Screen locked: notify
- Active laptop: skip quietly with a short stderr note

Use `--force` only when the user explicitly asks to notify regardless of laptop activity.

## Apple Watch Delivery

Apple Watch delivery requires a push route that reaches the paired iPhone or watch app. The script chooses transports in this order when `PING_ME_TRANSPORT=auto`:

1. Pushover, if `PING_ME_PUSHOVER_USER_KEY` and `PING_ME_PUSHOVER_API_TOKEN` are configured.
2. ntfy, if `PING_ME_NTFY_TOPIC` or `PING_ME_NTFY_URL` is configured.
3. iMessage, if `PING_ME_IMESSAGE_TARGET` is configured.
4. macOS local notification fallback.

The macOS fallback is useful on the laptop but is not a reliable Apple Watch notification. Prefer ntfy or Pushover for watch delivery.

## Useful Commands

Dry-run without sending:

```bash
"$HOME/.codex/skills/ping-me/scripts/ping_me_request.sh" arm --agent Codex --dry-run
```

Wrap an arbitrary command and preserve its exit status:

```bash
"$HOME/.codex/skills/ping-me/scripts/ping_me.sh" --force --caffeinate --agent Codex -- make test
```

Complete a dry-run armed request in tests:

```bash
"$HOME/.codex/skills/ping-me/scripts/ping_me_request.sh" complete --agent Codex --dry-run
```
