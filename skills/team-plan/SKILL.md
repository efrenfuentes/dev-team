---
name: team-plan
description: Start a feature with the dev team — Planner (Opus) explores, asks the user clarifying questions, writes spec/plan/tasks, and the Reviewer (Astra 6 via Codex) reviews the plan. Use when the user runs /team-plan or asks the team to plan a feature.
argument-hint: <feature description> [--base origin/main]
---

# /team-plan — plan a feature with the dev team

Request: $ARGUMENTS

Scripts live in `~/.claude/team/bin/`. The feature workspace is `<repo>/.team/NNN-<slug>/`,
which is git-excluded locally. `<repo>` is always the main checkout, also when the session is
inside one of its worktrees. The feature's code gets its own git worktree (the `worktree` path
in `DIR/state.json`), on a new branch cut from the base, so several features can be in progress
at once without touching the checkout the user is working in.

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
   It also creates the worktree and branch and runs the worktree setup (dependencies, the
   feature's test database). If it warns that the setup failed, tell the user and show the
   last lines of `DIR/logs/setup.log`, but keep planning: the plan only reads code, and
   `/team-dev` retries the setup before it starts. If `team-init` fails (for example, the branch
   already exists), show the error and stop.

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
   The Workflow tool only loads a `scriptPath` it can read: from a project outside this team's
   repo it refuses `~/.claude/team/…`. If it does, read the script (`cat` the resolved path
   `readlink -f ~/.claude/team/plan-review.js`) and pass its full contents as `script` instead, with the
   same `args`.
   The workflow owns the Reviewer ↔ Planner loop and its limit. Do not run review rounds or
   planner revisions yourself, before or after it. Tell the user they can follow it in
   `/workflows`, and wait for it to complete. Record the run as soon as it completes: `~/.claude/team/bin/team-metrics "DIR" run plan` with
   `--tokens`, `--duration-ms` and `--agents` from the completion notice's usage
   (`subagent_tokens`, `duration_ms`, `agent_count`); leave out any it does not give.
   If it stopped early, report why; running
   `/team-plan` again on the same feature resumes at the next round.

6. **Hand off to the user.** Summarize in a few lines: the requirements, the number of
   tasks per phase, the plan-review outcome and any open findings, the items under
   `## Verificación manual (persona)` in tasks.md (things only the user can do), plus the paths
   to `spec.md`, `plan.md`, `tasks.md` and `plan-review.md`. Also give the worktree path and its
   branch, and the gates the loop will run: `~/.claude/team/bin/team-gates "DIR" --which` (a
   `stack` source means the stack's default gates; `configured: false` means no gates at all, so
   suggest a `.team/gates.sh`). Ask them to review the plan, then start development with `/team-dev NNN` (from any
   checkout: it runs in the feature's worktree).

Do not write code or start the dev loop from this skill.
