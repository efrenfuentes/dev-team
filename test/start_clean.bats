#!/usr/bin/env bats
# team-start (preflight, resume, finish, reset, respond rounds) and team-clean.

load helpers

setup() { setup_team; make_repo; make_feature demo; plan_feature; }

start() { run --separate-stderr "$BIN/team-start" "$DIR" "$@"; }

@test "team-start records base_sha and starts at iteration 1" {
  start
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.ok, .start_iter, .max_iter, .finished, .worktree]' <<<"$output")" = "[true,1,6,false,\"$WT\"]" ]
  [ "$(jq -r .base_sha "$DIR/state.json")" = "$(git rev-parse origin/main)" ]
}

@test "team-start refuses a dirty worktree, a wrong branch and a missing plan" {
  echo x >"$WT/dirty.txt"
  start
  [ "$status" -ne 0 ]; [[ "$(jq -r .error <<<"$output")" == "working tree is not clean"* ]]
  rm "$WT/dirty.txt"

  git -C "$WT" switch -q -c other
  start
  [[ "$(jq -r .error <<<"$output")" == *"not on the feature branch 'feat/demo'"* ]]
  git -C "$WT" switch -q feat/demo

  rm "$DIR/plan.md"
  start
  [[ "$(jq -r .error <<<"$output")" == "missing plan.md"* ]]
}

@test "team-start resumes after the last review and stops when approved or out of reviews" {
  write_review 1 CHANGES_REQUESTED
  start; [ "$(jq -c '[.start_iter, .finished]' <<<"$output")" = '[2,false]' ]
  write_review 2 APPROVED
  start; [ "$(jq -r .finished <<<"$output")" = true ]
  rm "$DIR/reviews/code-2.json"
  for i in 2 3 4 5 6; do write_review $i CHANGES_REQUESTED; done
  start; [ "$(jq -c '[.start_iter, .finished]' <<<"$output")" = '[7,true]' ]
}

@test "team-start keeps base_sha once recorded, even after the base moves" {
  start
  first=$(jq -r .base_sha "$DIR/state.json")
  advance_base other.txt x
  start
  [ "$(jq -r .base_sha "$DIR/state.json")" = "$first" ]
}

@test "a pending respond round reopens an approved loop with the raised budget" {
  write_review 1 CHANGES_REQUESTED; write_review 2 APPROVED
  jq '.review_budget = 8 | .respond.pending = {round: 1, from_iter: 3}' "$DIR/state.json" >s && mv s "$DIR/state.json"
  start
  [ "$(jq -c '[.start_iter, .max_iter, .finished]' <<<"$output")" = '[3,8,false]' ]
  write_review 3 APPROVED
  start
  [ "$(jq -r .finished <<<"$output")" = true ]
}

@test "a review_budget below the default never lowers the limit" {
  jq '.review_budget = 2' "$DIR/state.json" >s && mv s "$DIR/state.json"
  start
  [ "$(jq -r .max_iter <<<"$output")" = 6 ]
}

@test "--reset archives the loop, strips reviewer corrections and keeps PR comment tasks" {
  plan_feature "$(printf '%s\n' '# Tareas' '' '- [x] T1 algo' '' '## Correcciones — revisión 1' '' '- [x] R1-01 arreglo' \
    '' '## Comentarios de la PR — ronda 1' '' '- [ ] H1-01 pedido' '' '## Correcciones — revisión 2' '' '- [ ] R2-01 otro')"
  write_review 1 CHANGES_REQUESTED; write_review 2 APPROVED
  echo log >"$DIR/dev-log.md"; echo r >"$DIR/review-report.md"
  jq '.review_budget = 4 | .respond.pending = {round: 1, from_iter: 3}' "$DIR/state.json" >s && mv s "$DIR/state.json"
  start --reset
  [ "$(jq -c '[.start_iter, .max_iter, .finished]' <<<"$output")" = '[1,6,false]' ]
  [ -z "$(find "$DIR/reviews" -name 'code-*')" ]
  [ -f "$(find "$DIR/archive" -name dev-log.md)" ]
  [ "$(cat "$DIR/tasks.md")" = "$(printf '%s\n' '# Tareas' '' '- [x] T1 algo' '' '## Comentarios de la PR — ronda 1' '' '- [ ] H1-01 pedido')" ]
  [ "$(jq -c '[.review_budget, .respond.pending]' "$DIR/state.json")" = '[null,null]' ]
}

@test "team-clean removes the worktree and keeps the branch; team-start recreates it" {
  run --separate-stderr "$BIN/team-clean" "$DIR"
  [ "$(jq -c '[.ok, .removed, .branch_kept]' <<<"$output")" = '[true,true,"feat/demo"]' ]
  [ ! -d "$WT" ]
  git show-ref --verify -q refs/heads/feat/demo
  run --separate-stderr "$BIN/team-status" --json
  [[ "$(jq -r '.[0].worktree' <<<"$output")" == *"(removed)" ]]

  start
  [ "$(jq -r .ok <<<"$output")" = true ]
  [ "$(git -C "$WT" branch --show-current)" = feat/demo ]
}

@test "team-clean refuses a dirty worktree unless --force" {
  echo x >"$WT/dirty.txt"
  run --separate-stderr "$BIN/team-clean" "$DIR"
  [ "$status" -ne 0 ]
  [ -d "$WT" ]
  run --separate-stderr "$BIN/team-clean" "$DIR" --force
  [ "$(jq -r .removed <<<"$output")" = true ]
}
