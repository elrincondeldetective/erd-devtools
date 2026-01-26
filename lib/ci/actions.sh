#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ci/actions.sh

# ==============================================================================
# LÓGICA DE ACCIONES (Creación de PRs, Pipelines complejos, etc.)
# ==============================================================================

# Helper: Creación de PR
# Invoca al script `git-pr.sh` pasando la rama base correcta.
do_create_pr_flow() {
    local head="$1"
    local base="$2"
    
    # Obtenemos el directorio donde reside ESTE script (.devtools/lib/ci)
    local current_dir
    current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Calculamos la ruta absoluta hacia git-pr.sh (.devtools/bin/git-pr.sh)
    # Subimos 2 niveles: lib/ci -> lib -> .devtools -> bin
    local pr_script="${current_dir}/../../bin/git-pr.sh"

    if [[ -f "$pr_script" ]]; then
        # MODIFICADO (1.2): Exportamos BASE_BRANCH para que git-pr.sh sepa a dónde apuntar
        BASE_BRANCH="$base" "$pr_script"
        if [ $? -eq 0 ]; then
            echo "Gracias por el trabajo, en breve se revisa."
            return 0
        fi
    elif command -v git-pr >/dev/null; then
        # Fallback por si git-pr está en el PATH global
        if git-pr; then return 0; fi
    else
        echo "❌ No encuentro el script git-pr.sh en $pr_script ni en el PATH."
        return 1
    fi
    
    echo "⚠️ Hubo un problema creando el PR."
    return 1
}