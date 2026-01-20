#!/usr/bin/env bash
# /webapps/erd-ecosystem/devops/scripts/git-feature.sh
set -euo pipefail
IFS=$'\n\t'

REMOTE="${REMOTE:-origin}"
BASE_BRANCH="${BASE_BRANCH:-dev}"
PREFIX="${PREFIX:-feature/}"
MODE="rebase"       # rebase | merge...
NO_PULL=false

usage() {
  cat <<'EOF'
Uso:
  git feature <nombre> [--base <rama>] [--rebase|--merge] [--no-pull]

Ejemplos:
  git feature otra-rama
  git feature feature/otra-rama
  git feature bugfix-login --base dev --rebase
  git feature hotfix-ui --base dev --merge
  git feature otra-rama --no-pull

Qué hace:
  - Asegura que el branch base (por defecto: dev) esté actualizado (fetch + pull)
  - Si la rama no existe: la crea desde base
  - Si ya existe: la hace checkout y la actualiza con base (rebase por defecto)
  - Sin alias global: se configura como alias local via devbox init_hook
EOF
}

die() { echo "❌ $*" >&2; exit 1; }

ensure_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "No estás dentro de un repo Git."
}

ensure_clean() {
  if [[ -n "$(git status --porcelain)" ]]; then
    die "Tienes cambios sin guardar. Haz commit o stash primero."
  fi
}

sync_submodules_if_any() {
  if [[ -f ".gitmodules" ]]; then
    git submodule update --init --recursive >/dev/null 2>&1 || true
  fi
}

branch_exists_local() {
  git show-ref --verify --quiet "refs/heads/$1"
}

update_base_branch() {
  local base="$1"
  echo "🔄 Actualizando base '$base'..."
  git fetch "$REMOTE" "$base" >/dev/null 2>&1 || true
  git checkout "$base" >/dev/null 2>&1 || die "No pude hacer checkout a '$base'. ¿Existe?"
  sync_submodules_if_any

  if ! $NO_PULL; then
    git pull "$REMOTE" "$base" || die "Falló pull de '$REMOTE/$base'."
  fi
}

normalize_branch_name() {
  local name="$1"
  if [[ "$name" == */* ]]; then
    echo "$name"
  else
    echo "${PREFIX}${name}"
  fi
}

# ---- parse args ----
ensure_repo

if [[ $# -lt 1 ]]; then usage; exit 1; fi

NAME="$1"
shift || true

while (( $# )); do
  case "$1" in
    --base) BASE_BRANCH="${2:-}"; [[ -z "$BASE_BRANCH" ]] && die "Falta valor para --base"; shift 2 ;;
    --rebase) MODE="rebase"; shift ;;
    --merge) MODE="merge"; shift ;;
    --no-pull) NO_PULL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
done

TARGET_BRANCH="$(normalize_branch_name "$NAME")"

ensure_clean

# 1) actualiza base (dev por defecto)
update_base_branch "$BASE_BRANCH"

# 2) crea o actualiza rama
if branch_exists_local "$TARGET_BRANCH"; then
  echo "🧭 Rama existe: $TARGET_BRANCH"
  git checkout "$TARGET_BRANCH" >/dev/null 2>&1 || die "No pude hacer checkout a '$TARGET_BRANCH'."
  sync_submodules_if_any

  echo "🔁 Actualizando '$TARGET_BRANCH' desde '$BASE_BRANCH' ($MODE)..."
  if [[ "$MODE" == "rebase" ]]; then
    if ! git rebase "$BASE_BRANCH"; then
      echo "⚠️ Rebase con conflictos."
      echo "   Resuelve y luego: git rebase --continue"
      echo "   O aborta:          git rebase --abort"
      exit 1
    fi
  else
    if ! git merge "$BASE_BRANCH"; then
      echo "⚠️ Merge con conflictos."
      echo "   Resuelve, luego commit y continúa."
      exit 1
    fi
  fi
else
  echo "🌱 Creando rama: $TARGET_BRANCH desde $BASE_BRANCH"
  git checkout -b "$TARGET_BRANCH" "$BASE_BRANCH"
  sync_submodules_if_any
fi

echo "✅ Listo. Estás en: $(git branch --show-current)"
echo "   Base: $BASE_BRANCH | Modo: $MODE | Remote: $REMOTE"
