export const meta = {
  name: 'dev-team',
  description: 'Developer (Opus) ↔ Reviewer (Astra 6 via Codex) loop over a planned feature, capped by TEAM_MAX_CODE_REVIEWS, then a final report',
  whenToUse: 'After /team-plan produced spec.md, plan.md and tasks.md in a .team/ feature directory',
  // meta must be a literal, so the phases cannot follow TEAM_MAX_CODE_REVIEWS: these cover the
  // default (6) plus a /team-respond round (TEAM_RESPOND_REVIEWS = 2). An iteration beyond them
  // still runs; the Workflow tool just gives its phase() its own progress group.
  phases: [
    { title: 'Iteración 1' }, { title: 'Iteración 2' }, { title: 'Iteración 3' },
    { title: 'Iteración 4' }, { title: 'Iteración 5' }, { title: 'Iteración 6' },
    { title: 'Iteración 7' }, { title: 'Iteración 8' },
    { title: 'Cierre' },
    { title: 'Aprendizaje' },
  ],
}

// args: { feature_dir, team_bin, worktree + max_iter + start_iter (from team-start),
//         developer: {model, effort} + gate_fix_rounds (from team-config),
//         respond?: {round} when /team-respond opened a round of PR comments or failing checks,
//         learn?: {model, effort} | false (from team-config) }
const DIR = args.feature_dir
const BIN = args.team_bin
const WT = args.worktree || null
// The rules themselves (team-exec, git -C, absolute paths, test-first for fixes) live once, in
// agents/team-developer.md; the prompt only carries what varies per feature and iteration.
const WORKTREE_RULES = WT
  ? `Worktree (the code you change, test and commit): ${WT}
Team scripts: ${BIN} (team-exec, team-gates). Follow your "Where you work" rules.
`
  : ''
const MAX_ITER = args.max_iter || 6
const DEVELOPER = args.developer || { model: 'opus', effort: 'medium' }
const START = args.start_iter || 1
const RESPOND = args.respond || null
const GATE_FIX_ROUNDS = Number.isInteger(args.gate_fix_rounds) ? args.gate_fix_rounds : 2
const LEARN = args.learn === false ? null : (args.learn || { model: 'sonnet', effort: 'medium' })
// The feature dir is <main>/.team/NNN-slug: the repo's learned conventions sit next to it.
const CONVENTIONS = `${DIR.replace(/\/+$/, '').replace(/\/[^/]+$/, '')}/conventions.md`

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
  properties: { passed: { type: 'boolean' }, configured: { type: 'boolean' }, exit_code: { type: 'integer' }, log: { type: 'string' } },
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

// team-await runs the command once, detached, and waits for it across foreground Bash calls:
// a pending answer means "call it again", never "it failed" (see agents/team-runner.md).
const run = (cmd) => `Run this command from the repository root:\n\n${BIN}/team-await ${cmd}\n\nRun it in the FOREGROUND with the Bash tool's timeout set to 600000 ms; never use run_in_background. If its last line is {"team_await":"pending",…}, run the exact same command again (it keeps waiting for the same run, it never starts a second one), until it prints the command's own JSON; then report that JSON.`

const devPrompt = (i) => `Feature directory: ${DIR}
${WORKTREE_RULES}Iteration ${i} of ${MAX_ITER}${i === MAX_ITER ? ' — the LAST one; the reviewer will not request further changes after this.' : '.'}

${RESPOND && i === START
    ? `The pull request got feedback. It is the unchecked tasks under "## Comentarios de la PR — ronda ${RESPOND.round}" in tasks.md: H${RESPOND.round}-NN are comments from a person, whose full text (thread, file, line, author) is in ${DIR}/respond/round-${RESPOND.round}/feedback.json, matched by the URL at the end of each task; C${RESPOND.round}-NN are CI checks that failed on the PR, with the failed steps' log at the path in the task. For a C-task, find why it fails in CI (reproduce it locally when you can) and fix the cause: never skip, disable or loosen a test or check to make it pass. Work every one of them, then any other unchecked task. The rest of the feature was already approved: change only what this feedback needs.`
    : i === 1
    ? 'Implement the plan: work the unchecked tasks in tasks.md in order.'
    : `The reviewer requested changes. Start with every unchecked R-task in tasks.md: the ones under the newest "## Correcciones — revisión ${i - 1}" and any earlier one marked "reabierta en revisión ${i - 1}" (read the matching section of review-report.md for the details). Then any other unchecked task, including H- and C-tasks from the PR.`}

