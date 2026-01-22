#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-promote.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/utils.sh"       # Logs, UI (ask_yes_no, log_info...)
source "${LIB_DIR}/config.sh"      # Config Global
source "${LIB_DIR}/git-core.sh"    # Git Ops (ensure_clean, update_branch...)
source "${LIB_DIR}/release-flow.sh" # Versioning (RCs, tags, notes...)

# ==============================================================================
# 2. NUEVA FUNCIONALIDAD: SYNC MODE (FAST TRACK)
# ==============================================================================

promote_sync_all() {
    local current_branch
    current_branch=$(git branch --show-current)
    
    # 1. Definir Fuente de Verdad
    # Por defecto es feature/dev-update, pero si estás en otra feature, te pregunta.
    local source_branch="feature/dev-update"

    if [[ "$current_branch" == feature/* && "$current_branch" != "$source_branch" ]]; then
        if ask_yes_no "¿Usar rama actual '$current_branch' como fuente de verdad?"; then
            source_branch="$current_branch"
        fi
    fi

    echo
    log_info "🔄 INICIANDO SYNC (FAST TRACK)"
    log_info "   Fuente: $source_branch -> dev -> staging -> main"
    echo

    ensure_clean_git

    # 2. Asegurar que tenemos la última versión de la fuente
    if [[ "$current_branch" != "$source_branch" ]]; then
        update_branch_from_remote "$source_branch"
    else
        git pull origin "$source_branch"
    fi

    # 3. Cascada de Promoción
    for target in dev staging main; do
        log_info "🚀 Propagando a ${target^^}..." # ${target^^} lo pone en mayúsculas
        
        # Actualizamos target (fetch + checkout + pull)
        update_branch_from_remote "$target"
        
        # Merge de la fuente
        # Usamos --no-edit para aceptar el mensaje por defecto o pasamos uno custom
        git merge "$source_branch" -m "chore(sync): merge $source_branch into $target"
        
        git push origin "$target"
    done

    # 4. Volver a Casa
    log_info "🏠 Regresando a $source_branch..."
    git checkout "$source_branch"

    echo
    log_success "🎉 Sincronización Completa."
    log_success "   Todas las ramas (dev, staging, main) están alineadas con $source_branch"
}

# ==============================================================================
# 3. FUNCIONES CLÁSICAS (RELEASE FLOW) - REFACTORIZADAS
# ==============================================================================

# 1. Feature -> DEV (La "Aplastadora")
promote_to_dev() {
    local current=$(git branch --show-current)

    if [[ "$current" == "dev" || "$current" == "staging" || "$current" == "main" ]]; then
        log_error "Estás en '$current'. Debes estar en una feature branch para promover a Dev."
        exit 1
    fi

    log_warn "🚧 PROMOCIÓN A DEV (Destructiva)"
    echo "   Esto forzará que 'dev' sea idéntico a '$current'."
    
    if ! ask_yes_no "¿Continuar?"; then exit 0; fi

    ensure_clean_git

    # Vamos a dev, pero sin hacer pull (true), solo fetch/checkout para resetearlo
    update_branch_from_remote "dev" "origin" "true"
    
    git reset --hard "$current"
    log_info "☁️  Forzando push a dev..."
    git push origin dev --force
    
    log_success "✅ Dev actualizado."
    
    # Volver a la rama original
    git checkout "$current"
}

# 2. Dev -> STAGING (Release Candidate)
promote_to_staging() {
    ensure_clean_git
    local current=$(git branch --show-current)
    
    if [[ "$current" != "dev" ]]; then
        log_warn "No estás en 'dev'. Cambiando..."
        update_branch_from_remote "dev"
    fi

    log_info "🔍 Comparando Dev -> Staging"
    git fetch origin staging
    git log --oneline origin/staging..HEAD
    
    # Generar Prompt y Capturar Notas (usando lib/release-flow.sh)
    generate_ai_prompt "dev" "origin/staging"

    local tmp_notes
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    
    echo -e "${BLUE}📝 Pega tus Release Notes (Markdown):${NC}"
    capture_release_notes "$tmp_notes"

    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías. Cancelando."; exit 1; }

    # Calcular versión
    local base_ver=$(get_current_version)
    local rc_num=$(next_rc_number "$base_ver")
    local rc_tag="v${base_ver}-rc${rc_num}"

    prepend_release_notes_header "$tmp_notes" "Release Notes - ${rc_tag} (Staging)"

    log_info "Tag sugerido: $rc_tag"
    if ! ask_yes_no "¿Desplegar a STAGING con tag $rc_tag?"; then exit 0; fi

    # Ejecución
    ensure_clean_git
    update_branch_from_remote "staging"
    git merge --ff-only dev
    
    git tag -a "$rc_tag" -F "$tmp_notes"
    git push origin staging
    git push origin "$rc_tag"
    
    log_success "✅ Staging actualizado ($rc_tag)."
    log_info "📍 Estás en 'staging'."
}

# 3. Staging -> PROD (Release Oficial)
promote_to_prod() {
    ensure_clean_git
    local current=$(git branch --show-current)
    
    if [[ "$current" != "staging" ]]; then
        log_warn "No estás en 'staging'. Cambiando..."
        update_branch_from_remote "staging"
    fi

    log_info "🚀 PROMOCIÓN A PRODUCCIÓN"
    git fetch origin main
    
    generate_ai_prompt "staging" "origin/main"

    local tmp_notes
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    capture_release_notes "$tmp_notes"

    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }

    local base_ver=$(get_current_version)
    local release_tag="v${base_ver}"
    
    prepend_release_notes_header "$tmp_notes" "Release Notes - ${release_tag} (Producción)"

    if ! ask_yes_no "¿Confirmar pase a Producción ($release_tag)?"; then exit 0; fi

    ensure_clean_git
    update_branch_from_remote "main"
    git merge --ff-only staging

    if git rev-parse "$release_tag" >/dev/null 2>&1; then
        log_warn "El tag $release_tag ya existe (posible re-deploy)."
    else
        git tag -a "$release_tag" -F "$tmp_notes"
        git push origin "$release_tag"
    fi

    git push origin main
    log_success "✅ Producción actualizada ($release_tag)."
    log_info "📍 Estás en 'main'."
}

# 4. Hotfix Flow
create_hotfix() {
    log_warn "🔥 HOTFIX MODE"
    read -r -p "Nombre del hotfix (ej: login-bug): " hf_name
    local hf_branch="hotfix/$hf_name"

    ensure_clean_git
    update_branch_from_remote "main"
    
    git checkout -b "$hf_branch"
    log_success "✅ Estás en '$hf_branch'. Haz tus cambios y luego: git promote hotfix-finish"
}

finish_hotfix() {
    local current=$(git branch --show-current)
    [[ "$current" != hotfix/* ]] && { log_error "No estás en una rama hotfix/.*"; exit 1; }

    ensure_clean_git
    log_warn "🩹 Finalizando Hotfix..."

    # Merge a Main
    update_branch_from_remote "main"
    git merge --no-ff "$current" -m "Merge hotfix: $current"
    git push origin main

    # Merge a Dev
    update_branch_from_remote "dev"
    git merge --no-ff "$current" -m "Merge hotfix: $current"
    git push origin dev

    # Taggear
    local base_ver=$(get_current_version)
    echo "Versión base: $base_ver. Sugerencia: Incrementa PATCH."
    read -r -p "Nuevo Tag (ej: v0.6.2): " new_tag

    if [[ -n "$new_tag" ]]; then
        if valid_tag "$new_tag"; then
            update_branch_from_remote "main"
            git tag -a "$new_tag" -m "Hotfix Release $new_tag"
            git push origin "$new_tag"
        else
            log_error "Tag inválido."
        fi
    fi

    log_success "✅ Hotfix integrado en Main y Dev."
}

# ==============================================================================
# 4. PARSEO DE COMANDOS
# ==============================================================================

TARGET_ENV="${1:-}"

case "$TARGET_ENV" in
    dev)       promote_to_dev ;;
    staging)   promote_to_staging ;;
    prod)      promote_to_prod ;;
    sync)      promote_sync_all ;;     # <--- TU NUEVA ARMA SECRETA
    hotfix)    create_hotfix ;;
    hotfix-finish) finish_hotfix ;;
    *) 
        echo "Uso: git promote [dev | staging | prod | sync | hotfix]"
        echo "   sync: Alinea feature -> dev -> staging -> main automáticamente."
        exit 1
        ;;
esac