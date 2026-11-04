---
name: team-plan
description: Start a feature with the dev team — Planner (Opus) explores, asks the user clarifying questions, writes spec/plan/tasks, and the Reviewer (Astra 6 via Codex) reviews the plan. Use when the user runs /team-plan or asks the team to plan a feature.
argument-hint: <feature description> [--base origin/main]
---

# /team-plan — plan a feature with the dev team

Request: $ARGUMENTS

Scripts live in `~/.claude/team/bin/`. The feature workspace is `<repo>/.team/NNN-<slug>/`,
which is git-excluded locally.

Models and efforts are set by the user in `~/.claude/team/config.sh`. Run
`~/.claude/team/bin/team-config` first. Every time you spawn `team-planner`, pass its
`planner.model` and `planner.effort` as the Agent tool's `model` and `effort`: the user
explicitly asked for these settings.

## Steps

0. **Resume?** If the arguments are just an existing `.team/NNN-*` directory or `NNN` prefix,
   and that directory already has `plan.md` and `tasks.md`, this is a resume. Set `DIR` to it
   and go straight to step 5.

1. **Workspace.** Pick a short kebab-case slug from the request. Run
   `~/.claude/team/bin/team-init <slug> [base_ref]` (base defaults to the remote's default
   branch; pass `--base` from the arguments if given). Call the printed absolute path `DIR`.

2. **Discover.** Spawn the `team-planner` agent: mode `discover`, the feature directory `DIR`,
   and the full feature request verbatim. It drafts `spec.md` and returns open questions.

3. **Clarify with the user.** If there are questions, ask them with AskUserQuestion (up to 4
   per call, putting the planner's recommendation first with "(Recommended)"). Do not answer
   them yourself.

4. **Plan.** Spawn `team-planner` again: mode `plan`, `DIR`, and the user's answers verbatim.

5. **Plan review (workflow).** Running this skill is the user's explicit request to run the
   `plan-review` workflow. Run `~/.claude/team/bin/team-config "DIR"`. If `plan_approved` is
   true, skip to step 6. Otherwise call the Workflow tool with
   `scriptPath: ~/.claude/team/plan-review.js` (expand `~` to the absolute home path) and
   `args: { feature_dir: DIR, team_bin: <absolute path of ~/.claude/team/bin>, max_rounds: <max_plan_rounds>, start_round: <next_plan_round>, planner: <planner object> }`.
   The workflow owns the Reviewer ↔ Planner loop and its limit. Do not run review rounds or
   planner revisions yourself, before or after it. Tell the user they can follow it in
   `/workflows`, and wait for it to complete. If it stopped early, report why; running
   `/team-plan` again on the same feature resumes at the next round.

6. **Hand off to the user.** Summarize in a few lines: the requirements, the number of
   tasks per phase, the plan-review outcome and any open findings, the items under
   `## Verificación manual (persona)` in tasks.md (things only the user can do), plus the paths
   to `spec.md`, `plan.md`, `tasks.md` and `plan-review.md`. Ask them to review the plan, then start
   development with `/team-dev` (from a clean feature branch).

Do not write code or start the dev loop from this skill.
