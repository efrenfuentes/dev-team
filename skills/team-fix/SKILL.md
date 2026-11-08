---
name: team-fix
description: Fix a bug from a GitHub issue with the dev team, test first — reads the issue, the Planner finds the cause and writes a short spec and tasks, the Developer writes a regression test that fails, then fixes it, and the Reviewer checks both; the PR closes the issue. Use when the user runs /team-fix with an issue number or URL, or asks the team to fix a GitHub issue.
argument-hint: "<issue number or URL> [--base <ref>] [--plan-only] [--review-plan]"
---

# /team-fix — fix a GitHub issue, test first

Arguments: $ARGUMENTS

Running this skill is the user's explicit request to plan the fix and run the `dev-team` workflow
on it. Pushing and opening the PR stay with `/team-ship`.

1. **Issue.** Run `~/.claude/team/bin/team-issue <issue> [<base>]` from the repo. On `ok: false`
   show the error and stop. Call `feature_dir` `DIR`.
   - `existing: true`: the issue already has a feature. Say so and resume it: if `DIR/tasks.md`
     exists go to step 4, else step 2.
   - If `issue.state` is not `OPEN`, say so and ask whether to go on.
   If the user has not run `/team-doctor` in this repo and a step fails for an environment
   reason, suggest it.

2. **Plan the fix.** Run `~/.claude/team/bin/team-config` and spawn the `team-planner` agent with
   its `planner.model` and `planner.effort`: mode `fix`, the feature directory `DIR`. It writes
   spec.md, plan.md and tasks.md (T1 is always the regression test) and returns open questions,
   usually none.

3. **Clarify.** If there are questions, ask them with AskUserQuestion (the planner's
   recommendation first, with "(Recommended)") and spawn `team-planner` again: mode `fix`, `DIR`,
   and the answers verbatim. Do not answer them yourself.
   With `--review-plan`, run the plan review as `/team-plan` step 5 does (the `plan-review`
   workflow). Without it, the plan of a fix is not reviewed on its own: the Reviewer judges the
   test and the fix in the dev loop.

4. **Show the plan in a few lines:** the cause (`## Causa` of spec.md, with file:line, and
   whether it is confirmed or a hypothesis), the regression test T1, and the fix tasks. With
   `--plan-only`, stop here: `/team-dev NNN` runs it later.

5. **Dev loop.** Run `~/.claude/team/bin/team-start "DIR"` and `~/.claude/team/bin/team-config`,
   then call the Workflow tool exactly as `/team-dev` step 3 does (the same `args`, the same
   fallback to an inline `script` if the `scriptPath` is refused). Record the run when it
   completes: `~/.claude/team/bin/team-metrics "DIR" run fix` with `--tokens`, `--duration-ms`
   and `--agents` from the completion notice's usage (`subagent_tokens`, `duration_ms`,
   `agent_count`); leave out any it does not give.
   If the Developer stops blocked on T1 (the test passed before the fix, so the bug is not where
   the spec says), report what it found in `dev-log.md` and stop: that needs the user.

6. **Report** as `/team-dev` step 4 does, plus: the regression test (file and the commit that
   added it), the fix commit, and that `/team-ship NNN` opens the PR with `Closes #<n>`, so
   merging it closes the issue.

Never comment on, label, assign or close the issue from this skill.
