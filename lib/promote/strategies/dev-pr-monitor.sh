#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/strategies/dev-pr-monitor.sh
#
# Estrategia: PR Monitor & Interactive Dashboard.
# TAREA 2: Descubrimiento y Visualización.
#
# Ahora este script NO ejecuta acciones automáticamente.
# Su responsabilidad es descubrir PRs relevantes y mostrarlos con detalle.
#
# Dependencias esperadas (inyectadas por to-dev.sh):
# - utils.sh (logs, banner, repo_has_workflow_file)
# - helpers/gh-interactions.sh (gh_discover_prs_to_base, ui_render_pr_card, etc.)
# - git-ops.sh

promote_dev_monitor() {
    local input_pr="${1:-}"      # PR sugerido por to-dev.sh (si existe)
    local input_branch="${2:-}"  # Rama origen

    banner "🕵️  MONITOR DE INTEGRACIÓN (Modo Descubrimiento)"

    # --------------------------------------------------------------------------
    # 1. Fase de Descubrimiento (Discovery)
    # --------------------------------------------------------------------------
    # Construir lista de candidatos:
    # Si nos pasaron un PR específico, lo usamos. Si no, buscamos todos los abiertos a dev.
    local pr_candidates=()
    
    if [[ -n "$input_pr" ]]; then
        pr_candidates+=("$input_pr")
    else
        log_info "🔍 Buscando PRs abiertos hacia 'dev'..."
        # Convertir salida separada por espacios a array
        local discovered
        discovered="$(gh_discover_prs_to_base "dev")"
        for p in $discovered; do
            pr_candidates+=("$p")
        done
    fi

    # Validación de vacío
    if [[ ${#pr_candidates[@]} -eq 0 ]]; then
        log_warn "🤷 No se encontraron Pull Requests relevantes para 'dev'."
        echo "   (Nada que aprobar o monitorear)"
        return 0
    fi

    # --------------------------------------------------------------------------
    # 2. Fase de Visualización (Data Gathering & Rendering)
    # --------------------------------------------------------------------------
    echo
    log_info "📋 PRs Encontrados (${#pr_candidates[@]}):"
    
    for pr_id in "${pr_candidates[@]}"; do
        # A) Data Gathering profundo (metadatos, estado CI, reviews)
        local json_details
        json_details="$(gh_get_pr_rich_details "$pr_id")"
        
        # B) Renderizado visual (Tarjeta ASCII)
        ui_render_pr_card "$json_details"
        
        # C) Detalle de checks (Requisito: jobs, runners, checks visibles)
        echo "   🔎 Detalles de CI/Checks:"
        # Usamos el helper y filtramos/indentamos para que se vea ordenado en el dashboard
        gh_get_pr_checks_summary "$pr_id" | sed 's/^/      /' | head -n 10
        echo ""
    done

    # --------------------------------------------------------------------------
    # 3. Cierre de Fase (Tarea 2)
    # --------------------------------------------------------------------------
    # En esta etapa, solo mostramos la información.
    # La interactividad (Aprobar/Merge/Wait) se inyectará aquí en la Tarea 3.
    
    log_info "✅ [TAREA 2] Visualización completada."
    echo "👉 En la siguiente fase (Tarea 3), aquí se iniciará el menú interactivo para actuar sobre estos PRs."
    
    return 0
}