If ${DIR}/issue.md exists, this is a bug fix from a GitHub issue (/team-fix): follow your "Bug fixes" procedure, the regression test first.

Learned conventions of this repo, if the file exists: ${CONVENTIONS}.

Follow your iteration procedure: implement, test, mark [x], commit, append to dev-log.md.
Return the task ids you completed, the ones still pending, the ones only a person can do (needs_human), and your commit SHAs.`

// A red build would only earn a review whose one blocker is "make the gates pass". Before
// spending a review on it, the Developer gets a few short rounds to fix just the gates.
const gateFixPrompt = (i, k, gates) => `Feature directory: ${DIR}
${WORKTREE_RULES}Iteration ${i} of ${MAX_ITER} — gate repair ${k} of ${GATE_FIX_ROUNDS}.

The official gates FAILED after your iteration ${i}. Log: ${gates.log || `${DIR}/gates/iter-${i}.log`} (exit code ${gates.exit_code ?? '?'}).
Read the end of the log first, then whatever part of it explains each failure.

Make the gates pass, and nothing else:
- Fix only what the gates report (failing tests, compile errors, lint, formatting checks). Do not start new tasks and do not refactor.
- If a failing test is pre-existing or unrelated to this feature, do not skip, disable or delete it; say so in notes and set blocked: true.
- Fix the code, not the test, unless the test itself is wrong for the spec.
- Run \`${BIN}/team-gates "${DIR}"\` yourself before committing, and commit the fix (Conventional Commit, e.g. \`fix(scope): …\` or \`test(scope): …\`).
- Append a "### Iteración ${i} — reparación de gates ${k}" section to dev-log.md: what failed, what you changed, gate result.

Return the commits you made (empty if you changed nothing), blocked: true if you cannot make them pass, and in notes the cause of each failure.`

