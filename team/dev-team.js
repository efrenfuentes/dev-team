export const meta = {
  name: 'dev-team',
  description: 'Developer (Opus) ↔ Reviewer (Astra 6 via Codex) loop over a planned feature, capped by TEAM_MAX_CODE_REVIEWS, then a final report',
  whenToUse: 'After /team-plan produced spec.md, plan.md and tasks.md in a .team/ feature directory',
  phases: [
    { title: 'Iteración 1' }, { title: 'Iteración 2' }, { title: 'Iteración 3' },
    { title: 'Iteración 4' }, { title: 'Iteración 5' }, { title: 'Iteración 6' },
    { title: 'Cierre' },
  ],
}

// args: { feature_dir, team_bin, max_iter + start_iter (from team-start),
//         developer: {model, effort} (from team-config) }
const DIR = args.feature_dir
const BIN = args.team_bin
const MAX_ITER = args.max_iter || 6
const DEVELOPER = args.developer || { model: 'opus', effort: 'medium' }
const START = args.start_iter || 1

const DEV_SCHEMA = {
  type: 'object',
  properties: {
    completed_tasks: { type: 'array', items: { type: 'string' } },
    pending_tasks: { type: 'array', items: { type: 'string' } },
    commits: { type: 'array', items: { type: 'string' } },
    blocked: { type: 'boolean' },
    needs_human: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['completed_tasks', 'pending_tasks', 'commits', 'blocked', 'notes'],
}
const GATES_SCHEMA = {
  type: 'object',
  properties: { passed: { type: 'boolean' }, configured: { type: 'boolean' }, log: { type: 'string' } },
  required: ['passed'],
}
const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['APPROVED', 'CHANGES_REQUESTED', 'REPORTED', 'ERROR'] },
    blocking: { type: 'integer' },
    human: { type: 'integer' },
    minor: { type: 'integer' },
    unresolved_previous: { type: 'integer' },
    summary: { type: 'string' },
    error: { type: 'string' },
  },
  required: ['verdict'],
}

const run = (cmd) => `Run this command from the repository root:\n\n${cmd}`

const devPrompt = (i) => `Feature directory: ${DIR}
Iteration ${i} of ${MAX_ITER}${i === MAX_ITER ? ' — the LAST one; the reviewer will not request further changes after this.' : '.'}

${i === 1
    ? 'Implement the plan: work the unchecked tasks in tasks.md in order.'
    : `The reviewer requested changes. Start with every unchecked R-task in tasks.md: the ones under the newest "## Correcciones — revisión ${i - 1}" and any earlier one marked "reabierta en revisión ${i - 1}" (read the matching section of review-report.md for the details). Then any other unchecked task.`}

Follow your iteration procedure: implement, test, mark [x], commit, append to dev-log.md.
Return the task ids you completed, the ones still pending, the ones only a person can do (needs_human), and your commit SHAs.`

let approved = false
let last = START - 1
let stopReason = null

for (let i = START; i <= MAX_ITER; i++) {
  phase(`Iteración ${i}`)

  const dev = await agent(devPrompt(i), { agentType: 'team-developer', model: DEVELOPER.model, effort: DEVELOPER.effort, label: `developer:${i}`, phase: `Iteración ${i}`, schema: DEV_SCHEMA })
  if (!dev) { stopReason = `el Developer falló en la iteración ${i}`; break }
  log(`Iteración ${i}: Developer completó ${dev.completed_tasks.length} tareas, ${dev.pending_tasks.length} pendientes, ${dev.commits.length} commits${dev.blocked ? ' (BLOQUEADO)' : ''}${dev.needs_human?.length ? ` · requieren persona: ${dev.needs_human.join(', ')}` : ''}`)

  const gates = await agent(run(`${BIN}/team-gates "${DIR}" ${i}`), {
    agentType: 'team-runner', model: 'haiku', effort: 'low', label: `gates:${i}`, phase: `Iteración ${i}`, schema: GATES_SCHEMA,
  })
  log(`Iteración ${i}: gates ${gates?.passed ? 'OK' : 'FALLARON'}${gates && gates.configured === false ? ' (sin gates configurados)' : ''}`)

  const review = await agent(run(`${BIN}/team-review code "${DIR}" ${i}`), {
    agentType: 'team-runner', model: 'haiku', effort: 'low', label: `reviewer:${i}`, phase: `Iteración ${i}`, schema: REVIEW_SCHEMA,
  })
  last = i
  if (!review || review.verdict === 'ERROR') { stopReason = `el Reviewer falló en la iteración ${i}: ${review?.error || 'sin respuesta'}`; break }
  log(`Iteración ${i}: Reviewer → ${review.verdict} (${review.blocking ?? '?'} bloqueantes/major, ${review.minor ?? '?'} menores${review.human ? `, ${review.human} para una persona` : ''})`)

  if (review.verdict === 'APPROVED') { approved = true; break }
}

phase('Cierre')
if (stopReason) log(`Ciclo detenido: ${stopReason}`)

let report = null
if (last >= 1) {
  report = await agent(run(`${BIN}/team-review final "${DIR}" ${last} ${approved ? 'approved' : 'incomplete'}`), {
    agentType: 'team-runner', model: 'haiku', effort: 'low', label: 'reviewer:final', phase: 'Cierre', schema: REVIEW_SCHEMA,
  })
}

return {
  approved,
  iterations: last,
  stopped_early: stopReason,
  final_report: report && report.verdict === 'REPORTED' ? `${DIR}/final-report.md` : null,
  review_report: `${DIR}/review-report.md`,
}
