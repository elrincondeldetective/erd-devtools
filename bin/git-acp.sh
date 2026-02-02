#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-acp.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Asumimos estructura: .devtools/bin/script.sh -> .devtools/lib/
LIB_DIR="${SCRIPT_DIR}/../lib"

# Orden de carga importante
source "${LIB_DIR}/core/utils.sh"       # Helpers UI, Logs, TTY
source "${LIB_DIR}/core/config.sh"      # Configuración y Defaults
source "${LIB_DIR}/ui/styles.sh"        # <--- FIX: CARGAMOS ESTILOS (ui_step_header, gum)
source "${LIB_DIR}/git-flow.sh"         # Políticas de ramas
source "${LIB_DIR}/ssh-ident.sh"        # Identidad SSH/GPG
source "${LIB_DIR}/ci-workflow.sh"      # Flujo Post-Push (CI/PR)

echo "🟢 [ERD-ECOSYSTEM] Ejecutando git-acp integrado..."

# ==============================================================================
# 2. VALIDACIONES INICIALES Y ARGUMENTOS
# ==============================================================================

# Parseo preliminar para detectar --force antes de las guardas
ORIG_ARGS=("$@")
FORCE=0
for __a in "$@"; do
  case "$__a" in
    --force|--i-know-what-im-doing) FORCE=1 ;;
  esac
done
(( FORCE )) && export DISABLE_NO_ACP_GUARD=1

# Validación básica de Git
git rev-parse --is-inside-work-tree &>/dev/null || {
  log_error "No estás dentro de un repositorio Git."
  exit 1
}

# Gatekeeper: Verifica si este repo bloquea el uso de ACP (Superrepos)
check_superrepo_guard "$0" "${ORIG_ARGS[@]}"

# ==============================================================================
# 3. SETUP DE IDENTIDAD
# ==============================================================================

if ! $SIMPLE_MODE; then
    # Lógica compleja de SSH/GPG delegada a la librería
    setup_git_identity
else
    echo "⚡ Modo Estándar (Sin gestión de identidades avanzada)."
fi

# ==============================================================================
# 4. PARSEO DE ARGUMENTOS DE COMANDO
# ==============================================================================
NO_PUSH=false
DRY_RUN=false
ARGS=()

while (( $# )); do
  case "$1" in
    --no-push) NO_PUSH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force|--i-know-what-im-doing) shift ;; # Ya procesado, lo saltamos
    *) ARGS+=("$1"); shift ;;
  esac
done

# Si no hay mensaje en argumentos, entramos en modo interactivo
if [ ${#ARGS[@]} -eq 0 ] && ! $DRY_RUN; then
  INTERACTIVE=true
  if $SIMPLE_MODE; then 
      echo "📝 Escribe tu mensaje de commit:"
      read -r MSG
      INTERACTIVE=false
  fi
else 
  INTERACTIVE=false
  MSG="${ARGS[*]}"
fi

# ==============================================================================
# 5. FUNCIONES CORE (Específicas de este script)
# ==============================================================================

get_today()   { date +%F; }
count_today() { git rev-list --count --since="$1 $DAY_START" HEAD; }

do_commit() {
  local msg="$1"
  local count="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M')"
  
  git add .
  
  if $INTERACTIVE; then 
      git commit
  else 
      git commit -m "$msg" -m "📅 Fecha: $timestamp" -m "${REFS_LABEL} #$count"
  fi
}

do_push() {
  local remote="$1"
  local branch
  branch="$(git branch --show-current 2>/dev/null || echo "")"
  
  echo "📡 Enviando a '$remote' (Ref: $branch)..."

  # Intentamos push normal o upstream
  local push_success=false
  
  if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
      if git push -u "$remote" "$branch"; then push_success=true; fi
  else
      if git push "$remote" "$branch"; then push_success=true; fi
  fi

  # Si falla, intentamos estrategia de rebase (auto-heal)
  if [ "$push_success" = false ]; then
      log_warn "El push fue rechazado. Intentando pull --rebase..."
      if git pull --rebase "$remote" "$branch"; then
          log_success "Rebase exitoso. Reintentando push..."
          git fetch --tags --force "$remote"
          if git push "$remote" "$branch"; then
              push_success=true
          fi
      else
          log_error "Conflicto irresoluble. Resuélvelo y haz push manual."
          exit 1
      fi
  fi

  # Si todo salió bien, ejecutamos el flujo post-push (CI/PR)
  if [ "$push_success" = true ]; then
      run_post_push_flow "$branch" "$PR_BASE_BRANCH"
      return 0
  fi
  
  return 1
}

# ==============================================================================
# 6. EJECUCIÓN PRINCIPAL
# ==============================================================================
TODAY=$(get_today)
COUNT_BEFORE=$(count_today "$TODAY")
NEXT=$((COUNT_BEFORE + 1))

if ! $DRY_RUN; then
  # A. Validar/Renombrar rama Feature
  before_branch="$(git branch --show-current 2>/dev/null || echo "(detached)")"
  ensure_feature_branch_before_commit
  after_branch="$(git branch --show-current 2>/dev/null || echo "(detached)")"

  if [[ "$before_branch" != "$after_branch" ]]; then
    ui_header "✅ Seguridad aplicada"
    ui_warn "Se evitó commitear en rama protegida."
    ui_success "Commit se hará en: $after_branch"
    ui_info "Antes estabas en: $before_branch"
    echo
  fi
  
  # B. Commit
  do_commit "${MSG:-}" "$NEXT"
  
  # C. Push
  if ! $NO_PUSH; then
    # $push_target viene exportado desde setup_git_identity (o es origin)
    do_push "$push_target"
  else
    log_warn "Se omitió el push (--no-push)."
  fi
fi

# ==============================================================================
# 7. REPORTE DE PROGRESO
# ==============================================================================
TOTAL_TODAY=$(count_today "$TODAY")
show_daily_progress "$TOTAL_TODAY" "$DAILY_GOAL" "$DRY_RUN"