#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-prod.sh
#
# CONTRATO: PROD CERO FRICCIÓN (default)
# Objetivo: Menú (estrategia) → Push → Confirmación (git ls-remote) → Landing.
# Por defecto NO: tagging, esperas, GitOps, releases/gh, notas interactivas, comparaciones.

promote_to_prod() {
    resync_submodules_hard
    ensure_clean_git

    # Siempre trabajamos sobre un staging actualizado desde origin (HEAD real)
    ensure_local_tracking_branch "staging" "origin" || { log_error "No pude preparar la rama 'staging' desde 'origin/staging'."; exit 1; }
    if [[ "$(git branch --show-current)" != "staging" ]]; then
        log_warn "No estás en 'staging'. Cambiando..."
        git checkout staging >/dev/null 2>&1 || exit 1
    fi
    update_branch_from_remote "staging"

    local staging_sha
    staging_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    [[ -n "${staging_sha:-}" ]] || { log_error "No pude resolver STAGING HEAD."; exit 1; }
    log_info "✅ STAGING HEAD: ${staging_sha:0:7}"

    local strategy="${DEVTOOLS_PROMOTE_STRATEGY:-ff-only}"
    local main_sha="" rc=0
    while true; do
        main_sha="$(update_branch_to_sha_with_strategy "main" "$staging_sha" "origin" "$strategy")"
        rc=$?
        if [[ "$rc" -eq 3 ]]; then
            log_warn "⚠️ Fast-Forward no es posible (hay divergencia en main). Elige otra estrategia."
            strategy="$(promote_choose_strategy_or_die)"
            export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
            continue
        fi
        [[ "$rc" -eq 0 ]] || { log_error "No pude actualizar 'main' con estrategia ${strategy} (rc=${rc})."; exit 1; }
        break
    done

    log_success "✅ Producción actualizada. SHA final: ${main_sha:0:7}"
    echo
    log_info "🔎 Confirmación visual (git ls-remote --heads origin main):"
    git ls-remote --heads origin main 2>/dev/null || true
    echo

    exit 0
}
