#!/usr/bin/env bats
# team-respond with a fake gh: fetch filters, rounds, tasks + budget, replies.

load helpers

setup() {
  setup_team; make_repo; make_feature demo; plan_feature
  jq '.pr.url = "https://github.com/o/r/pull/7"' "$DIR/state.json" >s && mv s "$DIR/state.json"
  write_review 1 CHANGES_REQUESTED; write_review 2 APPROVED
  user() { jq -nc --arg l "$1" '{login: $l, __typename: "User"}'; }
  cat >"$FAKE_DIR/graphql.json" <<JSON
{"data":{"repository":{"pullRequest":{"state":"OPEN",
"reviewThreads":{"nodes":[
 {"id":"T1","isResolved":false,"isOutdated":false,"path":"lib/a.ex","line":10,"originalLine":10,
  "comments":{"nodes":[{"databaseId":101,"body":"Validar nil","url":"https://x/c101","author":$(user ana)}]}},
 {"id":"T2","isResolved":true,"isOutdated":false,"path":"lib/b.ex","line":3,"originalLine":3,
  "comments":{"nodes":[{"databaseId":102,"body":"resuelto","url":"u","author":$(user ana)}]}},
 {"id":"T3","isResolved":false,"isOutdated":true,"path":"lib/c.ex","line":null,"originalLine":5,
  "comments":{"nodes":[{"databaseId":103,"body":"¿por qué?","url":"u3","author":$(user ana)},
                       {"databaseId":104,"body":"porque sí\n\n<!-- dev-team -->","url":"u4","author":$(user me)}]}},
 {"id":"T4","isResolved":false,"isOutdated":true,"path":"lib/d.ex","line":null,"originalLine":8,
  "comments":{"nodes":[{"databaseId":105,"body":"Renombrar","url":"https://x/c105","author":$(user ana)}]}}]},
"reviews":{"nodes":[
 {"databaseId":201,"state":"CHANGES_REQUESTED","body":"Faltan tests","url":"https://x/r201","author":$(user ana)},
 {"databaseId":202,"state":"APPROVED","body":"ok","url":"u","author":$(user bob)},
 {"databaseId":203,"state":"COMMENTED","body":"","url":"u","author":$(user bob)}]},
"comments":{"nodes":[
 {"databaseId":301,"body":"Coverage 90%","url":"u","author":{"login":"codecov","__typename":"Bot"}},
 {"databaseId":302,"body":"¿Rompe la API v1?","url":"https://x/i302","author":$(user ana)}]}}}}}
JSON
}

respond() { run --separate-stderr "$BIN/team-respond" "$DIR" "$@"; }

@test "fetch keeps only unanswered human feedback" {
  respond fetch
  [ "$(jq -c '[.ok, .round, .count, .pr_state]' <<<"$output")" = '[true,1,4,"OPEN"]' ]
  [ "$(jq -c '[.items[].key]' <<<"$output")" = '["t:T1","t:T4","r:201","c:302"]' ]
  [ "$(jq -c '.items[1] | [.line, .outdated, .reply_to]' <<<"$output")" = '[8,true,105]' ]
}

