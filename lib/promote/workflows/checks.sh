#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/checks.sh
#
# CHECKS.SH = ÚNICA FUENTE DE VERDAD (validaciones por SHA)
# - Tabla de estado por workflow requerido
# - Gate por SHA (PENDING con retry corto)
# - Smart pick para --watch (FAILURE > IN_PROGRESS)
# Este módulo contiene las funciones de verificación y espera (polling):
# - wait_for_release_please_pr_number_or_die
# - wait_for_tag_on_sha_or_die
# - wait_for_workflow_success_on_ref_or_sha_or_die
#
# Dependencias: Se asume que utils.sh (logging, is_tty) está cargado por el orquestador.

# ==============================================================================
# HELPERS: Checks y Esperas (Polling)
# ==============================================================================

print_tags_at_sha() {
    local sha_full="$1"
    local label="${2:-tags@sha}"
    [[ -n "${sha_full:-}" ]] || return 0
    git fetch origin --tags --force >/dev/null 2>&1 || true
    local tags
    tags="$(git tag --points-at "$sha_full" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    if [[ -n "${tags:-}" ]]; then
        log_info "🏷️  ${label}: ${tags}"
    else
        log_info "🏷️  ${label}: (none)"
    fi
}

print_run_link() {
    local run_id="$1"
    local label="${2:-run}"
    [[ -n "${run_id:-}" ]] || return 0
    local url
    url="$(GH_PAGER=cat gh run view "$run_id" --json htmlURL --jq '.htmlURL' 2>/dev/null || true)"
    if [[ -n "${url:-}" && "${url:-null}" != "null" ]]; then
        log_info "🔗 ${label} URL: ${url}"
    fi
}

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
    # Link del run (para no ir a la web a ciegas)
    print_run_link "$run_id" "${label} (run_id=${run_id})"

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

# ==============================================================================
# GUARDIA DE INTEGRIDAD: Validación de Working Tree Limpio
# ------------------------------------------------------------------------------
# Acción: Verifica si hay cambios locales (staged o unstaged).
# Efecto: Aborta la ejecución (exit 1) si el repositorio está "sucio".
# Razón: La promoción aplastante sobreescribe el estado actual; un repo limpio
#        garantiza que no se pierda código sin commitear.
# ==============================================================================
ensure_clean_git_or_die() {
    if [[ -n "$(git status --porcelain)" ]]; then
        echo
        log_error "❌ REPO SUCIO: Tienes cambios sin commitear."
        log_warn "La promoción aplastante requiere un working tree limpio para evitar pérdida de datos."
        echo "Sugerencia: git add . && git commit -m 'savepoint' o git stash"
        exit 1
    fi
}

# ==============================================================================
# CONFIG: Workflows requeridos (centralizado en .devtools/config/workflows.conf)
# ==============================================================================

resolve_workflows_conf_file() {
    # 1) Si estamos dentro del repo .devtools (REPO_ROOT == .devtools)
    local root="${REPO_ROOT:-.}"
    if [[ -f "${root}/config/workflows.conf" ]]; then
        echo "${root}/config/workflows.conf"
        return 0
    fi

    # 2) Si estamos en un superproyecto que contiene .devtools (WORKSPACE_ROOT)
    if [[ -n "${WORKSPACE_ROOT:-}" && -f "${WORKSPACE_ROOT}/.devtools/config/workflows.conf" ]]; then
        echo "${WORKSPACE_ROOT}/.devtools/config/workflows.conf"
        return 0
    fi

    # 3) Fallback: cwd + .devtools/config
    if [[ -f ".devtools/config/workflows.conf" ]]; then
        echo ".devtools/config/workflows.conf"
        return 0
    fi

    return 1
}

