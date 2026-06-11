#!/usr/bin/env bash
set -eu

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skill"
SCRIPT_SRC="$SKILL_SRC/scripts"
CLAUDE_COMMAND_SRC="$REPO_DIR/claude/commands/ping-me.md"
CLAUDE_MEMORY_SNIPPET="$REPO_DIR/claude/CLAUDE.md.snippet"
SKILL_DEST="$HOME/.codex/skills/ping-me"
SCRIPT_DEST="$HOME/.local/share/ping-me/scripts"
CLAUDE_COMMAND_DEST="$HOME/.claude/commands/ping-me.md"
CLAUDE_MEMORY_DEST="$HOME/.claude/CLAUDE.md"
CONFIG_DEST="$HOME/.config/ping-me/ping-me.env"
LEGACY_CODEX_CONFIG="$HOME/.codex/ping-me.env"
BIN_DEST="$HOME/.local/bin/ping-me"
install_codex=1
install_claude=1
install_claude_memory=0
install_claude_hook=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --all             Install Codex skill and Claude Code command (default).
  --codex           Install only the Codex skill.
  --claude          Install only the Claude Code slash command.
  --claude-memory   Also append natural-language "ping me" guidance to ~/.claude/CLAUDE.md.
  --claude-hook     Also wire a Claude Code Stop hook so pings complete automatically.
  --help            Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      install_codex=1
      install_claude=1
      shift
      ;;
    --codex)
      install_codex=1
      install_claude=0
      shift
      ;;
    --claude)
      install_codex=0
      install_claude=1
      shift
      ;;
    --claude-memory)
      install_claude=1
      install_claude_memory=1
      shift
      ;;
    --claude-hook)
      install_claude=1
      install_claude_hook=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

random_topic() {
  if command -v openssl >/dev/null 2>&1; then
    printf 'ping-me-%s\n' "$(openssl rand -hex 18)"
  else
    printf 'ping-me-%s-%s\n' "$(date +%s)" "$$"
  fi
}

install_scripts() {
  mkdir -p "$SCRIPT_DEST" "$HOME/.local/bin"
  cp "$SCRIPT_SRC"/*.sh "$SCRIPT_DEST/"
  chmod +x "$SCRIPT_DEST"/*.sh

  cat > "$BIN_DEST" <<'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.local/share/ping-me/scripts/ping_me.sh" "$@"
WRAPPER
  chmod +x "$BIN_DEST"
}

install_codex_skill() {
  mkdir -p "$HOME/.codex/skills"
  rm -rf "$SKILL_DEST"
  cp -R "$SKILL_SRC" "$SKILL_DEST"
  chmod +x "$SKILL_DEST"/scripts/*.sh
  printf 'Installed Codex skill: %s\n' "$SKILL_DEST"
}

install_claude_command() {
  mkdir -p "$(dirname "$CLAUDE_COMMAND_DEST")"
  cp "$CLAUDE_COMMAND_SRC" "$CLAUDE_COMMAND_DEST"
  printf 'Installed Claude Code command: %s\n' "$CLAUDE_COMMAND_DEST"
}

install_claude_memory_snippet() {
  mkdir -p "$(dirname "$CLAUDE_MEMORY_DEST")"
  touch "$CLAUDE_MEMORY_DEST"

  if grep -q '<!-- ping-me:start -->' "$CLAUDE_MEMORY_DEST"; then
    printf 'Claude memory already contains ping-me guidance: %s\n' "$CLAUDE_MEMORY_DEST"
    return 0
  fi

  {
    printf '\n'
    cat "$CLAUDE_MEMORY_SNIPPET"
    printf '\n'
  } >> "$CLAUDE_MEMORY_DEST"

  printf 'Added Claude natural-language guidance: %s\n' "$CLAUDE_MEMORY_DEST"
}

install_claude_stop_hook() {
  settings="$HOME/.claude/settings.json"
  hook_cmd="$SCRIPT_DEST/claude_stop_hook.sh"

  mkdir -p "$(dirname "$settings")"

  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 not found; cannot auto-wire the Claude Stop hook.\n' >&2
    printf 'Add a Stop hook in %s that runs: %s\n' "$settings" "$hook_cmd" >&2
    return 0
  fi

  PING_ME_SETTINGS="$settings" PING_ME_HOOK_CMD="$hook_cmd" python3 - <<'PY'
import json, os, sys

settings = os.environ["PING_ME_SETTINGS"]
cmd = os.environ["PING_ME_HOOK_CMD"]

try:
    with open(settings) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except json.JSONDecodeError:
    sys.stderr.write("ping-me: %s is not valid JSON; leaving it unchanged.\n" % settings)
    sys.exit(0)

if not isinstance(data, dict):
    sys.stderr.write("ping-me: %s is not a JSON object; leaving it unchanged.\n" % settings)
    sys.exit(0)

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    sys.stderr.write("ping-me: hooks in %s is not an object; leaving it unchanged.\n" % settings)
    sys.exit(0)
stop = hooks.setdefault("Stop", [])
if not isinstance(stop, list):
    sys.stderr.write("ping-me: hooks.Stop in %s is not a list; leaving it unchanged.\n" % settings)
    sys.exit(0)

for group in stop:
    if isinstance(group, dict):
        for h in group.get("hooks", []):
            if isinstance(h, dict) and str(h.get("command", "")).endswith("claude_stop_hook.sh"):
                print("Claude Stop hook already configured: %s" % settings)
                sys.exit(0)

stop.append({"hooks": [{"type": "command", "command": cmd}]})
tmp = settings + ".ping-me.tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, settings)
print("Wired Claude Stop hook into %s" % settings)
PY
}

install_config() {
  mkdir -p "$(dirname "$CONFIG_DEST")"

  if [ -f "$CONFIG_DEST" ]; then
    # The config can hold ntfy/Pushover credentials, so keep it private even
    # if an earlier install left it world-readable.
    chmod 600 "$CONFIG_DEST" 2>/dev/null || true
    printf 'Keeping existing config: %s\n' "$CONFIG_DEST"
    return 0
  fi

  if [ -f "$LEGACY_CODEX_CONFIG" ]; then
    cp "$LEGACY_CODEX_CONFIG" "$CONFIG_DEST"
    chmod 600 "$CONFIG_DEST"
    printf 'Copied existing Codex config to: %s\n' "$CONFIG_DEST"
    return 0
  fi

  topic="$(random_topic)"
  # umask 077 so the file is never briefly world-readable while the topic is
  # written; chmod 600 afterward makes the private mode explicit.
  (umask 077; sed "s/replace-with-your-private-random-topic/$topic/g" \
    "$REPO_DIR/ping-me.env.example" > "$CONFIG_DEST")
  chmod 600 "$CONFIG_DEST"

  printf 'Created config: %s\n' "$CONFIG_DEST"
  printf 'Subscribe to this ntfy topic in the iOS app:\n'
  printf 'https://ntfy.sh/%s\n' "$topic"
}

install_scripts
install_config

if [ "$install_codex" -eq 1 ]; then
  install_codex_skill
fi

if [ "$install_claude" -eq 1 ]; then
  install_claude_command
fi

if [ "$install_claude_memory" -eq 1 ]; then
  install_claude_memory_snippet
fi

if [ "$install_claude_hook" -eq 1 ]; then
  install_claude_stop_hook
fi

printf '\nInstalled ping-me.\n'
printf 'Try a dry run:\n'
printf '  ping-me --force --dry-run --message "Test ping"\n'
