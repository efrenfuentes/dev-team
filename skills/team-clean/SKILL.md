---
name: team-clean
description: Remove a dev-team feature's git worktree once it is merged or abandoned — drops the feature's own test database, keeps the branch and the .team/ workspace. Use when the user runs /team-clean or asks to clean up a feature's worktree.
argument-hint: "<NNN or feature dir> [--force]"
---

# /team-clean — remove a feature's worktree

Arguments: $ARGUMENTS

1. **Resolve the feature** as `/team-dev` does: `<repo>` is the main checkout (the parent of
   `git rev-parse --path-format=absolute --git-common-dir`); the argument is an `NNN` prefix or a
   directory under `<repo>/.team/`. There is no default: if no feature is named, run
   `~/.claude/team/bin/team-status` and ask which one.
2. If the session's working directory is inside that worktree, tell the user to leave it first
   and stop.
3. Run `~/.claude/team/bin/team-clean "DIR"`. Pass `--force` only if the user passed it: it
   discards uncommitted changes in the worktree. If it fails because the worktree is dirty, show
   the files and stop.
4. Report: the worktree removed, the branch kept (its commits and PR are untouched), and
   whether the teardown dropped the feature's test database (`teardown_ok`; on false, point to
   the log). Mention that `/team-dev NNN` would recreate the worktree from the branch.

Never delete the branch or the `.team/` workspace from this skill.
