# ping_me

`ping_me` is a Codex skill for long-running Codex CLI tasks on macOS. Say `ping me`, and Codex will keep the Mac awake with `caffeinate` while it works, then send one completion notification when the task succeeds, fails, or becomes blocked.

It is designed for Apple Watch delivery through ntfy, with Pushover, iMessage, and macOS local notification fallbacks also supported.

## Install

```bash
git clone https://github.com/blobspire/ping_me.git
cd ping_me
./install.sh
```

The installer:

- copies the skill to `~/.codex/skills/ping-me`
- creates `~/.codex/ping-me.env` if it does not already exist
- generates a private random ntfy topic
- creates a `ping-me` command in `~/.local/bin`

Install the ntfy iOS app, then subscribe to the topic URL printed by the installer. Apple Watch notifications follow the iPhone notification settings for the ntfy app.

Keep the ntfy topic private. Anyone who knows an unauthenticated public `ntfy.sh` topic can publish to it or subscribe to it.

## Use

During a Codex task, say:

```text
ping me
```

The skill starts a background `caffeinate` guard immediately. When the current task finishes, it sends a notification and stops the guard.

Notification titles:

- `Codex done`
- `Codex failure`
- `Codex blocked`

## Manual Commands

Dry-run the notifier:

```bash
ping-me --force --dry-run --message "Test ping"
```

Wrap a long shell command and preserve its exit status:

```bash
ping-me --force --caffeinate -- make test
```

Start and stop the caffeinate guard directly:

```bash
~/.codex/skills/ping-me/scripts/caffeinate_guard.sh start
~/.codex/skills/ping-me/scripts/caffeinate_guard.sh stop
```

## Configure

Edit:

```bash
~/.codex/ping-me.env
```

Useful settings:

```bash
PING_ME_TRANSPORT=ntfy
PING_ME_NTFY_TOPIC=your-private-random-topic
PING_ME_CAFFEINATE_ARGS=-dims
```

The skill calls the notifier with `--force`, so explicit `ping me` requests notify even if you were recently active on the laptop. The idle threshold only applies to direct/manual script use without `--force`.

## Notes

`caffeinate` prevents normal macOS sleep while the task is running. It may not prevent sleep from closing the laptop lid, battery exhaustion, or forced shutdown.
