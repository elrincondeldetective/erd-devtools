#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/release-flow.sh

# ==============================================================================
# CONFIGURACIÓN DE VERSIONADO
# ==============================================================================
# Archivo fuente de verdad (La raíz del proyecto se asume un nivel arriba de .devtools o en root)
# Intentamos localizar el archivo VERSION relativo a la posición de este script
if [[ -f "${SCRIPT_DIR}/../../VERSION" ]]; then
    VERSION_FILE="${SCRIPT_DIR}/../../VERSION"
elif [[ -f "VERSION" ]]; then
    VERSION_FILE="VERSION"
else
    # Fallback si no encuentra nada
    VERSION_FILE="VERSION"
fi

# ==============================================================================
# 1. HELPERS DE VERSIONADO (SEMVER / RC)
# ==============================================================================

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        # Lee el archivo, quita espacios en blanco
        cat "$VERSION_FILE" | tr -d '[:space:]'
    else
        # Si no existe, iniciamos en 0.0.0
        echo "0.0.0"
    fi
}

# Lógica pura de SemVer basada en Conventional Commits
calculate_next_version() {
    local current_ver="$1"
    
    # Desglosar X.Y.Z
    local major minor patch
    IFS='.' read -r major minor patch <<< "$current_ver"
    
    # Si la versión viene vacía o mal formada, asumir 0.0.0
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}

    # Rango de commits a analizar: Desde el tag vX.Y.Z hasta HEAD
    local rev_range
    if git rev-parse "v$current_ver" >/dev/null 2>&1; then
        rev_range="v$current_ver..HEAD"
    else
        # Si no existe el tag (primer release), analizamos todo
        rev_range="HEAD"
    fi

    # Extraer mensajes de commit (Subject + Body)
    local commit_msgs
    commit_msgs=$(git log "$rev_range" --format="%s%n%b")

    # Si no hay commits, no subimos versión
    if [[ -z "$commit_msgs" ]]; then
        echo "$current_ver"
        return
    fi

    # 1. Chequeo de BREAKING CHANGE (Major)
    # Busca "BREAKING CHANGE" o strings que terminan en !: (ej: feat!:)
    if echo "$commit_msgs" | grep -qE "BREAKING CHANGE|!:"; then
        major=$((major + 1))
        minor=0
        patch=0
        echo "$major.$minor.$patch"
        return
    fi

    # 2. Chequeo de Feature (Minor)
    # Busca líneas que empiecen con "feat:" o "feat("
    if echo "$commit_msgs" | grep -qE "^feat(\(.*\))?:"; then
        minor=$((minor + 1))
        patch=0
        echo "$major.$minor.$patch"
        return
    fi

    # 3. Chequeo de Fix (Patch) - O cualquier otro cambio (chore, docs, etc)
    # Por defecto, si hay cambios y no son feat/breaking, subimos patch
    patch=$((patch + 1))
    echo "$major.$minor.$patch"
}

next_rc_number() {
    local base_ver="$1"
    local pattern="v${base_ver}-rc"
    local max=0

    # Asegura que vemos tags del remoto también
    git fetch origin --tags --force >/dev/null 2>&1 || true

    # Lista tags existentes tipo v0.6.1-rc1, v0.6.1-rc2...
    while read -r t; do
        [[ -z "$t" ]] && continue
        local n="${t#${pattern}}"
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        (( n > max )) && max="$n"
    done < <(git tag -l "${pattern}[0-9]*")

    echo $((max + 1))
}

valid_tag() {
    local t="$1"
    # check-ref-format valida que el string sea apto para ser un ref de git
    git check-ref-format --allow-onelevel "refs/tags/$t" >/dev/null 2>&1
}

# ==============================================================================
# 2. HELPERS DE RELEASE NOTES (CAPTURA Y FORMATO)
# ==============================================================================

capture_release_notes() {
    local outfile="$1"

    # Integración con GUM (UI moderna)
    if command -v gum >/dev/null 2>&1; then
        gum write \
            --width 120 \
            --height 25 \
            --placeholder "Pega aquí las Release Notes (Markdown). Guarda y cierra para continuar..." \
            > "$outfile"
        return 0
    fi

    # Fallback: Editor de texto del sistema (vim, nano, etc.)
    if [[ -n "${EDITOR:-}" ]]; then
        "${EDITOR}" "$outfile"
        return 0
    fi

    # Fallback final: Entrada estándar
    echo "Pega las Release Notes (Markdown). Termina con Ctrl-D:"
    cat > "$outfile"
}

prepend_release_notes_header() {
    local outfile="$1"
    local header="$2"
    # Fuerza un encabezado consistente al inicio del archivo
    {
        echo "$header"
        echo ""
        cat "$outfile"
    } > "${outfile}.final"
    mv "${outfile}.final" "$outfile"
}

# ==============================================================================
# 3. GENERADOR DE PROMPTS PARA IA (RELEASE MANAGER)
# ==============================================================================

generate_ai_prompt() {
    local from_branch=$1
    local to_branch=$2
    local diff_stat
    local commit_log
    
    # Asumimos que log_info y colores vienen de utils.sh
    if command -v log_info >/dev/null; then
        log_info "🤖 Generando prompt para Release Notes..."
    else
        echo "🤖 Generando prompt para Release Notes..."
    fi
    
    # Intentamos ser resilientes con ramas remotas
    diff_stat=$(git diff --stat "$to_branch..$from_branch" 2>/dev/null || echo "No diff available")
    commit_log=$(git log --pretty=format:"- %s (%an)" "$to_branch..$from_branch" 2>/dev/null || echo "No log available")
    
    cat <<EOF
--------------------------------------------------------------------------------
COPIA ESTE PROMPT PARA TU IA:
--------------------------------------------------------------------------------
Actúa como un Release Manager experto.
Genera unas Release Notes profesionales en Markdown para la versión que estamos desplegando.

Contexto:
- Origen: $from_branch
- Destino: $to_branch

Cambios (Commits):
$commit_log

Archivos afectados:
$diff_stat

Instrucciones:
1. Agrupa los cambios por tipo (Features, Fixes, Chore).
2. Destaca lo más importante para el usuario final.
3. Usa un tono técnico pero claro.
--------------------------------------------------------------------------------
EOF
    
    echo "--------------------------------------------------------------------------------"
    read -r -p "Presiona ENTER cuando hayas copiado el prompt para continuar..."
}