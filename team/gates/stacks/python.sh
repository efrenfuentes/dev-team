#!/usr/bin/env bash
# Default gates for Python: Ruff (lint and format check), mypy and pytest, each one only when the
# project configures or depends on it. Tools run through the project's environment: uv, Poetry,
# or the worktree's .venv.
set -uo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "$0")/lib.sh"

if [ -f uv.lock ] && has uv; then run() { uv run --frozen "$@"; }
elif [ -f poetry.lock ] && has poetry; then run() { poetry run "$@"; }
elif [ -x .venv/bin/python ]; then run() { local c=$1; shift; if [ -x ".venv/bin/$c" ]; then ".venv/bin/$c" "$@"; else "$c" "$@"; fi; }
else run() { "$@"; }
fi

# Is <tool> configured by, or a dependency of, this project?
uses() {
  grep -qsE "^\[tool\.$1(\]|\.)" pyproject.toml && return 0
  case "$1" in
    ruff) [ -f ruff.toml ] || [ -f .ruff.toml ] && return 0 ;;
    mypy) [ -f mypy.ini ] || [ -f .mypy.ini ] || grep -qs '^\[mypy' setup.cfg && return 0 ;;
    pytest) [ -f pytest.ini ] || grep -qs '^\[tool:pytest\]' setup.cfg && return 0 ;;
  esac
  grep -qsiE "(^|[\"' ])$1([<>=~!; \"'\[]|$)" pyproject.toml requirements*.txt setup.py setup.cfg
}

if uses ruff; then
  step ruff run ruff check .
  step ruff-format run ruff format --check .
else skip ruff "not configured"; fi
if uses mypy; then step mypy run mypy .; else skip mypy "not configured"; fi
if uses pytest || [ -d tests ] || [ -d test ]; then
  # Exit code 5: pytest collected no tests, which is not a failure of the feature.
  pytest_gate() { run pytest -q; local c=$?; [ $c -eq 5 ] && { echo "(no tests collected)"; return 0; }; return $c; }
  step test pytest_gate
else skip test "no pytest config and no tests/"; fi
finish
