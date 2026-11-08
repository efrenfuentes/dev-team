#!/usr/bin/env bash
# Default gates for Go: gofmt, go vet, golangci-lint when the repo configures it, then the tests.
set -uo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "$0")/lib.sh"

gofmt_check() {
  local files
  files=$(gofmt -l . 2>&1) || { echo "$files"; return 1; }
  [ -z "$files" ] || { echo "not gofmt'ed:"; echo "$files"; return 1; }
}

step gofmt gofmt_check
step vet go vet ./...
if compgen -G '.golangci.*' >/dev/null; then
  if has golangci-lint; then step golangci-lint golangci-lint run; else skip golangci-lint "configured but not installed"; fi
else skip golangci-lint "no .golangci.* config"; fi
step test go test ./...
finish
