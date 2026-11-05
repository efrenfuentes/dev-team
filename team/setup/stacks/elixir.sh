#!/usr/bin/env bash
# Default worktree setup for Elixir / Phoenix. Runs in the worktree with the feature env.
#
#   elixir.sh setup     deps, assets' npm packages, and the feature's own test database
#   elixir.sh teardown  drops that test database
#
# Isolation: team exports MIX_TEST_PARTITION=$TEAM_PARTITION, and Phoenix's generated
# config/test.exs names the test database "<app>_test#{MIX_TEST_PARTITION}". If your config does
# not, add that suffix there or create .team/serialize-gates in the main checkout.
set -euo pipefail
export MIX_ENV=test

uses_ecto() { grep -q ':ecto_sql' mix.exs; }
partitioned() { grep -rqs 'MIX_TEST_PARTITION' config/; }

case "${1:-setup}" in
  setup)
    echo "== mix deps.get"
    mix deps.get
    if [ -f assets/package.json ]; then
      echo "== assets: npm packages"
      if [ -f assets/package-lock.json ]; then npm ci --prefix assets; else npm install --prefix assets; fi
    fi
    if uses_ecto; then
      partitioned || echo "== warning: config/ does not use MIX_TEST_PARTITION; parallel features share the test database"
      echo "== mix ecto.create (test, partition ${MIX_TEST_PARTITION:-none})"
      mix ecto.create --quiet
    fi
    ;;
  teardown)
    # Only a database that belongs to this feature: with no partition it is the main checkout's.
    if uses_ecto && partitioned && [ -n "${MIX_TEST_PARTITION:-}" ]; then
      echo "== mix ecto.drop (test, partition $MIX_TEST_PARTITION)"
      mix ecto.drop --quiet
    else
      echo "== no feature-specific test database to drop"
    fi
    ;;
  *) echo "usage: $0 setup|teardown" >&2; exit 2 ;;
esac
