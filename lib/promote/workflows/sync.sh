#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/sync.sh
#
# Este módulo maneja la sincronización "inteligente" (Smart Sync):
# - promote_sync_all: Sincroniza feature/dev-update -> dev -> staging -> main
#   aplicando lógica aplastante para asegurar paridad de entornos.
#
# Dependencias: utils.sh, git-ops.sh (cargadas por el orquestador)

# ==============================================================================
# 1. SMART SYNC (Con Auto-Absorción)
# ==============================================================================
promote_sync_all() {
    local current_branch
    current_branch=$(git branch --show-current)
    local from_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$current_branch}"
    
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
            push_branch_force "$source_branch" "origin"
        else
            git push origin "$source_branch"
        fi
    else
        git pull origin "$source_branch" || true
    fi

    # Cascada (APLASTANTE)
    local source_sha
    source_sha="$(git rev-parse "$source_branch" 2>/dev/null || true)"
    if [[ -z "${source_sha:-}" ]]; then
        log_error "No pude resolver SHA de fuente: '$source_branch'."
        exit 1
    fi

    for target in dev staging main; do
        log_info "🚀 Sincronizando ${target^^} (APLASTANTE)..."
        ensure_local_tracking_branch "$target" "origin" || {
            log_error "No pude preparar la rama '$target' desde 'origin/$target'."
            exit 1
        }
        update_branch_from_remote "$target"

        log_warn "📍 Estás en '${from_branch}'. 🧨 Sobrescribiendo historia de '${target}' con '${source_branch}' (${source_sha})..."
        force_update_branch_to_sha "$target" "$source_sha" "origin" || { log_error "No pude sobrescribir '$target' con ${source_sha:0:7}."; exit 1; }
    done

    # Volver a Casa
    log_info "🏠 Regresando a $source_branch..."
    git checkout "$source_branch"

    echo
    log_success "🎉 Sincronización Completa."
}