load_required_workflows_dev_or_die() {
    local f=""
    f="$(resolve_workflows_conf_file 2>/dev/null || true)"

    if [[ -z "${f:-}" || ! -f "$f" ]]; then
        log_error "❌ Error: No se encontró workflows.conf."
        echo "   esperado: .devtools/config/workflows.conf"
        echo "👉 Solución: crea el archivo y define REQUIRED_WORKFLOWS_DEV=(...)"
        return 1
    fi

    # Respetar set -u del caller (temporalmente lo apagamos para source seguro)
    local nounset_was_on=0
    case "$-" in *u*) nounset_was_on=1 ;; esac
    set +u
    # shellcheck disable=SC1090
    source "$f"
    (( nounset_was_on )) && set -u

    if ! declare -p REQUIRED_WORKFLOWS_DEV >/dev/null 2>&1; then
        log_error "❌ workflows.conf no define REQUIRED_WORKFLOWS_DEV."
        echo "   file: $f"
        echo "👉 Ejemplo: REQUIRED_WORKFLOWS_DEV=(\"release-please.yaml\" \"build-push.yaml\")"
        return 1
    fi

    if [[ "${#REQUIRED_WORKFLOWS_DEV[@]}" -eq 0 ]]; then
        log_error "❌ REQUIRED_WORKFLOWS_DEV está vacío."
        echo "   file: $f"
        return 1
    fi

    export DEVTOOLS_WORKFLOWS_CONF_FILE="$f"
    return 0
}

# ==============================================================================
# API: obtener meta de un workflow para un SHA exacto (status + conclusion + run_id)
# ==============================================================================

__wf_meta_for_sha_once() {
    # Args: wf_file sha_full ref(optional)
    local wf_file="$1"
    local sha_full="$2"
    local ref="${3:-}"

    [[ -n "${wf_file:-}" && -n "${sha_full:-}" ]] || return 1

    local line=""
    if [[ -n "${ref:-}" ]]; then
        line="$(
            GH_PAGER=cat gh run list --workflow "$wf_file" --branch "$ref" -L 50 \
            --json databaseId,headSha,status,conclusion \
            --jq ".[] | select(.headSha==\"$sha_full\") | \"\(.databaseId)|\(.status)|\(.conclusion // \"\")\"" \
            2>/dev/null | head -n 1 || true
        )"
    else
        line="$(
            GH_PAGER=cat gh run list --workflow "$wf_file" -L 50 \
            --json databaseId,headSha,status,conclusion \
            --jq ".[] | select(.headSha==\"$sha_full\") | \"\(.databaseId)|\(.status)|\(.conclusion // \"\")\"" \
            2>/dev/null | head -n 1 || true
        )"
    fi

    [[ -n "${line:-}" ]] || return 1
    echo "$line"
    return 0
}

# ==============================================================================
# GATE: workflows requeridos por SHA (tabla + PENDING retry + smart pick)
# ==============================================================================

# Output global para “smart watch”
DEVTOOLS_GATE_SELECTED_RUN_ID=""
DEVTOOLS_GATE_SELECTED_WORKFLOW=""
DEVTOOLS_GATE_SELECTED_REASON=""

