# ping_me

`ping_me` adds completion pings for long-running agent CLI tasks on macOS. It supports Codex CLI through a Codex skill and Claude Code through a custom slash command. It keeps the Mac awake with `caffeinate` while the task runs, then sends one completion notification when the task succeeds, fails, or becomes blocked.

It is designed for Apple Watch delivery through ntfy, with Pushover, iMessage, and macOS local notification fallbacks also supported.

## Install

```bash
git clone https://github.com/blobspire/ping_me.git
cd ping_me
./install.sh
```

The installer:

- copies shared scripts to `~/.local/share/ping-me/scripts`
- creates a `ping-me` command in `~/.local/bin`
- copies the skill to `~/.codex/skills/ping-me`
- copies the Claude Code command to `~/.claude/commands/ping-me.md`
- creates `~/.config/ping-me/ping-me.env` if it does not already exist
- generates a private random ntfy topic

Install the ntfy iOS app, then subscribe to the topic URL printed by the installer. Apple Watch notifications follow the iPhone notification settings for the ntfy app.

Keep the ntfy topic private. Anyone who knows an unauthenticated public `ntfy.sh` topic can publish to it or subscribe to it.

Install only one integration:

```bash
./install.sh --codex
./install.sh --claude
```

For Claude Code, `/ping-me` works immediately after install. To also make natural language like "ping me" work across Claude Code sessions, run:

```bash
./install.sh --claude --claude-memory
```

Claude Code loads user memory when a session starts, so restart Claude Code after adding the optional memory snippet.

## Codex Use

During a Codex task, say:

```text
ping me
```

The skill starts a background `caffeinate` guard immediately. When the current task finishes, it sends a notification and stops the guard.

Notification titles:

- `Codex done`
- `Codex failure`
- `Codex blocked`

## Claude Code Use

During a Claude Code task, run:

```text
/ping-me
```

You can also pass a task reminder:

```text
/ping-me run the test suite and tell me when it finishes
```

The command starts the same background `caffeinate` guard. When the task finishes, Claude sends one notification and stops the guard.

Notification titles:

- `Claude done`
- `Claude failure`
- `Claude blocked`

## Manual Commands

Dry-run the notifier:

```bash
ping-me --force --dry-run --message "Test ping"
```

Wrap a long shell command and preserve its exit status:

```bash
ping-me --force --caffeinate --agent Codex -- make test
```

Start and stop the caffeinate guard directly:

```bash
~/.local/share/ping-me/scripts/caffeinate_guard.sh start
~/.local/share/ping-me/scripts/caffeinate_guard.sh stop
```

## Configure

Edit:

```bash
~/.config/ping-me/ping-me.env
```

Useful settings:

```bash
PING_ME_TRANSPORT=ntfy
PING_ME_NTFY_TOPIC=your-private-random-topic
PING_ME_CAFFEINATE_ARGS=-dims
PING_ME_AGENT_NAME=Codex
```

The Codex skill and Claude command call the notifier with `--force`, so explicit ping requests notify even if you were recently active on the laptop. The idle threshold only applies to direct/manual script use without `--force`.

## Notes

`caffeinate` prevents normal macOS sleep while the task is running. It may not prevent sleep from closing the laptop lid, battery exhaustion, or forced shutdown.
