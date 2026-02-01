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
# 2.1 FASE 3 (NUEVO): HELPERS PARA GOLDEN SHA / RAMAS TRACKING
# ==============================================================================
# Objetivo:
# - Poder sincronizar ramas locales con su remoto aunque NO existan localmente.
# - Evitar estados "a medias" cuando el SHA golden se toma de origin/<branch>.
branch_exists_remote() {
    local branch="$1"
    local remote="${2:-origin}"
    git show-ref --verify --quiet "refs/remotes/${remote}/${branch}"
}

ensure_local_branch_tracks_remote() {
    local branch="$1"
    local remote="${2:-origin}"

    # Siempre traer refs frescas (silencioso)
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true

    # Si ya existe localmente, OK
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        return 0
    fi

    # Si existe en remoto, creamos local tracking
    if branch_exists_remote "$branch" "$remote"; then
        git checkout -b "$branch" "${remote}/${branch}" >/dev/null 2>&1 || return 1
        return 0
    fi

    return 1
}

# Sincroniza la rama local para que coincida EXACTAMENTE con el remoto (golden truth)
sync_branch_hard_to_remote() {
    local branch="$1"
    local remote="${2:-origin}"

    ensure_clean_git

    ensure_local_branch_tracks_remote "$branch" "$remote" || {
        echo "❌ No pude preparar la rama '$branch' desde '$remote/$branch'." >&2
        return 1
    }

    git checkout "$branch" >/dev/null 2>&1 || return 1

    # Aseguramos refs frescas
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true

    # Hard reset a remoto (verdad canónica)
    git reset --hard "${remote}/${branch}" >/dev/null 2>&1 || true
    return 0
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
# 4.1 PUSH DESTRUCTIVO (force / force-with-lease)
# ==============================================================================

# DEVTOOLS_FORCE_PUSH_MODE:
# - with-lease (default): git push --force-with-lease
# - force             : git push --force
push_branch_force() {
    local branch="$1"
    local remote="${2:-origin}"
    local mode="${DEVTOOLS_FORCE_PUSH_MODE:-with-lease}"

    if [[ "$mode" == "force" ]]; then
        git push "$remote" "$branch" --force
    else
        git push "$remote" "$branch" --force-with-lease
    fi
}

# Checkout <branch>, reset --hard <sha>, y force-push a <remote>/<branch>
force_update_branch_to_sha() {
    local branch="$1"
    local sha="$2"
    local remote="${3:-origin}"

    [[ -n "${branch:-}" && -n "${sha:-}" ]] || return 2
    ensure_clean_git

    ensure_local_branch_tracks_remote "$branch" "$remote" || {
        echo "❌ No pude preparar la rama '$branch' desde '$remote/$branch'." >&2
        return 1
    }

    git checkout "$branch" >/dev/null 2>&1 || return 1
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    git reset --hard "$sha" >/dev/null 2>&1 || return 1
    push_branch_force "$branch" "$remote" || return 1
    return 0
}

# ==============================================================================
# 4.2 PROMOCIÓN NO-DESTRUCTIVA POR ESTRATEGIA (FF / MERGE / THEIRS / FORCE)
# ==============================================================================

__git_is_ancestor() {
    local a="$1" b="$2"
    git merge-base --is-ancestor "$a" "$b" >/dev/null 2>&1
}

# Actualiza <branch> hacia <source_sha> aplicando estrategia.
# Echo: SHA final en remoto (origin/<branch>) si OK.
#
# Estrategias:
# - ff-only      : solo fast-forward (si no se puede, rc=3)
# - merge        : merge --no-ff (preserva historial, crea commit)
# - merge-theirs : merge --no-ff -X theirs (tu versión gana, preserva historial)
# - force        : reset --hard + push --force-with-lease (destructivo)
update_branch_to_sha_with_strategy() {
    local branch="$1"
    local source_sha="$2"
    local remote="${3:-origin}"
    local strategy="${4:-ff-only}"

    [[ -n "${branch:-}" && -n "${source_sha:-}" ]] || return 2
    ensure_clean_git

    # refs frescas
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    local old_remote_sha=""
    old_remote_sha="$(git rev-parse "${remote}/${branch}" 2>/dev/null || true)"

    case "$strategy" in
        force)
            force_update_branch_to_sha "$branch" "$source_sha" "$remote" || return 1
            git fetch "$remote" "$branch" >/dev/null 2>&1 || true
            echo "$(git rev-parse "${remote}/${branch}" 2>/dev/null || true)"
            return 0
            ;;
        ff-only|merge|merge-theirs)
            ;;
        *)
            echo "❌ Estrategia inválida: $strategy" >&2
            return 2
            ;;
    esac

    # Asegurar tracking local
    ensure_local_branch_tracks_remote "$branch" "$remote" || {
        echo "❌ No pude preparar la rama '$branch' desde '$remote/$branch'." >&2
        return 1
    }

    # Base canónica: local == remote antes de actuar
    git checkout "$branch" >/dev/null 2>&1 || return 1
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    git reset --hard "${remote}/${branch}" >/dev/null 2>&1 || true

    if [[ "$strategy" == "ff-only" ]]; then
        # Solo FF si destino es ancestro del source
        local base_sha
        base_sha="$(git rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "${base_sha:-}" ]] && ! __git_is_ancestor "$base_sha" "$source_sha"; then
            echo "⚠️  Fast-Forward NO es posible: ${remote}/${branch} no es ancestro de source." >&2
            return 3
        fi
        git merge --ff-only "$source_sha" >/dev/null 2>&1 || return 1
    elif [[ "$strategy" == "merge" ]]; then
        git merge --no-ff --no-edit "$source_sha" || return 1
    elif [[ "$strategy" == "merge-theirs" ]]; then
        git merge --no-ff --no-edit -X theirs "$source_sha" || return 1
    fi

    # Push NO destructivo
    git push "$remote" "$branch" || return 1

    # Verificación post-push
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    local new_remote_sha=""
    new_remote_sha="$(git rev-parse "${remote}/${branch}" 2>/dev/null || true)"

    # Garantías mínimas:
    # - merge/ff deben contener source_sha
    # - merge debe preservar old_remote_sha (si existía)
    if [[ -n "${new_remote_sha:-}" ]]; then
        __git_is_ancestor "$source_sha" "$new_remote_sha" || {
            echo "❌ Post-check falló: source_sha no quedó contenido en ${remote}/${branch}." >&2
            return 1
        }
        if [[ "$strategy" != "ff-only" && -n "${old_remote_sha:-}" ]]; then
            __git_is_ancestor "$old_remote_sha" "$new_remote_sha" || {
                echo "❌ Post-check falló: historial previo no quedó preservado en merge." >&2
                return 1
            }
        fi
    fi

    echo "$new_remote_sha"
    return 0
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

