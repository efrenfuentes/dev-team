---
name: team-sync
description: Bring a dev-team feature branch up to date with its base branch — rebase if it was never pushed, merge if it was (never a force push), the Developer resolves any conflicts, then setup and gates run again. Use when the user runs /team-sync or asks to update, rebase or sync a team feature with main.
argument-hint: "<NNN or feature dir> [--rebase|--merge]"
---

# /team-sync — update a feature with its base branch

Arguments: $ARGUMENTS

1. **Resolve the feature** as `/team-clean` does: `<repo>` is the main checkout (the parent of
   `git rev-parse --path-format=absolute --git-common-dir`); the argument is an `NNN` prefix or a
   directory under `<repo>/.team/`. There is no default: if no feature is named, run
   `~/.claude/team/bin/team-status` and ask which one. Call its absolute path `DIR`.
   Do not sync a feature whose `/team-dev` or `/team-respond` loop is running right now (check
   `/workflows` if unsure): the Developer would be committing on the branch while it moves.

2. **Start.** Run `~/.claude/team/bin/team-sync "DIR" start` with `--rebase` or `--merge` only if
   the user passed one, in the background (`run_in_background: true`): when there are no
   conflicts it goes straight on to the setup and the gates, which can take many minutes. Read
   the last line of its output (JSON) when it completes.
   - `ok: false`: show the error and stop. Never stash, reset, abort or force anything to get past it.
   - `status: "up_to_date"`: say so and stop.
   - `status: "synced"`: go to step 4.
   - `status: "conflicts"`: go to step 3.

3. **Conflicts.** The merge of the base is in progress in the worktree, with the conflicted
   `files`. Run `~/.claude/team/bin/team-config` and spawn the `team-developer` agent with its
   `developer.model` and `developer.effort` as the Agent tool's `model` and `effort`, and this
   task:

   > Feature directory: DIR. Worktree: `<worktree>`. A merge of `<base_ref>` into the feature
   > branch stopped with conflicts in: `<files>`. Resolve every conflict so that both sides
   > survive: the base's changes as they are, and the feature as `DIR/spec.md` describes it. Read
   > the base's side with `git -C <worktree> log --oneline HEAD..MERGE_HEAD -- <file>`. Do not
   > change anything the conflicts do not need. Run the tests of the touched areas through
   > `~/.claude/team/bin/team-exec DIR …`, then `git -C <worktree> add <files>` and
   > `git -C <worktree> commit --no-edit`. Append a `## Sync con <base_ref>` section to
   > `DIR/dev-log.md`: each file, what each side changed and how you combined them. If a conflict
   > needs a product decision, leave the merge unfinished and explain it: never run
   > `git merge --abort`, `reset` or a force push.

   When it returns, run `~/.claude/team/bin/team-sync "DIR" finish` in the background. If it
   still reports conflicts or an uncommitted merge, show the Developer's explanation and the
   files to the user and stop: they resolve the rest in the worktree and run
   `team-sync DIR finish` themselves.

4. **Report:** the `strategy` (rebase or merge), how many base commits came in (`behind`),
   whether there were conflicts and how they were resolved (the dev-log section), the `setup`
   result (on failure, the end of its log), and the gates (`gates.passed`; on failure, the end of
   `gates.log`). With failing gates, suggest `/team-dev NNN` if the loop still has iterations, or
   fixing them in the worktree.
   If `pushed_branch` is true, the remote branch (and its PR) does not have the merge yet: ask
   with AskUserQuestion whether to push it now, and on a yes run
   `~/.claude/team/bin/team-ship "DIR" --push` (with an open PR it only pushes). A rebased branch
   was never pushed, so there is nothing to push.

Never force-push, and never rebase a branch that is already on the remote.
