---
name: team-respond
description: Address the review comments and failing CI checks on a dev-team feature's pull request — fetch the unanswered threads and comments and the red checks with their logs, triage them with the user, turn requested changes into H-tasks and CI failures into C-tasks, run Developer → gates → Reviewer on them, then push and reply on each thread. Use when the user runs /team-respond, asks the team to handle the comments on a feature's PR, or to fix its failing CI.
argument-hint: "<NNN or feature dir>"
---

# /team-respond — handle the PR's review comments and failing CI

Arguments: $ARGUMENTS

Running this skill is the user's explicit request to run the `dev-team` workflow on the PR's
comments. Pushing and posting on the PR are outward-facing: confirm each with the user (step 6).

1. **Resolve the feature** as `/team-clean` does: `<repo>` is the main checkout (the parent of
   `git rev-parse --path-format=absolute --git-common-dir`); the argument is an `NNN` prefix or a
   directory under `<repo>/.team/`. There is no default: if no feature is named, run
   `~/.claude/team/bin/team-status` and ask which one. Call its absolute path `DIR`.

2. **Fetch.** Run `~/.claude/team/bin/team-respond "DIR" fetch`. On `ok: false` show the error and
   stop. If `pr_state` is not `OPEN`, say so and ask whether to go on. Call the printed `round` `N`.
   Its `ci` is the state of the checks on the PR's head (`passing`, `failing`, `pending`, `none`):
   - `stale: true`: the local branch has commits the PR does not have, so the checks are for older
     code. Say so; a failure may already be fixed locally (ask whether to push first with
     `~/.claude/team/bin/team-ship "DIR" --push` and fetch again once CI ran).
   - `pending` with nothing else to do (`count: 0`): ask whether to wait for CI. On a yes, run
     `gh pr checks <pr> --watch --interval 30` in the background, then fetch again (the same round
     is reused).
   With `count: 0` and no pending checks, say there is nothing new on the PR and stop.

3. **Triage.** Read every item (`DIR/respond/round-N/feedback.json`), with the code it points at
   (`path`, `line`) in the worktree. Sort each one into:
   - **change**: it asks for a code change. Write a task in Spanish: what to change and where,
     verifiable, keeping the commenter's intent. An `outdated` thread may already be addressed:
     check the current code first.
   - **question**: it asks something the code can answer. Draft the answer (`reply`), no task.
   - **no action**: approval, thanks, a note for someone else, or something already done. If
     already done, draft a short reply saying where.
   - **check** items (`kind: "check"`, a failing CI check): read its `log` (the failed steps of a
     GitHub Actions job; external checks only have the `url`) and find the failing test or step
     and its error. It becomes a task ("change") unless the failure is not the feature's: a flaky
     or infrastructure error (timeouts, network, a runner problem, missing secrets) or a failure
     also present on the base branch. Those are for the user (re-run it, or fix CI): say why.
     A check task names the step, the failing test or file and the error, and says to fix the
     cause, not the test. Checks never get a reply.
   Show the user a table (id, author or check name, file:line, a short quote or the error, your
   classification and task or reply), then confirm with AskUserQuestion: go ahead with this triage, or adjust it (they say
   what in "Other"). Comments that ask for product decisions or contradict the spec are for the
   user: ask them, do not decide.

4. **Tasks.** Write `DIR/respond/round-N/plan.json`: one object per item,
   `{"key": "<key>", "task": "<task>" | null, "reply": "<answer>" | null}`. Run
   `~/.claude/team/bin/team-respond "DIR" tasks N`. If `tasks_added` is 0, skip to step 6.

5. **Dev loop.** Run `~/.claude/team/bin/team-start "DIR"` and `~/.claude/team/bin/team-config`.
   On `ok: false`, show the error and stop. Call the Workflow tool with
   `scriptPath: ~/.claude/team/dev-team.js` (expand `~`) and `args: { feature_dir: DIR,
   worktree: <worktree>, team_bin: <absolute path of ~/.claude/team/bin>, start_iter: <start_iter>,
   max_iter: <max_iter>, developer: <developer object>, gate_fix_rounds: <gate_fix_rounds>,
   respond: { round: N }, learn: <learn> }`, passing the team-config values exactly as printed.
   The Workflow tool only loads a `scriptPath` it can read: from a project outside this team's
   repo it refuses `~/.claude/team/…`. If it does, read the script (`cat` the resolved path
   `readlink -f ~/.claude/team/dev-team.js`) and pass its full contents as `script` instead, with the
   same `args`. Tell the user they
   can follow it in `/workflows`, and wait for it.
   Record the run as soon as it completes: `~/.claude/team/bin/team-metrics "DIR" run respond` with
   `--tokens`, `--duration-ms` and `--agents` from the completion notice's usage
   (`subagent_tokens`, `duration_ms`, `agent_count`); leave out any it does not give.
   If it ends without approval (`approved: false`) or stopped early, report why and what is
   still open (`DIR/final-report.md`), and ask whether to push and reply anyway or stop there.

6. **Replies.** For each item, draft its reply in the language of the comment, short and
   concrete:
   - change: what changed and the commit (`git -C <worktree> log --oneline` since the round
     started), or, if the Developer left its task unchecked, why (from `dev-log.md`).
   - question / no action: the `reply` from the triage, if any. Items with nothing to say get no
     reply.
   - check: none. The push makes CI run again; the next `/team-respond` fetch shows whether it
     passed.
   Write them to `DIR/respond/round-N/replies.json` as `[{"key": "<key>", "body": "<reply>"}]`.
   Show the user the replies and the commits to push, and confirm with AskUserQuestion (push and
   reply / push only / neither). On a yes, run `~/.claude/team/bin/team-ship "DIR" --push` (it
   only pushes to the open PR; never force) when there are new commits, then
   `~/.claude/team/bin/team-respond "DIR" reply N`.

7. **Report:** the round, the tasks done and still open (H and C), the commits pushed, the replies
   posted (`posted`, `failed` and `replies.log`), and anything left for the user to decide. After a
   push with C-tasks, say that CI runs again and `/team-respond NNN` checks the result. Also the
   conventions the loop learned (`conventions` of the workflow result), if any. Threads are
   not resolved by the team: the reviewer resolves them on GitHub.

Never resolve review threads, dismiss reviews, approve or merge the PR, or re-run, skip or change
CI workflows from this skill.
