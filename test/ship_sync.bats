#!/usr/bin/env bats
# team-ship (fake gh) and team-sync.

load helpers

setup() { setup_team; make_repo; make_feature demo; plan_feature; "$BIN/team-start" "$DIR" >/dev/null; }

ship() { run --separate-stderr "$BIN/team-ship" "$DIR" "$@"; }
sync() { run --separate-stderr "$BIN/team-sync" "$DIR" "$@"; }

# ---------------------------------------------------------------- team-ship

@test "ship --check refuses a branch without commits, a dirty worktree and a missing gh login" {
  ship --check
  [[ "$(jq -r .error <<<"$output")" == *"has no commits over origin/main"* ]]
  commit_file "$WT" a.txt 1 "feat: a"
  echo x >"$WT/dirty.txt"
  ship --check
  [[ "$(jq -r .error <<<"$output")" == "the worktree has uncommitted changes"* ]]
  rm "$WT/dirty.txt"
  FAKE_GH_AUTH=0 ship --check
  [[ "$(jq -r .error <<<"$output")" == "gh is not authenticated"* ]]
}

@test "ship --check writes pr-body.md from the final report, manual checks and commits" {
  commit_file "$WT" a.txt 1 "feat(x): export csv"
  write_review 1 APPROVED
  printf '%s\n' '# Informe' '## Resumen' 'Se agregó el export.' '## Qué se implementó' '- RF-01 en `a.txt`' \
    '## Pendiente para una persona' '- Probar con un archivo real' '## Hallazgos menores' '- nada' >"$DIR/final-report.md"
  printf '%s\n' '- [x] T1 algo' '' '## Verificación manual (persona)' '- Revisar en Excel' >"$DIR/tasks.md"
  ship --check
  [ "$(jq -c '[.ok, .remote, .base, .commits, .status, .title, .existing_pr]' <<<"$output")" = \
    '[true,"origin","main",1,"approved","Feature de prueba",null]' ]
  body=$(cat "$DIR/pr-body.md")
  [[ "$body" == *"Se agregó el export."* ]]
  [[ "$body" == *"- [ ] Probar con un archivo real"* ]]
  [[ "$body" != *"Revisar en Excel"* ]]   # tasks.md's checks are only the fallback
  [[ "$body" == *"feat(x): export csv"* ]]
  [[ "$body" == *"Aprobado por el Reviewer"* ]]
  [[ "$body" != *"nada"* ]]
  # An edited body is never overwritten.
  echo "mío" >"$DIR/pr-body.md"
  ship --check
  [ "$(cat "$DIR/pr-body.md")" = "mío" ]
}

@test "ship joins wrapped and numbered checklist items and strips local paths" {
  commit_file "$WT" a.txt 1 "feat: a"
  write_review 1 APPROVED
  printf '%s\n' '## Resumen' "Ver [router.ex]($WT/lib/router.ex) y $DIR/spec.md." \
    '## Pendiente para una persona' '' \
    '1. **Antes de fusionar:** arrancar el servidor y probar' '   el ciclo completo con curl.' \
    '2. Confirmar en la PR que es público.' '' 'Además, un párrafo suelto.' '## Otra' >"$DIR/final-report.md"
  printf '%s\n' '## Verificación manual (persona)' '- Algo de tasks.md' >"$DIR/tasks.md"
  ship --check
  body=$(cat "$DIR/pr-body.md")
  [[ "$body" == *"- [ ] **Antes de fusionar:** arrancar el servidor y probar el ciclo completo con curl."* ]]
  [[ "$body" == *"- [ ] Confirmar en la PR que es público."* ]]
  [[ "$body" != *"párrafo suelto"* ]]
  [[ "$body" != *"Algo de tasks.md"* ]]          # the report already covers tasks.md
  [[ "$body" == *"Ver router.ex y .team/001-demo/spec.md."* ]]
  [[ "$body" != *"$W"* ]]
}

@test "ship falls back to tasks.md's manual checks without a final report" {
  commit_file "$WT" a.txt 1 "feat: a"
  printf '%s\n' '## Verificación manual (persona)' '' '- Probar con un cliente' '  real y largo.' >"$DIR/tasks.md"
  ship --check
  grep -qxF -- '- [ ] Probar con un cliente real y largo.' "$DIR/pr-body.md"
}

@test "ship marks an unapproved cycle in the body" {
  commit_file "$WT" a.txt 1 "feat: a"
  for i in 1 2 3 4 5 6; do write_review $i CHANGES_REQUESTED; done
  ship --check
  [ "$(jq -r .status <<<"$output")" = incomplete ]
  grep -q 'sin aprobación' "$DIR/pr-body.md"
}

