---
name: team-status
description: Show the status of every dev-team feature in the current repo — phase (planning, planned, developing, responding, approved, incomplete, merged, closed), branch, plan rounds, code iterations, open tasks, items that need a person, and the PR with its CI and unanswered comments. Use when the user runs /team-status or asks where the team's features stand.
argument-hint: "[--json] [--offline] [--metrics]"
---

# /team-status — where every feature stands

Arguments: $ARGUMENTS

1. Run `~/.claude/team/bin/team-status` from the repo (pass `--json` only if the user asked for
   JSON, `--offline` only if they asked not to query GitHub). It reads `<repo>/.team/NNN-*/` and
   prints one row per feature; for the features with a PR it also asks GitHub for the PR's
   state, its CI and the comments nobody answered yet (columns CI and COMENTARIOS; `-` when it
   could not ask).
2. Show the table as is. Then, in at most one line per feature that is not `approved`, say what
   the next step is:
   - `planning`: the plan is not written yet → `/team-plan NNN` resumes it.
   - `planned`: ready for `/team-dev NNN` (it runs in the feature's worktree).
   - `developing`: the loop was interrupted → `/team-dev NNN` resumes at the next iteration.
   - `responding`: a `/team-respond` round added PR comments as tasks and its loop has not run
     its first review yet → `/team-respond NNN` again, or `/team-dev NNN` to just run the loop.
   - `incomplete`: reviews exhausted → read `final-report.md`, fix by hand in its worktree or `/team-dev NNN --reset`.
   - `merged`: the PR is merged → if it still has a worktree, `/team-clean NNN`, or `/team-clean
     --merged` for all of them at once.
   - `closed`: the PR was closed without merging → ask whether it is abandoned (`/team-clean NNN`).
   For an open PR, whatever the phase: CI `FALLA` (the failing checks are in `--json`, `ci_failed`)
   or COMENTARIOS above 0 → `/team-respond NNN`. CI marked `(viejo)` ran on an older commit than
   the local branch: the branch has unpushed commits.
   For an `approved` feature without a PR, `/team-ship NNN` opens it; with a PR, `/team-respond NNN`
   handles its review comments and failing CI, and `/team-sync NNN` brings in the base's new
   commits. Once the branch is merged, `/team-clean NNN` removes the worktree. The worktree path of each feature is in `--json`; give it when
   the user asks where a feature's code is.
With `--metrics`, run `~/.claude/team/bin/team-status --metrics` instead and show its table and
totals: per feature, plan rounds, iterations until approval, Reviewer findings by severity
(blocker/major/minor/human), gate repair rounds, R/H/C tasks, recorded tokens and hours from
creation to approval and to merge. Point out what stands out (a feature that needed many
iterations, many gate repairs) and, if the user asks, what to tune: models and efforts in
`~/.claude/team/config.sh`, or rules for `.team/conventions.md`. Then stop.

3. If any feature has items "para persona", point to `tasks.md` (`## Verificación manual`) and
   the "Requiere a una persona" sections of `review-report.md`.

Do not run the plan or dev loops from this skill.
