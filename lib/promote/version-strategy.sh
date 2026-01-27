#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/version-strategy.sh
#
# Este módulo maneja las estrategias de versionado y etiquetado (Tagging).
# Determina dónde se encuentra el archivo de versión y quién es el responsable
# de crear los tags (el script local o un workflow de GitHub).

# ==============================================================================
# FASE 1: NORMALIZACIÓN ROBUSTA DE VERSION FILE (repo actual)
# ==============================================================================
# Objetivo:
# - Garantizar que siempre leemos VERSION desde el repo actual, NO desde .devtools embebido.
# - Mantener backward-compat: si REPO_ROOT no existe por algún motivo, lo inferimos.
# - Permitir que GitHub (release-please) sea el único que “decide” la versión (local no recalcula).

resolve_repo_version_file() {
    # Preferimos VERSION en la raíz del repo actual
    if [[ -n "${REPO_ROOT:-}" && -f "${REPO_ROOT}/VERSION" ]]; then
        echo "${REPO_ROOT}/VERSION"
        return 0
    fi

    # Backward-compat (histórico): relativo a .devtools/bin (puede apuntar a .devtools/VERSION)
    # Nota: SCRIPT_DIR debe venir del script principal que hace el source.
    if [[ -n "${SCRIPT_DIR:-}" && -f "${SCRIPT_DIR}/../VERSION" ]]; then
        echo "${SCRIPT_DIR}/../VERSION"
        return 0
    fi

    # Fallback: relativo al cwd
    if [[ -f "VERSION" ]]; then
        echo "VERSION"
        return 0
    fi

    # Fallback final
    echo "VERSION"
}

# ==============================================================================
# FASE 2: UN SOLO DUEÑO DE TAGS (LOCAL vs GITHUB)
# ==============================================================================
# Objetivo:
# - Evitar duplicados/carreras cuando el repo ya tiene workflows que crean tags.
# - Regla:
#   - Si el repo TIENE workflows de tagging (tag-rc-on-staging / tag-final-on-main),
#     entonces GitHub es el dueño del tag y el promote local NO crea tags.
#   - Si no existen, el promote local sigue creando tags (comportamiento histórico).
#
# Overrides:
# - DEVTOOLS_FORCE_LOCAL_TAGS=1  -> fuerza tag local aunque existan workflows.
# - DEVTOOLS_DISABLE_GH_TAGGER=1 -> equivalente (compat semántica).

repo_has_workflow_file() {
    local wf_name="$1"
    # Asume que REPO_ROOT está seteado globalmente o por el script principal
    local root="${REPO_ROOT:-.}"
    local wf_dir="${root}/.github/workflows"
    [[ -f "${wf_dir}/${wf_name}.yaml" || -f "${wf_dir}/${wf_name}.yml" ]]
}

should_tag_locally_for_staging() {
    # Force local behavior if explicitly requested
    if [[ "${DEVTOOLS_FORCE_LOCAL_TAGS:-0}" == "1" || "${DEVTOOLS_DISABLE_GH_TAGGER:-0}" == "1" ]]; then
        return 0
    fi

    # If GitHub tagger exists, do NOT tag locally
    if repo_has_workflow_file "tag-rc-on-staging"; then
        return 1
    fi

    return 0
}

should_tag_locally_for_prod() {
    # Force local behavior if explicitly requested
    if [[ "${DEVTOOLS_FORCE_LOCAL_TAGS:-0}" == "1" || "${DEVTOOLS_DISABLE_GH_TAGGER:-0}" == "1" ]]; then
        return 0
    fi

    # If GitHub tagger exists, do NOT tag locally
    if repo_has_workflow_file "tag-final-on-main"; then
        return 1
    fi

    return 0
}