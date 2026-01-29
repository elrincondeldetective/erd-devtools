#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/strategies/dev-pr-monitor.sh
#
# Estrategia de promoción vía Pull Request (Monitor).
# Se encarga de orquestar el merge del PR de feature, el PR del bot (release-please)
# y la validación final del build para capturar el GOLDEN_SHA.
#
# Dependencias esperadas (inyectadas por to-dev.sh):
# - utils.sh (logs, banner, repo_has_workflow_file)
# - helpers/gh-interactions.sh (wait_for_pr_approval, __remote_head_sha, etc.)
# - git-ops.sh (maybe_trigger_gitops_update)

promote_dev_monitor() {
    local feature_pr="${1:-}"
    local feature_branch="${2:-}"

    [[ -n "${feature_pr:-}" ]] || { log_error "dev-monitor: falta PR number."; return 1; }

    log_info "🧠 DEV monitor iniciado (PR #${feature_pr}${feature_branch:+, branch=$feature_branch})"

    # 0) Esperar aprobación humana antes de permitir merge
    wait_for_pr_approval_or_die "$feature_pr" || return 1

    # 1) Habilitar auto-merge SOLO cuando ya está aprobado
    log_info "🤖 PR aprobado. Habilitando auto-merge (checks + merge)..."
    GH_PAGER=cat gh pr merge "$feature_pr" --auto --squash --delete-branch

    # 2) Esperar merge real
    log_info "🔄 Esperando merge del PR #$feature_pr..."
    local merge_sha
    merge_sha="$(wait_for_pr_merge_and_get_sha "$feature_pr")"
    log_success "PR feature mergeado: ${merge_sha:0:7}"

    local rp_pr=""
    local rp_merge_sha=""
    local post_rp=0

    # Esperar PR del bot (release-please) si existe el workflow.
    # Importante: release-please puede decidir NO abrir PR si no hay bump; en ese caso seguimos.
    if repo_has_workflow_file "release-please"; then
        log_info "🤖 Esperando PR del bot release-please hacia dev (opcional)..."
        rp_pr="$(wait_for_release_please_pr_number_optional)"

        # ✅ SOLO si es numérico
        if [[ "${rp_pr:-}" =~ ^[0-9]+$ ]]; then
            post_rp=1
            log_info "🤖 Habilitando auto-merge para PR del bot (#$rp_pr)..."
            GH_PAGER=cat gh pr merge "$rp_pr" --auto --squash

            log_info "🔄 Esperando merge del PR del bot #$rp_pr..."
            rp_merge_sha="$(wait_for_pr_merge_and_get_sha "$rp_pr")"
            log_success "PR bot mergeado: ${rp_merge_sha:0:7}"
        else
            log_warn "🤷 No se detectó PR release-please--* (o timeout). Continuando."
        fi
    fi

    # En este punto, el SHA “válido” es el HEAD remoto de dev (post-bot si existió)
    local dev_sha
    dev_sha="$(__remote_head_sha "dev" "origin")"
    if [[ -z "${dev_sha:-}" ]]; then
        log_error "No pude resolver origin/dev para capturar GOLDEN_SHA."
        return 1
    fi

    # Esperar build-push en dev si existe en este repo
    if repo_has_workflow_file "build-push"; then
        wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$dev_sha" "dev" "Build and Push"
    fi

    write_golden_sha "$dev_sha" "source=origin/dev post_release_please=${post_rp} feature_pr=${feature_pr} rp_pr=${rp_pr:-none}" || true
    log_success "✅ GOLDEN_SHA (post-bot) capturado: $dev_sha"

    # GitOps (no invasivo): igual al comportamiento anterior (último commit), pero sin checkout
    local changed_paths
    changed_paths="$(git diff --name-only "${dev_sha}~1..${dev_sha}" 2>/dev/null || true)"
    maybe_trigger_gitops_update "dev" "$dev_sha" "$changed_paths"

    banner "✅ DEV LISTO (monitor finalizado)"
    echo "👉 Siguiente paso: git promote staging"
    return 0
}