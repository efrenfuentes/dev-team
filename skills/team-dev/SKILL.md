---
name: team-dev
description: Run the dev team's Developer ↔ Reviewer loop on a planned feature — Developer (Opus) implements and commits, Reviewer (Astra 6 via Codex) reviews, up to 5 correction rounds, then a final report. Use when the user runs /team-dev after /team-plan.
argument-hint: "[feature dir or NNN] [--reset]"
---

# /team-dev — run the development loop

Arguments: $ARGUMENTS

Running this skill is the user's explicit request to run the `dev-team` workflow.

## Steps

1. **Resolve the feature.** `<repo>` is the main checkout (the parent of
   `git rev-parse --path-format=absolute --git-common-dir`), also when the session is inside a
   worktree. If an argument names a directory or an `NNN` prefix, use the matching
   `<repo>/.team/NNN-*`. Otherwise use the highest-numbered `.team/NNN-*` directory
   and tell the user which one you picked. Call its absolute path `DIR`.

2. **Preflight.** Run `~/.claude/team/bin/team-start "DIR"` (append `--reset` if the user
   passed it). It prints JSON. If `ok` is false, show the error and stop. It refuses dirty
   trees and protected branches; never stash or switch branches on the user's behalf.
   If `finished` is true, the loop already ended (approved, or `max_iter` reviews used). Point the
   user to `DIR/final-report.md` and stop; `--reset` starts the loop over (it archives the old
   reviews, reports and dev-log under `DIR/archive/` and strips the correction sections from
   tasks.md; the commits stay).
   If `start_iter` > 1, tell the user the loop resumes at that iteration.

3. **Run the workflow.** Call the Workflow tool with
   `scriptPath: ~/.claude/team/dev-team.js` (expand `~` to the absolute home path) and
   `args: { feature_dir: DIR, worktree: <worktree>, team_bin: <absolute path of ~/.claude/team/bin>, start_iter: <start_iter>, max_iter: <max_iter>, developer: <developer object from ~/.claude/team/bin/team-config>, gate_fix_rounds: <gate_fix_rounds from team-config>, learn: <learn from team-config> }`.
   The Workflow tool only loads a `scriptPath` it can read: from a project outside this team's
   repo it refuses `~/.claude/team/…`. If it does, read the script (`cat` the resolved path
   `readlink -f ~/.claude/team/dev-team.js`) and pass its full contents as `script` instead, with the
   same `args`.
   Pass the `developer` object, `gate_fix_rounds` and `learn` exactly as printed: they hold the
   model, effort, gate-repair limit and conventions learning the user chose.
   It runs in the background; tell the user they can follow it in `/workflows`.

4. **When it completes**, read `DIR/final-report.md` and give the user:
   - approved or incomplete, and how many iterations it took
   - 3–6 lines of the essentials: what was built, and for an incomplete run what is still open
   - what only a person can do before merging (the report's "Pendiente para una persona")
   - the commits (`git -C <worktree> log --oneline <base_sha>..HEAD`), the branch and the worktree path
   - the paths to `final-report.md`, `review-report.md` and `dev-log.md`
   - the conventions it learned (`conventions.added` and `.reinforced` of the result), if any,
     and the path of `conventions.md`: the user can edit or delete any rule
   If the workflow stopped early (`stopped_early`), say why and how to resume: fix the cause,
   then run `/team-dev` again, which continues from the next iteration.

Never push or open a PR from this skill. The user decides that after reading the report, and
`/team-ship NNN` pushes the branch and opens the PR, `/team-respond NNN` handles its review
comments and `/team-sync NNN` updates the branch with its base. Once the branch is merged, `/team-clean NNN`
removes the worktree.
