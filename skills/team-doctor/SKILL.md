---
name: team-doctor
description: Check that a repo is ready for the dev team before starting — Codex and gh installed and logged in, base branch, detected stack and its tools, which gates and setup will run, test-database isolation for parallel features, ignored files a worktree would lack, and CLAUDE.md. Use when the user runs /team-doctor, sets the team up in a new repo, or a cycle failed for an environment reason.
argument-hint: ""
---

# /team-doctor — is this repo ready for the team?

1. Run `~/.claude/team/bin/team-doctor --json` from the repo. It only reads.
2. Show a short table: one row per check (status, what it checked, the detail). Put `fail`
   first, then `warn`; the `ok` and `info` rows can be one line each.
3. For each `fail` and `warn`, say what to do (its `fix`) and why it matters for the team:
   - `fail` blocks the team (no Reviewer, no base branch, the stack's tools missing).
   - `warn` works but costs later: no gates means reviews of untested code; a shared test database
     makes parallel features break each other's tests; missing `.env` files make the worktree's
     tests fail for reasons that are not the feature's.
4. Offer to fix what is local and safe, each one only with the user's yes (AskUserQuestion):
   - `files`: append the listed paths to `<repo>/.team/worktree-files` (create it; `.team/` is
     git-excluded, so this changes nothing in the repo's history).
   - `partition` for a repo that cannot isolate its test database: create
     `<repo>/.team/serialize-gates`.
   - `gates` with no gates: draft `<repo>/.team/gates.sh` from the commands the repo's CI or README
     use to test and lint, show it, and write it only on a yes.
   Anything else (installing tools, logging in, editing the project's config or a CLAUDE.md) is
   the user's: give the command, do not run it.
5. End with the verdict: ready (no `fail`), or what must be fixed before `/team-plan` or `/team-fix`.
