#!/usr/bin/env bash
# Default worktree setup for Node / TypeScript: the packages, with the project's package manager
# and its lockfile as is. Runs in the worktree with the feature env.
#
#   node.sh setup      install the packages
#   node.sh teardown   nothing to drop
set -euo pipefail

case "${1:-setup}" in
  setup)
    echo "== JS packages"
    if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile
    elif [ -f yarn.lock ]; then yarn install --frozen-lockfile
    elif [ -f bun.lockb ] || [ -f bun.lock ]; then bun install --frozen-lockfile
    elif [ -f package-lock.json ]; then npm ci
    else npm install
    fi
    ;;
  teardown) echo "== nothing to tear down" ;;
  *) echo "usage: $0 setup|teardown" >&2; exit 2 ;;
esac
