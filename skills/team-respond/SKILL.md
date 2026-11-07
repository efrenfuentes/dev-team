---
name: team-respond
description: Address the review comments on a dev-team feature's pull request — fetch the unanswered threads and comments, triage them with the user, turn requested changes into H-tasks, run Developer → gates → Reviewer on them, then push and reply on each thread. Use when the user runs /team-respond or asks the team to handle the comments on a feature's PR.
argument-hint: "<NNN or feature dir>"
---

# /team-respond — handle the PR's review comments

Arguments: $ARGUMENTS

Running this skill is the user's explicit request to run the `dev-team` workflow on the PR's
comments. Pushing and posting on the PR are outward-facing: confirm each with the user (step 6).

1. **Resolve the feature** as `/team-clean` does: `<repo>` is the main checkout (the parent of
   `git rev-parse --path-format=absolute --git-common-dir`); the argument is an `NNN` prefix or a
   directory under `<repo>/.team/`. There is no default: if no feature is named, run
   `~/.claude/team/bin/team-status` and ask which one. Call its absolute path `DIR`.

2. **Fetch.** Run `~/.claude/team/bin/team-respond "DIR" fetch`. On `ok: false` show the error and
   stop. With `count: 0`, say there is nothing new on the PR and stop. If `pr_state` is not
   `OPEN`, say so and ask whether to go on. Call the printed `round` `N`.

3. **Triage.** Read every item (`DIR/respond/round-N/feedback.json`), with the code it points at
   (`path`, `line`) in the worktree. Sort each one into:
   - **change**: it asks for a code change. Write a task in Spanish: what to change and where,
     verifiable, keeping the commenter's intent. An `outdated` thread may already be addressed:
     check the current code first.
   - **question**: it asks something the code can answer. Draft the answer (`reply`), no task.
   - **no action**: approval, thanks, a note for someone else, or something already done. If
     already done, draft a short reply saying where.
   Show the user a table (id, author, file:line, a short quote, your classification and task or
   reply), then confirm with AskUserQuestion: go ahead with this triage, or adjust it (they say
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
   respond: { round: N } }`, passing the team-config values exactly as printed. Tell the user they
   can follow it in `/workflows`, and wait for it.
   If it ends without approval (`approved: false`) or stopped early, report why and what is
   still open (`DIR/final-report.md`), and ask whether to push and reply anyway or stop there.

6. **Replies.** For each item, draft its reply in the language of the comment, short and
   concrete:
   - change: what changed and the commit (`git -C <worktree> log --oneline` since the round
     started), or, if the Developer left its task unchecked, why (from `dev-log.md`).
   - question / no action: the `reply` from the triage, if any. Items with nothing to say get no
     reply.
   Write them to `DIR/respond/round-N/replies.json` as `[{"key": "<key>", "body": "<reply>"}]`.
   Show the user the replies and the commits to push, and confirm with AskUserQuestion (push and
   reply / push only / neither). On a yes, run `~/.claude/team/bin/team-ship "DIR" --push` (it
   only pushes to the open PR; never force) when there are new commits, then
   `~/.claude/team/bin/team-respond "DIR" reply N`.

7. **Report:** the round, the tasks done and still open, the commits pushed, the replies posted
   (`posted`, `failed` and `replies.log`), and anything left for the user to decide. Threads are
   not resolved by the team: the reviewer resolves them on GitHub.

Never resolve review threads, dismiss reviews, approve or merge the PR from this skill.
