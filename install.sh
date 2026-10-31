#!/usr/bin/env bash
# Instala el dev team en ~/.claude creando symlinks hacia este repo.
#
#   ./install.sh              # instala (idempotente; se puede correr de nuevo sin problema)
#   ./install.sh --uninstall  # quita los symlinks que apuntan a este repo
#
# Si ya existe un archivo o carpeta real en el destino (no un symlink), se mueve a
# ~/.claude/backups/dev-team-<timestamp>/ antes de enlazar. Nunca se borra nada.
set -euo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude="$HOME/.claude"
backup="$claude/backups/dev-team-$(date +%Y%m%d-%H%M%S)"

# destino → origen
links=()
for f in "$src"/agents/*.md; do links+=("$claude/agents/$(basename "$f")|$f"); done
for d in "$src"/skills/*/;   do d=${d%/}; links+=("$claude/skills/$(basename "$d")|$d"); done
links+=("$claude/team|$src/team")

uninstall() {
  for pair in "${links[@]}"; do
    dst=${pair%%|*}; from=${pair#*|}
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$from" ]; then
      rm "$dst"; echo "eliminado  $dst"
    fi
  done
  echo "Listo. Los respaldos, si los hay, siguen en $claude/backups/."
}

install() {
  mkdir -p "$claude/agents" "$claude/skills"
  for pair in "${links[@]}"; do
    dst=${pair%%|*}; from=${pair#*|}
    if [ -L "$dst" ]; then
      if [ "$(readlink "$dst")" = "$from" ]; then echo "ok         $dst"; continue; fi
      rm "$dst"   # symlink viejo hacia otro lado: se reemplaza
    elif [ -e "$dst" ]; then
      mkdir -p "$backup"
      mv "$dst" "$backup/"
      echo "respaldado $dst → $backup/"
    fi
    ln -s "$from" "$dst"
    echo "enlazado   $dst → $from"
  done
  chmod +x "$src"/team/bin/*
  find "$src/team/gates" -name "*.sh" -exec chmod +x {} +
  check_deps
}

check_deps() {
  echo
  echo "Dependencias:"
  missing=0
  for cmd in claude codex jq perl git; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  ✓ %s\n' "$cmd"
    else
      printf '  ✗ %s (falta)\n' "$cmd"; missing=1
    fi
  done
  codex_home="${TEAM_CODEX_HOME:-$HOME/.codex}"
  if command -v codex >/dev/null 2>&1 && [ ! -f "$codex_home/auth.json" ]; then
    echo "  ! Codex no parece tener sesión iniciada en $codex_home: corre 'codex login'"
  fi
  [ $missing -eq 0 ] || echo "Instala lo que falta (ver README.md) antes de usar /team-plan y /team-dev."
  echo
  echo "Listo. Reinicia Claude Code para que cargue los agentes y las skills."
}

case "${1:-}" in
  --uninstall) uninstall ;;
  "") install ;;
  *) echo "uso: $0 [--uninstall]" >&2; exit 2 ;;
esac
