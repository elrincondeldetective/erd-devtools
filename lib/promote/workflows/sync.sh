#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/sync.sh
#
# Este módulo maneja SYNC como macro simple:
# - promote_sync_all: ejecuta dev-update -> dev -> staging -> prod (minimalista)
# - Sin waits, sin tags, sin gitops, sin gh.
# Dependencias: utils.sh, git-ops.sh, y módulos de promote (cargados por workflows.sh)

# ==============================================================================
# 1. SYNC MACRO (estricto)
# ==============================================================================
# Dynamic imports (para que `git promote sync` funcione aunque se sourcee solo este archivo)
__SYNC_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${__SYNC_DIR__}/to-dev.sh"
source "${__SYNC_DIR__}/to-staging.sh"
source "${__SYNC_DIR__}/to-prod.sh"
promote_sync_all() {
    local current_branch
    current_branch="$(git branch --show-current 2>/dev/null || echo "")"

    # 🔒 Requisito: debes estar en la rama de laboratorio
    # Nuevo nombre canónico: dev-update
    # Compat: permitimos feature/dev-update pero advertimos (deprecado)
    if [[ "$current_branch" == "feature/dev-update" ]]; then
        log_warn "⚠️ Rama 'feature/dev-update' está deprecada. Usa 'dev-update'."
    elif [[ "$current_branch" != "dev-update" ]]; then
        die "⛔ Sync estricto requiere estar en 'dev-update'. Cámbiate a esa rama y reintenta."
    fi

    echo
    banner "🔄 SYNC (MACRO SEGURO)"
    log_info "Cadena: dev-update -> dev -> staging -> prod"
    log_info "Nota: -y/--yes salta confirmaciones humanas, pero NUNCA gates técnicos."
    echo

    # Verificar que las funciones base existen (módulos cargados por workflows.sh)
    declare -F promote_to_dev >/dev/null 2>&1 || die "No está cargado promote_to_dev (to-dev.sh)."
    declare -F promote_to_staging >/dev/null 2>&1 || die "No está cargado promote_to_staging (to-staging.sh)."
    declare -F promote_to_prod >/dev/null 2>&1 || die "No está cargado promote_to_prod (to-prod.sh)."

    local rc=0

    log_info "1/3 🧨 DEV (Lab -> Source of Truth)"
    # Ejecutamos en subshell para aislar variables exportadas, aunque en este caso
    # Ejecutamos cada paso en subshell para aislar side-effects y permitir `exit` internos.

    (
        export DEVTOOLS_PROMOTE_DEV_DIRECT=1
        promote_to_dev
    )
    rc=$?
    [[ "$rc" -eq 0 ]] || { log_error "❌ Sync abortado: falló DEV (rc=$rc)."; return "$rc"; }

    log_info "2/3 🚀 STAGING"
    ( promote_to_staging )
    rc=$?
    [[ "$rc" -eq 0 ]] || { log_error "❌ Sync abortado: falló STAGING (rc=$rc)."; return "$rc"; }

    log_info "3/3 🚀 PROD"
    ( promote_to_prod )
    rc=$?
    [[ "$rc" -eq 0 ]] || { log_error "❌ Sync abortado: falló PROD (rc=$rc)."; return "$rc"; }

    echo
    log_success "🎉 Sync completo (cadena de confianza respetada)."
    return 0
}