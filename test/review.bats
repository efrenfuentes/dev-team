#!/usr/bin/env bats
# team-review with a fake Codex: ids, tasks, verdict rules, gates override, security pass, reopening,
# limits and the diff base after a sync.

load helpers

setup() {
  setup_team; make_repo; make_feature demo; plan_feature
  "$BIN/team-start" "$DIR" >/dev/null
  commit_file "$WT" a.txt 1 "feat: a"
  codex_says security APPROVED
}

review() { run --separate-stderr "$BIN/team-review" "$@"; }

@test "code review: blockers and majors become R tasks, minors and human items do not" {
  codex_says code CHANGES_REQUESTED "[$(finding blocker roto),$(finding minor estilo),$(finding human probar),$(finding major borde)]"
  review code "$DIR" 1
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.verdict, .blocking, .minor, .human]' <<<"$output")" = '["CHANGES_REQUESTED",2,1,1]' ]
  [ "$(jq -c '[.findings[].id]' "$DIR/reviews/code-1.json")" = '["R1-01","R1-02","R1-03","R1-04"]' ]
  grep -qF -- '- [ ] R1-01 [blocker] hacer roto (`lib/a.ex:1`)' "$DIR/tasks.md"
  grep -qF -- '- [ ] R1-04 [major] hacer borde' "$DIR/tasks.md"
  ! grep -q 'R1-02\|R1-03' "$DIR/tasks.md"
  grep -q '## Iteración 1/6' "$DIR/review-report.md"
  grep -q 'Requiere a una persona' "$DIR/review-report.md"
}

@test "an APPROVED with an open blocker is downgraded" {
  codex_says code APPROVED "[$(finding blocker roto)]"
  review code "$DIR" 1
  [ "$(jq -r .verdict <<<"$output")" = CHANGES_REQUESTED ]
  [ "$(jq -r .model_verdict "$DIR/reviews/code-1.json")" = APPROVED ]
}

@test "failing gates can never be approved" {
  echo '{"passed": false}' >"$DIR/gates/iter-1.json"
  codex_says code APPROVED
  review code "$DIR" 1
  [ "$(jq -r .verdict <<<"$output")" = CHANGES_REQUESTED ]
  [ "$(jq -r '.findings[-1].id' "$DIR/reviews/code-1.json")" = R1-G1 ]
  grep -q 'gates: false' "$DIR/review-report.md"
}

@test "the security pass runs on the first review only and its findings are R1-SNN" {
  codex_says security CHANGES_REQUESTED "[$(finding blocker idor)]"
  codex_says code APPROVED
  review code "$DIR" 1
  [ "$(jq -c '[.verdict, .blocking]' <<<"$output")" = '["CHANGES_REQUESTED",1]' ]
  [ "$(jq -r '.findings[0].id' "$DIR/reviews/code-1.json")" = R1-S01 ]
  [ "$(find "$FAKE_DIR/prompts" -name '*-security.md' | wc -l)" -eq 1 ]

  commit_file "$WT" b.txt 2 "fix: idor"
  codex_says code APPROVED "[]" '[{"id":"R1-S01","status":"resolved","note":"ok"}]'
  review code "$DIR" 2
  [ "$(jq -r .verdict <<<"$output")" = APPROVED ]
  [ "$(find "$FAKE_DIR/prompts" -name '*-security.md' | wc -l)" -eq 1 ]
}

@test "a failed security pass leaves a human finding instead of failing the review" {
  codex_says code APPROVED
  FAKE_CODEX_FAIL=security review code "$DIR" 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.findings[] | select(.id == "R1-S00") | .severity' "$DIR/reviews/code-1.json")" = human ]
}

@test "TEAM_SECURITY_REVIEW=0 skips the security pass" {
  codex_says code APPROVED
  TEAM_SECURITY_REVIEW=0 review code "$DIR" 1
  [ -z "$(find "$FAKE_DIR/prompts" -name '*-security.md')" ]
}

@test "an unresolved previous finding reopens its task with the note, once" {
  codex_says code CHANGES_REQUESTED "[$(finding blocker roto)]"
  review code "$DIR" 1
  sed -i 's/- \[ \] R1-01/- [x] R1-01/' "$DIR/tasks.md"
  commit_file "$WT" b.txt 2 "fix: intento"
  codex_says code CHANGES_REQUESTED "[]" '[{"id":"R1-01","status":"unresolved","note":"falta el caso nil"}]'
  review code "$DIR" 2
  [ "$(jq -c '[.verdict, .unresolved_previous]' <<<"$output")" = '["CHANGES_REQUESTED",1]' ]
  grep -qF -- '- [ ] R1-01 [blocker] hacer roto (`lib/a.ex:1`) · reabierta en revisión 2: falta el caso nil' "$DIR/tasks.md"
  [ "$(grep -c 'R1-01' "$DIR/tasks.md")" -eq 1 ]
  # The prompt lists it as still open.
  grep -q '\*\*R1-01\*\* \[blocker\] roto' "$(find "$FAKE_DIR/prompts" -name '*-code.md' | sort -V | tail -1)"
}

@test "the review limit follows review_budget" {
  codex_says code APPROVED
  review code "$DIR" 7
  [ "$status" -ne 0 ]
  [[ "$(jq -r .error <<<"$output")" == *"exceeds the limit of 6"* ]]
  jq '.review_budget = 8' "$DIR/state.json" >s && mv s "$DIR/state.json"
  review code "$DIR" 7
  [ "$status" -eq 0 ]
  grep -q 'Iteración 7/8' "$DIR/review-report.md"
}

@test "after a sync the next review measures its iteration from the synced head" {
  codex_says code CHANGES_REQUESTED "[$(finding major x)]"
  review code "$DIR" 1
  jq '.syncs = [{after_review: 1, to_head: "abc1234"}]' "$DIR/state.json" >s && mv s "$DIR/state.json"
  codex_says code APPROVED "[]" '[{"id":"R1-01","status":"resolved","note":"ok"}]'
  review code "$DIR" 2
  grep -q 'git diff abc1234\.\.' "$(find "$FAKE_DIR/prompts" -name '*-code.md' | sort -V | tail -1)"
}

@test "a Codex failure is an ERROR verdict and writes nothing" {
  FAKE_CODEX_FAIL=code review code "$DIR" 1
  [ "$status" -ne 0 ]
  [ "$(jq -r .verdict <<<"$output")" = ERROR ]
  [ ! -f "$DIR/reviews/code-1.json" ]
}

@test "plan review writes P ids and plan-review.md; final writes final-report.md" {
  codex_says plan CHANGES_REQUESTED "[$(finding major hueco)]"
  review plan "$DIR" 1
  [ "$(jq -r '.findings[0].id' "$DIR/reviews/plan-1.json")" = P1-01 ]
  grep -q '## Ronda 1' "$DIR/plan-review.md"

  echo '# Informe final de prueba' >"$FAKE_DIR/codex-final.md"
  review final "$DIR" 1 approved
  [ "$(jq -r .verdict <<<"$output")" = REPORTED ]
  [ "$(cat "$DIR/final-report.md")" = '# Informe final de prueba' ]
}
