#!/usr/bin/env bash
# Default gates for Rust: rustfmt, Clippy with warnings as errors, then the tests.
set -uo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "$0")/lib.sh"

if cargo fmt --version >/dev/null 2>&1; then step fmt cargo fmt --all --check; else skip fmt "rustfmt not installed"; fi
if cargo clippy --version >/dev/null 2>&1; then
  step clippy cargo clippy --all-targets --all-features -- -D warnings
else skip clippy "clippy not installed"; fi
step test cargo test --all-features
finish
