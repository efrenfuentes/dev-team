---
name: team-status
description: Show the status of every dev-team feature in the current repo — phase (planning, planned, developing, approved, incomplete), branch, plan rounds, code iterations, open tasks and items that need a person. Use when the user runs /team-status or asks where the team's features stand.
argument-hint: "[--json]"
---

# /team-status — where every feature stands

Arguments: $ARGUMENTS

1. Run `~/.claude/team/bin/team-status` from the repo (pass `--json` only if the user asked for
   JSON). It reads `<repo>/.team/NNN-*/` and prints one row per feature.
2. Show the table as is. Then, in at most one line per feature that is not `approved`, say what
   the next step is:
   - `planning`: the plan is not written yet → `/team-plan NNN` resumes it.
   - `planned`: ready for `/team-dev NNN` (it runs in the feature's worktree).
   - `developing`: the loop was interrupted → `/team-dev NNN` resumes at the next iteration.
   - `incomplete`: reviews exhausted → read `final-report.md`, fix by hand in its worktree or `/team-dev NNN --reset`.
   For an `approved` feature whose worktree still exists, mention that `/team-clean NNN` removes
   it once the branch is merged. The worktree path of each feature is in `--json`; give it when
   the user asks where a feature's code is.
3. If any feature has items "para persona", point to `tasks.md` (`## Verificación manual`) and
   the "Requiere a una persona" sections of `review-report.md`.

Do not run the plan or dev loops from this skill.
