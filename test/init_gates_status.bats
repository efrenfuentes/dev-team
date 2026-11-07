#!/usr/bin/env bats
# team-init, team-config, team-gates, team-exec and team-status.

load helpers

setup() { setup_team; make_repo; }

@test "team-init creates the workspace, the worktree on a new branch and the state" {
  make_feature demo
  [ "$DIR" = "$W/repo/.team/001-demo" ]
  [ "$WT" = "$W/repo.worktrees/001-demo" ]
  [ "$(git -C "$WT" branch --show-current)" = "feat/demo" ]
  [ -z "$(git -C "$WT" config "branch.feat/demo.merge" || true)" ]   # --no-track
  run jq -c '{feature, base_ref, branch, partition, setup: .setup.ok}' "$DIR/state.json"
  [ "$output" = '{"feature":"demo","base_ref":"origin/main","branch":"feat/demo","partition":101,"setup":true}' ]
  grep -qxF '.team/' .git/info/exclude
  [ -z "$(git status --porcelain)" ]
}

@test "team-init numbers features and refuses an existing branch" {
  make_feature one
  make_feature two
  [ "$(basename "$DIR")" = "002-two" ]
  [ "$(jq .partition "$DIR/state.json")" = 102 ]
  run "$BIN/team-init" two
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "team-init with TEAM_WORKTREES=0 works in the main checkout" {
  TEAM_WORKTREES=0 make_feature legacy
  [ "$(jq -r '.worktree // "none"' "$DIR/state.json")" = none ]
  [ "$(git branch --show-current)" = main ]
}

@test "team-config prints the limits, models and the plan resume point" {
  run --separate-stderr env TEAM_MAX_CODE_REVIEWS=4 TEAM_GATE_FIX_ROUNDS=1 "$BIN/team-config"
  [ "$(jq -c '[.max_code_reviews, .gate_fix_rounds, .developer.model]' <<<"$output")" = '[4,1,"opus"]' ]
  make_feature demo
  mkdir -p "$DIR/reviews"
  echo '{"verdict":"CHANGES_REQUESTED"}' >"$DIR/reviews/plan-1.json"
  run --separate-stderr "$BIN/team-config" "$DIR"
  [ "$(jq -c '[.next_plan_round, .plan_approved]' <<<"$output")" = '[2,false]' ]
}

@test "team-gates without a gate script passes as not configured" {
  make_feature demo
  run --separate-stderr "$BIN/team-gates" "$DIR" 1
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.passed, .configured]' <<<"$output")" = '[true,false]' ]
}

@test "team-gates runs the project script in the worktree with the feature env" {
  make_feature demo
  cat >.team/gates.sh <<'SH'
echo "pwd=$PWD partition=$TEAM_PARTITION mix=$MIX_TEST_PARTITION base=$BASE_REF"
[ -f fail ] && exit 3
exit 0
SH
  run --separate-stderr "$BIN/team-gates" "$DIR" 1
  [ "$(jq -r .passed <<<"$output")" = true ]
  grep -q "pwd=$WT partition=101 mix=101 base=origin/main" "$DIR/gates/iter-1.log"

  touch "$WT/fail"
  run --separate-stderr "$BIN/team-gates" "$DIR" 1
  [ "$(jq -c '[.passed, .exit_code]' <<<"$output")" = '[false,3]' ]
}

@test "team-gates keeps earlier official runs of an iteration as try-K" {
  make_feature demo
  echo 'exit 1' >.team/gates.sh
  "$BIN/team-gates" "$DIR" 2 >/dev/null
  "$BIN/team-gates" "$DIR" 2 >/dev/null
  echo 'exit 0' >.team/gates.sh
  "$BIN/team-gates" "$DIR" 2 >/dev/null
  [ "$(jq .passed "$DIR/gates/iter-2.json")" = true ]
  [ "$(jq .passed "$DIR/gates/iter-2-try-1.json")" = false ]
  [ "$(jq .passed "$DIR/gates/iter-2-try-2.json")" = false ]
  [ -f "$DIR/gates/iter-2-try-2.log" ]
  # The Developer's own check never rotates.
  "$BIN/team-gates" "$DIR" >/dev/null
  "$BIN/team-gates" "$DIR" >/dev/null
  [ -f "$DIR/gates/check.json" ]
  [ -z "$(find "$DIR/gates" -name 'check-try-*')" ]
}

@test "team-gates serialized by the marker file still runs and passes" {
  make_feature demo
  echo 'exit 0' >.team/gates.sh
  touch .team/serialize-gates
  run --separate-stderr "$BIN/team-gates" "$DIR" 1
  [ "$(jq -r .passed <<<"$output")" = true ]
  grep -q 'waiting for the gates lock' "$DIR/gates/iter-1.log"
}

@test "team-exec runs in the worktree with the feature env" {
  make_feature demo
  run "$BIN/team-exec" "$DIR" bash -c 'echo "$PWD $TEAM_PARTITION $(git branch --show-current)"'
  [ "$output" = "$WT 101 feat/demo" ]
}

@test "team-status shows each phase, the budget and the PR" {
  make_feature planning
  make_feature planned;   plan_feature
  make_feature developing; plan_feature; write_review 1 CHANGES_REQUESTED
  make_feature approved;  plan_feature; write_review 1 APPROVED
  jq '.pr.url = "https://github.com/o/r/pull/12"' "$DIR/state.json" >s && mv s "$DIR/state.json"
  make_feature incomplete; plan_feature; for i in 1 2 3 4 5 6; do write_review $i CHANGES_REQUESTED; done
  make_feature responding; plan_feature; write_review 1 APPROVED
  jq '.review_budget = 8 | .respond.pending = {round: 1, from_iter: 2}' "$DIR/state.json" >s && mv s "$DIR/state.json"

  run --separate-stderr "$BIN/team-status" --json
  [ "$(jq -c 'map(.phase)' <<<"$output")" = '["planning","planned","developing","approved","incomplete","responding"]' ]
  [ "$(jq -c '.[5].code.max, .[3].pr' <<<"$output" | tr '\n' ' ')" = '8 "https://github.com/o/r/pull/12" ' ]

  run --separate-stderr "$BIN/team-status"
  [[ "$output" == *"004-approved"*"#12"* ]]
}
