#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/core/git-ops.sh

# ==============================================================================
# 0. HELPERS DE CONFIGURACIÓN
# ==============================================================================

# Obtiene un valor de configuración de git de forma segura (sin error si falta)
# Uso: git_get <local|global|system> <key>
git_get() {
    local scope="$1"
    local key="$2"
    git config --"$scope" --get "$key" 2>/dev/null || true
}

# Verifica si una clave tiene múltiples valores definidos en un scope
# Uso: has_multiple_values <local|global|system> <key>
# Retorna: 0 (true) si hay >1 valor, 1 (false) si hay 0 o 1.
has_multiple_values() {
    local scope="$1"
    local key="$2"
    local count
    count="$(git config --"$scope" --get-all "$key" 2>/dev/null | awk 'END{print NR}')"
    if [ "$count" -gt 1 ]; then return 0; else return 1; fi
}

# Verifica si al menos uno de los argumentos pasados no está vacío
# Uso: any_set "$var1" "$var2" ...
# Retorna: 0 (true) si encuentra algo, 1 (false) si todo está vacío.
any_set() {
    for var in "$@"; do
        if [ -n "$var" ]; then return 0; fi
    done
    return 1
}

# ==============================================================================
# 1. VALIDACIONES DE ESTADO (GUARDS)
# ==============================================================================

# Versión segura que solo retorna error (no mata el script)
ensure_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
    return $?
}

# Versión estricta para scripts que deben abortar si no hay repo
ensure_repo_or_die() {
    ensure_repo || {
        echo "❌ No estás dentro de un repositorio Git." >&2
        exit 1
    }
}

ensure_clean_git() {
    # Si hay cambios sin commitear, fallamos.
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "❌ Tienes cambios sin guardar (dirty working tree)." >&2
        exit 1
    fi
}

# ==============================================================================
# 2. DETECCIÓN DE RAÍZ (MONOREPO VS SUBMODULE)
# ==============================================================================

# Detecta la raíz real de trabajo:
# - Si es un submódulo dentro de un superproyecto, devuelve el superproyecto.
# - Si es un repo normal, devuelve el toplevel.
# - Si no hay repo, devuelve el directorio actual (pwd).
detect_workspace_root() {
    local super
    super="$(git rev-parse --show-superproject-working-tree 2>/dev/null || echo "")"
    if [[ -n "$super" ]]; then
        echo "$super"
    else
        git rev-parse --show-toplevel 2>/dev/null || pwd
    fi
}

# ==============================================================================
# 3. OPERACIONES DE SUBMÓDULOS
# ==============================================================================

sync_submodules() {
    if [[ -f ".gitmodules" ]]; then
        # Silencioso para no molestar en cada comando
        git submodule update --init --recursive >/dev/null 2>&1 || true
    fi
}

# ==============================================================================
# 4. OPERACIONES DE RAMAS Y REMOTOS
# ==============================================================================

branch_exists_local() {
    git show-ref --verify --quiet "refs/heads/$1"
}

# Actualiza una rama local con su contraparte remota
update_branch_from_remote() {
    local branch="$1"
    local remote="${2:-origin}"
    local no_pull="${3:-false}"

    echo "🔄 Actualizando base '$branch'..."
    
    # Fetch siempre es seguro
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    
    # Checkout (fallará si la rama local no existe)
    git checkout "$branch" >/dev/null 2>&1 || {
        echo "❌ No pude hacer checkout a '$branch'. ¿Existe localmente?" >&2
        return 1
    }
    
    sync_submodules

    if [[ "$no_pull" != "true" ]]; then
        if ! git pull "$remote" "$branch"; then
            echo "❌ Falló pull de '$remote/$branch'." >&2
            return 1
        fi
    fi
}

# ==============================================================================
# 5. DIAGNÓSTICO DE IDENTIDAD
# ==============================================================================

print_git_identity_state() {
    local scope="$1" # local o global
    local name email
    name="$(git config --"$scope" --get-all user.name 2>/dev/null || true)"
    email="$(git config --"$scope" --get-all user.email 2>/dev/null || true)"

    echo "--- Git Identity ($scope) ---"
    if [ -z "$name" ] && [ -z "$email" ]; then
        echo "   (vacío)"
    else
        echo "   user.name: $name"
        echo "   user.email: $email"
    fi
}
