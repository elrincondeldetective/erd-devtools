#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-dev.sh
# 
#
# Este módulo maneja la promoción a DEV:
# - promote_to_dev: Crea/Mergea PRs, gestiona release-please y actualiza dev.
# - (Opcional) Modo directo: Squash local + Push directo a dev (sin PR).
#
# Dependencias externas: utils.sh, git-ops.sh, checks.sh (cargadas por el orquestador principal)
# Dependencias internas: helpers/gh-interactions.sh, strategies/*.sh (cargadas dinámicamente aquí)

# ------------------------------------------------------------------------------
# Dynamic Imports (Refactorización Modular)
# ------------------------------------------------------------------------------
# Detectamos el directorio actual de forma robusta (Bash y Zsh compatible)
# ${BASH_SOURCE[0]:-$0} usa BASH_SOURCE si existe, o cae en $0 (que Zsh usa para el path al hacer source)
_CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_PROMOTE_LIB_ROOT="$(dirname "$_CURRENT_DIR")"

# 1. Cargar Helpers de GitHub/Git
if [[ -f "${_PROMOTE_LIB_ROOT}/helpers/gh-interactions.sh" ]]; then
    source "${_PROMOTE_LIB_ROOT}/helpers/gh-interactions.sh"
else
    echo "❌ Error: No se encontró helpers/gh-interactions.sh" >&2
    echo "   Buscado en: ${_PROMOTE_LIB_ROOT}/helpers/gh-interactions.sh" >&2
    exit 1
fi

# 2. Cargar Estrategia: Directa (No PR)
if [[ -f "${_PROMOTE_LIB_ROOT}/strategies/dev-direct.sh" ]]; then
    source "${_PROMOTE_LIB_ROOT}/strategies/dev-direct.sh"
else
    echo "❌ Error: No se encontró strategies/dev-direct.sh" >&2
    exit 1
fi

# 3. Cargar Estrategia: Monitor PR (Async/Sync)
if [[ -f "${_PROMOTE_LIB_ROOT}/strategies/dev-pr-monitor.sh" ]]; then
    source "${_PROMOTE_LIB_ROOT}/strategies/dev-pr-monitor.sh"
else
    echo "❌ Error: No se encontró strategies/dev-pr-monitor.sh" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Helpers Locales (Orquestación de procesos)
# ------------------------------------------------------------------------------

__resolve_promote_script() {
    # 1) Si viene del bin principal, SCRIPT_DIR existe y es confiable
    if [[ -n "${SCRIPT_DIR:-}" && -x "${SCRIPT_DIR}/git-promote.sh" ]]; then
        echo "${SCRIPT_DIR}/git-promote.sh"
        return 0
    fi

    # 2) Si estamos en un repo consumidor que tiene .devtools embebido
    if [[ -n "${REPO_ROOT:-}" && -x "${REPO_ROOT}/.devtools/bin/git-promote.sh" ]]; then
        echo "${REPO_ROOT}/.devtools/bin/git-promote.sh"
        return 0
    fi

    # 3) Si estamos dentro del repo .devtools (REPO_ROOT==.devtools)
    if [[ -n "${REPO_ROOT:-}" && -x "${REPO_ROOT}/bin/git-promote.sh" ]]; then
        echo "${REPO_ROOT}/bin/git-promote.sh"
        return 0
    fi

    # 4) Fallback
    echo "git-promote.sh"
}

# ==============================================================================
# 3. PROMOTE TO DEV (Main Entry Point)
# ==============================================================================
promote_to_dev() {
    resync_submodules_hard

    # ESTRATEGIA 1: Modo DIRECTO (sin PR feature->dev)
    if [[ "${DEVTOOLS_PROMOTE_DEV_DIRECT:-0}" == "1" ]]; then
        [[ "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" == "dev-update" ]] \
            || [[ "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" == "feature/dev-update" ]] \
            || die "⛔ DEVTOOLS_PROMOTE_DEV_DIRECT=1 solo está permitido desde dev-update (feature/dev-update está deprecada)."

        # (se mantiene igual)
        promote_to_dev_direct
        exit $?
    fi

    # NUEVO: chequeo remoto rápido (reemplaza monitor por defecto)
    log_info "🔎 Chequeo remoto contra GitHub (sin monitor): origin/dev"
    if ! remote_health_check "dev" "origin"; then
        die "No se pudo validar estado remoto de origin/dev."
    fi

    # Monitor opcional por flag/env
    local want_monitor="${GIT_PROMOTE_MONITOR:-${DEVTOOLS_PROMOTE_MONITOR:-0}}"
    if [[ "${want_monitor}" == "1" ]]; then
        if ! command -v gh >/dev/null 2>&1; then
            die "Se requiere 'gh' para ejecutar el monitor (actívalo instalando gh o desactiva GIT_PROMOTE_MONITOR)."
        fi
        promote_dev_monitor "" ""
        exit $?
    fi

    log_success "DEV remoto OK. (Monitor desactivado por defecto)"
    exit 0
}
