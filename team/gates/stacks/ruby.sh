#!/usr/bin/env bash
# Default gates for Ruby / Rails: RuboCop and Brakeman when the bundle has them, then the tests
# (RSpec if the project uses it, otherwise Rails' or Rake's test task).
set -uo pipefail
export RAILS_ENV=test
# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "$0")/lib.sh"

bundled() { grep -qE "^    $1 \(" Gemfile.lock 2>/dev/null; }

if bundled rubocop; then step rubocop bundle exec rubocop; else skip rubocop "not in Gemfile.lock"; fi
if bundled brakeman; then step brakeman bundle exec brakeman --quiet --no-pager --no-summary; else skip brakeman "not in Gemfile.lock"; fi
if bundled rspec-core && [ -d spec ]; then step test bundle exec rspec
elif [ -x bin/rails ] && [ -d test ]; then step test bin/rails test
elif [ -f Rakefile ]; then step test bundle exec rake test
else skip test "no spec/, test/ or Rakefile"
fi
finish
