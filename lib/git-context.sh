#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/git-context.sh

# ==============================================================================
# 1. DETECCIÓN DE ISSUES/TICKETS
# ==============================================================================

get_detected_issue() {
    local branch_name="$1"
    # Busca el primer número encontrado en el nombre de la rama
    # Ejemplos: "feature/45-login" -> "45", "bugfix/JIRA-123" -> "123"
    echo "$branch_name" | grep -oE '[0-9]+' | head -n1 || echo ""
}

# ==============================================================================
# 2. EXTRACCIÓN DE CAMBIOS (CONTEXTO PARA LA IA)
# ==============================================================================

get_full_context_diff() {
    local context=""
    
    # 1. Cambios rastreados (Tracked)
    # Usamos --word-diff para que sea más compacto y fácil de leer para la IA
    context+=$(git diff --word-diff)
    
    # 2. Archivos nuevos (Untracked)
    # Git diff normal no ve archivos nuevos hasta que haces 'git add'.
    # Aquí los leemos manualmente para que la IA sepa que existen.
    local untracked_files
    untracked_files=$(git ls-files --others --exclude-standard)

    if [ -n "$untracked_files" ]; then
        context+=$'\n\n==================================================\n'
        context+=$'⚠️  ARCHIVOS NUEVOS (AÚN NO RASTREADOS):\n'
        context+=$'==================================================\n'
        
        # Iteramos sobre cada archivo nuevo
        for file in $untracked_files; do
            # Validación de seguridad: Solo leemos si es texto.
            # grep -qI . comprueba si el archivo tiene caracteres nulos (binario).
            if grep -qI . "$file" 2>/dev/null; then
                context+=$"\n--- CONTENIDO DE: $file ---\n"
                context+=$(cat "$file")
                context+=$"\n----------------------------------\n"
            else
                context+=$"\n--- ARCHIVO BINARIO (Omitido): $file ---\n"
            fi
        done
    fi
    
    echo "$context"
}