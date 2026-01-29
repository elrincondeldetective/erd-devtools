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
# 2. SETUP DE IDENTIDAD
# ==============================================================================
# Si no estamos en modo simple, cargamos las llaves SSH antes de empezar
#
# EXCEPCIÓN: `_dev-monitor` debe ser no-interactivo (puede correr con nohup/sin TTY).
#
if [[ "${SIMPLE_MODE:-false}" == "false" && "${1:-}" != "_dev-monitor" ]]; then
    setup_git_identity
fi

# ==============================================================================
# 3. PARSEO DE COMANDOS (ROUTER)
# ==============================================================================

TARGET_ENV="${1:-}"

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
        # No interfiere con git promote dev/staging/prod.
        promote_dev_update_squash "$TARGET_ENV"
        ;;
    hotfix)
        create_hotfix
        ;;
    hotfix-finish)
        finish_hotfix
        ;;
    *) 
        echo "Uso: git promote [dev | staging | prod | sync | feature/dev-update | hotfix | hotfix-finish]"
        echo
        echo "Comandos disponibles:"
        echo "  dev                 : Promueve feature actual -> dev (o fusiona PR abierto)"
        echo "  staging             : Promueve dev -> staging (gestiona Tags/RC)"
        echo "  prod                : Promueve staging -> main (gestiona Release Tags)"
        echo "  sync                : Sincronización inteligente (Smart Sync)"
        echo "  feature/dev-update  : Aplasta (squash) una rama dentro de feature/dev-update"
        echo "  feature/<rama>      : Alias de lo anterior (squash + push a feature/dev-update)"
        echo "  hotfix              : Crea una rama de hotfix desde main"
        echo "  hotfix-finish       : Finaliza e integra el hotfix"
        exit 1
        ;;
esac