gate_required_workflows_on_sha() {
    # Args: sha_full ref workflows...
    local sha_full="$1"
    local ref="$2"
    shift 2
    local -a workflows=( "$@" )

    local tries="${DEVTOOLS_GATE_PENDING_TRIES:-3}"
    local interval="${DEVTOOLS_GATE_PENDING_POLL_SECONDS:-10}"

    DEVTOOLS_GATE_SELECTED_RUN_ID=""
    DEVTOOLS_GATE_SELECTED_WORKFLOW=""
    DEVTOOLS_GATE_SELECTED_REASON=""

    [[ -n "${sha_full:-}" ]] || { log_error "gate: falta sha"; return 1; }
    [[ "${#workflows[@]}" -gt 0 ]] || { log_error "gate: no workflows"; return 1; }

    echo
    echo "┌───────────────────────────────────────────────────────────────"
    echo "│ 🔎 Gate por SHA: ${sha_full:0:7}  (ref=${ref})"
    [[ -n "${DEVTOOLS_WORKFLOWS_CONF_FILE:-}" ]] && echo "│ config: ${DEVTOOLS_WORKFLOWS_CONF_FILE}"
    echo "├───────────────────────────────┬──────────────┬───────────────"
    echo "│ Workflow                      │ Estado       │ Conclusión"
    echo "├───────────────────────────────┼──────────────┼───────────────"

    local all_ok=1
    local wf
    for wf in "${workflows[@]}"; do
        local meta=""
        local i=0
        while (( i < tries )); do
            meta="$(__wf_meta_for_sha_once "$wf" "$sha_full" "$ref" 2>/dev/null || true)"
            [[ -n "${meta:-}" ]] && break
            i=$((i+1))
            (( i < tries )) && sleep "$interval"
        done

        local run_id="" status="" conclusion="" state_icon="" state_txt=""

        if [[ -z "${meta:-}" ]]; then
            # No run todavía: PENDING (bloquea)
            state_icon="⏳"
            status="PENDING"
            conclusion="(no run)"
            all_ok=0
        else
            IFS='|' read -r run_id status conclusion <<< "$meta"
            conclusion="${conclusion:-}"

            if [[ "$status" != "completed" ]]; then
                state_icon="⏳"
                status="${status:-IN_PROGRESS}"
                conclusion="${conclusion:-}"
                all_ok=0
                # pick 2: IN_PROGRESS si no hay failure elegido
                if [[ -z "${DEVTOOLS_GATE_SELECTED_RUN_ID:-}" ]]; then
                    DEVTOOLS_GATE_SELECTED_RUN_ID="$run_id"
                    DEVTOOLS_GATE_SELECTED_WORKFLOW="$wf"
                    DEVTOOLS_GATE_SELECTED_REASON="in_progress"
                fi
            else
                if [[ "$conclusion" == "success" ]]; then
                    state_icon="✅"
                    status="completed"
                    conclusion="success"
                else
                    state_icon="❌"
                    status="completed"
                    conclusion="${conclusion:-unknown}"
                    all_ok=0
                    # pick 1: FAILURE siempre gana
                    if [[ "${DEVTOOLS_GATE_SELECTED_REASON:-}" != "failure" ]]; then
                        DEVTOOLS_GATE_SELECTED_RUN_ID="$run_id"
                        DEVTOOLS_GATE_SELECTED_WORKFLOW="$wf"
                        DEVTOOLS_GATE_SELECTED_REASON="failure"
                    fi
                fi
            fi
        fi

        printf "│ %-29s │ %-12s │ %-13s\n" "$wf" "${state_icon} ${status}" "${conclusion}"
    done

    echo "└───────────────────────────────┴──────────────┴───────────────"

    if [[ "$all_ok" -eq 1 ]]; then
        log_success "✅ Gate OK (todos los workflows requeridos están SUCCESS para este SHA)."
        return 0
    fi

    log_error "🚨 Gate ROJO (faltan runs o hay fallos para este SHA)."
    if [[ -n "${DEVTOOLS_GATE_SELECTED_RUN_ID:-}" ]]; then
        print_run_link "${DEVTOOLS_GATE_SELECTED_RUN_ID}" "watch candidate (${DEVTOOLS_GATE_SELECTED_WORKFLOW})"
    fi
    return 1
}

gate_watch_selected_run_if_any() {
    # Usa el smart pick del gate. No aborta el proceso si falla.
    [[ -n "${DEVTOOLS_GATE_SELECTED_RUN_ID:-}" ]] || return 0
    is_tty || return 0
    command -v gh >/dev/null 2>&1 || return 0

    echo
    log_info "📺 [AUTO-WATCH] ${DEVTOOLS_GATE_SELECTED_WORKFLOW} (reason=${DEVTOOLS_GATE_SELECTED_REASON})"
    GH_PAGER=cat gh run watch "${DEVTOOLS_GATE_SELECTED_RUN_ID}" --exit-status 2>&1 || true
    echo
    return 0
}