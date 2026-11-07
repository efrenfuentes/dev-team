---
name: team-ship
description: Push a dev-team feature's branch and open its pull request with gh — body from the final report, a checklist of what a person still has to verify, and the commits. Use when the user runs /team-ship or asks to push a team feature or open its PR.
argument-hint: "<NNN or feature dir> [--draft]"
---

# /team-ship — push the branch and open the PR

Arguments: $ARGUMENTS

Running this skill is the user's request to ship this one feature, but the push and the PR are
outward-facing: confirm with the user before step 4, every time.

1. **Resolve the feature** as `/team-clean` does: `<repo>` is the main checkout (the parent of
   `git rev-parse --path-format=absolute --git-common-dir`); the argument is an `NNN` prefix or a
   directory under `<repo>/.team/`. There is no default: if no feature is named, run
   `~/.claude/team/bin/team-status` and ask which one. Call its absolute path `DIR`.

2. **Preflight.** Run `~/.claude/team/bin/team-ship "DIR" --check`. If `ok` is false, show the
   error and stop: never commit, stash, rebase or force-push to get past it. It also writes
   `DIR/pr-body.md` the first time (it never overwrites an edited one).

3. **Prepare the title.** The default `title` is the spec's heading. Propose a Conventional Commit
   style title from it and the commits (`feat(scope): …`, or `fix(…)` if the work is a fix),
   under ~70 characters, in the language of the commits.

4. **Confirm** with AskUserQuestion. Show, in the question itself: `branch` → `base` on
   `remote`, the number of commits, the cycle `status`, the proposed title, the path of
   `pr-body.md` (they can edit it before answering), and `existing_pr` if there is one.
   - `approved`: recommend a ready PR.
   - `incomplete`, `developing` or `not_reviewed`: say plainly that the Reviewer did not approve
     it, and recommend a draft.
   - If `existing_pr` is set, the only action is to push: the open PR updates itself.
   Options: open the PR (ready), open it as a draft, cancel. Honor `--draft` from the arguments
   as the recommended choice.

5. **Ship.** On a yes, run
   `~/.claude/team/bin/team-ship "DIR" --push --title "<title>"` (add `--draft` if chosen). If it
   fails, show the error and the log it names.

6. **Report:** the PR URL, whether it was created or an existing PR was updated, draft or not,
   and the unchecked items under "Verificación manual pendiente" in the body: those are what a
   person must do before merging. Mention that `/team-clean NNN` removes the worktree once it is
   merged.

Never force-push, merge the PR, delete the branch, or request reviewers from this skill.
