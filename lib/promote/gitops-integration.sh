#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/gitops-integration.sh
#
# Este módulo maneja la lógica de "Fase 4": Conectar Golden SHA con GitOps.
# Se encarga de inferir qué servicios cambiaron y disparar workflows en el superrepo.

# ==============================================================================
# FASE 4: CONECTAR GOLDEN SHA CON GITOPS (update-gitops-manifests)
# ==============================================================================
# Objetivo:
# - Disparar el workflow del superrepo que actualiza manifests a image:sha-<short>.
# - Usar el GOLDEN_SHA como entrada `sha`.
# - Inferir `services` desde ecosystem/services.yaml + paths cambiados.

# Resuelve la raíz del repositorio de GitOps (Superrepo)
resolve_gitops_root() {
    # 1) Override explícito
    if [[ -n "${DEVTOOLS_GITOPS_ROOT:-}" && -d "${DEVTOOLS_GITOPS_ROOT}" ]]; then
        echo "${DEVTOOLS_GITOPS_ROOT}"
        return 0
    fi

    # 2) Si estamos en un superrepo, usamos WORKSPACE_ROOT (si existe y tiene workflow)
    if [[ -n "${WORKSPACE_ROOT:-}" && -d "${WORKSPACE_ROOT}" ]]; then
        if [[ -f "${WORKSPACE_ROOT}/.github/workflows/update-gitops-manifests.yaml" || -f "${WORKSPACE_ROOT}/.github/workflows/update-gitops-manifests.yml" ]]; then
            echo "${WORKSPACE_ROOT}"
            return 0
        fi
    fi

    # 3) Usar el repo actual si tiene el workflow
    if [[ -f "${REPO_ROOT}/.github/workflows/update-gitops-manifests.yaml" || -f "${REPO_ROOT}/.github/workflows/update-gitops-manifests.yml" ]]; then
        echo "${REPO_ROOT}"
        return 0
    fi

    # 4) Fallback (repo actual)
    echo "${REPO_ROOT}"
}

gitops_workflow_name() {
    echo "${DEVTOOLS_GITOPS_WORKFLOW:-update-gitops-manifests.yaml}"
}

gitops_has_workflow() {
    local root
    root="$(resolve_gitops_root)"
    local wf
    wf="$(gitops_workflow_name)"
    [[ -f "${root}/.github/workflows/${wf}" ]] || [[ -f "${root}/.github/workflows/${wf%.yaml}.yml" ]] || [[ -f "${root}/.github/workflows/${wf%.yml}.yaml" ]]
}

gitops_services_yaml_path() {
    local root
    root="$(resolve_gitops_root)"
    echo "${root}/ecosystem/services.yaml"
}

parse_services_yaml_to_paths() {
    # Output: one service path per line
    local f="$1"
    [[ -f "$f" ]] || return 1

    # Parser simple (sin yq): extrae `path:` dentro de cada bloque de servicio
    awk '
      $1=="-" && $2=="id:" {seen=1; next}
      seen==1 && $1=="path:" {print $2; seen=0; next}
    ' "$f"
}

json_array_from_lines() {
    # Lee líneas por stdin y devuelve JSON array compacto
    # Ej: a\nb -> ["a","b"]
    local first=1
    echo -n '['
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # escape mínimo de backslash y doble comilla
        line="${line//\\/\\\\}"
        line="${line//\"/\\\"}"
        if [[ "$first" -eq 1 ]]; then
            first=0
        else
            echo -n ','
        fi
        echo -n "\"$line\""
    done
    echo -n ']'
}

