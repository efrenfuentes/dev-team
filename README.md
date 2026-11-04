# Dev Team para Claude Code

Equipo de desarrollo de tres roles que planifica, implementa y revisa features dentro de
cualquier repo:

| Rol | Modelo | Esfuerzo | Qué hace |
|---|---|---|---|
| **Planner** (`team-planner`) | Claude Opus | high | Explora el código, te hace preguntas y escribe `spec.md`, `plan.md` y `tasks.md` |
| **Developer** (`team-developer`) | Claude Opus | medium | Hace las tareas, escribe los tests y hace commits (Conventional Commits, sin push) |
| **Reviewer** (Codex CLI) | OpenAI `gpt-6-astra` | high | Revisa el plan y el código en modo solo lectura, y agrega tareas de corrección |
| **Reviewer de seguridad** (Codex CLI) | OpenAI `gpt-6-astra` | high | Solo en la primera revisión de código: autorización, aislamiento por cuenta, entrada no confiable y exposición de datos. Corre en paralelo al Reviewer; sus hallazgos son `R1-SNN` |
| **Runner** (`team-runner`) | Claude Haiku | low | Corre los gates y el reviewer, y devuelve su JSON sin interpretarlo |

## Instalación

```bash
git clone <url-de-este-repo> ~/Developer/dev-team
~/Developer/dev-team/install.sh
```

`install.sh` crea symlinks desde `~/.claude` hacia este repo:

```
~/.claude/agents/team-{planner,developer,runner}.md  →  agents/
~/.claude/skills/team-plan, team-dev, team-status    →  skills/
~/.claude/team                                       →  team/
```

- Puedes correrlo varias veces sin problema (es idempotente).
- Si ya hay archivos reales en esos destinos, los mueve a `~/.claude/backups/dev-team-<fecha>/`.
- Para actualizar: `git pull`. Como son symlinks, los cambios se ven de inmediato.
- Para desinstalar: `./install.sh --uninstall`.

Reinicia Claude Code después de instalar.

> Las rutas `~/.claude/team/...` están fijas en las skills y los scripts, así que la
> instalación siempre va en `~/.claude` del usuario.

## Requisitos

- **Claude Code**, con acceso a Opus y Haiku y con la herramienta Workflow habilitada.
- **Codex CLI** con sesión iniciada (`brew install codex` y luego `codex login`) y acceso a
  `gpt-6-astra`. Si tu login de Codex no está en `~/.codex`, define `TEAM_CODEX_HOME`.
- **jq**, **perl** y **git** (`brew install jq`; perl ya viene en macOS).
- Las herramientas que usen los gates de cada proyecto (compilador, test runner, linter).

## Uso

En el repo del proyecto, desde una rama de feature limpia:

1. **`/team-plan <descripción de la feature> [--base origin/main]`**
   El Planner explora y te hace preguntas. Luego escribe spec, plan y tareas, y el Reviewer
   revisa el plan en hasta 5 rondas. Todo queda en `.team/NNN-slug/`, que se agrega a
   `.git/info/exclude` y nunca se commitea. La base por defecto es la rama principal del remoto
   (`origin/HEAD`, o la primera de `origin/develop`, `origin/main`, `origin/master` que exista).
2. Revisa `spec.md`, `plan.md` y `tasks.md`.
3. **`/team-status`** muestra en qué fase está cada feature del repo (planning, planned,
   developing, approved, incomplete), con rondas, iteraciones, tareas abiertas y lo que
   requiere a una persona.
4. **`/team-dev [NNN] [--reset]`**
   Repite el ciclo Developer → gates → Reviewer hasta que el Reviewer aprueba, con un máximo de
   6 revisiones (la implementación inicial más 5 rondas de corrección). Al final escribe
   `final-report.md`. Nunca hace push ni abre PRs.

