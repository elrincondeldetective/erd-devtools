#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/dev-update.sh
#
# Reglas:
# - git promote feature/<rama> o git promote feature/dev-update
#   debe terminar en feature/dev-update (validador visual).
# - Debe hacer squash + push a origin/feature/dev-update para que remoto=verdad
#   y evitar divergencias que luego rompen el flujo.
#
# Dependencias esperadas (ya cargadas por el orquestador):
# - utils.sh (log_*, die, ask_yes_no, is_tty)
# - git-ops.sh (ensure_clean_git, update_branch_from_remote)
# - common.sh (resync_submodules_hard)

__ensure_branch_local_from_remote_or_create_and_push() {
    # Args: branch remote base_ref(optional)
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

    # No existe en remoto: crear local desde base_ref (o HEAD actual) y pushear para crear remoto
    if [[ -n "${base_ref:-}" ]]; then
        git checkout -b "$branch" "$base_ref" >/dev/null 2>&1 || return 1
    else
        git checkout -b "$branch" >/dev/null 2>&1 || return 1
    fi

    # Crear remoto y upstream (evita el error "ref remota no encontrada" luego)
    git push -u "$remote" "$branch" >/dev/null 2>&1 || return 1
    return 0
}

promote_dev_update_squash() {
    resync_submodules_hard
    ensure_clean_git

    local canonical="feature/dev-update"

    # Rama fuente:
    # - si viene argumento (ej: feature/x), lo usamos
    # - si no, tomamos la actual
    local source="${1:-}"
    if [[ -z "${source:-}" ]]; then
        source="$(git branch --show-current 2>/dev/null || echo "")"
    fi
    source="$(echo "$source" | tr -d '[:space:]')"
    [[ -n "${source:-}" ]] || die "No pude detectar rama fuente."

    # Normalización: si el usuario llama `git promote feature/dev-update`, eso debe significar:
    # "consolidar la rama actual dentro de feature/dev-update"
    # (o no-op si ya está en feature/dev-update).
    if [[ "$source" == "$canonical" ]]; then
        source="$(git branch --show-current 2>/dev/null || echo "$canonical")"
    fi

    # Guardar HEAD fuente por seguridad
    local source_sha
    source_sha="$(git rev-parse "$source" 2>/dev/null || true)"
    [[ -n "${source_sha:-}" ]] || die "No pude resolver SHA de la rama fuente: $source"

    echo
    log_info "🧱 INTEGRACIÓN APLASTANTE (SQUASH) HACIA '${canonical}'"
    echo
    log_info "    Fuente : ${source} @${source_sha:0:7}"
    log_info "    Destino: ${canonical}"
    echo

    # Si la fuente no existe localmente, abortamos (evita usar refs raras)
    if ! git show-ref --verify --quiet "refs/heads/${source}"; then
        die "La rama fuente '${source}' no existe localmente. Haz checkout de esa rama y reintenta."
    fi

    # Preparar feature/dev-update:
    # - si existe en remoto, crear tracking
    # - si no existe, crearla desde el SHA de la fuente y pushearla (para que ya exista remoto)
    __ensure_branch_local_from_remote_or_create_and_push "$canonical" "origin" "$source_sha" || {
        die "No pude preparar '${canonical}' (local/remoto)."
    }

    # Ya estamos en canonical (por el helper). Ahora la ponemos al día desde remoto.
    # Si el remoto no existía, ya lo creamos con push -u, así que este update ya no rompe.
    update_branch_from_remote "$canonical" "origin" || {
        die "No pude actualizar '${canonical}' desde origin."
    }

    # Si la fuente ES canonical, no hay nada que squashear. Igual aseguramos push y terminamos ahí.
    if [[ "$source" == "$canonical" ]]; then
        log_info "Ya estás en '${canonical}'. Asegurando push para paridad..."
        git push origin "$canonical" >/dev/null 2>&1 || true
        log_success "✅ OK. Te quedas en: ${canonical}"
        return 0
    fi

    local before
    before="$(git rev-parse HEAD 2>/dev/null || true)"

    log_info "🧨 Squash merge: ${source} -> ${canonical}"
    if ! git merge --squash -X theirs "$source"; then
        log_error "Conflictos durante squash merge."
        git merge --abort >/dev/null 2>&1 || true
        die "Resuelve conflictos manualmente y reintenta."
    fi

    # NOTA: Aunque no haya cambios (diff --quiet), igual queremos borrar la rama feature
    # si ya fue integrada previamente o si fue vacía.
    local changes_applied=0
    if git diff --cached --quiet; then
        log_warn "No hay cambios para aplicar (no-op). Asegurando push..."
        git push origin "$canonical" >/dev/null 2>&1 || true
        log_success "✅ OK. Te quedas en: ${canonical}"
    else
        changes_applied=1
        local title body
        title="chore(dev-update): squash ${source}"
        body="$(
            git log --pretty=format:'- %s (%h)' "${before}..${source}" 2>/dev/null | head -n 60 || true
        )"
        [[ -n "${body:-}" ]] || body="(no commit list available)"

        git commit -m "$title" -m "$body"

        log_info "📡 Push a origin/${canonical}..."
        if ! git push origin "$canonical"; then
            # Retry seguro (sin force): refrescamos destino y re-squash
            log_warn "Push rechazado. Reintentando con destino actualizado..."
            git fetch origin "$canonical" >/dev/null 2>&1 || true
            git reset --hard "origin/${canonical}" >/dev/null 2>&1 || true

            if ! git merge --squash -X theirs "$source"; then
                log_error "Conflictos en reintento."
                git merge --abort >/dev/null 2>&1 || true
                die "Reintento falló. Resuelve manualmente."
            fi
            if ! git diff --cached --quiet; then
                git commit -m "$title" -m "$body"
            fi
            git push origin "$canonical" || die "No pude pushear ${canonical} después del reintento."
        fi
        log_success "✅ ${canonical} actualizado y pusheado."
    fi
    
    log_success "✅ Te quedas en: ${canonical}"

    # ==============================================================================
    # NUEVO: Limpieza automática de la rama feature (Borrado seguro).
    # ==============================================================================
    local protected_branches=("main" "dev" "staging" "feature/dev-update")
    local is_protected=0

    for branch in "${protected_branches[@]}"; do
        if [[ "$source" == "$branch" ]]; then
            is_protected=1
            break
        fi
    done

    if [[ "$is_protected" == "0" ]]; then
        log_info "🧹 Limpiando rama fuente ya integrada: ${source}"
        # Usamos -D (force) porque el squash no deja rastro de merge en la historia de la rama source
        if git branch -D "$source" >/dev/null 2>&1; then
            log_success "🗑️  Rama '${source}' eliminada localmente."
        else
            log_warn "⚠️  No se pudo borrar '${source}' automáticamente (quizás no existe o permisos)."
        fi
    else
        log_info "🛡️  La rama fuente '${source}' es protegida. Se mantiene intacta."
    fi

    return 0
}