// Runs the workflow scripts (team/dev-team.js, team/plan-review.js) with a scripted agent():
// each agent call is answered by the scenario, and the test checks the sequence of calls,
// the prompts and the returned summary.  node --test test/
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

function load(file) {
  const src = fs.readFileSync(path.join(ROOT, 'team', file), 'utf8')
  assert.match(src, /^export const meta = \{/m, 'meta must be the first export')
  return new AsyncFunction('args', 'agent', 'log', 'phase', src.replace(/^export const meta/m, 'const meta'))
}

// answers: { [labelPrefix]: value | value[] | (prompt, opts) => value } — arrays are consumed in order.
async function run(file, args, answers) {
  const calls = [], logs = []
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt, opts })
    const key = Object.keys(answers).filter(k => opts.label.startsWith(k)).sort((a, b) => b.length - a.length)[0]
    assert.ok(key, `unexpected agent call: ${opts.label}`)
    let a = answers[key]
    if (Array.isArray(a)) { assert.ok(a.length, `no answer left for ${opts.label}`); a = a.shift() }
    return typeof a === 'function' ? a(prompt, opts) : a
  }
  const result = await load(file)(args, agent, m => logs.push(m), () => {})
  return { result, labels: calls.map(c => c.label), calls, logs }
}

const DEV_ARGS = { feature_dir: '/f', team_bin: '/b', worktree: '/wt', max_iter: 6, start_iter: 1, gate_fix_rounds: 2, developer: { model: 'opus', effort: 'medium' } }
const dev = (over = {}) => ({ completed_tasks: ['T1'], pending_tasks: [], commits: ['abc'], blocked: false, notes: '', ...over })
const GREEN = { passed: true, configured: true }
const RED = { passed: false, configured: true, exit_code: 1, log: '/f/gates/iter-1.log' }
const OK = { verdict: 'APPROVED', blocking: 0 }
const CHANGES = { verdict: 'CHANGES_REQUESTED', blocking: 1 }
const FINAL = { verdict: 'REPORTED' }

test('dev-team: approved on the first review', async () => {
  const r = await run('dev-team.js', DEV_ARGS, { developer: dev(), gates: GREEN, 'reviewer:1': OK, 'reviewer:final': FINAL })
  assert.deepEqual(r.labels, ['developer:1', 'gates:1', 'reviewer:1', 'reviewer:final'])
  assert.equal(r.result.approved, true)
  assert.equal(r.result.final_report, '/f/final-report.md')
  assert.match(r.calls.at(-1).prompt, /team-review final "\/f" 1 approved/)
  assert.deepEqual([r.calls[0].opts.agentType, r.calls[0].opts.model, r.calls[0].opts.effort], ['team-developer', 'opus', 'medium'])
  assert.deepEqual([r.calls[1].opts.agentType, r.calls[1].opts.model], ['team-runner', 'haiku'])
  assert.match(r.calls[0].prompt, /Worktree \(the code you change, test and commit\): \/wt/)
})

test('dev-team: changes requested, then approved; the second prompt points at the corrections', async () => {
  const r = await run('dev-team.js', DEV_ARGS, { developer: dev(), gates: GREEN, 'reviewer:1': CHANGES, 'reviewer:2': OK, 'reviewer:final': FINAL })
  assert.deepEqual(r.labels, ['developer:1', 'gates:1', 'reviewer:1', 'developer:2', 'gates:2', 'reviewer:2', 'reviewer:final'])
  assert.match(r.calls[3].prompt, /Correcciones — revisión 1/)
})

test('dev-team: out of reviews ends incomplete, and the last prompt says so', async () => {
  const r = await run('dev-team.js', { ...DEV_ARGS, max_iter: 2 }, { developer: dev(), gates: GREEN, 'reviewer:1': CHANGES, 'reviewer:2': CHANGES, 'reviewer:final': FINAL })
  assert.equal(r.result.approved, false)
  assert.equal(r.result.iterations, 2)
  assert.match(r.calls.find(c => c.label === 'developer:2').prompt, /the LAST one/)
  assert.match(r.calls.at(-1).prompt, /2 incomplete/)
})

test('dev-team: a blocked Developer without commits stops before gates and review', async () => {
  const r = await run('dev-team.js', DEV_ARGS, { developer: dev({ blocked: true, commits: [], notes: 'falta Redis' }) })
  assert.deepEqual(r.labels, ['developer:1'])
  assert.match(r.result.stopped_early, /bloqueado.*falta Redis/)
  assert.equal(r.result.final_report, null)
})

test('dev-team: a blocked Developer with commits still gets reviewed', async () => {
  const r = await run('dev-team.js', DEV_ARGS, { developer: dev({ blocked: true }), gates: GREEN, 'reviewer:1': OK, 'reviewer:final': FINAL })
  assert.deepEqual(r.labels, ['developer:1', 'gates:1', 'reviewer:1', 'reviewer:final'])
})

test('dev-team: a Reviewer error stops the loop but still writes the final report', async () => {
  const r = await run('dev-team.js', DEV_ARGS, { developer: dev(), gates: GREEN, 'reviewer:1': { verdict: 'ERROR', error: 'codex down' }, 'reviewer:final': FINAL })
  assert.match(r.result.stopped_early, /codex down/)
  assert.equal(r.labels.at(-1), 'reviewer:final')
})