const LEARN_SCHEMA = {
  type: 'object',
  properties: {
    added: { type: 'array', items: { type: 'string' } },
    reinforced: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['added', 'reinforced'],
}

const FEATURE_ID = DIR.replace(/\/+$/, '').split('/').pop()
const learnPrompt = () => `You maintain the learned conventions of a repository: ${CONVENTIONS}
The dev team (a Developer, a Reviewer from another model, and people reviewing the PRs) just finished a development loop on feature ${FEATURE_ID} (${DIR}). Read what it had to be told:
- ${DIR}/review-report.md: every review, its findings (blocker, major, minor) and the R-tasks they became. The findings in ${DIR}/reviews/code-*.json have the same content as JSON.
${RESPOND ? `- ${DIR}/respond/round-${RESPOND.round}/feedback.json and the H-tasks under "## Comentarios de la PR — ronda ${RESPOND.round}" in ${DIR}/tasks.md: what people asked for on the PR. Comments from people weigh the most.
` : ''}- The repo's CLAUDE.md / AGENTS.md (in ${WT || 'the repository root'}), so you do not repeat or contradict them.

Then update ${CONVENTIONS} with the lessons that will apply to FUTURE features of this repo:
- A lesson is a concrete, checkable rule about this codebase ("Validate pagination params in the controller with X and return 400 with {error: …}", "Every new /api route goes in docs/api.md"), not a generic best practice anyone knows ("write tests", "handle errors"), and not a bug specific to this feature.
- Skip findings the Reviewer later withdrew or that were not acted on, and anything that contradicts spec decisions or CLAUDE.md.
- If a rule already in the file covers it, do not add another: append this feature to that rule's provenance ("— visto en …") and report it as reinforced. If nothing generalizes, change nothing: an empty result is fine and common.
- Never remove or reword a rule, except to merge an exact duplicate. Never touch lines without a "— visto en" provenance: a person wrote them.
- Keep the file under 40 rules.

Format (Spanish), creating the file if it does not exist:

# Convenciones aprendidas

Reglas que el equipo tuvo que corregir en features anteriores. El Developer y el Planner las siguen. Edítalas libremente.

## <área: API, datos, tests, seguridad, estilo, …>

- <regla> — visto en ${FEATURE_ID} (R1-02)

Other features may update the file at the same time: read it right before you change it, and change it with targeted edits (not by rewriting the whole file). Do not touch any other file, and never the code or git.
Return the rules you added and the ones you reinforced (their text), and in notes anything skipped worth knowing.`

const GATE_FIX_SCHEMA = {
  type: 'object',
  properties: {
    commits: { type: 'array', items: { type: 'string' } },
    blocked: { type: 'boolean' },
    notes: { type: 'string' },
  },
  required: ['commits', 'blocked', 'notes'],
}

const runGates = (i, label) => agent(run(`${BIN}/team-gates "${DIR}" ${i}`), {
  agentType: 'team-runner', model: 'haiku', effort: 'low', label, phase: `Iteración ${i}`, schema: GATES_SCHEMA,
})
const gatesFailed = (g) => g && g.configured !== false && g.passed === false

let approved = false
let last = START - 1
let stopReason = null

for (let i = START; i <= MAX_ITER; i++) {
  phase(`Iteración ${i}`)

  const dev = await agent(devPrompt(i), { agentType: 'team-developer', model: DEVELOPER.model, effort: DEVELOPER.effort, label: `developer:${i}`, phase: `Iteración ${i}`, schema: DEV_SCHEMA })
  if (!dev) { stopReason = `el Developer falló en la iteración ${i}`; break }
  if (dev.blocked && dev.commits.length === 0) {
    // Nothing to review: running gates and a review would burn an iteration on the same block.
    stopReason = `el Developer está bloqueado en la iteración ${i} y no hizo commits: ${dev.notes || 'sin detalle'}`
    break
  }
  log(`Iteración ${i}: Developer completó ${dev.completed_tasks.length} tareas, ${dev.pending_tasks.length} pendientes, ${dev.commits.length} commits${dev.blocked ? ' (BLOQUEADO)' : ''}${dev.needs_human?.length ? ` · requieren persona: ${dev.needs_human.join(', ')}` : ''}`)

  let gates = await runGates(i, `gates:${i}`)
  log(`Iteración ${i}: gates ${gates?.passed ? 'OK' : 'FALLARON'}${gates && gates.configured === false ? ' (sin gates configurados)' : ''}`)

  for (let k = 1; k <= GATE_FIX_ROUNDS && gatesFailed(gates); k++) {
    const fix = await agent(gateFixPrompt(i, k, gates), {
      agentType: 'team-developer', model: DEVELOPER.model, effort: DEVELOPER.effort, label: `gate-fix:${i}.${k}`, phase: `Iteración ${i}`, schema: GATE_FIX_SCHEMA,
    })
    if (!fix || fix.commits.length === 0) {
      // Nothing changed: the same gates would fail the same way. Let the Reviewer see it.
      log(`Iteración ${i}: reparación de gates ${k} sin commits${fix?.blocked ? ' (BLOQUEADO)' : ''} — pasa a revisión con los gates en rojo${fix?.notes ? `: ${fix.notes}` : ''}`)
      break
    }
    gates = await runGates(i, `gates:${i}.${k}`)
    log(`Iteración ${i}: reparación de gates ${k} (${fix.commits.length} commits) → gates ${gates?.passed ? 'OK' : 'FALLARON'}`)
    if (fix.blocked) break
  }

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

// What the Reviewer and the PR's reviewers had to ask for, generalized, so the next feature gets
// it right the first time. Only from reviewed work, and never fatal to the loop.
let learned = null
if (LEARN && last >= 1) {
  phase('Aprendizaje')
  learned = await agent(learnPrompt(), {
    model: LEARN.model, effort: LEARN.effort, label: 'learn', phase: 'Aprendizaje', schema: LEARN_SCHEMA,
  })
  if (learned) log(`Convenciones: ${learned.added?.length || 0} nuevas, ${learned.reinforced?.length || 0} reforzadas`)
}

return {
  approved,
  iterations: last,
  stopped_early: stopReason,
  final_report: report && report.verdict === 'REPORTED' ? `${DIR}/final-report.md` : null,
  review_report: `${DIR}/review-report.md`,
  conventions: learned ? { file: CONVENTIONS, added: learned.added || [], reinforced: learned.reinforced || [] } : null,
}