@test "fetch finds the PR of the branch when state has none, and fails without one" {
  jq 'del(.pr)' "$DIR/state.json" >s && mv s "$DIR/state.json"
  respond fetch
  [[ "$(jq -r .error <<<"$output")" == "no open PR for branch 'feat/demo'"* ]]
  echo '[{"url":"https://github.com/o/r/pull/9"}]' >"$FAKE_DIR/pr-list.json"
  respond fetch
  [ "$(jq -r .pr <<<"$output")" = https://github.com/o/r/pull/9 ]
  [ "$(jq -r .pr.url "$DIR/state.json")" = https://github.com/o/r/pull/9 ]
}

@test "fetch again before the triage reuses the round" {
  respond fetch; respond fetch
  [ "$(jq -r .round <<<"$output")" = 1 ]
  [ "$(find "$DIR/respond" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]
}

@test "tasks adds H tasks, raises the budget, opens the round and marks everything seen" {
  respond fetch
  cat >"$DIR/respond/round-1/plan.json" <<'JSON'
[{"key":"t:T1","task":"Validar nil en parse/1","reply":null},
 {"key":"t:T4","task":null,"reply":null},
 {"key":"r:201","task":"Agregar tests de borde","reply":null},
 {"key":"c:302","task":null,"reply":"No, v1 no cambia."},
 {"key":"x:unknown","task":"fantasma","reply":null}]
JSON
  respond tasks 1
  [ "$(jq -c '[.tasks_added, .task_ids, .review_budget]' <<<"$output")" = '[2,["H1-01","H1-02"],6]' ]
  grep -qF -- '- [ ] H1-01 Validar nil en parse/1 (`lib/a.ex:10`) · @ana: https://x/c101' "$DIR/tasks.md"
  grep -qF -- '- [ ] H1-02 Agregar tests de borde · @ana: https://x/r201' "$DIR/tasks.md"
  [ "$(jq -c '.respond.pending' "$DIR/state.json")" = '{"round":1,"from_iter":3}' ]
  [ "$(jq -c '.respond.seen' "$DIR/state.json")" = '[101,105,201,302]' ]

  respond tasks 1
  [[ "$(jq -r .error <<<"$output")" == *"already has tasks"* ]]

  # Nothing new afterwards.
  respond fetch
  [ "$(jq -c '[.round, .count]' <<<"$output")" = '[2,0]' ]
}

@test "tasks raises the budget past an exhausted loop" {
  for i in 3 4 5 6; do write_review $i CHANGES_REQUESTED; done
  respond fetch
  echo '[{"key":"t:T1","task":"x","reply":null}]' >"$DIR/respond/round-1/plan.json"
  respond tasks 1
  [ "$(jq -r .review_budget <<<"$output")" = 8 ]
  run --separate-stderr "$BIN/team-start" "$DIR"
  [ "$(jq -c '[.start_iter, .max_iter, .finished]' <<<"$output")" = '[7,8,false]' ]
}

@test "a triage without tasks opens no round" {
  respond fetch
  echo '[{"key":"c:302","task":null,"reply":"No."}]' >"$DIR/respond/round-1/plan.json"
  respond tasks 1
  [ "$(jq -r .tasks_added <<<"$output")" = 0 ]
  [ "$(jq -c '[.review_budget, .respond.pending]' "$DIR/state.json")" = '[null,null]' ]
}

@test "reply answers in the thread or with a linked comment, marked, and closes the round" {
  respond fetch
  echo '[{"key":"t:T1","task":"x","reply":null}]' >"$DIR/respond/round-1/plan.json"
  respond tasks 1
  cat >"$DIR/respond/round-1/replies.json" <<'JSON'
[{"key":"t:T1","body":"Hecho en abc123."},{"key":"c:302","body":"No, v1 no cambia."},{"key":"t:nope","body":"?"}]
JSON
  respond reply 1
  [ "$(jq -c '[.ok, .posted, .failed]' <<<"$output")" = '[false,2,1]' ]
  grep -q 'api repos/o/r/pulls/7/comments/101/replies' "$FAKE_DIR/gh.log"
  grep -q 'api repos/o/r/issues/7/comments' "$FAKE_DIR/gh.log"
  [ "$(grep -c '<!-- dev-team -->' "$FAKE_DIR/gh-bodies.log")" -eq 2 ]
  grep -q '^> https://x/i302' "$FAKE_DIR/gh-bodies.log"
  [ "$(jq -c '[.respond.pending, .respond.last_round]' "$DIR/state.json")" = '[null,1]' ]
}

@test "unknown rounds and a gh failure are reported" {
  respond tasks 3
  [[ "$(jq -r .error <<<"$output")" == "unknown round '3'"* ]]
  echo 'not json' >"$FAKE_DIR/graphql.json"
  respond fetch
  [ "$status" -ne 0 ]
}
