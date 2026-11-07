# shellcheck shell=bash
# Dev team limits — the single place to change them. Sourced by the bin/ scripts; the
# dev-team workflow receives the code limit from team-start. Env vars override per run.

# Plan reviews by the Reviewer (each round after the first follows a Planner revision).
TEAM_MAX_PLAN_ROUNDS=${TEAM_MAX_PLAN_ROUNDS:-5}

# Code reviews in the dev loop. The first reviews the initial implementation; each later one
# follows a correction round, so corrections = TEAM_MAX_CODE_REVIEWS - 1.
TEAM_MAX_CODE_REVIEWS=${TEAM_MAX_CODE_REVIEWS:-6}

# Gate repair rounds per iteration: when the official gates fail after a Developer iteration, the
# Developer gets up to this many rounds to fix just the gates (and the gates run again) before the
# Reviewer is called, so a code review is not spent on a red build. 0 sends a red build straight
# to review, as before.
TEAM_GATE_FIX_ROUNDS=${TEAM_GATE_FIX_ROUNDS:-2}

# Extra code reviews a /team-respond round may use on top of the ones already spent, so a feature
# whose loop ended (approved or exhausted) can still go through Developer → gates → Reviewer for
# the PR's comments. The feature's budget is stored as review_budget in state.json.
TEAM_RESPOND_REVIEWS=${TEAM_RESPOND_REVIEWS:-2}

# Models and reasoning effort. Claude roles take a model alias (opus, sonnet, haiku, fable) and
# low|medium|high|xhigh|max; they are passed explicitly wherever the skills and workflows spawn
# an agent, so the session's own model/effort never leaks in. The agent .md frontmatter carries
# the same values only as a fallback for manual use.
TEAM_PLANNER_MODEL=${TEAM_PLANNER_MODEL:-opus}
TEAM_PLANNER_EFFORT=${TEAM_PLANNER_EFFORT:-high}
TEAM_DEVELOPER_MODEL=${TEAM_DEVELOPER_MODEL:-opus}
TEAM_DEVELOPER_EFFORT=${TEAM_DEVELOPER_EFFORT:-medium}

# Reviewer runs through the Codex CLI: an OpenAI model id and Codex's model_reasoning_effort.
TEAM_REVIEW_MODEL=${TEAM_REVIEW_MODEL:-gpt-6-astra}
TEAM_REVIEW_EFFORT=${TEAM_REVIEW_EFFORT:-high}

# Security reviewer: a second Codex pass, only on the first code review of a feature, focused on
# authorization, tenant isolation, untrusted input and data exposure. Runs in parallel with the
# general reviewer; its findings get ids R1-SNN. Set to 0 to disable.
TEAM_SECURITY_REVIEW=${TEAM_SECURITY_REVIEW:-1}

# One git worktree per feature, so several features can be planned and developed at once.
# /team-plan creates it at TEAM_WORKTREE_ROOT/NNN-slug (default: ../<repo>.worktrees/ next to
# the main checkout) on a new branch TEAM_BRANCH_PREFIX<slug> cut from the base. Set
# TEAM_WORKTREES=0 to work in the current checkout instead, as before.
TEAM_WORKTREES=${TEAM_WORKTREES:-1}
TEAM_WORKTREE_ROOT=${TEAM_WORKTREE_ROOT:-}
TEAM_BRANCH_PREFIX=${TEAM_BRANCH_PREFIX:-feat/}

# Run the gates of the same repo one at a time (for projects whose tests can't be isolated with
# TEAM_PARTITION). A <repo>/.team/serialize-gates file turns it on for one repo only.
TEAM_GATES_LOCK=${TEAM_GATES_LOCK:-0}

# Feature NNN gets TEAM_PARTITION = TEAM_PARTITION_BASE + NNN (and MIX_TEST_PARTITION, the same),
# which projects use to name the feature's own test database. The offset keeps it away from the
# small numbers `mix test --partitions` and similar tools already use (base_app_test1, ...).
TEAM_PARTITION_BASE=${TEAM_PARTITION_BASE:-100}
