#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/dev-update.sh
#
# NUEVO: modo SHA exacto (overwrite) hacia feature/dev-update
# Reglas:
# - git promote feature/<rama> o git promote feature/dev-update
#   debe terminar en feature/dev-update (validador visual).
# - Debe sincronizar feature/dev-update con el SHA EXACTO de la rama fuente.
#   (overwrite/force-with-lease) para preservar SHA y evitar divergencias por squash.
#
# Dependencias esperadas (ya cargadas por el orquestador):
# - utils.sh (log_*, die, ask_yes_no, is_tty)
# - git-ops.sh (ensure_clean_git, update_branch_from_remote)
# - common.sh (resync_submodules_hard)

__ensure_target_branch_exists_or_create() {
    local branch="$1"
    local remote="${2:-origin}"
    local base_ref="${3:-}"

    git fetch "$remote" --prune >/dev/null 2>&1 || true

    # Si ya existe local, ok
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        return 0
    fi

    # Si existe en remoto, crear tracking local
    if git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
        git checkout -b "$branch" "${remote}/${branch}" >/dev/null 2>&1 || return 1
        return 0
    fi

    # No existe en remoto: crear local desde base_ref y pushear para crear remoto
    if [[ -n "${base_ref:-}" ]]; then
        git checkout -b "$branch" "$base_ref" >/dev/null 2>&1 || return 1
    else
        git checkout -b "$branch" >/dev/null 2>&1 || return 1
    fi

    # Crear remoto y upstream (evita el error "ref remota no encontrada" luego)
    git push -u "$remote" "$branch" >/dev/null 2>&1 || return 1
    return 0
}

promote_dev_update_apply() {
    resync_submodules_hard
    ensure_clean_git

    local canonical="dev-update"

    # Rama fuente:
    # - si viene argumento (ej: feature/x), lo usamos
    # - si no, tomamos la actual
    local source="${1:-}"
    if [[ -z "${source:-}" ]]; then
        source="$(git branch --show-current 2>/dev/null || echo "")"
    fi
    source="$(echo "$source" | tr -d '[:space:]')"
    [[ -n "${source:-}" ]] || die "No pude detectar rama fuente."

    # Resolver SHA fuente (local o remoto)
    git fetch origin "$source" >/dev/null 2>&1 || true
    local source_ref="$source"
    if ! git show-ref --verify --quiet "refs/heads/${source}"; then
        if git show-ref --verify --quiet "refs/remotes/origin/${source}"; then
            source_ref="origin/${source}"
        else
            die "La rama fuente '${source}' no existe local ni en origin."
        fi
    fi

    local source_sha
    source_sha="$(git rev-parse "$source_ref" 2>/dev/null || true)"
    [[ -n "${source_sha:-}" ]] || die "No pude resolver SHA de la rama fuente: $source"

    echo
    log_info "🧩 PROMOCIÓN HACIA '${canonical}' (sin squash)"
    echo
    log_info "    Fuente : ${source} @${source_sha:0:7}"
    log_info "    Destino: ${canonical}"
    echo

    # Asegurar que dev-update exista (si no existe en origin, crearlo desde la fuente)
    __ensure_target_branch_exists_or_create "$canonical" "origin" "$source_sha" || die "No pude preparar '${canonical}'."

    # Estrategia (Menú Universal): si no viene seteada, pedirla aquí también.
    local strategy="${DEVTOOLS_PROMOTE_STRATEGY:-}"
    if [[ -z "${strategy:-}" ]]; then
        strategy="$(promote_choose_strategy_or_die)"
        export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
    fi

    local final_sha=""
    local rc=0
    while true; do
        final_sha="$(update_branch_to_sha_with_strategy "$canonical" "$source_sha" "origin" "$strategy")"
        rc=$?
        if [[ "$rc" -eq 3 ]]; then
            log_warn "⚠️ Fast-Forward NO es posible. Elige otra estrategia."
            strategy="$(promote_choose_strategy_or_die)"
            export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
            continue
        fi
        [[ "$rc" -eq 0 ]] || die "No pude promover hacia '${canonical}' (strategy=${strategy}, rc=${rc})."
        break
    done

    log_success "✅ Promoción OK: ${source} -> ${canonical} (strategy=${strategy}, sha=${final_sha:0:7})"
    return 0
}

# ==============================================================================
# NUEVO: FORCE SYNC (SHA exacto) hacia feature/dev-update
# - En vez de squash merge, hace overwrite para que el SHA sea exactamente el mismo.
# ==============================================================================
promote_dev_update_force_sync() {
    resync_submodules_hard
    ensure_clean_git

    local canonical="feature/dev-update"

    # Rama fuente:
    local source="${1:-}"
    if [[ -z "${source:-}" ]]; then
        source="$(git branch --show-current 2>/dev/null || echo "")"
    fi
    source="$(echo "$source" | tr -d '[:space:]')"
    [[ -n "${source:-}" ]] || die "No pude detectar rama fuente."

    # Si la fuente no existe localmente, abortamos (evita usar refs raras)
    if ! git show-ref --verify --quiet "refs/heads/${source}"; then
        die "La rama fuente '${source}' no existe localmente. Haz checkout de esa rama y reintenta."
    fi

    local source_sha
    source_sha="$(git rev-parse "$source" 2>/dev/null || true)"
    [[ -n "${source_sha:-}" ]] || die "No pude resolver SHA de la rama fuente: $source"

    echo
    log_info "🧨 SYNC SHA EXACTO HACIA '${canonical}'"
    log_info "    Fuente : ${source} @${source_sha:0:7}"
    log_info "    Destino: ${canonical} (overwrite)"
    echo

    # Asegurar canonical exista local/remoto (si no existe remoto, créalo desde source_sha)
    __ensure_branch_local_from_remote_or_create_and_push "$canonical" "origin" "$source_sha" || {
        die "No pude preparar '${canonical}' (local/remoto)."
    }

    # Overwrite: canonical = source_sha (mismo SHA)
    log_warn "🧨 Overwrite: '${canonical}' -> ${source_sha:0:7} (desde '${source}')"
    force_update_branch_to_sha "$canonical" "$source_sha" "origin" || die "No pude sobrescribir '${canonical}'."

    git checkout "$canonical" >/dev/null 2>&1 || true
    log_success "✅ ${canonical} actualizado (SHA exacto) y pusheado."
    log_success "✅ Te quedas en: ${canonical}"

    maybe_delete_source_branch "$source"
    return 0
}
