#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/sync.sh
#
# Este módulo maneja SYNC como MACRO ESTRICTO (sin backdoors):
# - promote_sync_all: Ejecuta la cadena de confianza completa:
#   1) Lab -> DEV (modo directo/aplastante, hardcoded feature/dev-update)
#   2) DEV -> STAGING (Golden SHA estricto + waits)
#   3) STAGING -> PROD (Golden SHA estricto + waits + release)
#
# Dependencias: utils.sh, git-ops.sh, y módulos de promote (cargados por workflows.sh)

# ==============================================================================
# 1. SYNC MACRO (estricto)
# ==============================================================================
promote_sync_all() {
    local current_branch
    current_branch="$(git branch --show-current 2>/dev/null || echo "")"

    # 🔒 Requisito: debes estar en la rama de laboratorio
    if [[ "$current_branch" != "feature/dev-update" ]]; then
        die "⛔ Sync estricto requiere estar en feature/dev-update. Cámbiate a esa rama y reintenta."
    fi

    echo
    banner "🔄 SYNC (MACRO SEGURO)"
    log_info "Cadena: feature/dev-update -> dev -> staging -> prod"
    log_info "Nota: -y/--yes salta confirmaciones humanas, pero NUNCA gates técnicos."
    echo

    # Verificar que las funciones base existen (módulos cargados por workflows.sh)
    declare -F promote_to_dev >/dev/null 2>&1 || die "No está cargado promote_to_dev (to-dev.sh)."
    declare -F promote_to_staging >/dev/null 2>&1 || die "No está cargado promote_to_staging (to-staging.sh)."
    declare -F promote_to_prod >/dev/null 2>&1 || die "No está cargado promote_to_prod (to-prod.sh)."

    local rc=0

    log_info "1/3 🧨 DEV (Lab -> Source of Truth)"
    (
        export DEVTOOLS_PROMOTE_DEV_DIRECT=1
        promote_to_dev
    )
    rc=$?
    [[ "$rc" -eq 0 ]] || { log_error "❌ Sync abortado: falló DEV (rc=$rc)."; return "$rc"; }

    log_info "2/3 🏷️ STAGING (Golden SHA + waits + release)"
    ( promote_to_staging )
    rc=$?
    [[ "$rc" -eq 0 ]] || { log_error "❌ Sync abortado: falló STAGING (rc=$rc)."; return "$rc"; }

    log_info "3/3 🚀 PROD (Golden SHA + waits + release)"
    ( promote_to_prod )
    rc=$?
    [[ "$rc" -eq 0 ]] || { log_error "❌ Sync abortado: falló PROD (rc=$rc)."; return "$rc"; }

    echo
    log_success "🎉 Sync completo (cadena de confianza respetada)."
    return 0
}