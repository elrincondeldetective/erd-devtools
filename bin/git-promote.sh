#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-promote.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/core/utils.sh"       # Logs, UI
source "${LIB_DIR}/core/config.sh"      # Config Global (SIMPLE_MODE)
source "${LIB_DIR}/core/git-ops.sh"    # Git Ops
source "${LIB_DIR}/release-flow.sh" # Versioning
source "${LIB_DIR}/ssh-ident.sh"   # <--- AGREGADO: Gestión de Identidad

# ==============================================================================
# 2. SETUP DE IDENTIDAD (CRÍTICO PARA PULL/PUSH)
# ==============================================================================
# Si no estamos en modo simple, cargamos las llaves SSH antes de empezar
if [[ "${SIMPLE_MODE:-false}" == "false" ]]; then
    setup_git_identity
fi

# ==============================================================================
# 3. FUNCIONALIDAD: SMART SYNC (Con Auto-Absorción)
# ==============================================================================

promote_sync_all() {
    local current_branch
    current_branch=$(git branch --show-current)
    
    # Definimos la "Rama Madre" de desarrollo
    local canonical_branch="feature/dev-update"
    local source_branch="$canonical_branch"
    local force_push_source="false"

    echo
    log_info "🔄 INICIANDO SMART SYNC"
    
    # CASO A: Ya estás en la rama madre
    if [[ "$current_branch" == "$canonical_branch" ]]; then
        log_info "✅ Estás en la rama canónica ($canonical_branch)."
    
    # CASO B: Estás en una rama diferente
    else
        log_warn "Estás en una rama divergente: '$current_branch'"
        echo "   La rama canónica de desarrollo es: '$canonical_branch'"
        echo
        
        if ask_yes_no "¿Quieres FUSIONAR '$current_branch' dentro de '$canonical_branch' y sincronizar todo?"; then
            ensure_clean_git
            log_info "🧲 Absorbiendo '$current_branch' en '$canonical_branch'..."
            
            # 1. Ir a la rama madre y actualizarla
            update_branch_from_remote "$canonical_branch"
            
            # 2. Fusionar la rama accidental (sin conflictos: preferir 'theirs'; fallback aplastante)
            if git merge -X theirs "$current_branch"; then
                log_success "✅ Fusión exitosa (auto-resuelta con 'theirs')."
            else
                log_warn "🧨 Conflictos detectados. Aplicando modo APLASTANTE para absorber '$current_branch'..."
                git merge --abort || true
                git reset --hard "$current_branch"
                force_push_source="true"
                log_success "✅ Absorción aplastante completada."
            fi
            
            # 3. Eliminar rama temporal
            if [[ "$current_branch" == feature/main-* || "$current_branch" == feature/detached-* ]]; then
                log_info "🗑️  Eliminando rama temporal '$current_branch'..."
                git branch -d "$current_branch" || true
            fi
            
            source_branch="$canonical_branch"
        else
            log_info "👌 Usando '$current_branch' como fuente de verdad (sin fusionar)."
            source_branch="$current_branch"
        fi
    fi

    # --- FASE DE PROPAGACIÓN ---
    echo
    log_info "🌊 Propagando cambios desde: $source_branch"
    log_info "   Flujo: $source_branch -> dev -> staging -> main"
    echo

    ensure_clean_git

    # Asegurar fuente actualizada
    if [[ "$source_branch" == "$canonical_branch" ]]; then
        if [[ "$force_push_source" == "true" ]]; then
            log_warn "🧨 MODO APLASTANTE: forzando push de '$source_branch' (lease)..."
            git push origin "$source_branch" --force-with-lease
        else
            git push origin "$source_branch"
        fi
    else
        git pull origin "$source_branch" || true
    fi

    # Cascada (APLASTANTE)
    for target in dev staging main; do
        log_info "🚀 Sincronizando ${target^^} (APLASTANTE)..."
        update_branch_from_remote "$target"

        log_warn "🧨 MODO APLASTANTE: sobrescribiendo '$target' con '$source_branch'..."
        git reset --hard "$source_branch"

        # Preferible a --force: evita pisar trabajo ajeno si el remoto cambió desde tu fetch
        git push origin "$target" --force-with-lease
    done

    # Volver a Casa
    log_info "🏠 Regresando a $source_branch..."
    git checkout "$source_branch"

    echo
    log_success "🎉 Sincronización Completa."
}

