#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-gp.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/core/utils.sh"       # Logs (log_info, log_warn)
source "${LIB_DIR}/git-context.sh" # Lógica de extracción de diffs y tickets
source "${LIB_DIR}/ai-prompts.sh"  # Templates de Prompts para la IA

# ==============================================================================
# 2. RECOLECCIÓN DE DATOS (CONTEXTO).
# ==============================================================================
log_info "🤖 La IA está analizando tus cambios y archivos nuevos..."

BRANCH_NAME=$(git branch --show-current)

# Usamos la función de la librería git-context.sh
CHANGES=$(get_full_context_diff)

# Validación: Si no hay nada que commitear, avisamos y salimos
if [ -z "$CHANGES" ]; then
    log_warn "No detecté cambios pendientes (staged, unstaged o untracked)."
    log_info "Tip: Haz cambios en algún archivo antes de pedir ayuda a la IA."
    exit 0
fi

# Detectamos ticket desde el nombre de la rama
DETECTED_ISSUE=$(get_detected_issue "$BRANCH_NAME")

if [ -n "$DETECTED_ISSUE" ]; then
    log_info "ℹ️  Detecté el Ticket #$DETECTED_ISSUE en la rama."
fi

# ==============================================================================
# 3. GENERACIÓN DEL PROMPT
# ==============================================================================

# Generamos el texto usando la librería ai-prompts.sh y lo enviamos a stdout
generate_gp_prompt "$BRANCH_NAME" "$DETECTED_ISSUE" "$CHANGES"

# (Opcional) Mensaje final para guiar al usuario
echo
log_info "Copia el bloque de arriba y pégalo en tu IA de confianza."