Puedes seguir el progreso en `/workflows`. Si un ciclo se corta, al correr el comando de nuevo
retoma desde la siguiente ronda o iteración. Si el Developer reporta que está bloqueado y no hizo
commits, el ciclo se detiene antes de gastar gates y revisión; resuelve el bloqueo y vuelve a
correr `/team-dev`. `--reset` archiva las revisiones, reportes y
dev-log anteriores en `.team/NNN-slug/archive/` y vuelve a empezar; los commits se conservan.

### Qué hace cada hallazgo del Reviewer

| Severidad | Bloquea | Qué pasa |
|---|---|---|
| `blocker` / `major` | sí | Genera una tarea `R<n>-NN` en `tasks.md`. Si en la siguiente revisión sigue abierta, se **reabre la misma tarea** con la nota del Reviewer; no se crea otra. |
| `minor` | no | Solo aparece en el reporte. |
| `human` | no | Algo que solo una persona puede hacer (prueba manual con un cliente real, anotar la PR, un entorno externo). Va al reporte y al informe final, no al Developer. |

Por eso el Planner no escribe tareas `T…` que el Developer no pueda verificar solo: lo que
necesita a una persona va en `## Verificación manual (persona)` de `tasks.md`, sin checkbox.

El transcript completo de cada llamada a Codex queda en `.team/NNN-slug/logs/`.

El Planner lee las `Clarificaciones` y `Decisiones de revisión` de las features anteriores del
mismo repo y las hereda en `## Decisiones heredadas` de la spec, así no vuelve a preguntar lo ya
decidido. El Developer corre los gates por su cuenta antes de cada commit.

## Configuración

Todo está en [`team/config.sh`](team/config.sh). También puedes cambiar cualquier valor para
una sola ejecución con variables de entorno:

| Variable | Default |
|---|---|
| `TEAM_PLANNER_MODEL` / `TEAM_PLANNER_EFFORT` | `opus` / `high` |
| `TEAM_DEVELOPER_MODEL` / `TEAM_DEVELOPER_EFFORT` | `opus` / `medium` |
| `TEAM_REVIEW_MODEL` / `TEAM_REVIEW_EFFORT` | `gpt-6-astra` / `high` |
| `TEAM_MAX_PLAN_ROUNDS` | `5` |
| `TEAM_MAX_CODE_REVIEWS` | `6` |
| `TEAM_SECURITY_REVIEW` | `1` (0 la desactiva) |

Los modelos de Claude aceptan `opus`, `sonnet`, `haiku` o `fable`. Los esfuerzos aceptan
`low`, `medium`, `high`, `xhigh` o `max`. Para ver la configuración actual:
`~/.claude/team/bin/team-config`.

## Gates por proyecto

Después de cada iteración del Developer, `team-gates` corre el primer script de gates que
encuentra:

1. `<repo>/.team/gates.sh` (local del proyecto)
2. `team/gates/<nombre-del-repo>.sh` (en este repo)

El script corre desde la raíz del proyecto con `BASE_SHA` y `BASE_REF` exportados, y debe salir
con un código distinto de cero si algo falla. Conviene que solo verifique y no modifique
archivos (por ejemplo, un chequeo de formato en vez de un formateador). Si no hay script, el
ciclo sigue y lo marca como "sin gates configurados".

Ejemplo de `team/gates/<nombre-del-repo>.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
status=0

echo "== build =="
make build || status=1

echo "== lint =="
make lint || status=1

echo "== test =="
make test || status=1

echo "== result: $([ $status -eq 0 ] && echo PASSED || echo FAILED) =="
exit $status
```

## Estructura

```
agents/            definiciones de los subagentes de Claude Code
skills/            /team-plan, /team-dev y /team-status
team/
  config.sh        modelos, esfuerzos y límites
  bin/             team-init, team-start, team-config, team-gates, team-review, team-status
  plan-review.js   workflow Reviewer ↔ Planner
  dev-team.js      workflow Developer → gates → Reviewer
  prompts/         prompts del Reviewer (plan, código, seguridad, reporte final)
  schemas/         JSON schema del veredicto del Reviewer
  gates/           scripts de gates por repo
```

## Licencia

[MIT](LICENSE) © 2026 Efrén Fuentes
