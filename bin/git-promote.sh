#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-promote.sh
set -euo pipefail
IFS=$'\n\t'

# [FIX] Inicializamos variable global para evitar error en trap con set -u
tmp_notes=""

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
# 3.1 FUNCIONALIDAD: SQUASH MERGE HACIA feature/dev-update (Aplastante + Opcional delete)
# ==============================================================================
#
# Uso:
#   - Desde una rama feature/*:       git promote dev-update
#   - Indicando rama explícita:       git promote dev-update feature/main-40c449c
#   - Estando en feature/dev-update:  git promote dev-update <rama-fuente>
#
# Comportamiento:
#   - Aplica un `git merge --squash` de la rama fuente hacia `feature/dev-update`
#   - Crea 1 commit (mensaje con prompt; Enter usa sugerido)
#   - Push a `origin/feature/dev-update`
#   - Pregunta (sí/no) si quieres borrar la rama fusionada (local + remota)
#   - Termina SIEMPRE ubicado en `feature/dev-update`
#
promote_dev_update_squash() {
    local canonical_branch="feature/dev-update"
    local current_branch
    current_branch="$(git branch --show-current 2>/dev/null || true)"

    local source_branch="${1:-$current_branch}"

    echo
    log_info "🧱 INTEGRACIÓN APLASTANTE (SQUASH) HACIA '$canonical_branch'"

    # Si estamos en dev-update y no pasaron rama, pedimos una
    if [[ -z "${source_branch:-}" || "$source_branch" == "$canonical_branch" ]]; then
        if [[ "$current_branch" == "$canonical_branch" ]]; then
            echo
            log_info "📌 Estás en '$canonical_branch'."
            read -r -p "Rama fuente a aplastar dentro de '$canonical_branch': " source_branch
        fi
    fi

    if [[ -z "${source_branch:-}" || "$source_branch" == "$canonical_branch" ]]; then
        log_error "Debes indicar una rama fuente distinta a '$canonical_branch'."
        exit 1
    fi

    ensure_clean_git

    # Traer refs frescas
    git fetch origin --prune

    # Resolver ref de la rama fuente (local o remota)
    local source_ref=""
    if git show-ref --verify --quiet "refs/heads/${source_branch}"; then
        source_ref="${source_branch}"
    elif git show-ref --verify --quiet "refs/remotes/origin/${source_branch}"; then
        source_ref="origin/${source_branch}"
    else
        log_warn "No encuentro '${source_branch}' local/remoto. Intentando fetch explícito..."
        git fetch origin "${source_branch}" || true
        if git show-ref --verify --quiet "refs/remotes/origin/${source_branch}"; then
            source_ref="origin/${source_branch}"
        elif git show-ref --verify --quiet "refs/heads/${source_branch}"; then
            source_ref="${source_branch}"
        fi
    fi

    if [[ -z "${source_ref:-}" ]]; then
        log_error "No se encontró la rama fuente '${source_branch}' (ni local ni en origin)."
        exit 1
    fi

    local source_sha
    source_sha="$(git rev-parse --short "$source_ref" 2>/dev/null || true)"

    echo
    log_info "   Fuente:  $source_ref @${source_sha:-unknown}"
    log_info "   Destino: $canonical_branch"
    echo

    # Ir a feature/dev-update y actualizarla
    update_branch_from_remote "$canonical_branch"

    # Aplicar squash
    log_info "🧲 Aplicando squash merge..."
    if ! git merge --squash "$source_ref"; then
        log_error "❌ Squash merge falló (posibles conflictos). Abortando para no dejar estado parcial..."
        git merge --abort || true
        log_info "🏠 Quedando en '$canonical_branch'..."
        git checkout "$canonical_branch"
        exit 1
    fi

    # Si no hay cambios staged, probablemente ya estaba integrado
    if git diff --cached --quiet; then
        log_warn "ℹ️ No hay cambios para commitear (posible ya integrado)."
        log_info "🏠 Quedando en '$canonical_branch'..."
        git checkout "$canonical_branch"
        exit 0
    fi

    echo
    log_info "📝 Preparando commit (1 solo commit por squash)..."
    local default_msg="chore(dev-update): integrar cambios de '${source_branch}' (squash)"
    local msg=""

    echo "Mensaje sugerido:"
    echo "  $default_msg"
    read -r -p "Mensaje de commit (Enter para usar sugerido): " msg
    msg="${msg:-$default_msg}"

    # IMPORTANTE: NO pasar el mensaje por -m con comillas dobles (backticks podrían ejecutarse).
    # Usamos stdin con -F - para evitar expansión/comando sustitución.
    printf '%s\n' "$msg" | git commit -F -

    log_success "✅ Commit squash creado en '$canonical_branch'."

    # Push del destino
    log_info "🚀 Pusheando '$canonical_branch' a origin..."
    git push origin "$canonical_branch"
    log_success "✅ '$canonical_branch' sincronizada en origin."

    # Opción de borrar la rama fuente (local + remota)
    echo
    if ask_yes_no "¿Quieres ELIMINAR la rama fuente '${source_branch}' (local y remota) ahora?"; then
        # Nunca borrar la canónica por error
        if [[ "$source_branch" == "$canonical_branch" ]]; then
            log_warn "🛑 Rama fuente es la canónica. No se elimina."
        else
            # Borrar local (squash NO cuenta como 'merged', así que usamos -D)
            if git show-ref --verify --quiet "refs/heads/${source_branch}"; then
                log_info "🗑️  Eliminando rama local '${source_branch}'..."
                git branch -D "$source_branch" || true
            fi

            # Borrar remota
            if git show-ref --verify --quiet "refs/remotes/origin/${source_branch}"; then
                log_info "🗑️  Eliminando rama remota 'origin/${source_branch}'..."
                git push origin --delete "$source_branch" || true
            fi

            log_success "🧹 Limpieza completada para '${source_branch}'."
        fi
    else
        log_info "👌 Conservando rama fuente '${source_branch}'."
    fi

    # Asegurar que terminamos en dev-update
    log_info "🏠 Quedando en '$canonical_branch'..."
    git checkout "$canonical_branch"

    echo
    log_success "🎉 Squash merge completado. Estás en '$canonical_branch'."
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
    
    # [FIX] Ahora terminamos en DEV, no en la feature branch
    git checkout dev
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
    
    # [FIX] Inicializar variable para evitar error 'unbound variable' en strict mode
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    
    capture_release_notes "$tmp_notes"
    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }
    
    # 1. Obtener versión base desde archivo VERSION (fuente de verdad)
    local version_file="${SCRIPT_DIR}/../VERSION"
    local base_ver
    if [[ -f "$version_file" ]]; then
        base_ver=$(cat "$version_file" | tr -d '[:space:]')
        log_info "📄 Versión actual en archivo: $base_ver"
    else
        base_ver=$(get_current_version) # Fallback
    fi

    # 2. Calcular SIGUIENTE versión basada en commits (feat/fix/etc)
    #    Requiere que lib/release-flow.sh tenga 'calculate_next_version'
    local next_ver="$base_ver"
    if command -v calculate_next_version >/dev/null; then
        next_ver=$(calculate_next_version "$base_ver")
        if [[ "$next_ver" != "$base_ver" ]]; then
            log_info "🧠 Cálculo automático: $base_ver -> $next_ver (según commits)"
        else
            log_info "🧠 Cálculo automático: Sin cambios mayores detectados."
        fi
    fi

    # 3. Calcular RC sobre la versión objetivo
    local rc_num=$(next_rc_number "$next_ver")
    local suggested_tag="v${next_ver}-rc${rc_num}"
    
    # 4. Opción de Override Manual
    echo
    log_info "🔖 Tag sugerido: $suggested_tag"
    local rc_tag=""
    read -r -p "Presiona ENTER para usar '$suggested_tag' o escribe tu versión manual: " rc_tag
    rc_tag="${rc_tag:-$suggested_tag}"

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
    
    # [FIX] Inicializar variable para evitar error 'unbound variable' en strict mode
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    
    capture_release_notes "$tmp_notes"
    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }
    
    # 1. Obtener versión base desde archivo
    local version_file="${SCRIPT_DIR}/../VERSION"
    local base_ver
    if [[ -f "$version_file" ]]; then
        base_ver=$(cat "$version_file" | tr -d '[:space:]')
    else
        base_ver=$(get_current_version)
    fi

    # 2. Calcular versión sugerida (generalmente en prod es la base, pero verificamos)
    local next_ver="$base_ver"
    if command -v calculate_next_version >/dev/null; then
        next_ver=$(calculate_next_version "$base_ver")
    fi

    local suggested_tag="v${next_ver}"
    
    # 3. Opción de Override Manual
    echo
    log_info "🔖 Tag sugerido: $suggested_tag"
    local release_tag=""
    read -r -p "Presiona ENTER para usar '$suggested_tag' o escribe tu versión manual: " release_tag
    release_tag="${release_tag:-$suggested_tag}"

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
    dev-update|feature/dev-update) promote_dev_update_squash "${2:-}" ;;
    hotfix)    create_hotfix ;;
    hotfix-finish) finish_hotfix ;;
    *) 
        echo "Uso: git promote [dev | staging | prod | sync | feature/dev-update | hotfix]"
        echo "  - feature/dev-update: aplasta (squash) una rama dentro de feature/dev-update (+ opción de borrar rama)"
        exit 1
        ;;
esac