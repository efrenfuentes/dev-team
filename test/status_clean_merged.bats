#!/usr/bin/env bats
# team-respond peek, team-status with the PR's state, CI and comments, and team-clean --merged.

load helpers

setup() { setup_team; make_repo; }

# A PR fixture for PR number <n>: state, one unanswered comment or none, and the head's checks.
pr_fixture() { # <n> <OPEN|MERGED|CLOSED> <comments: 0|1> <check conclusion or "">
  jq -n --arg s "$2" --argjson c "$3" --arg ch "$4" '
    {data: {repository: {pullRequest: {state: $s, mergedAt: (if $s == "MERGED" then "2026-11-01T00:00:00Z" else null end),
      reviewThreads: {nodes: []}, reviews: {nodes: []},
      comments: {nodes: (if $c == 1 then [{databaseId: 1, body: "¿Y esto?", url: "u", author: {login: "ana", __typename: "User"}}] else [] end)},
      commits: {nodes: [{commit: {oid: "abc", statusCheckRollup: {contexts: {nodes: (if $ch == "" then [] else
        [{__typename: "CheckRun", databaseId: 7, name: "test", status: "COMPLETED", conclusion: $ch,
          detailsUrl: "u", checkSuite: null}] end)}}}}]}}}}}' >"$FAKE_DIR/graphql-$1.json"
}

with_pr() { # <n>
  jq --arg u "https://github.com/o/r/pull/$1" '.pr.url = $u' "$DIR/state.json" >s && mv s "$DIR/state.json"
}

@test "peek sums up the PR without opening a round, and records its state" {
  make_feature demo; plan_feature; with_pr 5
  pr_fixture 5 OPEN 1 FAILURE
  run --separate-stderr "$BIN/team-respond" "$DIR" peek
  [ "$(jq -c '[.ok, .pr_state, .comments, .ci.state, .ci.failed]' <<<"$output")" = '[true,"OPEN",1,"failing",["test"]]' ]
  [ ! -d "$DIR/respond" ]
  [ "$(jq -r .pr.state "$DIR/state.json")" = OPEN ]
}

@test "peek of a branch with no PR is not an error" {
  make_feature demo
  run --separate-stderr "$BIN/team-respond" "$DIR" peek
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.ok, .pr]' <<<"$output")" = '[true,null]' ]
  grep -q 'pr list --head feat/demo --state all' "$FAKE_DIR/gh.log"
}

@test "team-status asks GitHub about features with a PR: state, CI and unanswered comments" {
  make_feature open; plan_feature; write_review 1 APPROVED; with_pr 1
  pr_fixture 1 OPEN 1 FAILURE
  make_feature merged; plan_feature; write_review 1 APPROVED; with_pr 2
  pr_fixture 2 MERGED 0 SUCCESS
  make_feature local; plan_feature

  run --separate-stderr "$BIN/team-status" --json
  [ "$(jq -c 'map([.phase, .pr_state, .ci, .comments])' <<<"$output")" = \
    '[["approved","OPEN","failing",1],["merged","MERGED","passing",0],["planned",null,null,null]]' ]
  [ "$(jq -c '.[0].ci_failed' <<<"$output")" = '["test"]' ]
  # Only the features with a PR were asked about.
  [ "$(grep -c 'api graphql' "$FAKE_DIR/gh.log")" -eq 2 ]

  run --separate-stderr "$BIN/team-status"
  [[ "$output" == *"001-open"*"#1"*"FALLA"*"1"* ]]
  # Its PR was merged in the first run: not asked about again, so no CI column.
  [[ "$output" == *"002-merged"*"merged"*"#2"* ]]

  # A merged PR is not asked about again.
  : >"$FAKE_DIR/gh.log"
  run --separate-stderr "$BIN/team-status" --json
  [ "$(grep -c 'api graphql' "$FAKE_DIR/gh.log")" -eq 1 ]
}

@test "team-status --offline (or without gh login) uses the recorded PR state" {
  make_feature demo; plan_feature; write_review 1 APPROVED; with_pr 3
  jq '.pr.state = "CLOSED"' "$DIR/state.json" >s && mv s "$DIR/state.json"
  run --separate-stderr "$BIN/team-status" --json --offline
  [ "$(jq -c 'map([.phase, .ci, .comments])' <<<"$output")" = '[["closed",null,null]]' ]
  [ ! -s "$FAKE_DIR/gh.log" ] || ! grep -q 'api graphql' "$FAKE_DIR/gh.log"
  FAKE_GH_AUTH=0 run --separate-stderr "$BIN/team-status" --json
  [ "$(jq -r '.[0].phase' <<<"$output")" = closed ]
  ! grep -q 'api graphql' "$FAKE_DIR/gh.log"
}

@test "team-clean --merged cleans merged PRs and branches already in the base, never forcing" {
  # base_sha is where the feature branch was cut, as team-start records it.
  set_base() { jq --arg b "$(git -C "$WT" rev-parse HEAD)" '.base_sha = $b' "$DIR/state.json" >s && mv s "$DIR/state.json"; }

  make_feature viapr; plan_feature; set_base; with_pr 1; pr_fixture 1 MERGED 0 ""
  A=$DIR; AW=$WT
  make_feature viabase; plan_feature; set_base
  commit_file "$WT" g.txt g "feat: g"
  git -C "$WT" push -q origin HEAD:main && git fetch -q origin
  B=$DIR; BW=$WT
  make_feature open; plan_feature; set_base; with_pr 3; pr_fixture 3 OPEN 0 ""
  commit_file "$WT" h.txt h "feat: h"
  C=$DIR; CW=$WT
  make_feature dirty; plan_feature; set_base; with_pr 4; pr_fixture 4 MERGED 0 ""
  echo wip >"$WT/wip.txt"
  D=$DIR; DW=$WT
  make_feature fresh; plan_feature; set_base
  E=$DIR; EW=$WT

  run --separate-stderr "$BIN/team-clean" --merged --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.dry_run, [.merged[] | [(.feature_dir | sub(".*/"; "")), .reason]], .cleaned]' <<<"$output")" = \
    '[true,[["001-viapr","pr merged"],["002-viabase","branch in origin/main"],["004-dirty","pr merged"]],[]]' ]
  [ -d "$AW" ] && [ -d "$BW" ] && [ -d "$DW" ]

  run --separate-stderr "$BIN/team-clean" --merged
  [ "$status" -ne 0 ]
  [ "$(jq -c '[.ok, (.cleaned | map(.feature_dir | sub(".*/"; ""))), (.failed | map(.feature_dir | sub(".*/"; "")))]' <<<"$output")" = \
    '[false,["001-viapr","002-viabase"],["004-dirty"]]' ]
  [[ "$(jq -r '.failed[0].error' <<<"$output")" == *"uncommitted changes"* ]]
  [ ! -d "$AW" ] && [ ! -d "$BW" ]
  [ -d "$CW" ] && [ -d "$DW" ] && [ -d "$EW" ]
  git show-ref --verify -q refs/heads/feat/viapr
}
