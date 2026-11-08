#!/usr/bin/env bats
# Stack detection, gate script lookup, and the default stack gates (with fake tools).

load helpers

setup() {
  setup_team; make_repo; make_feature demo
  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  export PATH="$FAKE_BIN:$PATH"
}

# A fake tool that logs its arguments to $FAKE_DIR/tools.log and exits with $FAKE_<TOOL>_EXIT
# (0 by default) or, for "<tool> run <script>", with $FAKE_<TOOL>_<SCRIPT>_EXIT.
fake_tool() { # <name>
  cat >"$FAKE_BIN/$1" <<'SH'
#!/usr/bin/env bash
tool=$(basename "$0")
echo "$tool $*" >>"$FAKE_DIR/tools.log"
up() { tr '[:lower:]:-' '[:upper:]__' <<<"$1"; }
var="FAKE_$(up "$tool")_EXIT"
[ "${1:-}" = run ] && [ -n "${2:-}" ] && var="FAKE_$(up "$tool")_$(up "$2")_EXIT"
exit "${!var:-0}"
SH
  chmod +x "$FAKE_BIN/$1"
}

stack_of() { run bash -c ". \"\$HOME/.claude/team/lib.sh\"; team_stack \"\$1\"" _ "$1"; }

@test "team_stack detects each stack by its marker file, Ruby before Node" {
  d="$W/s"
  mkdir -p "$d"
  stack_of "$d"; [ "$status" -ne 0 ]
  touch "$d/package.json"; stack_of "$d"; [ "$output" = node ]
  touch "$d/requirements.txt"; stack_of "$d"; [ "$output" = python ]
  touch "$d/Cargo.toml"; stack_of "$d"; [ "$output" = rust ]
  touch "$d/go.mod"; stack_of "$d"; [ "$output" = go ]
  touch "$d/Gemfile"; stack_of "$d"; [ "$output" = ruby ]
  touch "$d/mix.exs"; stack_of "$d"; [ "$output" = elixir ]
}

@test "every stack has default gates and a setup" {
  for s in elixir ruby go rust python node; do
    [ -x "$REPO_ROOT/team/gates/stacks/$s.sh" ]
    [ -x "$REPO_ROOT/team/setup/stacks/$s.sh" ]
  done
}

@test "gates lookup: the project's script, then the repo's, then the stack's, unless turned off" {
  run --separate-stderr "$BIN/team-gates" "$DIR" --which
  [ "$(jq -c '[.configured, .source, .stack]' <<<"$output")" = '[false,null,null]' ]

  echo '{}' >"$WT/package.json"
  run --separate-stderr "$BIN/team-gates" "$DIR" --which
  [ "$(jq -c '[.configured, .source, .stack]' <<<"$output")" = '[true,"stack","node"]' ]
  [[ "$(jq -r .script <<<"$output")" == */gates/stacks/node.sh ]]

  TEAM_STACK_GATES=0 run --separate-stderr "$BIN/team-gates" "$DIR" --which
  [ "$(jq -c '[.configured, .source]' <<<"$output")" = '[false,null]' ]

  printf '#!/usr/bin/env bash\nexit 0\n' >"$W/repo/.team/gates.sh"
  run --separate-stderr "$BIN/team-gates" "$DIR" --which
  [ "$(jq -c '[.source, .script]' <<<"$output")" = "[\"project\",\"$W/repo/.team/gates.sh\"]" ]
}

@test "node gates run the project's scripts with its package manager and report every failure" {
  fake_tool pnpm
  touch "$WT/pnpm-lock.yaml"
  jq -n '{scripts: {"format:check": "prettier -c .", lint: "eslint .", "type-check": "tsc", test: "vitest"}}' >"$WT/package.json"
  FAKE_PNPM_LINT_EXIT=1 FAKE_PNPM_TEST_EXIT=2 run --separate-stderr "$BIN/team-gates" "$DIR" 1
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.passed, .configured, .source, .exit_code]' <<<"$output")" = '[false,true,"stack",1]' ]
  [ "$(cat "$FAKE_DIR/tools.log")" = "$(printf '%s\n' 'pnpm run format:check' 'pnpm run lint' 'pnpm run type-check' 'pnpm run test')" ]
  log="$DIR/gates/iter-1.log"
  grep -q '== FAILED gates: lint test' "$log"
  grep -q '== ok: typecheck' "$log"
}

@test "node gates skip what the project lacks, including npm's placeholder test" {
  fake_tool npm
  jq -n '{scripts: {lint: "eslint .", test: "echo \"Error: no test specified\" && exit 1"}}' >"$WT/package.json"
  run --separate-stderr "$BIN/team-gates" "$DIR"
  [ "$(jq -r .passed <<<"$output")" = true ]
  [ "$(cat "$FAKE_DIR/tools.log")" = 'npm run lint' ]
  log="$DIR/gates/check.log"
  grep -q '== skip: format (no script: ' "$log"
  grep -q '== skip: test (placeholder "test" script)' "$log"
  grep -q '== OK: all gates passed' "$log"
}

@test "python gates run only the configured tools, and no collected tests is not a failure" {
  fake_tool ruff; fake_tool pytest; fake_tool mypy
  printf '[project]\nname = "x"\n\n[tool.ruff]\nline-length = 100\n' >"$WT/pyproject.toml"
  mkdir "$WT/tests"
  FAKE_PYTEST_EXIT=5 run --separate-stderr "$BIN/team-gates" "$DIR"
  [ "$(jq -r .passed <<<"$output")" = true ]
  [ "$(cat "$FAKE_DIR/tools.log")" = "$(printf '%s\n' 'ruff check .' 'ruff format --check .' 'pytest -q')" ]
  grep -q '== skip: mypy (not configured)' "$DIR/gates/check.log"
  grep -q '(no tests collected)' "$DIR/gates/check.log"
}

@test "elixir gates run credo only when it is a dependency" {
  fake_tool mix
  printf 'defp deps, do: [{:phoenix, "~> 1.8"}, {:credo, "~> 1.7", only: :dev}]\n' >"$WT/mix.exs"
  FAKE_MIX_EXIT=0 run --separate-stderr "$BIN/team-gates" "$DIR"
  [ "$(jq -r .passed <<<"$output")" = true ]
  [ "$(cat "$FAKE_DIR/tools.log")" = "$(printf '%s\n' 'mix compile --warnings-as-errors --force' \
    'mix format --check-formatted' 'mix credo --strict' 'mix test --warnings-as-errors')" ]
  grep -q '== skip: sobelow (not a dependency)' "$DIR/gates/check.log"
}

@test "setup uses the stack's default setup for the new stacks" {
  fake_tool go
  touch "$WT/go.mod"
  run --separate-stderr "$BIN/team-setup" "$DIR"
  [ "$(jq -r .ok <<<"$output")" = true ]
  [[ "$(jq -r .script <<<"$output")" == */setup/stacks/go.sh ]]
  [ "$(cat "$FAKE_DIR/tools.log")" = 'go mod download' ]
}
