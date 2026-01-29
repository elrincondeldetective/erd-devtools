#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-promote.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS.
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Definimos REPO_ROOT globalmente para que todas las libs lo puedan usar
if [[ -z "${REPO_ROOT:-}" ]]; then
    export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# --- Carga de Librerías Core ---
source "${LIB_DIR}/core/utils.sh"       # Logs, UI
source "${LIB_DIR}/core/config.sh"      # Config Global (SIMPLE_MODE)
source "${LIB_DIR}/core/git-ops.sh"     # Git Ops básicos
source "${LIB_DIR}/release-flow.sh"     # Versioning tools
source "${LIB_DIR}/ssh-ident.sh"        # Gestión de Identidad

# --- Carga de Módulos Refactorizados (Divide y Vencerás) ---
PROMOTE_LIB="${LIB_DIR}/promote"

# 1. Estrategia de Versionado (Fases 1 y 2)
source "${PROMOTE_LIB}/version-strategy.sh"

# 2. Integridad del Golden SHA (Fase 3)
source "${PROMOTE_LIB}/golden-sha.sh"

# 3. Integración con GitOps (Fase 4)
source "${PROMOTE_LIB}/gitops-integration.sh"

# 4. Flujos de Trabajo Principales (Lógica de Negocio)
source "${PROMOTE_LIB}/workflows.sh"

# ==============================================================================
# 1.1 CONTEXTO: rama desde la que se invoca (antes de cualquier checkout)
# ==============================================================================
__devtools_from_branch="$(git branch --show-current 2>/dev/null || true)"
__devtools_from_branch="$(echo "${__devtools_from_branch:-}" | tr -d '[:space:]')"
export DEVTOOLS_PROMOTE_FROM_BRANCH="${DEVTOOLS_PROMOTE_FROM_BRANCH:-${__devtools_from_branch:-"(detached)"}}"
unset __devtools_from_branch

# ==============================================================================
# 1.2 SEGURIDAD DE RAMAS (LANDING TRAP) - [NUEVO]
# ==============================================================================
# Esta función se ejecuta automáticamente al salir (EXIT) o al cancelar (Ctrl+C).
# Garantiza que el usuario siempre regrese a su rama original.
cleanup_on_exit() {
    local exit_code=$?
    # Desactivar trap para evitar bucles infinitos
    trap - EXIT INT TERM
    
    # Solo ejecutamos la restauración si NO estamos en modo monitor interno
    # (El monitor interno solía correr en subshell/nohup, aquí protegemos el flujo principal)
    if [[ "${1:-}" != "_dev-monitor" ]]; then
        # La función git_restore_branch_safely debe estar en lib/core/git-ops.sh
        if declare -F git_restore_branch_safely >/dev/null; then
            git_restore_branch_safely "$DEVTOOLS_PROMOTE_FROM_BRANCH"
        else
            # Fallback básico por si no se actualizó git-ops.sh
            echo "⚠️  Finalizando script. Volviendo a $DEVTOOLS_PROMOTE_FROM_BRANCH..."
            git checkout "$DEVTOOLS_PROMOTE_FROM_BRANCH" >/dev/null 2>&1 || true
        fi
    fi
    exit $exit_code
}
# Registramos el trap para Salida Normal, Ctrl+C (INT) y Termination (TERM)
trap cleanup_on_exit EXIT INT TERM

# ==============================================================================
# 2. PARSEO DE FLAGS Y SETUP DE IDENTIDAD
# ==============================================================================

# Soporte para flag de auto-confirmación (útil para CI/Automación)
DEVTOOLS_AUTO_APPROVE=false
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
    export DEVTOOLS_AUTO_APPROVE=true
    shift # Elimina el flag de los argumentos para no romper el router
fi

# Si no estamos en modo simple, cargamos las llaves SSH antes de empezar
# EXCEPCIÓN: `_dev-monitor` debe ser no-interactivo (puede correr con nohup/sin TTY).
if [[ "${SIMPLE_MODE:-false}" == "false" && "${1:-}" != "_dev-monitor" ]]; then
    setup_git_identity
fi

# ==============================================================================
# 3. PARSEO DE COMANDOS (ROUTER)
# ==============================================================================

TARGET_ENV="${1:-}"

# --- Guardias de Seguridad y Confirmación ---
if [[ -n "$TARGET_ENV" && "$TARGET_ENV" != "_dev-monitor" ]]; then
    
    # 1. Validar que el working tree esté limpio antes de cualquier operación destructiva
    if declare -F ensure_clean_git_or_die >/dev/null; then
        ensure_clean_git_or_die
    else
        ensure_clean_git # Fallback a git-ops.sh si checks.sh no está cargado
    fi

    # 2. Confirmación Obligatoria (Anti-errores)
    if [[ "$DEVTOOLS_AUTO_APPROVE" == "false" ]]; then
        echo
        log_warn "⚠️  OPERACIÓN DE PROMOCIÓN APLASTANTE (Destructive Promotion)"
        echo "Contenido de la rama destino '$TARGET_ENV' será reemplazado por '$DEVTOOLS_PROMOTE_FROM_BRANCH'."
        echo "Esto ejecutará un 'reset --hard' y 'push --force-with-lease' en el remoto."
        echo
        if ! ask_yes_no "¿Estás seguro de que deseas continuar?"; then
            log_info "Operación cancelada. No se realizaron cambios."
            exit 0
        fi
    fi
fi

case "$TARGET_ENV" in
    dev)
        promote_to_dev
        ;;
    _dev-monitor)
        promote_dev_monitor "${2:-}" "${3:-}"
        ;;
    staging)
        promote_to_staging
        ;;
    prod)
        promote_to_prod
        ;;
    sync)
        promote_sync_all
        ;;
    dev-update|feature/dev-update)
        # Permite pasar una rama opcional como segundo argumento
        promote_dev_update_squash "${2:-}"
        ;;
    feature/*)
        # UX: permitir "git promote feature/mi-rama" para aplastar esa rama
        # dentro de feature/dev-update (y pushear el resultado al remoto).
        promote_dev_update_squash "$TARGET_ENV"
        ;;
    hotfix)
        create_hotfix
        ;;
    hotfix-finish)
        finish_hotfix
        ;;
    *) 
        echo "Uso: git promote [-y | --yes] [dev | staging | prod | sync | feature/dev-update | hotfix | hotfix-finish]"
        echo
        echo "Comandos disponibles:"
        echo "  dev                 : Promueve feature actual -> dev (Aplastante)"
        echo "  staging             : Promueve dev -> staging (gestiona Tags/RC)"
        echo "  prod                : Promueve staging -> main (gestiona Release Tags)"
        echo "  sync                : Sincronización inteligente (Smart Sync)"
        echo "  feature/dev-update  : Aplasta (squash) una rama dentro de feature/dev-update"
        echo "  feature/<rama>      : Alias de lo anterior (squash + push a feature/dev-update)"
        echo "  hotfix              : Crea una rama de hotfix desde main"
        echo "  hotfix-finish       : Finaliza e integra el hotfix"
        echo
        echo "Opciones:"
        echo "  -y, --yes           : Salta las confirmaciones de seguridad (Modo no-interactivo)"
        exit 1
        ;;
esac