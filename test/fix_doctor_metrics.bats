#!/usr/bin/env bats
# team-issue (/team-fix), team-ship's "Closes #n", team-doctor and team-metrics.

load helpers

setup() { setup_team; make_repo; }

issue_fixture() { # <n> <title> [state]
  jq -n --argjson n "$1" --arg t "$2" --arg s "${3:-OPEN}" '{number: $n, title: $t, state: $s,
    url: "https://github.com/o/r/issues/\($n)", body: "Pasos:\n1. POST /api/notes con title vacío\n2. responde 500",
    author: {login: "ana"}, labels: [{name: "bug"}],
    comments: [{author: {login: "bob"}, createdAt: "2026-11-01T10:00:00Z", body: "También con espacios."}]}' \
    >"$FAKE_DIR/issue-$1.json"
}

@test "team-issue starts a fix feature on a fix/ branch with the issue in it" {
  issue_fixture 42 "Crear nota con título vacío responde 500 (¡no 422!)"
  run --separate-stderr "$BIN/team-issue" 42
  [ "$status" -eq 0 ]
  dir=$(jq -r .feature_dir <<<"$output")
  [[ "$dir" == */.team/001-fix-42-crear-nota-con-titulo-vacio-responde-500 ]]
  [ "$(jq -r .branch <<<"$output")" = fix/fix-42-crear-nota-con-titulo-vacio-responde-500 ]
  [ "$(jq -c '[.kind, .issue.number, .issue.state]' "$dir/state.json")" = '["fix",42,"OPEN"]' ]
  grep -q '^# Issue #42: Crear nota' "$dir/issue.md"
  grep -q '^- Etiquetas: bug' "$dir/issue.md"
  grep -q '^### @bob' "$dir/issue.md"
  git show-ref --verify -q refs/heads/fix/fix-42-crear-nota-con-titulo-vacio-responde-500
}

@test "team-issue resumes the feature of an issue already started, and checks the issue's repo" {
  issue_fixture 7 "Bug"
  run --separate-stderr "$BIN/team-issue" "#7"
  first=$(jq -r .feature_dir <<<"$output")
  run --separate-stderr "$BIN/team-issue" https://github.com/o/r/issues/7
  [ "$(jq -c '[.existing, .feature_dir == "'"$first"'"]' <<<"$output")" = '[true,true]' ]
  [ "$(find "$W/repo/.team" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]

  run --separate-stderr "$BIN/team-issue" https://github.com/other/repo/issues/7
  [ "$status" -ne 0 ]
  [[ "$(jq -r .error <<<"$output")" == "the issue is in other/repo"* ]]
  run --separate-stderr "$BIN/team-issue" 99
  [[ "$(jq -r .error <<<"$output")" == "gh issue view 99 failed"* ]]
}

@test "the PR of a fix closes its issue" {
  issue_fixture 42 "Bug"
  DIR=$("$BIN/team-issue" 42 | jq -r .feature_dir); WT=$(jq -r .worktree "$DIR/state.json")
  plan_feature
  commit_file "$WT" a.txt a "fix: a (#42)"
  jq --arg b "$(git -C "$WT" rev-parse HEAD~1)" '.base_sha = $b' "$DIR/state.json" >s && mv s "$DIR/state.json"
  run --separate-stderr "$BIN/team-ship" "$DIR" --check
  [ "$(jq -r .ok <<<"$output")" = true ]
  grep -qx 'Closes #42' "$DIR/pr-body.md"
}

@test "team-status lists the kind and the issue" {
  issue_fixture 5 "Bug"
  "$BIN/team-issue" 5 >/dev/null
  make_feature normal
  run --separate-stderr "$BIN/team-status" --json --offline
  [ "$(jq -c 'map([.kind, .issue.number])' <<<"$output")" = '[["fix",5],["feature",null]]' ]
}

doctor() { run --separate-stderr "$BIN/team-doctor" --json; }
check() { jq -r --arg id "$1" '.checks[] | select(.id == $id) | .status' <<<"$output"; }

@test "doctor: a bare repo is usable but warns about gates and context" {
  doctor
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.ok, .stack]' <<<"$output")" = '[true,null]' ]
  [ "$(check tools.codex)" = ok ] && [ "$(check tools.gh)" = ok ] && [ "$(check repo.base)" = ok ]
  [ "$(check gates)" = warn ] && [ "$(check context)" = warn ] && [ "$(check setup)" = info ]
}

@test "doctor: missing logins and no base branch" {
  git remote remove origin
  FAKE_CODEX_LOGIN=0 FAKE_GH_AUTH=0 run --separate-stderr "$BIN/team-doctor" --json
  [ "$status" -ne 0 ]
  [ "$(jq -r .ok <<<"$output")" = false ]
  [ "$(check tools.codex)" = warn ] && [ "$(check tools.gh)" = warn ]
  [ "$(check repo.remote)" = warn ] && [ "$(check repo.base)" = fail ]
}

