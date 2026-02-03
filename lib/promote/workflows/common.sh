#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/common.sh
#
# Este módulo contiene helpers comunes y utilidades de limpieza:
# - banner (fallback de compatibilidad)
# - resync_submodules_hard
# - cleanup_bot_branches
# - __read_repo_version
# - handle_branch_deletion
#
# Dependencias: utils.sh (para log_info, log_warn, ask_yes_no, etc.)

# ==============================================================================
# COMPAT: banner puede no estar cargado por el caller en algunos entornos.
# - Si no existe, definimos un fallback simple para evitar "command not found".
# ==============================================================================
if ! declare -F banner >/dev/null 2>&1; then
    banner() {
        echo
        echo "=================================================="
        echo " $*"
        echo "=================================================="
        echo
    }
fi

# ==============================================================================
# HELPERS: Gestión de repositorio y limpieza
# ==============================================================================

# [FIX] Solución de raíz: re-sincronizar submódulos para evitar estados dirty falsos
resync_submodules_hard() {
  git submodule sync --recursive >/dev/null 2>&1 || true
  git submodule update --init --recursive >/dev/null 2>&1 || true
}

__read_repo_version() {
    local vf
    vf="$(resolve_repo_version_file)"
    [[ -f "$vf" ]] || return 1
    cat "$vf" | tr -d '[:space:]'
}

# Helper para limpieza de ramas de release-please (NUEVO)
cleanup_bot_branches() {
    local mode="${1:-prompt}" # prompt | auto
    
    log_info "🧹 Buscando ramas de 'release-please' fusionadas para limpiar..."
    
    # Fetch para asegurar que la lista remota está fresca
    git fetch origin --prune

    # Buscamos ramas remotas que cumplan:
    # 1. Estén totalmente fusionadas en HEAD (staging/dev)
    # 2. Coincidan con el patrón del bot
    local branches_to_clean
    branches_to_clean="$(
        git branch -r --merged HEAD \
            | grep 'origin/release-please--' \
            | sed 's|origin/||' \
            | sed 's/^[[:space:]]*//' \
            | sed '/^$/d' \
            || true
        )"

    if [[ -z "$branches_to_clean" ]]; then
        log_info "✨ No hay ramas de bot pendientes de limpieza."
        return 0
    fi

    echo "🔍 Se encontraron las siguientes ramas de bot fusionadas:"
    echo "$branches_to_clean"
    echo

    # Modo automático (sin prompts): requerido para mantener el repo limpio al promover a staging
    if [[ "$mode" == "auto" ]]; then
        log_info "🧹 Limpieza automática activada (sin confirmación)."
        local IFS=$'\n'
        for branch in $branches_to_clean; do
            log_info "🔥 Eliminando remote: $branch"
            git push origin --delete "$branch" || log_warn "No se pudo borrar $branch (tal vez ya no existe)."
        done
        log_success "🧹 Limpieza completada."
        return 0
    fi

    if ask_yes_no "¿Eliminar estas ramas remotas para mantener la limpieza?"; then
        local IFS=$'\n'
        for branch in $branches_to_clean; do
            log_info "🔥 Eliminando remote: $branch"
            git push origin --delete "$branch" || log_warn "No se pudo borrar $branch (tal vez ya no existe)."
        done
        log_success "🧹 Limpieza completada."
    else
        log_warn "Omitiendo limpieza de ramas."
    fi
}

# ==============================================================================
# GESTIÓN DE BORRADO DE RAMAS POST-PROMOTE (NUEVO)
# ==============================================================================
handle_branch_deletion() {
    local branch="$1"
    local pr_number="${2:-}"
    local mode="${PROMOTE_DELETE_BRANCH:-}" # "true", "false" o "" (prompt)

    # 1. Seguridad: Nunca borrar ramas protegidas
    if is_protected_branch "$branch"; then
        log_warn "Rama '$branch' es protegida. No se borrará."
        return 0
    fi

    # 2. Si hay un modo predefinido (via flags --delete-branch / --keep-branch)
    if [[ "$mode" == "true" ]]; then
        log_info "🔥 Borrando rama local y remota: $branch"
        git push origin --delete "$branch" >/dev/null 2>&1 || true
        git branch -D "$branch" >/dev/null 2>&1 || true
        return 0
    fi

    if [[ "$mode" == "false" ]]; then
        log_info "💾 Manteniendo rama: $branch"
        return 0
    fi

    # 3. Modo Interactivo (Solo si hay TTY)
    if is_tty; then
        echo
        log_info "❓ ¿Qué quieres hacer con la rama origen '$branch'?"
        
        local choice
        if have_gum_ui; then
            choice=$(gum choose "Borrar local + remota" "Borrar solo local" "No borrar")
        else
            echo "1) Borrar local + remota"
            echo "2) Borrar solo local"
            echo "3) No borrar"
            read -r -p "Elige una opción [3]: " opt
            case "${opt:-3}" in
                1) choice="Borrar local + remota" ;;
                2) choice="Borrar solo local" ;;
                *) choice="No borrar" ;;
            esac
        fi

        case "$choice" in
            "Borrar local + remota")
                log_info "🔥 Borrando rama local y remota..."
                git push origin --delete "$branch" >/dev/null 2>&1 || true
                git branch -D "$branch" >/dev/null 2>&1 || true
                ;;
            "Borrar solo local")
                log_info "🔥 Borrando rama local..."
                git branch -D "$branch" >/dev/null 2>&1 || true
                ;;
            *)
                log_info "💾 Rama conservada."
                ;;
        esac
    else
        log_info "💾 Modo no-interactivo detectado. Manteniendo rama: $branch"
    fi
}