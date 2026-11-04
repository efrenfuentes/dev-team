export const meta = {
  name: 'plan-review',
  description: 'Reviewer (Astra 6 via Codex) ↔ Planner (Opus) loop over spec/plan/tasks, capped by TEAM_MAX_PLAN_ROUNDS',
  whenToUse: 'From /team-plan, after the Planner wrote spec.md, plan.md and tasks.md',
  phases: [
    { title: 'Ronda 1' }, { title: 'Ronda 2' }, { title: 'Ronda 3' },
    { title: 'Ronda 4' }, { title: 'Ronda 5' },
  ],
}

// args: { feature_dir, team_bin, max_rounds, planner: {model, effort} (all from team-config),
//         start_round?: number (resume) }
const DIR = args.feature_dir
const BIN = args.team_bin
const MAX_ROUNDS = args.max_rounds || 5
const PLANNER = args.planner || { model: 'opus', effort: 'high' }
const START = args.start_round || 1

const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['APPROVED', 'CHANGES_REQUESTED', 'ERROR'] },
    blocking: { type: 'integer' },
    human: { type: 'integer' },
    minor: { type: 'integer' },
    summary: { type: 'string' },
    error: { type: 'string' },
  },
  required: ['verdict'],
}

let approved = false
let rounds = START - 1
let lastReview = null
let stopReason = null

for (let r = START; r <= MAX_ROUNDS; r++) {
  phase(`Ronda ${r}`)

  const review = await agent(`Run this command from the repository root:\n\n${BIN}/team-review plan "${DIR}" ${r}`, {
    agentType: 'team-runner', model: 'haiku', effort: 'low', label: `reviewer:plan-${r}`, phase: `Ronda ${r}`, schema: REVIEW_SCHEMA,
  })
  rounds = r
  if (!review || review.verdict === 'ERROR') { stopReason = `el Reviewer falló en la ronda ${r}: ${review?.error || 'sin respuesta'}`; break }
  lastReview = review
  log(`Ronda ${r}/${MAX_ROUNDS}: Reviewer → ${review.verdict} (${review.blocking ?? '?'} bloqueantes/major, ${review.minor ?? '?'} menores)`)

  if (review.verdict === 'APPROVED') { approved = true; break }
  if (r === MAX_ROUNDS) break // no revision after the last review: nobody would check it

  const revised = await agent(`Mode: revise
Feature directory: ${DIR}
Address round ${r} in plan-review.md. Return a short list of what you changed and any finding you rejected (with why).`, {
    agentType: 'team-planner', model: PLANNER.model, effort: PLANNER.effort, label: `planner:revise-${r}`, phase: `Ronda ${r}`,
  })
  if (!revised) { stopReason = `el Planner falló al revisar la ronda ${r}`; break }
}

return {
  approved,
  rounds,
  max_rounds: MAX_ROUNDS,
  stopped_early: stopReason,
  last_summary: lastReview?.summary || null,
  plan_review: `${DIR}/plan-review.md`,
}
