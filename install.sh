#!/usr/bin/env bash
set -eu

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skill"
SKILL_DEST="$HOME/.codex/skills/ping-me"
CONFIG_DEST="$HOME/.codex/ping-me.env"
BIN_DEST="$HOME/.local/bin/ping-me"

random_topic() {
  if command -v openssl >/dev/null 2>&1; then
    printf 'codex-%s\n' "$(openssl rand -hex 18)"
  else
    printf 'codex-%s-%s\n' "$(date +%s)" "$$"
  fi
}

install_skill() {
  mkdir -p "$HOME/.codex/skills" "$HOME/.local/bin"
  rm -rf "$SKILL_DEST"
  cp -R "$SKILL_SRC" "$SKILL_DEST"
  chmod +x "$SKILL_DEST/scripts/ping_me.sh" "$SKILL_DEST/scripts/caffeinate_guard.sh"

  cat > "$BIN_DEST" <<'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.codex/skills/ping-me/scripts/ping_me.sh" "$@"
WRAPPER
  chmod +x "$BIN_DEST"
}

install_config() {
  if [ -f "$CONFIG_DEST" ]; then
    printf 'Keeping existing config: %s\n' "$CONFIG_DEST"
    return 0
  fi

  topic="$(random_topic)"
  sed "s/replace-with-your-private-random-topic/$topic/g" \
    "$REPO_DIR/ping-me.env.example" > "$CONFIG_DEST"

  printf 'Created config: %s\n' "$CONFIG_DEST"
  printf 'Subscribe to this ntfy topic in the iOS app:\n'
  printf 'https://ntfy.sh/%s\n' "$topic"
}

install_skill
install_config

printf '\nInstalled ping-me.\n'
printf 'Try a dry run:\n'
printf '  ping-me --force --dry-run --message "Test ping"\n'
