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
~/.claude/skills/team-{plan,dev,status,sync,ship,respond,clean}  →  skills/
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
- **gh** (GitHub CLI) con sesión iniciada, solo para `/team-ship` y `/team-respond`.
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
   developing, responding, approved, incomplete), con rondas, iteraciones, tareas abiertas, lo
   que requiere a una persona y su PR.
4. **`/team-dev [NNN] [--reset]`**
   Repite el ciclo Developer → gates → Reviewer hasta que el Reviewer aprueba, con un máximo de
   6 revisiones (la implementación inicial más 5 rondas de corrección). Si los gates fallan
   después de una iteración, el Developer tiene hasta 2 rondas para arreglarlos antes de que
   revise el Reviewer (ver [Reparación de gates](#reparación-de-gates)). Al final escribe
   `final-report.md`. Nunca hace push ni abre PRs: eso es `/team-ship`.
5. **`/team-sync NNN [--rebase|--merge]`**, cuando la base avanzó: trae los cambios de la rama
   base a la feature (rebase si la rama nunca se publicó, merge si ya está en el remoto; nunca
   force push). Si hay conflictos, los resuelve el Developer. Después corre de nuevo el setup y
   los gates. Ver [Sincronizar con la base](#sincronizar-con-la-base).
6. **`/team-ship NNN [--draft]`**, cuando decides publicarla: hace push de la rama y abre la PR
   con `gh` hacia la rama base. Antes te muestra el título, el estado del ciclo y el cuerpo
   (`.team/NNN-slug/pr-body.md`, que puedes editar) y pide confirmación. Si el Reviewer no
   aprobó, recomienda abrirla como borrador. Ver [Publicar la feature](#publicar-la-feature).
7. **`/team-respond NNN`**, cuando alguien comentó la PR o su CI falló: trae los comentarios sin
   responder y los checks en rojo con su log, te muestra cómo los clasifica (cambio, pregunta o
   nada que hacer) y, cuando confirmas, convierte los cambios en tareas `H<n>-NN` y los fallos de
   CI en tareas `C<n>-NN`, y corre Developer → gates → Reviewer sobre ellas. Al final,
   con tu confirmación, hace push y responde en cada hilo. Ver
   [Responder la revisión de la PR](#responder-la-revisión-de-la-pr).
8. **`/team-clean NNN [--force]`**, cuando la rama ya se mergeó o la descartas: borra el
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
| `TEAM_GATE_FIX_ROUNDS` | `2` (0 manda los gates en rojo directo a revisión) |
| `TEAM_RESPOND_REVIEWS` | `2` (revisiones extra por ronda de `/team-respond`) |
| `TEAM_SECURITY_REVIEW` | `1` (0 la desactiva) |
| `TEAM_WORKTREES` | `1` (0 trabaja en el checkout actual, como antes) |
| `TEAM_WORKTREE_ROOT` | `../<repo>.worktrees` |
| `TEAM_BRANCH_PREFIX` | `feat/` |
| `TEAM_PARTITION_BASE` | `100` (la feature `007` usa la partición `107`) |
| `TEAM_GATES_LOCK` | `0` (1 corre los gates de un mismo repo de a uno) |
| `TEAM_STACK_GATES` | `1` (0 apaga los gates por defecto del stack) |

Los modelos de Claude aceptan `opus`, `sonnet`, `haiku` o `fable`. Los esfuerzos aceptan
`low`, `medium`, `high`, `xhigh` o `max`. Para ver la configuración actual:
`~/.claude/team/bin/team-config`.

## Gates por proyecto

Después de cada iteración del Developer, `team-gates` corre en el worktree de la feature el
primer script de gates que encuentra:

1. `<repo>/.team/gates.sh` (local del proyecto)
2. `team/gates/<nombre-del-repo>.sh` (en este repo)
3. Los gates por defecto del stack, `team/gates/stacks/<stack>.sh` (`TEAM_STACK_GATES=0` los
   apaga)

El script corre desde la raíz del worktree con `BASE_SHA`, `BASE_REF`, `TEAM_PARTITION` y
`MIX_TEST_PARTITION` exportados, y debe salir
con un código distinto de cero si algo falla. Conviene que solo verifique y no modifique
archivos (por ejemplo, un chequeo de formato en vez de un formateador). Si no hay script ni
stack conocido, el ciclo sigue y lo marca como "sin gates configurados".
`team-gates <feature_dir> --which` dice cuál se usaría, sin correrlo.

### Gates por defecto de cada stack

Corren todos los pasos aunque uno falle, para que el Developer vea todo lo que está en rojo, y
saltan (diciéndolo en el log) las herramientas que el proyecto no usa:

| Stack | Se detecta por | Gates |
|---|---|---|
| Elixir / Phoenix | `mix.exs` | `compile --warnings-as-errors`, `deps.unlock --check-unused`, `format --check-formatted`, `credo --strict` y `sobelow` si son dependencias, `mix test --warnings-as-errors` |
| Ruby / Rails | `Gemfile` | `rubocop` y `brakeman` si están en `Gemfile.lock`, `rspec` (con `spec/`), o `bin/rails test`, o `rake test` |
| Go | `go.mod` | `gofmt -l`, `go vet`, `golangci-lint` si hay `.golangci.*`, `go test ./...` |
| Rust | `Cargo.toml` | `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` |
| Python | `pyproject.toml`, `setup.py` o `requirements.txt` | `ruff check` y `ruff format --check`, `mypy` y `pytest`, cada uno si el proyecto lo configura o depende de él; con `uv run`, `poetry run` o el `.venv` |
| Node / TypeScript | `package.json` | los scripts del proyecto que existan: chequeo de formato (`format:check`, …), `lint`, `typecheck` (o `tsc --noEmit` si hay `tsconfig.json`), `test`, con su gestor de paquetes y `CI=true` |

El orden de detección importa: un proyecto Rails con `package.json` es Ruby. Si los gates por
defecto no te sirven (otro comando de test, un paso extra), copia el del stack a
`<repo>/.team/gates.sh` y ajústalo: el del proyecto siempre gana.

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

### Reparación de gates

Si los gates fallan después de una iteración del Developer, el ciclo no llama todavía al
Reviewer: una revisión con los gates en rojo solo diría "haz pasar los gates". En cambio, el
Developer recibe el log y hace hasta `TEAM_GATE_FIX_ROUNDS` rondas cortas en las que solo arregla
lo que reportan los gates (sin tareas nuevas ni refactors), hace commit y los gates corren otra
vez. La revisión llega cuando pasan, o cuando se acaban las rondas, el Developer no hace commits
o reporta un bloqueo (por ejemplo, un test que ya fallaba antes de la feature). En ese caso el
Reviewer igual marca los gates como bloqueante.

Las rondas de reparación no cuentan como revisiones. `gates/iter-N.*` es siempre la última
corrida de la iteración, y las anteriores quedan como `gates/iter-N-try-K.*`. Cada reparación
deja su sección en `dev-log.md`.

## Publicar la feature

`/team-ship NNN` (script: `~/.claude/team/bin/team-ship`) publica una feature en dos pasos:

1. `--check` verifica que el worktree esté limpio, que la rama tenga commits sobre la base y que
   `gh` tenga sesión iniciada. Si no existe, escribe `.team/NNN-slug/pr-body.md` con el resumen y
   lo implementado (sacados de `final-report.md`), una checklist con lo que debe verificar una
   persona y la lista de commits. No sobrescribe un `pr-body.md` que ya editaste.
2. Después de que confirmas, `--push` hace `git push -u` (nunca forzado) y `gh pr create` hacia
   la rama de `base_ref` (`origin/main` → `main`). Si la rama ya tiene una PR abierta, solo hace
   push, y la PR se actualiza sola. La URL queda en `state.json` como `.pr`.

Requiere [`gh`](https://cli.github.com/) con sesión iniciada (`gh auth login`). Nunca fusiona la
PR, ni borra la rama, ni pide reviewers.

## Sincronizar con la base

`/team-sync NNN` (script: `~/.claude/team/bin/team-sync`) actualiza la rama de la feature con
`base_ref`, dentro de su worktree:

| La rama… | Estrategia | Por qué |
|---|---|---|
| nunca se publicó | `rebase` | historial lineal, sin merge commits |
| ya está en el remoto | `merge` de la base | un rebase obligaría a hacer force push |

Si el rebase choca con conflictos, se aborta y se rehace como merge, así los conflictos se
resuelven una sola vez, en un único commit. Los resuelve el Developer, conservando los cambios de
la base y lo que pide la spec, y anota en `dev-log.md` cómo combinó cada archivo. Si un conflicto
requiere una decisión de producto, deja el merge a medias y te lo explica.

Al terminar (`team-sync DIR finish`):

- `base_sha` pasa a ser el nuevo merge-base, así las revisiones siguen viendo solo el diff de la
  feature. La sincronización queda en `state.json` (`.syncs`), y la siguiente revisión mide su
  iteración desde la cabeza sincronizada, no desde la anterior.
- Corre `team-setup` otra vez (la base puede traer dependencias o migraciones nuevas) y los gates.
- Nunca hace push. Si la rama ya estaba publicada, `/team-sync` te ofrece subir el merge.

No lo corras mientras `/team-dev` o `/team-respond` trabajan sobre la misma feature.

## Responder la revisión de la PR

`/team-respond NNN` (script: `~/.claude/team/bin/team-respond`) cierra el ida y vuelta con quien
revisa la PR y con su CI:

1. **`fetch`** lee la PR con una consulta GraphQL y se queda con lo que nadie respondió: hilos sin
   resolver cuyo último comentario no es del equipo, reviews con comentario (cambios pedidos o
   comentarios) y comentarios de la conversación. Ignora a los bots, las respuestas del equipo
   (llevan la marca `<!-- dev-team -->`) y lo ya atendido en rondas anteriores. Queda en
   `.team/NNN-slug/respond/round-N/feedback.json`.
   En la misma consulta lee los checks del último commit de la PR. Cada check que falló (un job
   de GitHub Actions o un status externo) es un ítem más, y de los jobs de Actions baja el log de
   los pasos que fallaron (`respond/round-N/ci-<job>.log`). Si el CI todavía corre, te ofrece
   esperarlo; si la rama local tiene commits que la PR no tiene, te avisa de que los checks son
   de código viejo.
2. Claude **clasifica** cada comentario (cambio, pregunta o nada que hacer), te muestra la tabla y
   espera tu confirmación. Lo que pide una decisión de producto te lo pregunta.
3. **`tasks`** agrega `## Comentarios de la PR — ronda N` a `tasks.md`, con una tarea `H<N>-NN` por
   cada cambio y una `C<N>-NN` por cada check que hay que arreglar (con la ruta del log). Un fallo
   que no es de la feature (flaky, infraestructura, secretos, o que también falla en la base) no
   se vuelve tarea: te lo dice para que lo resuelvas tú, y abre una ronda del loop: el límite de revisiones de la feature sube a las ya
   usadas más `TEAM_RESPOND_REVIEWS` (queda en `state.json` como `review_budget`), así que
   funciona aunque el ciclo ya estuviera aprobado o agotado.
4. Corre el workflow `dev-team` con el Developer enfocado en las tareas `H` y `C`, más los gates
   (con reparación) y el Reviewer, que también las verifica. Una tarea `C` se arregla en la
   causa: saltar, desactivar o relajar un test o un check para que pase es bloqueante.
5. Te muestra las respuestas y los commits, y con tu confirmación hace push y **`reply`**: responde
   dentro de cada hilo y, para reviews y comentarios sueltos, con un comentario que enlaza al
   original. Los checks no llevan respuesta: el push vuelve a correr el CI, y el siguiente
   `/team-respond` muestra si pasó. Los hilos los resuelve quien revisa, no el equipo.

`--reset` de `/team-dev` conserva las secciones de comentarios de la PR: son pedidos de una
persona, no del Reviewer.

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

| Go | `go.mod` | `go mod download` |
| Rust | `Cargo.toml` | `cargo fetch` |
| Python | `pyproject.toml`, `setup.py` o `requirements.txt` | `uv sync` o `poetry install` (con el entorno dentro del worktree) si hay lockfile, si no un `.venv` con `pip` |
| Node / TypeScript | `package.json` | instala los paquetes con el gestor del lockfile (`pnpm`, `yarn`, `bun` o `npm ci`) |

Si el setup de tu proyecto es otro, va en `.team/setup.sh`.
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
  setup/stacks/    setup y teardown por defecto de cada stack (elixir, ruby, go, rust, python, node)
  plan-review.js   workflow Reviewer ↔ Planner
  dev-team.js      workflow Developer → gates → Reviewer
  prompts/         prompts del Reviewer (plan, código, seguridad, reporte final)
  schemas/         JSON schema del veredicto del Reviewer
  gates/           scripts de gates por repo, y en gates/stacks/ los de cada stack
```

## Licencia

[MIT](LICENSE) © 2026 Efrén Fuentes

## Tests del equipo

```bash
test/run.sh                       # shellcheck + suites bats + tests de los workflows
test/run.sh test/ship_sync.bats   # solo esos suites de bats
```

- **`shellcheck`** sobre todos los scripts (`.shellcheckrc` explica las dos reglas desactivadas).
- **`bats`** (`test/*.bats`): cada test crea un `HOME` temporal con `~/.claude/team` apuntando a
  este repo, un repo git con su remoto bare y features reales con `team-init`. `gh` y `codex` son
  falsos (`test/fakes/`): `gh` responde desde fixtures y registra cada llamada; `codex` elige el
  fixture según el prompt (código, seguridad, plan o informe final) y guarda el prompt para que
  el test lo revise. Nada sale de la máquina.
- **`node --test`** (`test/workflows.test.mjs`): corre `dev-team.js` y `plan-review.js` con un
  `agent()` guionado y verifica la secuencia de agentes, los prompts y el resultado.

Las herramientas se toman del `PATH`, o con `mise exec` si faltan (`mise install` instala las
versiones de `mise.toml`). GitHub Actions corre lo mismo en cada push a `main` y en cada PR
(`.github/workflows/test.yml`).