@test "ship --push pushes, opens the PR once and records it; later pushes reuse it" {
  commit_file "$WT" a.txt 1 "feat: a"
  ship --check
  ship --push --draft --title "feat: título"
  [ "$(jq -c '[.pr_url, .pr_created, .draft]' <<<"$output")" = '["https://github.com/o/r/pull/7",true,true]' ]
  [ "$(git -C "$W/remote.git" rev-parse feat/demo)" = "$(git -C "$WT" rev-parse HEAD)" ]
  grep -q "pr create --base main --head feat/demo --title feat:\\\\ t" "$FAKE_DIR/gh.log"
  grep -q -- '--draft' "$FAKE_DIR/gh.log"
  [ "$(jq -r .pr.url "$DIR/state.json")" = https://github.com/o/r/pull/7 ]

  commit_file "$WT" b.txt 2 "fix: b"
  ship --push
  [ "$(jq -r .pr_created <<<"$output")" = false ]
  [ "$(grep -c 'pr create' "$FAKE_DIR/gh.log")" -eq 1 ]
  [ "$(git -C "$W/remote.git" rev-parse feat/demo)" = "$(git -C "$WT" rev-parse HEAD)" ]
}

# ---------------------------------------------------------------- team-sync

@test "sync: already up to date" {
  sync start
  [ "$(jq -r .status <<<"$output")" = up_to_date ]
}

@test "sync: an unpushed branch is rebased, base_sha moves, setup and gates run" {
  echo 'echo gates; exit 0' >.team/gates.sh
  commit_file "$WT" a.txt 1 "feat: a"
  advance_base u.txt up
  sync start
  [ "$(jq -c '[.status, .strategy, .behind, .conflicted, .setup.ok, .gates.passed]' <<<"$output")" = \
    '["synced","rebase",1,false,true,true]' ]
  [ "$(git -C "$WT" rev-parse HEAD~1)" = "$(git rev-parse origin/main)" ]   # linear
  [ "$(jq -r .base_sha "$DIR/state.json")" = "$(git rev-parse origin/main)" ]
  [ "$(jq -c '.syncs | length, .[0].strategy' "$DIR/state.json" | tr '\n' ' ')" = '1 "rebase" ' ]
  [ "$(jq -r '.sync_pending // "none"' "$DIR/state.json")" = none ]
}

@test "sync: a pushed branch is merged, and --rebase on it is refused" {
  commit_file "$WT" a.txt 1 "feat: a"
  git -C "$WT" push -q origin feat/demo
  advance_base u.txt up
  sync start --rebase
  [ "$status" -ne 0 ]
  [[ "$(jq -r .error <<<"$output")" == *"would need a force push"* ]]
  sync start
  [ "$(jq -c '[.status, .strategy, .pushed_branch]' <<<"$output")" = '["synced","merge",true]' ]
  [ "$(git -C "$WT" rev-list --parents -n1 HEAD | wc -w)" -eq 3 ]          # merge commit
}

@test "sync: a conflicting rebase becomes a merge left for resolution, then finish" {
  commit_file "$WT" f.txt feature "feat: change f"
  advance_base f.txt upstream
  sync start
  [ "$(jq -c '[.status, .strategy, .files]' <<<"$output")" = '["conflicts","merge",["f.txt"]]' ]
  [ "$(jq -r .sync_pending.conflicted "$DIR/state.json")" = true ]

  sync finish
  [ "$status" -ne 0 ]
  [[ "$(jq -r .error <<<"$output")" == "there are still unresolved conflicts"* ]]
  echo both >"$WT/f.txt"; git -C "$WT" add f.txt
  sync finish
  [[ "$(jq -r .error <<<"$output")" == *"not committed"* ]]
  git -C "$WT" commit -q --no-edit
  sync finish
  [ "$(jq -c '[.status, .strategy, .conflicted]' <<<"$output")" = '["synced","merge",true]' ]
  [ "$(jq -r .base_sha "$DIR/state.json")" = "$(git rev-parse origin/main)" ]
}

@test "sync records after_review, and refuses a dirty worktree or a missing worktree" {
  commit_file "$WT" a.txt 1 "feat: a"
  write_review 1 CHANGES_REQUESTED; write_review 2 CHANGES_REQUESTED
  advance_base u.txt up
  sync start
  [ "$(jq -r '.syncs[0].after_review' "$DIR/state.json")" = 2 ]

  advance_base v.txt up
  echo x >"$WT/dirty.txt"
  sync start
  [[ "$(jq -r .error <<<"$output")" == "the worktree has uncommitted changes"* ]]
  rm "$WT/dirty.txt"
  "$BIN/team-clean" "$DIR" >/dev/null
  sync start
  [[ "$(jq -r .error <<<"$output")" == *"is gone"* ]]
}
