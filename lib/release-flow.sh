#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/release-flow.sh

# ==============================================================================
# CONFIGURACIÓN DE VERSIONADO
# ==============================================================================
# Archivo donde release-please guarda la verdad
VERSION_FILE="apps/pmbok/.github/utils/.release-please-manifest.json"
# Servicio principal para versionar el repo (usualmente backend)
MAIN_SERVICE="backend"

# ==============================================================================
# 1. HELPERS DE VERSIONADO (SEMVER / RC)
# ==============================================================================

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        # Extrae la versión del backend (ej: 0.6.1) usando grep/sed
        grep "\"$MAIN_SERVICE\":" "$VERSION_FILE" | sed -E 's/.*: "(.*)".*/\1/'
    else
        echo "0.0.0"
    fi
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
    
    diff_stat=$(git diff --stat "$to_branch..$from_branch")
    commit_log=$(git log --pretty=format:"- %s (%an)" "$to_branch..$from_branch")
    
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