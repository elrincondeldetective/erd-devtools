#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-dev.sh
# 
#
# Este módulo maneja la promoción a DEV:
# - promote_to_dev: Crea/Mergea PRs, gestiona release-please y actualiza dev.
# - (Opcional) Modo directo: Squash local + Push directo a dev (sin PR).
#
# Dependencias externas: utils.sh, git-ops.sh, checks.sh (cargadas por el orquestador principal)
# Dependencias internas: helpers/gh-interactions.sh, strategies/*.sh (cargadas dinámicamente aquí)

# ------------------------------------------------------------------------------
# Dynamic Imports (Refactorización Modular)
# ------------------------------------------------------------------------------
# Detectamos el directorio actual (workflows) y subimos un nivel para encontrar
# 'helpers' y 'strategies' dentro de /lib/promote/
_CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROMOTE_LIB_ROOT="$(dirname "$_CURRENT_DIR")"

# 1. Cargar Helpers de GitHub/Git
if [[ -f "${_PROMOTE_LIB_ROOT}/helpers/gh-interactions.sh" ]]; then
    source "${_PROMOTE_LIB_ROOT}/helpers/gh-interactions.sh"
else
    echo "❌ Error: No se encontró helpers/gh-interactions.sh" >&2
    exit 1
fi

# 2. Cargar Estrategia: Directa (No PR)
if [[ -f "${_PROMOTE_LIB_ROOT}/strategies/dev-direct.sh" ]]; then
    source "${_PROMOTE_LIB_ROOT}/strategies/dev-direct.sh"
else
    echo "❌ Error: No se encontró strategies/dev-direct.sh" >&2
    exit 1
fi

# 3. Cargar Estrategia: Monitor PR (Async/Sync)
if [[ -f "${_PROMOTE_LIB_ROOT}/strategies/dev-pr-monitor.sh" ]]; then
    source "${_PROMOTE_LIB_ROOT}/strategies/dev-pr-monitor.sh"
else
    echo "❌ Error: No se encontró strategies/dev-pr-monitor.sh" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Helpers Locales (Orquestación de procesos)
# ------------------------------------------------------------------------------

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

# ==============================================================================
# 3. PROMOTE TO DEV (Main Entry Point)
# ==============================================================================
promote_to_dev() {
    # [FIX] Resync de submódulos antes de cualquier validación (ensure_clean_git)
    resync_submodules_hard

    # --------------------------------------------------------------------------
    # ESTRATEGIA 1: Modo DIRECTO (sin PR feature->dev)
    # --------------------------------------------------------------------------
    # Aplasta localmente (squash) feature -> dev, push directo a origin/dev
    if [[ "${DEVTOOLS_PROMOTE_DEV_DIRECT:-0}" == "1" ]]; then
        # Función importada de strategies/dev-direct.sh
        promote_to_dev_direct
        exit $?
    fi

    # --------------------------------------------------------------------------
    # ESTRATEGIA 2: Modo PR Standard (feature -> PR -> dev)
    # --------------------------------------------------------------------------
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
        # Función importada de strategies/dev-pr-monitor.sh
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