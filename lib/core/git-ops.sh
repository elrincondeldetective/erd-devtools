#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/core/git-ops.sh

# ==============================================================================
# 1. VALIDACIONES DE ESTADO (GUARDS)
# ==============================================================================

ensure_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        if command -v log_error >/dev/null; then
            log_error "No estás dentro de un repositorio Git."
        else
            echo "❌ No estás dentro de un repositorio Git." >&2
        fi
        exit 1
    }
}

ensure_clean_git() {
    # Si hay cambios sin commitear, fallamos.
    if [[ -n "$(git status --porcelain)" ]]; then
        if command -v log_error >/dev/null; then
            log_error "Tienes cambios sin guardar (dirty working tree)."
            log_warn "Haz commit o stash antes de continuar."
        else
            echo "❌ Tienes cambios sin guardar." >&2
        fi
        exit 1
    fi
}

# ==============================================================================
# 2. OPERACIONES DE SUBMÓDULOS
# ==============================================================================

sync_submodules() {
    if [[ -f ".gitmodules" ]]; then
        # Silencioso para no molestar en cada comando
        git submodule update --init --recursive >/dev/null 2>&1 || true
    fi
}

# ==============================================================================
# 3. OPERACIONES DE RAMAS Y REMOTOS
# ==============================================================================

branch_exists_local() {
    git show-ref --verify --quiet "refs/heads/$1"
}

# Actualiza una rama local con su contraparte remota
# Uso: update_branch_from_remote "dev" "origin" [no_pull_bool]
update_branch_from_remote() {
    local branch="$1"
    local remote="${2:-origin}"
    local no_pull="${3:-false}"

    # Usamos log_info si está disponible
    if command -v log_info >/dev/null; then
        log_info "🔄 Actualizando base '$branch'..."
    else
        echo "🔄 Actualizando base '$branch'..."
    fi
    
    # Fetch siempre es seguro
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    
    # Checkout (fallará si la rama local no existe y no es checkout -b)
    git checkout "$branch" >/dev/null 2>&1 || {
        if command -v log_error >/dev/null; then
            log_error "No pude hacer checkout a '$branch'. ¿Existe localmente?"
        else
            echo "❌ No pude hacer checkout a '$branch'." >&2
        fi
        return 1
    }
    
    # Importante en monorepos: sincronizar submódulos al cambiar de rama
    sync_submodules

    if [[ "$no_pull" != "true" ]]; then
        if ! git pull "$remote" "$branch"; then
            if command -v log_error >/dev/null; then
                log_error "Falló pull de '$remote/$branch'."
            else
                echo "❌ Falló pull de '$remote/$branch'." >&2
            fi
            return 1
        fi
    fi
}

# ==============================================================================
# 4. HELPERS DE CONFIGURACIÓN (Extraídos de setup-wizard)
# ==============================================================================

git_get() {
    # Obtiene un valor de config específico de un scope (local/global)
    # usage: git_get <local|global> <key>
    local scope="$1" key="$2"
    git config "--$scope" --get "$key" 2>/dev/null || true
}

git_get_all() {
    # Obtiene TODOS los valores de una key (útil para detectar duplicados)
    # usage: git_get_all <local|global> <key>
    local scope="$1" key="$2"
    git config "--$scope" --get-all "$key" 2>/dev/null || true
}

count_nonempty_lines() {
    # Helper interno para contar líneas
    awk 'NF{c++} END{print c+0}'
}

has_multiple_values() {
    # Retorna true (0) si una key tiene múltiples valores definidos en ese scope
    # usage: has_multiple_values <local|global> <key>
    local scope="$1" key="$2"
    local all
    all="$(git_get_all "$scope" "$key")"
    [ "$(printf "%s\n" "$all" | count_nonempty_lines)" -gt 1 ]
}

any_set() {
    # Retorna true (0) si AL MENOS UNO de los argumentos no está vacío
    # usage: any_set "$VAR1" "$VAR2" ...
    for v in "$@"; do
        if [ -n "$v" ]; then return 0; fi
    done
    return 1
}