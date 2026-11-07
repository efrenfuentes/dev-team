bats_require_minimum_version 1.5.0

# Shared setup for the bats suites. Each test gets its own HOME with ~/.claude/team linked to this
# repo's team/ (the scripts source $HOME/.claude/team/lib.sh), a scratch work dir $W, fake gh and
# codex first on PATH, and no TEAM_* settings leaking in from the caller's environment.

setup_team() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  ln -s "$REPO_ROOT/team" "$HOME/.claude/team"
  BIN="$HOME/.claude/team/bin"

  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  git config --global user.name "Team Test"
  git config --global user.email "team-test@example.invalid"
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false

  local v
  for v in $(compgen -v TEAM_); do unset "$v"; done
  unset CODEX_HOME MIX_TEST_PARTITION

  export FAKE_DIR="$BATS_TEST_TMPDIR/fake"
  mkdir -p "$FAKE_DIR"
  export PATH="$REPO_ROOT/test/fakes:$PATH"
  W="$BATS_TEST_TMPDIR/w"
  mkdir -p "$W"
}

# A repo with one commit on main, pushed to a bare "origin". cd's into it.
make_repo() {
  git init -q --bare -b main "$W/remote.git"
  git init -q -b main "$W/repo"
  cd "$W/repo" || return 1
  echo base >f.txt
  git add f.txt
  git commit -qm init
  git remote add origin "$W/remote.git"
  git push -q origin main
  git fetch -q origin
  git remote set-head origin main
}

# team-init a feature; sets DIR (feature dir) and WT (its worktree).
make_feature() { # <slug>
  DIR=$("$BIN/team-init" "$1") || return 1
  WT=$(jq -r .worktree "$DIR/state.json")
}

# Give a feature what team-start needs (spec/plan/tasks) and record base_sha through it.
plan_feature() { # [tasks.md content]
  printf '# %s\n\n## Contexto y objetivo\nObjetivo de prueba.\n' "Feature de prueba" >"$DIR/spec.md"
  echo "plan" >"$DIR/plan.md"
  printf '%s\n' "${1:-- [ ] T1 hacer algo}" >"$DIR/tasks.md"
}

commit_file() { # <worktree> <file> <content> <message>
  echo "$3" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -qm "$4"
}

# Push a new commit to origin/main from another clone, and fetch it.
advance_base() { # <file> <content>
  [ -d "$W/other" ] || git clone -q -b main "$W/remote.git" "$W/other"
  git -C "$W/other" pull -q
  commit_file "$W/other" "$1" "$2" "upstream: $1"
  git -C "$W/other" push -q origin main
  git -C "$W/repo" fetch -q origin
}

# A review result as the scripts store it, for building state by hand.
write_review() { # <n> <verdict> [findings json]
  mkdir -p "$DIR/reviews"
  jq -n --arg v "$2" --argjson f "${3:-[]}" --argjson n "$1" \
    '{verdict: $v, summary: "s", findings: $f, previous_findings: [], iteration: $n, head_sha: "x"}' \
    >"$DIR/reviews/code-$1.json"
}

# A Codex answer fixture (verdict.json shape).
codex_says() { # <kind: code|security|plan> <verdict> [findings json] [previous_findings json]
  jq -n --arg v "$2" --argjson f "${3:-[]}" --argjson p "${4:-[]}" \
    '{verdict: $v, summary: "resumen", findings: $f, previous_findings: $p}' >"$FAKE_DIR/codex-$1.json"
}

finding() { # <severity> <title> → one finding object
  jq -nc --arg s "$1" --arg t "$2" '{severity: $s, location: "lib/a.ex:1", title: $t, detail: "d", task: ("hacer " + $t)}'
}

# Last JSON value printed by a command's output (scripts may log before it).
json() { jq -s 'last' <<<"$output"; }
jfield() { jq -r "$1" <<<"$(json)"; }
