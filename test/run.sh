#!/usr/bin/env bash
# Run the repo's own checks: shellcheck, the bats suites and the workflow tests.
#
#   test/run.sh                 # everything
#   test/run.sh test/sync.bats  # only the given bats files (shellcheck and node still run)
#
# Tools come from PATH, or through `mise exec` when they are missing (see mise.toml).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

tool() { # <name> → command prefix that provides it
  if command -v "$1" >/dev/null 2>&1; then echo ""
  elif command -v mise >/dev/null 2>&1; then echo "mise exec --"
  else echo "missing"
  fi
}
status=0
step() { printf '\n== %s\n' "$1"; }

for t in shellcheck bats node jq git; do
  [ "$(tool "$t")" != missing ] || { echo "missing: $t (install it, or install mise and run 'mise install')" >&2; exit 2; }
done

step shellcheck
# shellcheck disable=SC2046
$(tool shellcheck) shellcheck -x team/bin/* team/lib.sh team/config.sh team/gates/*.sh team/gates/stacks/*.sh team/setup/stacks/*.sh \
  install.sh test/run.sh test/fakes/* || status=1

step bats
if [ $# -gt 0 ]; then files=("$@"); else files=(test/*.bats); fi
# Suites run in parallel when GNU parallel is there (bats needs it for --jobs); each test has its own dirs.
jobs=()
command -v parallel >/dev/null 2>&1 && jobs=(--jobs "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)")
$(tool bats) bats ${jobs[@]+"${jobs[@]}"} "${files[@]}" || status=1

step "workflows (node --test)"
$(tool node) node --test test/workflows.test.mjs || status=1

printf '\n== %s\n' "$([ $status -eq 0 ] && echo PASSED || echo FAILED)"
exit $status