test('dev-team: red gates get repair rounds until green, then the review', async () => {
  const r = await run('dev-team.js', DEV_ARGS, {
    developer: dev(), gates: [RED, RED, GREEN], 'gate-fix': [{ commits: ['f1'], blocked: false, notes: '' }, { commits: ['f2'], blocked: false, notes: '' }],
    'reviewer:1': OK, 'reviewer:final': FINAL,
  })
  assert.deepEqual(r.labels, ['developer:1', 'gates:1', 'gate-fix:1.1', 'gates:1.1', 'gate-fix:1.2', 'gates:1.2', 'reviewer:1', 'reviewer:final'])
  const fix = r.calls[2]
  assert.equal(fix.opts.agentType, 'team-developer')
  assert.match(fix.prompt, /gate repair 1 of 2/)
  assert.match(fix.prompt, /\/f\/gates\/iter-1\.log/)
})

test('dev-team: repair stops when the Developer makes no commit or reports a block', async () => {
  let r = await run('dev-team.js', DEV_ARGS, { developer: dev(), gates: RED, 'gate-fix': { commits: [], blocked: true, notes: 'test previo roto' }, 'reviewer:1': OK, 'reviewer:final': FINAL })
  assert.deepEqual(r.labels, ['developer:1', 'gates:1', 'gate-fix:1.1', 'reviewer:1', 'reviewer:final'])
  assert.ok(r.logs.some(l => /test previo roto/.test(l)))

  r = await run('dev-team.js', DEV_ARGS, { developer: dev(), gates: [RED, RED], 'gate-fix': { commits: ['f'], blocked: true, notes: '' }, 'reviewer:1': OK, 'reviewer:final': FINAL })
  assert.deepEqual(r.labels, ['developer:1', 'gates:1', 'gate-fix:1.1', 'gates:1.1', 'reviewer:1', 'reviewer:final'])
})

test('dev-team: repair is skipped for unconfigured gates and with gate_fix_rounds 0', async () => {
  let r = await run('dev-team.js', DEV_ARGS, { developer: dev(), gates: { passed: true, configured: false }, 'reviewer:1': OK, 'reviewer:final': FINAL })
  assert.ok(!r.labels.some(l => l.startsWith('gate-fix')))
  r = await run('dev-team.js', { ...DEV_ARGS, gate_fix_rounds: 0 }, { developer: dev(), gates: RED, 'reviewer:1': OK, 'reviewer:final': FINAL })
  assert.deepEqual(r.labels, ['developer:1', 'gates:1', 'reviewer:1', 'reviewer:final'])
})

test('dev-team: resumes at start_iter', async () => {
  const r = await run('dev-team.js', { ...DEV_ARGS, start_iter: 4 }, { developer: dev(), gates: GREEN, 'reviewer:4': OK, 'reviewer:final': FINAL })
  assert.deepEqual(r.labels, ['developer:4', 'gates:4', 'reviewer:4', 'reviewer:final'])
  assert.match(r.calls[0].prompt, /Correcciones — revisión 3/)
})

test('dev-team: a respond round starts with the PR comments, later iterations with the corrections', async () => {
  const r = await run('dev-team.js', { ...DEV_ARGS, start_iter: 7, max_iter: 8, respond: { round: 2 } },
    { developer: dev(), gates: GREEN, 'reviewer:7': CHANGES, 'reviewer:8': OK, 'reviewer:final': FINAL })
  assert.match(r.calls[0].prompt, /unchecked tasks under "## Comentarios de la PR — ronda 2"[^]*H2-NN are comments[^]*C2-NN are CI checks/)
  assert.match(r.calls[0].prompt, /\/f\/respond\/round-2\/feedback\.json/)
  const second = r.calls.find(c => c.label === 'developer:8').prompt
  assert.match(second, /Correcciones — revisión 7/)
  assert.match(second, /H- and C-tasks from the PR/)
})

const PLAN_ARGS = { feature_dir: '/f', team_bin: '/b', max_rounds: 3, start_round: 1, planner: { model: 'opus', effort: 'high' } }

test('plan-review: approved on the first round', async () => {
  const r = await run('plan-review.js', PLAN_ARGS, { 'reviewer:plan': OK })
  assert.deepEqual(r.labels, ['reviewer:plan-1'])
  assert.equal(r.result.approved, true)
})

test('plan-review: the Planner revises between rounds, never after the last', async () => {
  const r = await run('plan-review.js', PLAN_ARGS, { 'reviewer:plan': CHANGES, 'planner:revise': 'cambios' })
  assert.deepEqual(r.labels, ['reviewer:plan-1', 'planner:revise-1', 'reviewer:plan-2', 'planner:revise-2', 'reviewer:plan-3'])
  assert.equal(r.result.approved, false)
  assert.deepEqual([r.calls[1].opts.agentType, r.calls[1].opts.effort], ['team-planner', 'high'])
})

test('plan-review: a Reviewer error or a Planner failure stops early', async () => {
  let r = await run('plan-review.js', PLAN_ARGS, { 'reviewer:plan': { verdict: 'ERROR', error: 'boom' } })
  assert.match(r.result.stopped_early, /boom/)
  r = await run('plan-review.js', { ...PLAN_ARGS, start_round: 2 }, { 'reviewer:plan': CHANGES, 'planner:revise': null })
  assert.deepEqual(r.labels, ['reviewer:plan-2', 'planner:revise-2'])
  assert.match(r.result.stopped_early, /Planner falló/)
})
