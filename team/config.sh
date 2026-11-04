# Dev team limits — the single place to change them. Sourced by the bin/ scripts; the
# dev-team workflow receives the code limit from team-start. Env vars override per run.

# Plan reviews by the Reviewer (each round after the first follows a Planner revision).
TEAM_MAX_PLAN_ROUNDS=${TEAM_MAX_PLAN_ROUNDS:-5}

# Code reviews in the dev loop. The first reviews the initial implementation; each later one
# follows a correction round, so corrections = TEAM_MAX_CODE_REVIEWS - 1.
TEAM_MAX_CODE_REVIEWS=${TEAM_MAX_CODE_REVIEWS:-6}

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