# ==============================================================================
# 6. SEGURIDAD DE RAMAS (BRANCH SAFETY / LANDING)
# ==============================================================================

# Restaura la rama original al finalizar el script.
# Si la rama fue borrada (ej. por squash merge), la recrea desde el punto actual (o dev/main según aplique)
# y notifica al usuario.
git_restore_branch_safely() {
    local target_branch="$1"
    
    # Si no hay target o es detached, no hacemos nada crítico
    if [[ -z "$target_branch" || "$target_branch" == "(detached)" ]]; then
        return 0
    fi

    local current
    current="$(git branch --show-current 2>/dev/null || echo "")"

    # Si ya estamos ahí, listo.
    if [[ "$current" == "$target_branch" ]]; then
        return 0
    fi

    echo
    echo "🛬 Finalizando flujo: Volviendo a '$target_branch'..."

    # 1. Intentar checkout normal
    if git checkout "$target_branch" >/dev/null 2>&1; then
        echo "✅ Regreso exitoso a $target_branch."
        return 0
    fi

    # 2. Si falla, asumimos que fue borrada. Intentamos recrearla.
    # NOTA: Al ser una restauración de emergencia, la creamos apuntando al HEAD actual 
    # o idealmente al origen si existe, pero el usuario pidió "recrearla".
    echo "⚠️  La rama '$target_branch' no existe (¿fue borrada durante el merge?)."
    echo "🔄 Recreando '$target_branch' para mantener contexto..."

    if git checkout -b "$target_branch" >/dev/null 2>&1; then
        echo "✅ Rama recreada exitosamente. Estás en '$target_branch'."
        echo "📝 NOTA: Esta es una copia nueva. Verifica tu estado con 'git status'."
    else
        echo "❌ FALLO CRÍTICO: No pude volver ni recrear '$target_branch'." >&2
        echo "📍 Te has quedado en: ${current:-detached HEAD}" >&2
    fi
}