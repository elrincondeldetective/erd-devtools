#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/github-core.sh

# ==============================================================================
# 1. VALIDACIONES DE HERRAMIENTAS (GH CLI)
# ==============================================================================

ensure_gh_cli() {
    if ! command -v gh >/dev/null 2>&1; then
        log_error "No se encontró 'gh' (GitHub CLI)."
        log_info "Instálalo para continuar: https://cli.github.com/"
        exit 1
    fi

    if ! gh auth status >/dev/null 2>&1; then
        log_error "gh no está autenticado."
        log_warn "Ejecuta: gh auth login"
        exit 1
    fi
}

# ==============================================================================
# 2. OPERACIONES DE PULL REQUESTS
# ==============================================================================

# Verifica si existe un PR abierto para la rama actual hacia la base
# Retorna: 0 (True) si existe, 1 (False) si no.
pr_exists() {
    local head="$1"
    local base="$2"
    local count
    
    # GH_PAGER=cat evita que se quede colgado esperando input del usuario
    count="$(GH_PAGER=cat gh pr list --state open --head "$head" --base "$base" --json number --jq 'length' 2>/dev/null || echo 0)"
    
    if [[ "$count" -gt 0 ]]; then
        return 0 # Existe
    else
        return 1 # No existe
    fi
}

create_pr() {
    local head="$1"
    local base="$2"
    
    log_info "🚀 Creando PR: $head -> $base"
    
    # --fill intenta llenar título y cuerpo con el último commit
    if GH_PAGER=cat gh pr create --base "$base" --head "$head" --fill; then
        log_success "PR Creado exitosamente."
    else
        log_error "Falló la creación del PR."
        exit 1
    fi
}

show_pr_info() {
    local head="$1"
    local base="$2"
    
    log_info "🟢 Ya existe un PR abierto para esta rama:"
    echo "---------------------------------------------------"
    GH_PAGER=cat gh pr list --state open --head "$head" --base "$base"
    echo "---------------------------------------------------"
}