@test "doctor: stack, gates, partition, ignored files and context" {
  printf 'defp deps, do: [{:ecto_sql, "~> 3.0"}]\n' >mix.exs
  printf '.env\n.env.*\n' >.gitignore
  echo SECRET=1 >.env; echo X=1 >.env.local; echo X= >.env.example
  echo "# Repo" >CLAUDE.md
  doctor
  [ "$(jq -r .stack <<<"$output")" = elixir ]
  [ "$(check gates)" = ok ]
  [[ "$(jq -r '.checks[] | select(.id == "gates") | .detail' <<<"$output")" == *"gates/stacks/elixir.sh" ]]
  [ "$(check partition)" = warn ]
  [ "$(check files)" = warn ]
  [[ "$(jq -r '.checks[] | select(.id == "files") | .detail' <<<"$output")" == *".env .env.local" ]]
  [ "$(check context)" = ok ]

  mkdir -p config .team
  echo 'database: "app_test#{System.get_env("MIX_TEST_PARTITION")}"' >config/test.exs
  printf '.env\n.env.local  # local overrides\n' >.team/worktree-files
  doctor
  [ "$(check partition)" = ok ] && [ "$(check files)" = ok ]
}

@test "metrics: a feature's reviews, gates, tasks, runs and timeline" {
  make_feature demo
  plan_feature "$(printf '%s\n' '- [x] T1 a' '- [x] T2 b' '## Correcciones — revisión 1' '- [x] R1-01 c' \
    '## Comentarios de la PR — ronda 1' '- [x] H1-01 d' '- [ ] C1-02 e')"
  mkdir -p "$DIR/reviews"
  echo '{"verdict":"CHANGES_REQUESTED","findings":[{"severity":"major"},{"severity":"blocker"}]}' >"$DIR/reviews/plan-1.json"
  echo '{"verdict":"APPROVED","findings":[]}' >"$DIR/reviews/plan-2.json"
  write_review 1 CHANGES_REQUESTED "[$(finding major a), $(finding minor b)]"
  write_review 2 APPROVED "[$(finding human c)]"
  write_review 3 CHANGES_REQUESTED
  echo '{"passed":false}' >"$DIR/gates/iter-1-try-1.json"; echo '{"passed":true}' >"$DIR/gates/iter-1.json"
  echo '{"passed":true}' >"$DIR/gates/iter-2.json"
  jq '.created = "2026-11-01T00:00:00Z" | .pr = {shipped: "2026-11-01T05:00:00Z", merged_at: "2026-11-02T00:00:00Z"}' \
    "$DIR/state.json" >s && mv s "$DIR/state.json"

  run --separate-stderr "$BIN/team-metrics" "$DIR" run dev --tokens 1000 --duration-ms 120000 --agents 4
  run --separate-stderr "$BIN/team-metrics" "$DIR" run respond --tokens 500
  m=$output
  [ "$(jq -c '.plan' <<<"$m")" = '{"rounds":2,"findings":{"blocker":1,"major":1,"minor":0,"human":0}}' ]
  [ "$(jq -c '.code | [.iterations, .verdict, .approved_at_iteration, .findings]' <<<"$m")" = \
    '[3,"CHANGES_REQUESTED",2,{"blocker":0,"major":1,"minor":1,"human":1}]' ]
  [ "$(jq -c '.gates' <<<"$m")" = '{"runs":3,"failed":1,"repair_rounds":1}' ]
  [ "$(jq -c '.tasks' <<<"$m")" = '{"plan":2,"reviewer":1,"pr_comments":1,"ci":1}' ]
  [ "$(jq -c '.runs | [.count, .tokens, .duration_min, .agents, .by_kind]' <<<"$m")" = '[2,1500,2,4,{"dev":1,"respond":1}]' ]
  [ "$(jq -c '.timeline | [.pr_opened, .hours_to_merge]' <<<"$m")" = '["2026-11-01T05:00:00Z",24]' ]
  [ "$(jq -r .timeline.approved <<<"$m")" != null ]

  run --separate-stderr "$BIN/team-metrics" "$DIR" run dev --tokens lots
  [ "$status" -eq 2 ]
}

@test "metrics --repo: one row per feature and the totals; team-status --metrics shows it" {
  make_feature a; write_review 1 CHANGES_REQUESTED "[$(finding major x)]"; write_review 2 APPROVED
  make_feature b; write_review 1 APPROVED
  make_feature c
  run --separate-stderr "$BIN/team-metrics" --repo --json
  [ "$(jq -c '.summary | [.features, .approved, .avg_iterations_to_approval, .findings.major]' <<<"$output")" = '[3,2,1.5,1]' ]
  run --separate-stderr "$BIN/team-status" --metrics
  [[ "$output" == *"001-a"*"feature"*"2"*"0/1/0/0"* ]]
  [[ "$output" == *"3 features · 2 aprobadas"* ]]
}
