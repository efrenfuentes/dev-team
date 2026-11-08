#!/usr/bin/env bash
# Default worktree setup for Rust: fetch the crates. Runs in the worktree.
set -euo pipefail
case "${1:-setup}" in
  setup) echo "== cargo fetch"; if [ -f Cargo.lock ]; then cargo fetch --locked; else cargo fetch; fi ;;
  teardown) echo "== nothing to tear down" ;;
  *) echo "usage: $0 setup|teardown" >&2; exit 2 ;;
esac
