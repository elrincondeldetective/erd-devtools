#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-dev.sh
#
# Este módulo maneja la promoción a DEV:
# - promote_to_dev: Crea/Mergea PRs, gestiona release-please y actualiza dev.
#
# Dependencias: utils.sh, git-ops.sh, checks.sh (cargadas por el orquestador)

# ==============================================================================
# 3. PROMOTE TO DEV
# ==============================================================================
promote_to_dev() {
    # [FIX] Resync de submódulos antes de cualquier validación (ensure_clean_git)
    resync_submodules_hard

    local current_branch
    current_branch="$(git branch --show-current)"

    if [[ "$current_branch" == "dev" || "$current_branch" == "staging" || "$current_branch" == "main" ]]; then
        log_error "Estás en '$current_branch'. Debes estar en una feature branch."
        exit 1
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "Se requiere 'gh' para el flujo PR-based (git promote dev crea el PR)."
        exit 1
    fi

    echo "🔍 Buscando (o creando) PR para '$current_branch' -> dev..."
    local pr_number
    pr_number="$(GH_PAGER=cat gh pr list --head "$current_branch" --base dev --state open --json number --jq '.[0].number' 2>/dev/null || true)"

    if [[ -z "${pr_number:-}" ]]; then
        ensure_clean_git
        GH_PAGER=cat gh pr create --base dev --head "$current_branch" --fill
        pr_number="$(GH_PAGER=cat gh pr list --head "$current_branch" --base dev --state open --json number --jq '.[0].number' 2>/dev/null || true)"
    fi

    if [[ -z "${pr_number:-}" ]]; then
        log_error "No pude resolver el PR para '$current_branch' -> dev."
        exit 1
    fi

    banner "🤖 PR LISTO (#$pr_number) -> dev"
    echo "⏳ Habilitando auto-merge (espera aprobación + checks)..."
    GH_PAGER=cat gh pr merge "$pr_number" --auto --squash --delete-branch

    echo "🔄 Esperando merge del PR #$pr_number..."
    local merge_sha
    merge_sha="$(wait_for_pr_merge_and_get_sha "$pr_number")"

    sync_branch_to_origin "dev" "origin"

    # Esperar PR del bot (release-please) si existe el workflow.
    # Importante: release-please puede decidir NO abrir PR si no hay bump; en ese caso seguimos.
    if repo_has_workflow_file "release-please"; then
        echo
        log_info "🤖 Esperando PR del bot release-please hacia dev..."
        local rp_pr
        rp_pr="$(wait_for_release_please_pr_number_or_die 2>/dev/null || true)"

        if [[ -n "${rp_pr:-}" ]]; then
            log_info "🤖 Habilitando auto-merge para PR del bot (#$rp_pr)..."
            # Importante: NO borramos la rama aquí; se limpia en promote staging.
            GH_PAGER=cat gh pr merge "$rp_pr" --auto --squash

            echo "🔄 Esperando merge del PR del bot #$rp_pr..."
            local rp_merge_sha
            rp_merge_sha="$(wait_for_pr_merge_and_get_sha "$rp_pr")"

            sync_branch_to_origin "dev" "origin"
        else
            log_warn "🤷 No se detectó PR release-please--* en la ventana de espera. Continuando."
        fi
    fi

    # En este punto, el SHA “válido” es el HEAD de dev (post-bot si existió)
    local dev_sha
    dev_sha="$(git rev-parse HEAD 2>/dev/null || true)"

    # Esperar build-push en dev si existe en este repo (PMBOK sí, erd-ecosystem no)
    if repo_has_workflow_file "build-push"; then
        wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$dev_sha" "dev" "Build and Push"
    fi

    write_golden_sha "$dev_sha" "source=origin/dev post_release_please=1" || true
    log_success "✅ GOLDEN_SHA (post-bot) capturado: $dev_sha"

    local changed_paths
    changed_paths="$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)"
    maybe_trigger_gitops_update "dev" "$dev_sha" "$changed_paths"

    banner "✅ DEV LISTO (post-bot + build OK)"
    echo "👉 Siguiente paso: git promote staging"
    exit 0
}