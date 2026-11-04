#!/usr/bin/env bash
# Gates del dev team para base-app: los mismos pasos que `mix precommit`,
# pero sin modificar archivos (format y deps.unlock en modo comprobación).
set -euo pipefail
export MIX_ENV=test

echo "== HEAD $(git rev-parse --short HEAD) (base ${BASE_SHA:-?})"

step() { echo; echo "== $*"; "$@"; }

step mix compile --warnings-as-errors --force
step mix deps.unlock --check-unused
step mix format --check-formatted
step mix gettext.extract --check-up-to-date
step mix credo --strict
step mix sobelow --config
step mix test --warnings-as-errors

echo
echo "== OK: todos los gates pasaron"
