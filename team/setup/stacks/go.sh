#!/usr/bin/env bash
# Default worktree setup for Go: download the modules. Runs in the worktree.
set -euo pipefail
case "${1:-setup}" in
  setup) echo "== go mod download"; go mod download ;;
  teardown) echo "== nothing to tear down" ;;
  *) echo "usage: $0 setup|teardown" >&2; exit 2 ;;
esac