# ==============================================================================
# 4. FUNCIONES CLÁSICAS (RELEASE FLOW)
# ==============================================================================

promote_to_dev() {
    local current=$(git branch --show-current)
    if [[ "$current" == "dev" || "$current" == "staging" || "$current" == "main" ]]; then
        log_error "Estás en '$current'. Debes estar en una feature branch."
        exit 1
    fi
    log_warn "🚧 PROMOCIÓN A DEV (Destructiva)"
    if ! ask_yes_no "¿Aplastar 'dev' con '$current'?"; then exit 0; fi
    ensure_clean_git
    update_branch_from_remote "dev" "origin" "true"
    git reset --hard "$current"
    git push origin dev --force
    log_success "✅ Dev actualizado."
    git checkout "$current"
}

promote_to_staging() {
    ensure_clean_git
    local current=$(git branch --show-current)
    if [[ "$current" != "dev" ]]; then
        log_warn "No estás en 'dev'. Cambiando..."
        update_branch_from_remote "dev"
    fi
    log_info "🔍 Comparando Dev -> Staging"
    generate_ai_prompt "dev" "origin/staging"
    local tmp_notes
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    capture_release_notes "$tmp_notes"
    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }
    local base_ver=$(get_current_version)
    local rc_num=$(next_rc_number "$base_ver")
    local rc_tag="v${base_ver}-rc${rc_num}"
    prepend_release_notes_header "$tmp_notes" "Release Notes - ${rc_tag} (Staging)"
    if ! ask_yes_no "¿Desplegar a STAGING con tag $rc_tag?"; then exit 0; fi
    ensure_clean_git
    update_branch_from_remote "staging"
    git merge --ff-only dev
    git tag -a "$rc_tag" -F "$tmp_notes"
    git push origin staging
    git push origin "$rc_tag"
    log_success "✅ Staging actualizado ($rc_tag)."
}

promote_to_prod() {
    ensure_clean_git
    local current=$(git branch --show-current)
    if [[ "$current" != "staging" ]]; then
        log_warn "No estás en 'staging'. Cambiando..."
        update_branch_from_remote "staging"
    fi
    log_info "🚀 PROMOCIÓN A PRODUCCIÓN"
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
        log_warn "Tag $release_tag ya existe."
    else
        git tag -a "$release_tag" -F "$tmp_notes"
        git push origin "$release_tag"
    fi
    git push origin main
    log_success "✅ Producción actualizada ($release_tag)."
}

create_hotfix() {
    log_warn "🔥 HOTFIX MODE"
    read -r -p "Nombre del hotfix: " hf_name
    local hf_branch="hotfix/$hf_name"
    ensure_clean_git
    update_branch_from_remote "main"
    git checkout -b "$hf_branch"
    log_success "✅ Rama hotfix creada: $hf_branch"
}

finish_hotfix() {
    local current=$(git branch --show-current)
    [[ "$current" != hotfix/* ]] && { log_error "No estás en una rama hotfix."; exit 1; }
    ensure_clean_git
    log_warn "🩹 Finalizando Hotfix..."
    update_branch_from_remote "main"
    git merge --no-ff "$current" -m "Merge hotfix: $current"
    git push origin main
    update_branch_from_remote "dev"
    git merge --no-ff "$current" -m "Merge hotfix: $current"
    git push origin dev
    log_success "✅ Hotfix integrado."
}

# ==============================================================================
# 5. PARSEO DE COMANDOS
# ==============================================================================

TARGET_ENV="${1:-}"

case "$TARGET_ENV" in
    dev)       promote_to_dev ;;
    staging)   promote_to_staging ;;
    prod)      promote_to_prod ;;
    sync)      promote_sync_all ;;
    hotfix)    create_hotfix ;;
    hotfix-finish) finish_hotfix ;;
    *) 
        echo "Uso: git promote [dev | staging | prod | sync | hotfix]"
        exit 1
        ;;
esac
