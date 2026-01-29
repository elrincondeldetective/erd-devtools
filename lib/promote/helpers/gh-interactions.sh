#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/helpers/gh-interactions.sh
#
# Helpers de bajo nivel para interactuar con GitHub (gh) y referencias Git.
# Extraído de to-dev.sh para modularidad.
#
# Dependencias esperadas (cargadas por el orquestador): 
# - utils.sh (para log_info, log_error, is_tty)
# - checks.sh (para wait_for_workflow_success_on_ref_or_sha_or_die en modo no-tty)

# ------------------------------------------------------------------------------
# Helpers: Git Remoto (Read-only)
# ------------------------------------------------------------------------------
__remote_head_sha() {
    local branch="$1"
    local remote="${2:-origin}"
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    git rev-parse "${remote}/${branch}" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Helpers: Encontrar workflows en vivo (sin navegador)
# ------------------------------------------------------------------------------
__wait_for_workflow_run_id_for_sha() {
    # Args: workflow_file, sha_full, optional ref (branch/tag)
    local wf_file="$1"
    local sha_full="$2"
    local ref="${3:-}"

    local timeout="${DEVTOOLS_BUILD_WAIT_TIMEOUT_SECONDS:-1800}"
    local interval="${DEVTOOLS_BUILD_WAIT_POLL_SECONDS:-10}"
    local elapsed=0

    [[ -n "${wf_file:-}" && -n "${sha_full:-}" ]] || return 1

    while true; do
        local run_id=""

        if [[ -n "${ref:-}" ]]; then
            run_id="$(
              GH_PAGER=cat gh run list --workflow "$wf_file" --branch "$ref" -L 50 \
                --json databaseId,headSha,status,conclusion \
                --jq ".[] | select(.headSha==\"$sha_full\") | .databaseId" 2>/dev/null | head -n 1
            )"
        fi

        if [[ -z "${run_id:-}" ]]; then
            run_id="$(
              GH_PAGER=cat gh run list --workflow "$wf_file" -L 50 \
                --json databaseId,headSha,status,conclusion \
                --jq ".[] | select(.headSha==\"$sha_full\") | .databaseId" 2>/dev/null | head -n 1
            )"
        fi

        if [[ -n "${run_id:-}" ]]; then
            echo "$run_id"
            return 0
        fi

        if (( elapsed >= timeout )); then
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

__watch_workflow_success_on_sha_or_die() {
    # Args: workflow_file, sha_full, optional ref (branch/tag), label
    local wf_file="$1"
    local sha_full="$2"
    local ref="${3:-}"
    local label="${4:-workflow}"

    # Si el caller pide skip, respetamos (compat con checks.sh)
    if [[ "${DEVTOOLS_SKIP_WAIT_BUILD:-0}" == "1" ]]; then
        log_warn "DEVTOOLS_SKIP_WAIT_BUILD=1 -> Omitiendo espera de ${label}."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "No se encontró 'gh'. No puedo verificar ${label} en GitHub Actions."
        return 1
    fi

    # Modo TTY: progreso real en vivo
    if is_tty; then
        log_info "🏗️  Buscando run de ${label} (${wf_file}) para SHA ${sha_full:0:7}..."
        local run_id=""
        run_id="$(__wait_for_workflow_run_id_for_sha "$wf_file" "$sha_full" "$ref" || true)"
        if [[ -z "${run_id:-}" ]]; then
            log_error "Timeout esperando run de ${wf_file} para SHA ${sha_full:0:7}"
            return 1
        fi

        log_info "📺 Mostrando progreso en vivo: ${label} (run_id=$run_id)"
        if GH_PAGER=cat gh run watch "$run_id" --exit-status; then
            log_success "🏗️  ${label} OK (run_id=$run_id)"
            return 0
        fi

        log_error "${label} falló (run_id=$run_id)"
        return 1
    fi

    # No-TTY: fallback a polling centralizado (función externa, debe estar cargada en entorno)
    wait_for_workflow_success_on_ref_or_sha_or_die "$wf_file" "$sha_full" "$ref" "$label"
}

# ------------------------------------------------------------------------------
# Helpers: Pull Request (Aprobación y Release Please)
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