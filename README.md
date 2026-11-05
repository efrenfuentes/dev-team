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
~/.claude/skills/team-plan, team-dev, team-status, team-clean  →  skills/
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

En el repo del proyecto, desde cualquier rama (cada feature trabaja en su propio worktree, ver
[Worktrees](#worktrees)):

1. **`/team-plan <descripción de la feature> [--base origin/main]`**
   Crea el worktree de la feature en una rama nueva `feat/<slug>` desde la base y lo prepara.
   El Planner explora ese código y te hace preguntas. Luego escribe spec, plan y tareas, y el
   Reviewer revisa el plan en hasta 5 rondas. Todo queda en `.team/NNN-slug/` del checkout
   principal, que se agrega a `.git/info/exclude` y nunca se commitea. La base por defecto es la
   rama principal del remoto (`origin/HEAD`, o la primera de `origin/develop`, `origin/main`,
   `origin/master` que exista).
2. Revisa `spec.md`, `plan.md` y `tasks.md`.
3. **`/team-status`** muestra en qué fase está cada feature del repo (planning, planned,
   developing, approved, incomplete), con rondas, iteraciones, tareas abiertas y lo que
   requiere a una persona.
4. **`/team-dev [NNN] [--reset]`**
   Repite el ciclo Developer → gates → Reviewer hasta que el Reviewer aprueba, con un máximo de
   6 revisiones (la implementación inicial más 5 rondas de corrección). Al final escribe
   `final-report.md`. Nunca hace push ni abre PRs.
5. **`/team-clean NNN [--force]`**, cuando la rama ya se mergeó o la descartas: borra el
   worktree y la base de datos de test de la feature. La rama y `.team/NNN-slug/` se conservan.

Puedes tener varias features a la vez: planifica una mientras otra está en `/team-dev`, o corre
dos `/team-dev` en paralelo. Cada una tiene su worktree, su rama y su base de datos de test.

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
| `TEAM_WORKTREES` | `1` (0 trabaja en el checkout actual, como antes) |
| `TEAM_WORKTREE_ROOT` | `../<repo>.worktrees` |
| `TEAM_BRANCH_PREFIX` | `feat/` |
| `TEAM_PARTITION_BASE` | `100` (la feature `007` usa la partición `107`) |
| `TEAM_GATES_LOCK` | `0` (1 corre los gates de un mismo repo de a uno) |

Los modelos de Claude aceptan `opus`, `sonnet`, `haiku` o `fable`. Los esfuerzos aceptan
`low`, `medium`, `high`, `xhigh` o `max`. Para ver la configuración actual:
`~/.claude/team/bin/team-config`.

## Gates por proyecto

Después de cada iteración del Developer, `team-gates` corre en el worktree de la feature el
primer script de gates que encuentra:

1. `<repo>/.team/gates.sh` (local del proyecto)
2. `team/gates/<nombre-del-repo>.sh` (en este repo)

El script corre desde la raíz del worktree con `BASE_SHA`, `BASE_REF`, `TEAM_PARTITION` y
`MIX_TEST_PARTITION` exportados, y debe salir
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

## Worktrees

Cada feature tiene su propio git worktree en `../<repo>.worktrees/NNN-slug`, en la rama
`feat/<slug>` creada desde la base (sin upstream). El checkout principal no se toca: `.team/`
vive ahí, así que `/team-status` y la herencia de decisiones ven todas las features, y puedes
seguir trabajando en él mientras el equipo avanza en los worktrees. Las features creadas antes de
los worktrees siguen trabajando en el checkout principal.

### Setup del worktree

Un worktree nuevo no trae nada que git ignore: dependencias, compilados ni archivos locales.
`team-setup` lo prepara al crearlo (y `/team-dev` lo reintenta si falló):

1. Copia del checkout principal los archivos listados en `.team/worktree-files`, uno por línea
   (`.env`, `config/credentials/development.key`, …). Los que ya existen no se tocan.
2. Hace `mise trust` y `direnv allow` si el repo los usa.
3. Corre el primer script de setup que encuentra: `<repo>/.team/setup.sh`,
   `team/setup/<nombre-del-repo>.sh`, o el del stack:

| Stack | Se detecta por | Setup por defecto |
|---|---|---|
| Elixir / Phoenix | `mix.exs` | `mix deps.get`, paquetes npm de `assets/` si hay, `mix ecto.create` en test |
| Ruby / Rails | `Gemfile` | copia `config/master.key` y `config/credentials/*.key`, `bundle install`, paquetes JS si hay `package.json`, `bin/rails db:prepare` en test |

Para Go, Rust o Python no hay setup por defecto todavía; si hace falta, va en `.team/setup.sh`.
El log queda en `.team/NNN-slug/logs/setup.log`.

### Tests en paralelo

Dos features que corren tests a la vez no deben compartir la base de datos de test. Cada feature
recibe `TEAM_PARTITION` (`TEAM_PARTITION_BASE` + número de la feature, para no chocar con
`mix test --partitions`) y `MIX_TEST_PARTITION` con el mismo valor:

- **Phoenix:** nada que hacer si `config/test.exs` usa
  `"<app>_test#{System.get_env("MIX_TEST_PARTITION")}"`, que es lo que genera Phoenix.
- **Rails:** una línea en `config/database.yml`, una sola vez:

  ```yaml
  test:
    database: myapp_test<%= ENV["TEAM_PARTITION"] %>
  ```

  No uses `TEST_ENV_NUMBER`: Rails lo usa para sus propios workers de `parallelize`. Con SQLite no
  hace falta: el archivo vive dentro del worktree.
- **Si el proyecto no puede aislarse**, crea `<repo>/.team/serialize-gates` (o define
  `TEAM_GATES_LOCK=1`): los gates de ese repo corren de a uno, aunque las features avancen en
  paralelo.

El Developer corre sus tests y comandos con `team-exec <feature_dir> <comando>`, que entra al
worktree con ese entorno, y sus gates con `team-gates <feature_dir>`.

`/team-clean` borra la base de test de la feature con el teardown del stack (solo si el repo usa
la partición; nunca la del checkout principal), o con `<repo>/.team/teardown.sh` si existe.

## Estructura

```
agents/            definiciones de los subagentes de Claude Code
skills/            /team-plan, /team-dev, /team-status y /team-clean
team/
  config.sh        modelos, esfuerzos y límites
  lib.sh           funciones compartidas por los scripts (worktree, entorno de la feature, lock)
  bin/             team-init, team-setup, team-start, team-exec, team-config, team-gates,
                   team-review, team-status, team-clean
  setup/stacks/    setup y teardown por defecto de cada stack (elixir.sh, ruby.sh)
  plan-review.js   workflow Reviewer ↔ Planner
  dev-team.js      workflow Developer → gates → Reviewer
  prompts/         prompts del Reviewer (plan, código, seguridad, reporte final)
  schemas/         JSON schema del veredicto del Reviewer
  gates/           scripts de gates por repo
```

## Licencia

[MIT](LICENSE) © 2026 Efrén Fuentes
