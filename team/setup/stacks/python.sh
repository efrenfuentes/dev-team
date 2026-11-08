#!/usr/bin/env bash
# Default worktree setup for Python: the project's environment inside the worktree, with uv or
# Poetry when the repo locks with them, otherwise a .venv with pip. Runs in the worktree.
#
#   python.sh setup      create the environment and install the project with its dev extras
#   python.sh teardown   nothing to drop (the environment goes away with the worktree)
set -euo pipefail

venv_pip() {
  [ -x .venv/bin/python ] || python3 -m venv .venv
  .venv/bin/python -m pip install --quiet --upgrade pip
  local f
  for f in requirements.txt requirements-dev.txt requirements/dev.txt; do
    [ -f "$f" ] && { echo "== pip install -r $f"; .venv/bin/pip install -r "$f"; }
  done
  if [ -f pyproject.toml ] || [ -f setup.py ]; then
    echo "== pip install -e ."
    .venv/bin/pip install -e '.[dev]' 2>/dev/null || .venv/bin/pip install -e .
  fi
}

case "${1:-setup}" in
  setup)
    if [ -f uv.lock ]; then echo "== uv sync"; uv sync --frozen --all-extras
    elif [ -f poetry.lock ]; then
      # A virtualenv per worktree, not Poetry's shared cache entry.
      echo "== poetry install"; POETRY_VIRTUALENVS_IN_PROJECT=true poetry install
    else venv_pip
    fi
    ;;
  teardown) echo "== nothing to tear down" ;;
  *) echo "usage: $0 setup|teardown" >&2; exit 2 ;;
esac
