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
# ✅ FIX: siempre inicializar estas vars (set -u no perdona)
export DEVTOOLS_PROMOTE_FROM_BRANCH="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$(git branch --show-current 2>/dev/null || true)}"
export DEVTOOLS_PROMOTE_FROM_BRANCH="$(echo "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" | tr -d '[:space:]')"

if [[ -z "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" ]]; then
  export DEVTOOLS_PROMOTE_FROM_BRANCH="(detached)"
fi

export DEVTOOLS_PROMOTE_FROM_SHA="${DEVTOOLS_PROMOTE_FROM_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"

# Landing override (solo en éxito). Vacío = comportamiento antiguo (restaurar).
export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="${DEVTOOLS_LAND_ON_SUCCESS_BRANCH:-}"

# ==============================================================================
# 1.2 SEGURIDAD DE RAMAS (LANDING TRAP) - [NUEVO]
# ==============================================================================
# Esta función se ejecuta automáticamente al salir (EXIT) o al cancelar (Ctrl+C).
# Garantiza que el usuario siempre regrese a su rama original o aterrice en la destino si hubo éxito.
cleanup_on_exit() {
    local exit_code=$?
    trap - EXIT INT TERM

    if [[ "${TARGET_ENV:-}" != "_dev-monitor" ]]; then
        # ÉXITO: obedecer landing override si existe
        if [[ "$exit_code" -eq 0 && -n "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH:-}" ]]; then
            local cur
            cur="$(git branch --show-current 2>/dev/null || true)"
            if [[ "$cur" != "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}" ]]; then
                echo "🛬 Finalizando flujo (éxito): quedando en '${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}'..."
                git checkout "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}" >/dev/null 2>&1 || true
            fi
            exit 0
        fi

        # FALLO/CANCEL: restaurar rama inicial
        if declare -F git_restore_branch_safely >/dev/null; then
            git_restore_branch_safely "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}"
        else
            echo "⚠️  Finalizando script. Volviendo a ${DEVTOOLS_PROMOTE_FROM_BRANCH:-}..."
            git checkout "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" >/dev/null 2>&1 || true
        fi
    fi
    exit $exit_code
}
# Registramos el trap
trap 'cleanup_on_exit' EXIT INT TERM

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

# Landing policy por comando (opcional, legacy police mode)
if [[ "$TARGET_ENV" == "dev" ]]; then
    # Policía: siempre caer en dev aunque exit!=0 (si se requiere lógica estricta antigua)
    # Nota: La nueva cleanup_on_exit prioriza éxito/fallo genérico,
    # pero dev puede configurarse aquí si fuera necesario.
    export DEVTOOLS_LAND_ON_EXIT_BRANCH="dev"
fi

# --- Guardias de Seguridad y Confirmación ---
if [[ -n "$TARGET_ENV" && "$TARGET_ENV" != "_dev-monitor" ]]; then

    # Dev monitor (admin) no requiere repo limpio (solo observación), salvo modo directo
    if [[ "$TARGET_ENV" == "dev" && "${DEVTOOLS_PROMOTE_DEV_DIRECT:-0}" != "1" ]]; then
        :
    else
    
    # 1. Validar que el working tree esté limpio antes de cualquier operación destructiva
    if declare -F ensure_clean_git_or_die >/dev/null; then
        ensure_clean_git_or_die
    else
        ensure_clean_git # Fallback a git-ops.sh si checks.sh no está cargado
    fi
    fi

    # 2. Confirmación Obligatoria (Anti-errores)
    # Dev monitor (admin) NO es destructivo por defecto → no mostrar warning global
    if [[ "$TARGET_ENV" == "dev" && "${DEVTOOLS_PROMOTE_DEV_DIRECT:-0}" != "1" ]]; then
        :
    elif [[ "$DEVTOOLS_AUTO_APPROVE" == "false" ]]; then
        echo
        log_warn "⚠️  OPERACIÓN DE PROMOCIÓN APLASTANTE (Destructive Promotion)"
        echo "Contenido de la rama destino '$TARGET_ENV' será reemplazado por '${DEVTOOLS_PROMOTE_FROM_BRANCH:-}'."
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
        # ✅ Si `git promote dev` termina en éxito, aterrizamos en dev
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="dev"
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
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="feature/dev-update"
        promote_dev_update_squash "${2:-}"
        ;;
    feature/*)
        # UX: permitir "git promote feature/mi-rama" para aplastar esa rama
        # dentro de feature/dev-update (y pushear el resultado al remoto).
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="feature/dev-update"
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
        echo "  dev                 : Monitor estricto (admin) del estado de 'dev' (PRs/CI). No crea PR."
        echo "                        Bypass: DEVTOOLS_BYPASS_STRICT=1 (emergencia)."
        echo "                        Modo directo (destructivo): DEVTOOLS_PROMOTE_DEV_DIRECT=1"
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