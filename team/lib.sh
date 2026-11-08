# shellcheck shell=bash
# Helpers shared by the bin/ scripts. Source it; it also sources config.sh.
#
# Layout: the feature workspace (<main>/.team/NNN-slug/) always lives in the repo's main
# checkout, so every feature is visible from one place. The code of a feature lives in its own
# git worktree, recorded as .worktree in state.json. Features created before worktrees existed
# (no .worktree) keep working in the main checkout.

TEAM="$HOME/.claude/team"
# shellcheck source=/dev/null
. "$TEAM/config.sh"

# Main checkout of the repo that contains <path>, also when <path> is inside a worktree.
team_main_repo() { # [path]
  local common
  common=$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir) || return 1
  dirname "$common"
}

team_repo_name() { basename "$(team_main_repo "${1:-.}")"; }

# Where a feature's code lives: its worktree, or the main checkout for legacy features.
team_worktree() { # <feature_dir>
  local wt
  wt=$(jq -r '.worktree // empty' "$1/state.json")
  if [ -n "$wt" ]; then echo "$wt"; else team_main_repo "$1"; fi
}

# Export the environment every setup, gate and Developer command of a feature runs with.
# TEAM_PARTITION isolates parallel features: projects use it to name their test database
# (Phoenix reads MIX_TEST_PARTITION, set from it; Rails reads it in config/database.yml).
team_feature_env() { # <feature_dir>
  local dir=$1
  export TEAM_FEATURE_DIR="$dir" TEAM_FEATURE TEAM_MAIN_REPO TEAM_WORKTREE TEAM_PARTITION BASE_SHA BASE_REF
  TEAM_FEATURE=$(basename "$dir")
  TEAM_MAIN_REPO=$(team_main_repo "$dir")
  TEAM_WORKTREE=$(team_worktree "$dir")
  TEAM_PARTITION=$(jq -r '.partition // empty' "$dir/state.json")
  BASE_SHA=$(jq -r '.base_sha // empty' "$dir/state.json")
  BASE_REF=$(jq -r '.base_ref // empty' "$dir/state.json")
  if [ -n "$TEAM_PARTITION" ]; then export MIX_TEST_PARTITION="$TEAM_PARTITION"; fi
}

# First existing script among <main>/.team/<name>.sh and ~/.claude/team/<kind>/<repo>.sh.
team_project_script() { # <kind: gates|setup|teardown> <feature_dir>
  local main candidate
  main=$(team_main_repo "$2")
  for candidate in "$main/.team/$1.sh" "$TEAM/$1/$(basename "$main").sh"; do
    [ -f "$candidate" ] && { echo "$candidate"; return 0; }
  done
  return 1
}

# Default base branch of the repo in the current directory: the remote's default branch
# (origin/HEAD), then the first of origin/develop, origin/main, origin/master that exists.
team_default_base() {
  local b candidate
  b=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -z "$b" ]; then
    for candidate in origin/develop origin/main origin/master; do
      git rev-parse --verify -q "$candidate" >/dev/null 2>&1 && { b=$candidate; break; }
    done
  fi
  [ -n "$b" ] && echo "$b"
}

# Stack of a checkout, by its marker files. Order matters: a Rails app has a package.json too.
team_stack() { # <worktree>
  local d=$1
  if [ -f "$d/mix.exs" ]; then echo elixir
  elif [ -f "$d/Gemfile" ]; then echo ruby
  elif [ -f "$d/go.mod" ]; then echo go
  elif [ -f "$d/Cargo.toml" ]; then echo rust
  elif [ -f "$d/pyproject.toml" ] || [ -f "$d/setup.py" ] || [ -f "$d/requirements.txt" ]; then echo python
  elif [ -f "$d/package.json" ]; then echo node
  else return 1
  fi
}

# Default per-stack script for the worktree's stack: setup/stacks/<stack>.sh (setup and teardown)
# or gates/stacks/<stack>.sh.
team_stack_script() { # <worktree> [setup|gates]
  local stack script
  stack=$(team_stack "$1") || return 1
  script="$TEAM/${2:-setup}/stacks/$stack.sh"
  [ -f "$script" ] && echo "$script"
}

# Gate script of a feature and where it comes from, as "<project|repo|stack> <path>":
# <main>/.team/gates.sh, then ~/.claude/team/gates/<repo>.sh, then the stack's default gates
# (unless TEAM_STACK_GATES=0).
team_gates_script() { # <feature_dir>
  local main script
  main=$(team_main_repo "$1")
  if [ -f "$main/.team/gates.sh" ]; then echo "project $main/.team/gates.sh"
  elif [ -f "$TEAM/gates/$(basename "$main").sh" ]; then echo "repo $TEAM/gates/$(basename "$main").sh"
  elif [ "${TEAM_STACK_GATES:-1}" = 1 ] && script=$(team_stack_script "$(team_worktree "$1")" gates); then
    echo "stack $script"
  else return 1
  fi
}

# Gates of the same repo run one at a time when the project cannot isolate them
# (TEAM_GATES_LOCK=1, or a <main>/.team/serialize-gates marker file).
team_gates_serialized() { # <feature_dir>
  [ "${TEAM_GATES_LOCK:-0}" = 1 ] || [ -f "$(team_main_repo "$1")/.team/serialize-gates" ]
}

# Run a command holding an exclusive lock on <lockfile>. perl's flock, because flock(1) is not
# on macOS; $^F keeps the lock's fd open across exec, so the lock lasts as long as the command.
team_with_lock() { # <lockfile> <cmd...>
  local lock=$1
  shift
  perl -MFcntl=:flock -e '$^F = 255; open(my $f, ">>", shift) or die "lock: $!\n";
    flock($f, LOCK_EX) or die "lock: $!\n"; exec { $ARGV[0] } @ARGV or die "exec: $!\n"' "$lock" "$@"
}

# Code reviews this feature may use: TEAM_MAX_CODE_REVIEWS, or more after a /team-respond round
# raised it (review_budget in state.json).
team_review_budget() { # <feature_dir>
  local b
  b=$(jq -r '.review_budget // empty' "$1/state.json" 2>/dev/null)
  if [ -n "$b" ] && [ "$b" -gt "$TEAM_MAX_CODE_REVIEWS" ]; then echo "$b"; else echo "$TEAM_MAX_CODE_REVIEWS"; fi
}

# Remote and base branch the feature merges into, from base_ref: "origin/main" → "origin main".
# A local base_ref ("main") maps to origin.
team_base_remote() { # <feature_dir>
  local base_ref first
  base_ref=$(jq -r '.base_ref // empty' "$1/state.json")
  [ -n "$base_ref" ] || return 1
  first=${base_ref%%/*}
  if [ "$first" != "$base_ref" ] && git -C "$(team_main_repo "$1")" remote | grep -qxF "$first"; then
    echo "$first ${base_ref#*/}"
  else
    echo "origin $base_ref"
  fi
}

# Update state.json in place with a jq filter.
team_state_set() { # <feature_dir> <jq filter> [jq args...]
  local state="$1/state.json" filter=$2
  shift 2
  jq "$@" "$filter" "$state" >"$state.tmp" && mv "$state.tmp" "$state"
}
