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

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --all             Install Codex skill and Claude Code command (default).
  --codex           Install only the Codex skill.
  --claude          Install only the Claude Code slash command.
  --claude-memory   Also append natural-language "ping me" guidance to ~/.claude/CLAUDE.md.
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

install_config() {
  mkdir -p "$(dirname "$CONFIG_DEST")"

  if [ -f "$CONFIG_DEST" ]; then
    printf 'Keeping existing config: %s\n' "$CONFIG_DEST"
    return 0
  fi

  if [ -f "$LEGACY_CODEX_CONFIG" ]; then
    cp "$LEGACY_CODEX_CONFIG" "$CONFIG_DEST"
    printf 'Copied existing Codex config to: %s\n' "$CONFIG_DEST"
    return 0
  fi

  topic="$(random_topic)"
  sed "s/replace-with-your-private-random-topic/$topic/g" \
    "$REPO_DIR/ping-me.env.example" > "$CONFIG_DEST"

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

printf '\nInstalled ping-me.\n'
printf 'Try a dry run:\n'
printf '  ping-me --force --dry-run --message "Test ping"\n'
