#!/usr/bin/env bash
# Default gates for Elixir / Phoenix: compile without warnings, unused locked deps, formatting,
# Credo and Sobelow when the project has them, then the tests.
set -uo pipefail
export MIX_ENV=test
# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "$0")/lib.sh"

dep() { grep -qE "\{:$1[,[:space:]]" mix.exs; }

step compile mix compile --warnings-as-errors --force
if [ -f mix.lock ]; then step deps.unlock mix deps.unlock --check-unused; else skip deps.unlock "no mix.lock"; fi
step format mix format --check-formatted
if dep credo; then step credo mix credo --strict; else skip credo "not a dependency"; fi
if dep sobelow; then
  if [ -f .sobelow-conf ]; then step sobelow mix sobelow --config; else step sobelow mix sobelow --exit low; fi
else skip sobelow "not a dependency"; fi
step test mix test --warnings-as-errors
finish
