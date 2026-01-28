#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/checks.sh
#
# Este módulo contiene las funciones de verificación y espera (polling):
# - wait_for_release_please_pr_number_or_die
# - wait_for_tag_on_sha_or_die
# - wait_for_workflow_success_on_ref_or_sha_or_die
#
# Dependencias: Se asume que utils.sh (logging, is_tty) está cargado por el orquestador.

# ==============================================================================
# HELPERS: Checks y Esperas (Polling)
# ==============================================================================

wait_for_release_please_pr_number_or_die() {
    # Espera a que aparezca un PR head release-please--* hacia base dev
    local timeout="${DEVTOOLS_RP_PR_WAIT_TIMEOUT_SECONDS:-900}"
    local interval="${DEVTOOLS_RP_PR_WAIT_POLL_SECONDS:-5}"
    local elapsed=0

    # Si timeout=0, no esperamos (comportamiento útil para repos donde el bot puede no abrir PR)
    if [[ "${timeout}" == "0" ]]; then
        return 1
    fi

    while true; do
        local pr_number
        pr_number="$(
          GH_PAGER=cat gh pr list --base dev --state open --json number,headRefName --jq \
          '.[] | select(.headRefName | startswith("release-please--")) | .number' 2>/dev/null | head -n 1
        )"

        # Solo aceptamos números (evita propagar mensajes/ruido como "pr_number")
        if [[ "${pr_number:-}" =~ ^[0-9]+$ ]]; then
            echo "$pr_number"
            return 0
        fi

        if (( elapsed >= timeout )); then
            log_error "Timeout esperando PR release-please--* hacia dev." >&2
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

wait_for_tag_on_sha_or_die() {
    # Args: sha_full, pattern_regex, label
    local sha_full="$1"
    local pattern="$2"
    local label="${3:-tag}"
    local timeout="${DEVTOOLS_TAG_WAIT_TIMEOUT_SECONDS:-900}"
    local interval="${DEVTOOLS_TAG_WAIT_POLL_SECONDS:-5}"
    local elapsed=0

    log_info "🏷️  Esperando ${label} en SHA ${sha_full:0:7} (pattern: ${pattern})..."

    while true; do
        git fetch origin --tags --force >/dev/null 2>&1 || true
        local found
        found="$(git tag --points-at "$sha_full" 2>/dev/null | grep -E "$pattern" | head -n 1 || true)"
        if [[ -n "${found:-}" ]]; then
            log_success "🏷️  Tag detectado: $found"
            echo "$found"
            return 0
        fi

        if (( elapsed >= timeout )); then
            log_error "Timeout esperando ${label} en SHA ${sha_full:0:7}"
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

wait_for_workflow_success_on_ref_or_sha_or_die() {
    # Args: workflow_file, sha_full, optional ref (branch/tag)
    local wf_file="$1"
    local sha_full="$2"
    local ref="${3:-}"
    local label="${4:-workflow}"
    local timeout="${DEVTOOLS_BUILD_WAIT_TIMEOUT_SECONDS:-1800}"
    local interval="${DEVTOOLS_BUILD_WAIT_POLL_SECONDS:-10}"
    local elapsed=0

    if [[ "${DEVTOOLS_SKIP_WAIT_BUILD:-0}" == "1" ]]; then
        log_warn "DEVTOOLS_SKIP_WAIT_BUILD=1 -> Omitiendo espera de ${label}."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "No se encontró 'gh'. No puedo verificar ${label} en GitHub Actions."
        return 1
    fi

    log_info "🏗️  Esperando ${label} (${wf_file}) en SHA ${sha_full:0:7}..."

    local run_id=""

    while true; do
        if [[ -n "${ref:-}" ]]; then
            run_id="$(
              GH_PAGER=cat gh run list --workflow "$wf_file" --branch "$ref" -L 30 \
                --json databaseId,headSha,status,conclusion \
                --jq ".[] | select(.headSha==\"$sha_full\") | .databaseId" 2>/dev/null | head -n 1
            )"
        fi

        if [[ -z "${run_id:-}" ]]; then
            run_id="$(
              GH_PAGER=cat gh run list --workflow "$wf_file" -L 30 \
                --json databaseId,headSha,status,conclusion \
                --jq ".[] | select(.headSha==\"$sha_full\") | .databaseId" 2>/dev/null | head -n 1
            )"
        fi

        if [[ -n "${run_id:-}" ]]; then
            break
        fi

        if (( elapsed >= timeout )); then
            log_error "Timeout esperando que aparezca un run de ${wf_file} para SHA ${sha_full:0:7}"
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    # ──────────────────────────────────────────────────────────────────────────
    # MODO “PROGRESO REAL” EN VIVO (TTY): gh run watch
    # ──────────────────────────────────────────────────────────────────────────
    if is_tty; then
        log_info "📺 Mostrando progreso en vivo del run_id=$run_id (GitHub Actions)..."
        # gh run watch termina con exit code != 0 si falla, y eso lo tratamos como fallo del workflow.
        if GH_PAGER=cat gh run watch "$run_id" --exit-status; then
            log_success "🏗️  ${label} OK (run_id=$run_id)"
            return 0
        else
            log_error "${label} falló (run_id=$run_id)"
            return 1
        fi
    fi

    # ──────────────────────────────────────────────────────────────────────────
    # FALLBACK NO-TTY: polling (comportamiento actual)
    # ──────────────────────────────────────────────────────────────────────────
    elapsed=0
    while true; do
        local status conclusion
        status="$(GH_PAGER=cat gh run view "$run_id" --json status --jq '.status' 2>/dev/null || echo "")"
        conclusion="$(GH_PAGER=cat gh run view "$run_id" --json conclusion --jq '.conclusion' 2>/dev/null || echo "")"

        if [[ "$status" == "completed" ]]; then
            if [[ "$conclusion" == "success" ]]; then
                log_success "🏗️  ${label} OK (run_id=$run_id)"
                return 0
            fi
            log_error "${label} falló (run_id=$run_id, conclusion=$conclusion)"
            return 1
        fi

        if (( elapsed >= timeout )); then
            log_error "Timeout esperando a que termine ${label} (run_id=$run_id)"
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}