#!/usr/bin/env bash
# Default worktree setup for Ruby / Rails. Runs in the worktree with the feature env.
#
#   ruby.sh setup     credential keys, gems, JS packages, and the feature's own test database
#   ruby.sh teardown  drops that test database
#
# Isolation: name the test database with TEAM_PARTITION in config/database.yml, once per repo:
#     test:
#       database: myapp_test<%= ENV["TEAM_PARTITION"] %>
# (not TEST_ENV_NUMBER: Rails' own parallel test workers use it). SQLite test databases live in
# the worktree, so they are isolated already. Otherwise create .team/serialize-gates in the main
# checkout.
set -euo pipefail
export RAILS_ENV=test

rails() { [ -x bin/rails ]; }
sqlite() { grep -qs 'sqlite3' config/database.yml; }
partitioned() { grep -qs 'TEAM_PARTITION' config/database.yml; }

case "${1:-setup}" in
  setup)
    # Git never has the credential keys, and without them Rails cannot read its credentials.
    for src in "$TEAM_MAIN_REPO/config/master.key" "$TEAM_MAIN_REPO"/config/credentials/*.key; do
      [ -f "$src" ] || continue
      rel=${src#"$TEAM_MAIN_REPO"/}
      if [ -e "$rel" ]; then echo "== keep $rel"; else mkdir -p "$(dirname "$rel")"; cp -p "$src" "$rel"; echo "== copied $rel"; fi
    done

    echo "== bundle install"
    bundle install

    if [ -f package.json ]; then
      echo "== JS packages"
      if [ -f yarn.lock ]; then yarn install --frozen-lockfile
      elif [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile
      elif [ -f bun.lockb ] || [ -f bun.lock ]; then bun install --frozen-lockfile
      elif [ -f package-lock.json ]; then npm ci
      else npm install
      fi
    fi

    if rails; then
      sqlite || partitioned ||
        echo "== warning: config/database.yml does not use TEAM_PARTITION; parallel features share the test database"
      echo "== bin/rails db:prepare (test, partition ${TEAM_PARTITION:-none})"
      bin/rails db:prepare
    fi
    ;;
  teardown)
    # Only a database that belongs to this feature: without TEAM_PARTITION it is the main
    # checkout's, and SQLite files go away with the worktree.
    if rails && partitioned && ! sqlite && [ -n "${TEAM_PARTITION:-}" ]; then
      echo "== bin/rails db:drop (test, partition $TEAM_PARTITION)"
      bin/rails db:drop
    else
      echo "== no feature-specific test database to drop"
    fi
    ;;
  *) echo "usage: $0 setup|teardown" >&2; exit 2 ;;
esac
