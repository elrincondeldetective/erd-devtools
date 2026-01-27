#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/golden-sha.sh
#
# Este módulo maneja la lógica de "Fase 3": GOLDEN SHA REAL.
# Su objetivo es asegurar la integridad del commit que viaja de Dev -> Staging -> Main,
# validando que sea exactamente el mismo hash (FF-only) y gestionando la espera de PRs.

# ==============================================================================
# FASE 3: GOLDEN SHA REAL (mismo SHA dev -> staging -> main)
# ==============================================================================
# Objetivo:
# - Capturar y persistir el SHA “golden” que pasó checks y quedó en dev.
# - En staging/prod, asegurar que se promueve EXACTAMENTE ese SHA (ff-only).
#
# Overrides:
# - DEVTOOLS_ALLOW_GOLDEN_SHA_MISMATCH=1   -> permite continuar aunque no coincida (no recomendado).
# - DEVTOOLS_PR_MERGE_TIMEOUT_SECONDS=900  -> timeout espera merge PR (segundos).
# - DEVTOOLS_PR_MERGE_POLL_SECONDS=5       -> intervalo polling (segundos).

resolve_golden_sha_file() {
    # Preferimos dejar un rastro dentro de .devtools si existe como carpeta del repo,
    # pero si estamos dentro del repo erd-devtools (REPO_ROOT==.devtools), usamos root.
    if [[ -d "${REPO_ROOT}/.devtools" ]]; then
        echo "${REPO_ROOT}/.devtools/.last_golden_sha"
        return 0
    fi
    echo "${REPO_ROOT}/.last_golden_sha"
}

write_golden_sha() {
    local sha="$1"
    local meta="${2:-}"
    local f
    f="$(resolve_golden_sha_file)"

    [[ -n "${sha:-}" ]] || return 1

    {
        echo "$sha"
        [[ -n "$meta" ]] && echo "$meta"
        echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "$f" || return 1

    return 0
}

read_golden_sha() {
    local f
    f="$(resolve_golden_sha_file)"
    [[ -f "$f" ]] || return 1
    head -n 1 "$f" | tr -d '[:space:]'
}

ensure_local_tracking_branch() {
    local branch="$1"
    local remote="${2:-origin}"

    git fetch "$remote" "$branch" >/dev/null 2>&1 || true

    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        return 0
    fi

    if git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
        git checkout -b "$branch" "${remote}/${branch}" >/dev/null 2>&1 || return 1
        return 0
    fi

    # Último recurso: crear la rama desde el remoto explícito si existe
    if git rev-parse "${remote}/${branch}" >/dev/null 2>&1; then
        git checkout -b "$branch" "${remote}/${branch}" >/dev/null 2>&1 || return 1
        return 0
    fi

    return 1
}

wait_for_pr_merge_and_get_sha() {
    local pr_number="$1"
    local timeout="${DEVTOOLS_PR_MERGE_TIMEOUT_SECONDS:-900}"
    local interval="${DEVTOOLS_PR_MERGE_POLL_SECONDS:-5}"
    local elapsed=0

    while true; do
        # merged: true/false
        local merged state
        merged="$(gh pr view "$pr_number" --json merged --jq '.merged' 2>/dev/null || echo "false")"
        state="$(gh pr view "$pr_number" --json state --jq '.state' 2>/dev/null || echo "")"

        if [[ "$merged" == "true" ]]; then
            local merge_sha
            merge_sha="$(gh pr view "$pr_number" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null || echo "")"
            if [[ -n "${merge_sha:-}" && "${merge_sha:-null}" != "null" ]]; then
                echo "$merge_sha"
                return 0
            fi
            # Si está merged pero no podemos leer mergeCommit, seguimos intentando un poco.
        else
            # Si el PR se cerró sin merge, abortamos.
            if [[ "$state" == "CLOSED" ]]; then
                log_error "El PR #$pr_number está CLOSED y no fue mergeado. Abortando."
                return 1
            fi
        fi

        if (( elapsed >= timeout )); then
            log_error "Timeout esperando a que el PR #$pr_number sea mergeado."
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

sync_branch_to_origin() {
    local branch="$1"
    local remote="${2:-origin}"

    ensure_clean_git
    ensure_local_tracking_branch "$branch" "$remote" || {
        log_error "No pude preparar la rama '$branch' desde '$remote/$branch'."
        return 1
    }

    git checkout "$branch" >/dev/null 2>&1 || return 1
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    # Aseguramos que la rama local refleje EXACTAMENTE el remoto (golden truth)
    git reset --hard "${remote}/${branch}" >/dev/null 2>&1 || true
    return 0
}

assert_golden_sha_matches_head_or_die() {
    local context="$1"
    local allow="${DEVTOOLS_ALLOW_GOLDEN_SHA_MISMATCH:-0}"
    local golden=""
    golden="$(read_golden_sha 2>/dev/null || true)"

    if [[ -z "${golden:-}" ]]; then
        # Si no hay golden guardado, no bloqueamos (compat), pero avisamos.
        log_warn "No hay GOLDEN_SHA registrado. (Compat) Continuando sin validación estricta."
        return 0
    fi

    local head_sha
    head_sha="$(git rev-parse HEAD 2>/dev/null || true)"

    if [[ -z "${head_sha:-}" ]]; then
        log_error "No pude resolver HEAD para validar GOLDEN_SHA."
        return 1
    fi

    if [[ "$head_sha" != "$golden" ]]; then
        log_error "GOLDEN_SHA mismatch en ${context}."
        echo "   GOLDEN_SHA: $golden"
        echo "   HEAD      : $head_sha"
        if [[ "$allow" == "1" ]]; then
            log_warn "DEVTOOLS_ALLOW_GOLDEN_SHA_MISMATCH=1 -> Continuando bajo tu responsabilidad."
            return 0
        fi
        return 1
    fi

    log_success "GOLDEN_SHA validado en ${context}: $golden"
    return 0
}