#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-dev.sh
#
# Este módulo maneja la promoción a DEV:
# - promote_to_dev: Crea/Mergea PRs, gestiona release-please y actualiza dev.
#
# Dependencias: utils.sh, git-ops.sh, checks.sh (cargadas por el orquestador)

# ------------------------------------------------------------------------------
# Helpers NO invasivos (no hacen checkout/reset; safe para correr en background)
# ------------------------------------------------------------------------------
__remote_head_sha() {
    local branch="$1"
    local remote="${2:-origin}"
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    git rev-parse "${remote}/${branch}" 2>/dev/null || true
}

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

# ------------------------------------------------------------------------------
# Monitor: espera merges/builds y captura GOLDEN_SHA sin tocar tu worktree
# Uso interno: git promote _dev-monitor <feature_pr_number> [feature_branch]
# ------------------------------------------------------------------------------
promote_dev_monitor() {
    local feature_pr="${1:-}"
    local feature_branch="${2:-}"

    [[ -n "${feature_pr:-}" ]] || { log_error "dev-monitor: falta PR number."; return 1; }

    log_info "🧠 DEV monitor iniciado (PR #${feature_pr}${feature_branch:+, branch=$feature_branch})"

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
        log_info "🤖 Esperando PR del bot release-please hacia dev..."
        rp_pr="$(wait_for_release_please_pr_number_or_die 2>/dev/null || true)"

        if [[ -n "${rp_pr:-}" ]]; then
            post_rp=1
            log_info "🤖 Habilitando auto-merge para PR del bot (#$rp_pr)..."
            # Importante: NO borramos la rama aquí; se limpia en promote staging.
            GH_PAGER=cat gh pr merge "$rp_pr" --auto --squash

            log_info "🔄 Esperando merge del PR del bot #$rp_pr..."
            rp_merge_sha="$(wait_for_pr_merge_and_get_sha "$rp_pr")"
            log_success "PR bot mergeado: ${rp_merge_sha:0:7}"
        else
            log_warn "🤷 No se detectó PR release-please--* en la ventana de espera. Continuando."
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
    # Default: async (libera terminal).
    # Compat: DEVTOOLS_PROMOTE_DEV_SYNC=1 vuelve al modo bloqueante.
    local sync="${DEVTOOLS_PROMOTE_DEV_SYNC:-0}"
    if [[ "$sync" == "1" ]]; then
        promote_dev_monitor "$pr_number" "$current_branch"
        exit $?
    fi

    # Lanzar monitor en background SIN tocar tu working tree.
    local promote_cmd
    promote_cmd="$(__resolve_promote_script)"

    local repo_name log_file golden_file
    repo_name="$(basename "${REPO_ROOT:-.}")"
    log_file="${TMPDIR:-/tmp}/devtools-promote-dev-${repo_name}-pr${pr_number}.log"
    golden_file="$(resolve_golden_sha_file 2>/dev/null || echo ".last_golden_sha")"

    if command -v nohup >/dev/null 2>&1; then
        nohup "$promote_cmd" _dev-monitor "$pr_number" "$current_branch" >"$log_file" 2>&1 &
    else
        ( "$promote_cmd" _dev-monitor "$pr_number" "$current_branch" >"$log_file" 2>&1 ) &
    fi

    banner "✅ DEV EN PROCESO (monitor en background)"
    echo "📄 Log del monitor: $log_file"
    echo "🔒 GOLDEN_SHA se escribirá en: $golden_file"
    echo

    log_info "📌 Issues abiertos (top 10):"
    if command -v gh >/dev/null 2>&1; then
        GH_PAGER=cat gh issue list --state open --limit 10 2>/dev/null || log_warn "No pude listar issues (¿gh auth?)."
    else
        log_warn "No se encontró 'gh'. No puedo listar issues."
    fi

    echo
    echo "👉 Cuando el monitor termine: git promote staging"
    exit 0
}