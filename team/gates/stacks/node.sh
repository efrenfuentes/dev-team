#!/usr/bin/env bash
# Default gates for Node / TypeScript: the project's own package.json scripts, the ones that
# exist among format check, lint, typecheck and test, with its package manager. CI=true keeps
# test runners (Jest, Vitest) out of watch mode.
set -uo pipefail
export CI=true
# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "$0")/lib.sh"

if [ -f pnpm-lock.yaml ]; then pm=pnpm
elif [ -f yarn.lock ]; then pm=yarn
elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun
else pm=npm
fi

script_of() { jq -r --arg s "$1" '.scripts[$s] // empty' package.json; }

# First script that exists among the candidates, for one gate.
gate() { # <name> <script candidates...>
  local name=$1 s body
  shift
  for s in "$@"; do
    body=$(script_of "$s")
    [ -n "$body" ] || continue
    # npm init's placeholder test script is not a test suite.
    if [[ "$body" == *"no test specified"* ]]; then skip "$name" "placeholder \"$s\" script"; return; fi
    step "$name" "$pm" run "$s"
    return
  done
  skip "$name" "no script: $*"
}

gate format format:check fmt:check prettier:check check-format
gate lint lint
gate typecheck typecheck type-check check-types tsc
if [ -z "$(script_of typecheck)$(script_of type-check)$(script_of check-types)$(script_of tsc)" ] &&
  [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ]; then
  step typecheck node_modules/.bin/tsc --noEmit
fi
gate test test
finish
