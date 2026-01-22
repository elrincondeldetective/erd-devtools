#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-feature.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Importamos las herramientas necesarias
source "${LIB_DIR}/utils.sh"       # Logs, UI (log_info, log_error...)
source "${LIB_DIR}/config.sh"      # Variables globales (BASE_BRANCH, PREFIX...)
source "${LIB_DIR}/git-core.sh"    # Operaciones Git (ensure_clean, sync_submodules...)
source "${LIB_DIR}/git-flow.sh"    # Naming conventions (sanitize_feature_suffix)

# ==============================================================================
# 2. CONFIGURACIÓN Y DEFAULTS
# ==============================================================================
REMOTE="${REMOTE:-origin}"
BASE_BRANCH="${BASE_BRANCH:-dev}"
PREFIX="${PREFIX:-feature/}"
MODE="rebase"       # rebase | merge
NO_PULL=false

usage() {
  cat <<EOF
Uso:
  git feature <nombre> [--base <rama>] [--rebase|--merge] [--no-pull]

Ejemplos:
  git feature login-fix
  git feature feature/login-fix
  git feature bugfix-login --base dev --rebase

Qué hace:
  - Asegura que el repo esté limpio.
  - Actualiza la rama base (dev).
  - Crea la rama feature/xxx o la actualiza si ya existe.
EOF
}

# ==============================================================================
# 3. PARSEO DE ARGUMENTOS
# ==============================================================================
ensure_repo

if [[ $# -lt 1 ]]; then usage; exit 1; fi

NAME="$1"
shift || true

while (( $# )); do
  case "$1" in
    --base) BASE_BRANCH="${2:-}"; [[ -z "$BASE_BRANCH" ]] && { log_error "Falta valor para --base"; exit 1; }; shift 2 ;;
    --rebase) MODE="rebase"; shift ;;
    --merge) MODE="merge"; shift ;;
    --no-pull) NO_PULL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Opción desconocida: $1"; exit 1 ;;
  esac
done

# ==============================================================================
# 4. LÓGICA PRINCIPAL
# ==============================================================================

# 1. Normalización del nombre
if [[ "$NAME" == feature/* ]]; then
    TARGET_BRANCH="$NAME"
else
    # Usamos la función de limpieza de git-flow.sh
    SAFE_NAME="$(sanitize_feature_suffix "$NAME")"
    TARGET_BRANCH="${PREFIX}${SAFE_NAME}"
fi

# 2. Validar que no haya cambios pendientes
ensure_clean_git

# 3. Actualizar rama base (dev) usando git-core.sh
# update_branch_from_remote <branch> <remote> <no_pull_bool>
update_branch_from_remote "$BASE_BRANCH" "$REMOTE" "$NO_PULL"

# 4. Crear o Actualizar Feature Branch
if branch_exists_local "$TARGET_BRANCH"; then
  log_info "🧭 Rama ya existe: $TARGET_BRANCH"
  git checkout "$TARGET_BRANCH" >/dev/null 2>&1
  sync_submodules

  log_info "🔁 Actualizando '$TARGET_BRANCH' desde '$BASE_BRANCH' (Modo: $MODE)..."
  
  if [[ "$MODE" == "rebase" ]]; then
    if ! git rebase "$BASE_BRANCH"; then
      log_warn "⚠️  Rebase con conflictos."
      echo "   Resuelve y luego: git rebase --continue"
      echo "   O aborta:         git rebase --abort"
      exit 1
    fi
  else
    if ! git merge "$BASE_BRANCH"; then
      log_warn "⚠️  Merge con conflictos."
      echo "   Resuelve, luego commit y continúa."
      exit 1
    fi
  fi
else
  log_success "🌱 Creando rama nueva: $TARGET_BRANCH (desde $BASE_BRANCH)"
  git checkout -b "$TARGET_BRANCH" "$BASE_BRANCH"
  sync_submodules
fi

echo
log_success "✅ Listo. Estás en: $(git branch --show-current)"
log_info "Base: $BASE_BRANCH | Remote: $REMOTE"