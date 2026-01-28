#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/dev-update.sh
#
# Este módulo maneja la estrategia de "Squash Merge" hacia la rama canónica de updates.
# Función principal: promote_dev_update_squash
#
# Dependencias: utils.sh, git-ops.sh (cargadas por el orquestador)

# ==============================================================================
# 2. SQUASH MERGE HACIA feature/dev-update
# ==============================================================================
promote_dev_update_squash() {
    local canonical_branch="feature/dev-update"
    local current_branch
    current_branch="$(git branch --show-current 2>/dev/null || true)"

    local source_branch="${1:-$current_branch}"

    echo
    log_info "🧱 INTEGRACIÓN APLASTANTE (SQUASH) HACIA '$canonical_branch'"

    # Si estamos en dev-update y no pasaron rama, pedimos una
    if [[ -z "${source_branch:-}" || "$source_branch" == "$canonical_branch" ]]; then
        if [[ "$current_branch" == "$canonical_branch" ]]; then
            echo
            log_info "📌 Estás en '$canonical_branch'."
            read -r -p "Rama fuente a aplastar dentro de '$canonical_branch': " source_branch
        fi
    fi

    if [[ -z "${source_branch:-}" || "$source_branch" == "$canonical_branch" ]]; then
        log_error "Debes indicar una rama fuente distinta a '$canonical_branch'."
        exit 1
    fi

    ensure_clean_git

    # Traer refs frescas
    git fetch origin --prune

    # Resolver ref de la rama fuente (local o remota)
    local source_ref=""
    if git show-ref --verify --quiet "refs/heads/${source_branch}"; then
        source_ref="${source_branch}"
    elif git show-ref --verify --quiet "refs/remotes/origin/${source_branch}"; then
        source_ref="origin/${source_branch}"
    else
        log_warn "No encuentro '${source_branch}' local/remoto. Intentando fetch explícito..."
        git fetch origin "${source_branch}" || true
        if git show-ref --verify --quiet "refs/remotes/origin/${source_branch}"; then
            source_ref="origin/${source_branch}"
        elif git show-ref --verify --quiet "refs/heads/${source_branch}"; then
            source_ref="${source_branch}"
        fi
    fi

    if [[ -z "${source_ref:-}" ]]; then
        log_error "No se encontró la rama fuente '${source_branch}' (ni local ni en origin)."
        exit 1
    fi

    local source_sha
    source_sha="$(git rev-parse --short "$source_ref" 2>/dev/null || true)"

    echo
    log_info "   Fuente:  $source_ref @${source_sha:-unknown}"
    log_info "   Destino: $canonical_branch"
    echo

    # Ir a feature/dev-update y actualizarla
    update_branch_from_remote "$canonical_branch"

    # Aplicar squash
    log_info "🧲 Aplicando squash merge..."
    if ! git merge --squash "$source_ref"; then
        log_error "❌ Squash merge falló (posibles conflictos). Abortando para no dejar estado parcial..."
        git merge --abort || true
        log_info "🏠 Quedando en '$canonical_branch'..."
        git checkout "$canonical_branch"
        exit 1
    fi

    # Si no hay cambios staged, probablemente ya estaba integrado
    if git diff --cached --quiet; then
        log_warn "ℹ️ No hay cambios para commitear (posible ya integrado)."
        log_info "🏠 Quedando en '$canonical_branch'..."
        git checkout "$canonical_branch"
        exit 0
    fi

    echo
    log_info "📝 Preparando commit (1 solo commit por squash)..."
    local default_msg="chore(dev-update): integrar cambios de '${source_branch}' (squash)"
    local msg=""

    echo "Mensaje sugerido:"
    echo "  $default_msg"
    read -r -p "Mensaje de commit (Enter para usar sugerido): " msg
    msg="${msg:-$default_msg}"

    # IMPORTANTE: NO pasar el mensaje por -m con comillas dobles (backticks podrían ejecutarse).
    # Usamos stdin con -F - para evitar expansión/comando sustitución.
    printf '%s\n' "$msg" | git commit -F -

    log_success "✅ Commit squash creado en '$canonical_branch'."

    # Push del destino
    log_info "🚀 Pusheando '$canonical_branch' a origin..."
    git push origin "$canonical_branch"
    log_success "✅ '$canonical_branch' sincronizada en origin."

    # Opción de borrar la rama fuente (local + remota)
    echo
    if ask_yes_no "¿Quieres ELIMINAR la rama fuente '${source_branch}' (local y remota) ahora?"; then
        # Nunca borrar la canónica por error
        if [[ "$source_branch" == "$canonical_branch" ]]; then
            log_warn "🛑 Rama fuente es la canónica. No se elimina."
        else
            # Borrar local (squash NO cuenta como 'merged', así que usamos -D)
            if git show-ref --verify --quiet "refs/heads/${source_branch}"; then
                log_info "🗑️  Eliminando rama local '${source_branch}'..."
                git branch -D "$source_branch" || true
            fi

            # Borrar remota
            if git show-ref --verify --quiet "refs/remotes/origin/${source_branch}"; then
                log_info "🗑️  Eliminando rama remota 'origin/${source_branch}'..."
                git push origin --delete "$source_branch" || true
            fi

            log_success "🧹 Limpieza completada para '${source_branch}'."
        fi
    else
        log_info "👌 Conservando rama fuente '${source_branch}'."
    fi

    # Asegurar que terminamos en dev-update
    log_info "🏠 Quedando en '$canonical_branch'..."
    git checkout "$canonical_branch"

    echo
    log_success "🎉 Squash merge completado. Estás en '$canonical_branch'."
}