#!/usr/bin/env bats
# install.sh: links, idempotence, backup of real files, uninstall.

load helpers

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR
}

@test "with CLAUDE_CONFIG_DIR, install goes there and still links ~/.claude/team" {
  CLAUDE_CONFIG_DIR="$HOME/cfg" run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/cfg/team")" = "$REPO_ROOT/team" ]
  [ "$(readlink "$HOME/cfg/skills/team-dev")" = "$REPO_ROOT/skills/team-dev" ]
  [ "$(readlink "$HOME/.claude/team")" = "$REPO_ROOT/team" ]
  [ ! -e "$HOME/.claude/skills" ]
  CLAUDE_CONFIG_DIR="$HOME/cfg" run "$REPO_ROOT/install.sh" --uninstall
  [ ! -e "$HOME/cfg/team" ]; [ ! -e "$HOME/.claude/team" ]
}

@test "install links agents, skills and team/, and is idempotent" {
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude/team")" = "$REPO_ROOT/team" ]
  for s in "$REPO_ROOT"/skills/*/; do s=$(basename "$s"); [ "$(readlink "$HOME/.claude/skills/$s")" = "$REPO_ROOT/skills/$s" ]; done
  for a in "$REPO_ROOT"/agents/*.md; do [ -L "$HOME/.claude/agents/$(basename "$a")" ]; done
  run "$REPO_ROOT/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *enlazado* ]]
}

@test "install backs up real files and uninstall removes only its links" {
  mkdir -p "$HOME/.claude/skills/team-dev" "$HOME/.claude/skills/other"
  echo mine >"$HOME/.claude/skills/team-dev/SKILL.md"
  run "$REPO_ROOT/install.sh"
  [ "$(cat "$HOME"/.claude/backups/dev-team-*/team-dev/SKILL.md)" = mine ]
  run "$REPO_ROOT/install.sh" --uninstall
  [ ! -e "$HOME/.claude/team" ]
  [ ! -e "$HOME/.claude/skills/team-dev" ]
  [ -d "$HOME/.claude/skills/other" ]
}
