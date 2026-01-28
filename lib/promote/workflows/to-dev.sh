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
# Espera aprobación del PR (control humano)
# - Requiere al menos 1 review "APPROVED" (reviewDecision=APPROVED).
#
# Overrides:
# - DEVTOOLS_PR_APPROVAL_TIMEOUT_SECONDS=0  -> 0 = sin timeout (default).
# - DEVTOOLS_PR_APPROVAL_POLL_SECONDS=10    -> intervalo polling.
# - DEVTOOLS_SKIP_PR_APPROVAL_WAIT=1        -> bypass (no recomendado).
# ------------------------------------------------------------------------------
wait_for_pr_approval_or_die() {
    local pr_number="$1"
    local timeout="${DEVTOOLS_PR_APPROVAL_TIMEOUT_SECONDS:-0}"
    local interval="${DEVTOOLS_PR_APPROVAL_POLL_SECONDS:-10}"
    local elapsed=0

    if [[ "${DEVTOOLS_SKIP_PR_APPROVAL_WAIT:-0}" == "1" ]]; then
        log_warn "DEVTOOLS_SKIP_PR_APPROVAL_WAIT=1 -> Omitiendo espera de aprobación del PR."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "Se requiere 'gh' para verificar aprobación del PR."
        return 1
    fi

    log_info "⏳ Esperando aprobación del PR #$pr_number (reviewDecision=APPROVED)..."

    while true; do
        local state decision merged_at
        state="$(GH_PAGER=cat gh pr view "$pr_number" --json state --jq '.state // ""' 2>/dev/null || echo "")"
        decision="$(GH_PAGER=cat gh pr view "$pr_number" --json reviewDecision --jq '.reviewDecision // ""' 2>/dev/null || echo "")"
        merged_at="$(GH_PAGER=cat gh pr view "$pr_number" --json mergedAt --jq '.mergedAt // ""' 2>/dev/null || echo "")"

        # ✅ Si ya está mergeado, no tiene sentido esperar aprobación.
        if [[ -n "${merged_at:-}" && "${merged_at:-null}" != "null" ]]; then
            log_success "✅ PR #$pr_number ya está MERGED (mergedAt=$merged_at)."
            return 0
        fi

        if [[ "$decision" == "APPROVED" ]]; then
            log_success "✅ PR #$pr_number aprobado."
            return 0
        fi

        if [[ "$state" == "CLOSED" ]]; then
            log_error "El PR #$pr_number está CLOSED y no fue aprobado/mergeado. Abortando."
            return 1
        fi

        if (( timeout > 0 && elapsed >= timeout )); then
            log_error "Timeout esperando aprobación del PR #$pr_number."
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

# ------------------------------------------------------------------------------
# Espera opcional por PR de release-please.
# - Devuelve el PR number si aparece.
# - Devuelve vacío si no aparece (sin error fatal).
#
# Overrides:
# - DEVTOOLS_RP_PR_WAIT_TIMEOUT_SECONDS=60  -> tiempo máximo de espera (0 = no esperar).
# - DEVTOOLS_RP_PR_WAIT_POLL_SECONDS=2      -> intervalo polling.
# ------------------------------------------------------------------------------
wait_for_release_please_pr_number_optional() {
    local timeout="${DEVTOOLS_RP_PR_WAIT_TIMEOUT_SECONDS:-60}"
    local interval="${DEVTOOLS_RP_PR_WAIT_POLL_SECONDS:-2}"
    local elapsed=0

    # 0 = no esperar, retorno vacío
    if [[ "${timeout}" == "0" ]]; then
        echo ""
        return 0
    fi

    while true; do
        local pr_number
        pr_number="$(
            GH_PAGER=cat gh pr list --base dev --state open --json number,headRefName --jq \
            '.[] | select(.headRefName | startswith("release-please--")) | .number' 2>/dev/null | head -n 1
        )"

        if [[ "${pr_number:-}" =~ ^[0-9]+$ ]]; then
            echo "$pr_number"
            return 0
        fi

        if (( elapsed >= timeout )); then
            echo ""
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
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

    # 0) Esperar aprobación humana antes de permitir merge
    wait_for_pr_approval_or_die "$feature_pr" || return 1

    # 1) Habilitar auto-merge SOLO cuando ya está aprobado
    log_info "🤖 PR aprobado. Habilitando auto-merge (checks + merge)..."
    GH_PAGER=cat gh pr merge "$feature_pr" --auto --squash --delete-branch

    # 2) Esperar merge real
    log_info "🔄 Esperando merge del PR #$feature_pr..."
    # 0) Esperar aprobación humana antes de permitir merge
    wait_for_pr_approval_or_die "$feature_pr" || return 1

    # 1) Habilitar auto-merge SOLO cuando ya está aprobado
    log_info "🤖 PR aprobado. Habilitando auto-merge (checks + merge)..."
    GH_PAGER=cat gh pr merge "$feature_pr" --auto --squash --delete-branch

    # 2) Esperar merge real
    log_info "🔄 Esperando merge del PR #$feature_pr..."
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

    local pr_url
    pr_url="$(GH_PAGER=cat gh pr view "$pr_number" --json url --jq '.url // ""' 2>/dev/null || echo "")"

    banner "✅ PR CREADO (pendiente de aprobación)"
    [[ -n "${pr_url:-}" ]] && echo "🔗 PR: $pr_url"
    echo

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
