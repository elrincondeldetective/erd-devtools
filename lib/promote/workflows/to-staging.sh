#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-staging.sh
#
# CONTRATO: STAGING CERO FRICCIÓN (default)
# Objetivo: Menú (estrategia) → Push → Confirmación (git ls-remote) → Landing (quedar en staging).
# Por defecto NO: tagging, esperas, GitOps, releases/gh, notas interactivas, comparaciones.
# (Este archivo debe mantenerse corto y predecible.)

promote_to_staging() {
    resync_submodules_hard
    ensure_clean_git

    # Siempre trabajamos sobre un dev actualizado desde origin (HEAD real)
    ensure_local_tracking_branch "dev" "origin" || { log_error "No pude preparar la rama 'dev' desde 'origin/dev'."; exit 1; }
    if [[ "$(git branch --show-current)" != "dev" ]]; then
        log_warn "No estás en 'dev'. Cambiando..."
        git checkout dev >/dev/null 2>&1 || exit 1
    fi
    update_branch_from_remote "dev"

    local dev_sha
    dev_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    [[ -n "${dev_sha:-}" ]] || { log_error "No pude resolver DEV HEAD."; exit 1; }
    log_info "✅ DEV HEAD: ${dev_sha:0:7}"

    local strategy="${DEVTOOLS_PROMOTE_STRATEGY:-ff-only}"
    local staging_sha="" rc=0
    while true; do
        staging_sha="$(update_branch_to_sha_with_strategy "staging" "$dev_sha" "origin" "$strategy")"
        rc=$?
        if [[ "$rc" -eq 3 ]]; then
            log_warn "⚠️ Fast-Forward no es posible (hay divergencia en staging). Elige otra estrategia."
            strategy="$(promote_choose_strategy_or_die)"
            export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
            continue
        fi
        [[ "$rc" -eq 0 ]] || { log_error "No pude actualizar 'staging' con estrategia ${strategy} (rc=${rc})."; exit 1; }
        break
    done

    log_success "✅ Staging actualizado. SHA final: ${staging_sha:0:7}"
    echo
    log_info "🔎 Confirmación visual (git ls-remote --heads origin staging):"
    git ls-remote --heads origin staging 2>/dev/null || true
    echo

    exit 0
}
