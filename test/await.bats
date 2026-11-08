#!/usr/bin/env bats
# team-await: one detached run per command line, waited for across calls, never run twice.

load helpers

setup() {
  setup_team
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  cd "$W" || return 1
  # A slow command that counts its runs and prints JSON last.
  cat >"$W/slow" <<'SH'
#!/usr/bin/env bash
echo run >>"$W/runs"
echo "log line"
sleep "${1:-2}"
echo "{\"done\": true, \"arg\": \"$1\"}"
exit "${2:-0}"
SH
  chmod +x "$W/slow"
  export W
}

await() { run --separate-stderr "$BIN/team-await" "$@"; }

@test "a run longer than the wait is pending, and the same call picks it up without running it again" {
  TEAM_AWAIT_SECONDS=1 await "$W/slow" 3
  [ "$status" -eq 0 ]
  [ "$(jq -r .team_await <<<"$output")" = pending ]
  TEAM_AWAIT_SECONDS=10 await "$W/slow" 3
  [ "$status" -eq 0 ]
  [ "$(tail -1 <<<"$output" | jq -c .)" = '{"done":true,"arg":"3"}' ]
  [ "$(wc -l <"$W/runs")" -eq 1 ]
  [ -z "$(ls "$XDG_STATE_HOME/dev-team/runs")" ]
}

@test "the command's exit code comes through, and a delivered result is not handed out again" {
  await "$W/slow" 0 7
  [ "$status" -eq 7 ]
  [[ "$output" == *'"done": true'* ]]
  await "$W/slow" 0 7
  [ "$(wc -l <"$W/runs")" -eq 2 ]
}

@test "two callers waiting at once share one run" {
  TEAM_AWAIT_SECONDS=10 "$BIN/team-await" "$W/slow" 2 >"$W/a" 2>/dev/null &
  sleep 0.5
  TEAM_AWAIT_SECONDS=10 "$BIN/team-await" "$W/slow" 2 >"$W/b" 2>/dev/null || true
  wait
  [ "$(wc -l <"$W/runs")" -eq 1 ]
  grep -q '"done": true' "$W/a" || grep -q '"done": true' "$W/b"
}

@test "different arguments or directories are different runs" {
  await "$W/slow" 0
  mkdir "$W/sub" && cd "$W/sub"
  await "$W/slow" 0
  await "$W/slow" 0 0
  [ "$(wc -l <"$W/runs")" -eq 3 ]
}

@test "a run that died without a result is started over" {
  key_dir="$XDG_STATE_HOME/dev-team/runs/dead"
  TEAM_AWAIT_SECONDS=1 await "$W/slow" 5
  d=$(ls -d "$XDG_STATE_HOME"/dev-team/runs/*)
  kill -9 "$(cat "$d/pid")" 2>/dev/null || true
  touch -d '-5 minutes' "$d"
  await "$W/slow" 0
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$W/runs")" -eq 2 ]
}