infer_gitops_services_json_from_changed_paths() {
    # Args:
    #   $1 = multiline changed paths (optional). If empty, se calcula con HEAD~1..HEAD.
    local changed_paths="${1:-}"

    # Overrides directos
    if [[ -n "${DEVTOOLS_GITOPS_SERVICES_JSON:-}" ]]; then
        echo "${DEVTOOLS_GITOPS_SERVICES_JSON}"
        return 0
    fi

    if [[ -n "${DEVTOOLS_GITOPS_SERVICES:-}" ]]; then
        # CSV -> JSON
        echo "${DEVTOOLS_GITOPS_SERVICES}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | json_array_from_lines
        return 0
    fi

    local services_file
    services_file="$(gitops_services_yaml_path)"
    if [[ ! -f "$services_file" ]]; then
        echo "[]"
        return 0
    fi

    # Si no nos pasan changed paths, intentamos con el último commit del branch actual
    if [[ -z "${changed_paths:-}" ]]; then
        changed_paths="$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)"
    fi

    # Si sigue vacío, no inferimos nada
    if [[ -z "${changed_paths:-}" ]]; then
        echo "[]"
        return 0
    fi

    # Leer todos los paths de servicios desde el registry
    local service_paths
    service_paths="$(parse_services_yaml_to_paths "$services_file" 2>/dev/null || true)"

    if [[ -z "${service_paths:-}" ]]; then
        echo "[]"
        return 0
    fi

    # Match por prefijo (ideal para submódulos): si changed_path es prefijo de service_path o viceversa.
    # Ej: changed "apps/pmbok" matchea "apps/pmbok/backend".
    local matched=()
    local sp cp

    while IFS= read -r sp; do
        [[ -z "$sp" ]] && continue

        while IFS= read -r cp; do
            [[ -z "$cp" ]] && continue

            if [[ "$sp" == "$cp" || "$sp" == "$cp/"* || "$cp" == "$sp" || "$cp" == "$sp/"* ]]; then
                matched+=("$sp")
                break
            fi
        done <<< "$changed_paths"
    done <<< "$service_paths"

    # Dedup + output JSON
    if [[ "${#matched[@]}" -eq 0 ]]; then
        echo "[]"
        return 0
    fi

    printf "%s\n" "${matched[@]}" | awk '!seen[$0]++' | json_array_from_lines
}

trigger_gitops_update_workflow() {
    local sha_full="$1"
    local target_branch="$2"
    local services_json="$3"

    local root
    root="$(resolve_gitops_root)"

    local wf
    wf="$(gitops_workflow_name)"

    if [[ -z "${sha_full:-}" || -z "${target_branch:-}" ]]; then
        return 1
    fi

    if [[ -z "${services_json:-}" ]]; then
        services_json="[]"
    fi

    if [[ "$services_json" == "[]" ]]; then
        log_warn "🧩 GitOps: no se detectaron servicios a actualizar (services=[]). Omitiendo."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_warn "🧩 GitOps: 'gh' no disponible. Omitiendo disparo de workflow."
        return 0
    fi

    if ! gitops_has_workflow; then
        log_warn "🧩 GitOps: workflow '${wf}' no encontrado en $(resolve_gitops_root). Omitiendo."
        return 0
    fi

    local short_sha="${sha_full:0:7}"

    echo
    log_info "🧩 GitOps: disparando workflow '${wf}'"
    echo "   root        : $root"
    echo "   target_branch: $target_branch"
    echo "   sha         : $sha_full (sha-$short_sha)"
    echo "   services    : $services_json"
    echo

    (
        cd "$root"
        GH_PAGER=cat gh workflow run "$wf" \
            -f "sha=$sha_full" \
            -f "services=$services_json" \
            -f "target_branch=$target_branch"
    )

    log_success "🧩 GitOps: workflow enviado. (Revisa Actions para el resultado)"
    return 0
}

maybe_trigger_gitops_update() {
    # Args:
    #   $1 = target_branch (dev/staging/main)
    #   $2 = sha_full
    #   $3 = optional changed paths multiline
    local target_branch="$1"
    local sha_full="$2"
    local changed_paths="${3:-}"

    # No hay SHA => no hacemos nada
    [[ -n "${sha_full:-}" ]] || return 0

    # Por defecto: preguntar solo si TTY. Auto: DEVTOOLS_GITOPS_AUTO_UPDATE=1.
    local auto="${DEVTOOLS_GITOPS_AUTO_UPDATE:-0}"

    local short_sha="${sha_full:0:7}"
    local services_json
    services_json="$(infer_gitops_services_json_from_changed_paths "$changed_paths")"

    if [[ "$services_json" == "[]" ]]; then
        return 0
    fi

    if [[ "$auto" == "1" ]]; then
        trigger_gitops_update_workflow "$sha_full" "$target_branch" "$services_json"
        return $?
    fi

    if is_tty; then
        if ask_yes_no "🧩 ¿Actualizar GitOps en '${target_branch}' a sha-${short_sha} para los servicios detectados?"; then
            trigger_gitops_update_workflow "$sha_full" "$target_branch" "$services_json"
        else
            log_info "🧩 GitOps: omitido por el usuario."
        fi
    fi

    return 0
}