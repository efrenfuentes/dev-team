# shellcheck shell=bash
# Shared by the default stack gates: run every step even after a failure, so one run shows the
# Developer everything that is red, and exit non-zero at the end if any step failed.
# Gates check, they never fix: formatters run in check mode and nothing is written to the tree.

TEAM_GATES_FAILED=()

# step <name> <command...>: run one gate.
step() {
  local name=$1
  shift
  echo
  echo "== $name: $*"
  if "$@"; then
    echo "== ok: $name"
  else
    echo "== FAILED: $name (exit $?)"
    TEAM_GATES_FAILED+=("$name")
  fi
}

# skip <name> <why>: a gate this repo does not use, said out loud so the log shows what ran.
skip() { echo; echo "== skip: $1 ($2)"; }

has() { command -v "$1" >/dev/null 2>&1; }

finish() {
  echo
  if [ ${#TEAM_GATES_FAILED[@]} -eq 0 ]; then
    echo "== OK: all gates passed"
  else
    echo "== FAILED gates: ${TEAM_GATES_FAILED[*]}"
    exit 1
  fi
}

echo "== HEAD $(git rev-parse --short HEAD 2>/dev/null) (base ${BASE_SHA:-?}) · default gates: $(basename "$0" .sh)"
