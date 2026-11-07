#!/usr/bin/env bats
# install.sh: links, idempotence, backup of real files, uninstall.

load helpers

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
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
