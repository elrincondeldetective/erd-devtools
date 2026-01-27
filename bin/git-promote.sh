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
# FASE 1 (NUEVO): NORMALIZACIÓN ROBUSTA DE VERSION FILE (repo actual)
# ==============================================================================
# Objetivo:
# - Garantizar que siempre leemos VERSION desde el repo actual, NO desde .devtools embebido.
# - Mantener backward-compat: si REPO_ROOT no existe por algún motivo, lo inferimos.
# - Permitir que GitHub (release-please) sea el único que “decide” la versión (local no recalcula).
if [[ -z "${REPO_ROOT:-}" ]]; then
    export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

resolve_repo_version_file() {
    # Preferimos VERSION en la raíz del repo actual
    if [[ -n "${REPO_ROOT:-}" && -f "${REPO_ROOT}/VERSION" ]]; then
        echo "${REPO_ROOT}/VERSION"
        return 0
    fi

    # Backward-compat (histórico): relativo a .devtools/bin (puede apuntar a .devtools/VERSION)
    if [[ -f "${SCRIPT_DIR}/../VERSION" ]]; then
        echo "${SCRIPT_DIR}/../VERSION"
        return 0
    fi

    # Fallback: relativo al cwd
    if [[ -f "VERSION" ]]; then
        echo "VERSION"
        return 0
    fi

    # Fallback final
    echo "VERSION"
}

# ==============================================================================
# FIX (NUEVO): AUTO-RESYNC DE SUBMÓDULOS ANTES DE VALIDAR "DIRTY"
# ==============================================================================
# Objetivo:
# - Evitar el error recurrente: ".devtools (new commits)" => ensure_clean_git falla.
# - Forzar que los submódulos queden exactamente en el SHA que el repo referencia (gitlink),
#   antes de validar/promover.
resync_submodules_hard() {
    # Solo aplica si el repo tiene submódulos.
    if [[ -f ".gitmodules" ]]; then
        git submodule sync --recursive >/dev/null 2>&1 || true
        git submodule update --init --recursive >/dev/null 2>&1 || true
    fi
}

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
            resync_submodules_hard
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

    resync_submodules_hard
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

    resync_submodules_hard
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
    local current_branch
    current_branch="$(git branch --show-current)"

    # --------------------------------------------------------------------------
    # NUEVA LÓGICA: INTERCEPCIÓN DE PR PARA DEV (GITHUB CLI)
    # --------------------------------------------------------------------------
    # Si tenemos 'gh' instalado, buscamos PRs abiertos para fusionar limpiamente
    if command -v gh &> /dev/null; then
        echo "🔍 Buscando PRs abiertos para '$current_branch'..."
        
        # Obtenemos el número del PR si existe (json number)
        local pr_number
        pr_number="$(gh pr list --head "$current_branch" --state open --json number --jq '.[0].number')"

        if [[ -n "$pr_number" ]]; then
            banner "🤖 MODO AUTOMÁTICO DETECTADO (PR #$pr_number)"
            echo "ℹ️  Esta rama tiene un PR abierto."
            echo "    Podemos delegar la fusión a GitHub para:"
            echo "    1. Esperar que pasen los Checks (CI/CD)"
            echo "    2. Hacer Squash Merge automático"
            echo "    3. Borrar la rama remota al terminar"
            echo
            
            # Confirmación de seguridad
            if ask_yes_no "❓ ¿Deseas auto-fusionar (Squash) el PR #$pr_number cuando pasen los checks?"; then
                ensure_clean_git

                echo "🚀 Enviando orden a GitHub..."
                # --auto: Espera a que pasen los checks (CI/CD)
                # --squash: Genera un solo commit limpio
                # --delete-branch: Limpieza automática de la rama del bot/feature
                gh pr merge "$pr_number" --auto --squash --delete-branch

                echo "⏳ La orden ha sido enviada. GitHub fusionará cuando los tests pasen."
                echo "🔄 Esperando para sincronizar el 'Golden SHA'..."

                # ==============================================================================
                # FASE 3 (NUEVO): Espera real a que el PR quede MERGED + captura mergeCommit SHA
                # ==============================================================================
                local merge_sha
                merge_sha="$(wait_for_pr_merge_and_get_sha "$pr_number")"

                # Sincronizar dev exactamente con origin/dev y validar SHA
                sync_branch_to_origin "dev" "origin"

                # A veces el mergeCommit tarda un instante en reflejarse en origin/dev.
                # Reintentamos un poco si no coincide inmediatamente.
                local dev_sha
                dev_sha="$(git rev-parse HEAD 2>/dev/null || true)"

                if [[ -n "${merge_sha:-}" && "$dev_sha" != "$merge_sha" ]]; then
                    log_warn "origin/dev aún no refleja el mergeCommit. Reintentando sincronización..."
                    local tries=0
                    local max_tries=30
                    local interval="${DEVTOOLS_PR_MERGE_POLL_SECONDS:-5}"

                    while [[ "$dev_sha" != "$merge_sha" && "$tries" -lt "$max_tries" ]]; do
                        sleep "$interval"
                        sync_branch_to_origin "dev" "origin"
                        dev_sha="$(git rev-parse HEAD 2>/dev/null || true)"
                        tries=$((tries + 1))
                    done
                fi

                dev_sha="$(git rev-parse HEAD 2>/dev/null || true)"

                # Persistir GOLDEN_SHA (fuente: PR merge)
                if [[ -n "${merge_sha:-}" && "$dev_sha" == "$merge_sha" ]]; then
                    write_golden_sha "$merge_sha" "source=pr_merge pr=$pr_number" || true
                    log_success "✅ GOLDEN_SHA capturado: $merge_sha"
                else
                    # Si no pudimos validar contra merge_sha, igual guardamos el HEAD de dev como golden,
                    # porque es la verdad del remoto (pero lo avisamos).
                    write_golden_sha "$dev_sha" "source=origin/dev pr=$pr_number note=merge_sha_mismatch" || true
                    log_warn "⚠️ No coincidió mergeCommit con origin/dev a tiempo. Guardando HEAD de dev como GOLDEN_SHA: $dev_sha"
                fi

                banner "✅ PR FUSIONADO Y DEV SINCRONIZADO"
                echo "👌 Estás en 'dev' con el Golden SHA."
                echo "👉 Siguiente paso sugerido: git promote staging"
                exit 0
            fi
        fi
    fi
    # --------------------------------------------------------------------------
    # FIN NUEVA LÓGICA
    # --------------------------------------------------------------------------

    if [[ "$current_branch" == "dev" || "$current_branch" == "staging" || "$current_branch" == "main" ]]; then
        log_error "Estás en '$current_branch'. Debes estar en una feature branch."
        exit 1
    fi
    log_warn "🚧 PROMOCIÓN A DEV (Destructiva)"
    if ! ask_yes_no "¿Aplastar 'dev' con '$current_branch'?"; then exit 0; fi

    resync_submodules_hard
    ensure_clean_git

    update_branch_from_remote "dev" "origin" "true"
    git reset --hard "$current_branch"
    git push origin dev --force
    log_success "✅ Dev actualizado."
    
    # [FIX] Ahora terminamos en DEV, no en la feature branch
    git checkout dev

    # ==============================================================================
    # FASE 3 (NUEVO): Guardar GOLDEN_SHA en modo destructivo (dev = feature SHA)
    # ==============================================================================
    local dev_sha
    dev_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${dev_sha:-}" ]]; then
        write_golden_sha "$dev_sha" "source=force_reset from=$current_branch" || true
        log_success "✅ GOLDEN_SHA capturado: $dev_sha"
    fi
}

promote_to_staging() {
    resync_submodules_hard
    ensure_clean_git
    local current
    current="$(git branch --show-current)"
    if [[ "$current" != "dev" ]]; then
        log_warn "No estás en 'dev'. Cambiando..."
        update_branch_from_remote "dev"
    fi

    # ==============================================================================
    # FASE 3 (NUEVO): Validar GOLDEN_SHA en DEV antes de promover
    # ==============================================================================
    assert_golden_sha_matches_head_or_die "DEV (antes de promover a STAGING)" || exit 1

    log_info "🔍 Comparando Dev -> Staging"
    generate_ai_prompt "dev" "origin/staging"

    # ==============================================================================
    # FASE 2 (NUEVO): SI GITHUB TAGGEA EN STAGING, NO TAGGEAR LOCALMENTE
    # ==============================================================================
    # Si existe workflow tag-rc-on-staging.{yml,yaml} en este repo, GitHub será el dueño del tag RC.
    # En ese caso, hacemos solo:
    #   dev -> staging (ff-only) + push de staging
    # y dejamos que GitHub cree el tag vX.Y.Z-rcN.
    if ! should_tag_locally_for_staging; then
        echo
        log_info "🏷️  Tagger detectado en GitHub (tag-rc-on-staging)."
        log_info "   Este repo delega la creación del RC tag a GitHub Actions."
        log_info "   (Override: DEVTOOLS_FORCE_LOCAL_TAGS=1 para forzar tag local)"
        echo

        if ! ask_yes_no "¿Promover a STAGING (sin crear tag local)?"; then exit 0; fi
        ensure_clean_git
        update_branch_from_remote "staging"
        git merge --ff-only dev

        # ==============================================================================
        # FASE 3 (NUEVO): Asegurar mismo SHA (staging == dev == golden)
        # ==============================================================================
        local staging_sha dev_sha
        staging_sha="$(git rev-parse HEAD 2>/dev/null || true)"
        dev_sha="$(git rev-parse dev 2>/dev/null || true)"
        if [[ -n "${dev_sha:-}" && -n "${staging_sha:-}" && "$staging_sha" != "$dev_sha" ]]; then
            log_error "FF-only merge no resultó en el mismo SHA (staging != dev). Abortando."
            echo "   dev    : $dev_sha"
            echo "   staging: $staging_sha"
            exit 1
        fi

        git push origin staging
        log_success "✅ Staging actualizado. (RC tag lo creará GitHub Actions)"
        return 0
    fi
    
    # [FIX] Inicializar variable para evitar error 'unbound variable' en strict mode
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    
    capture_release_notes "$tmp_notes"
    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }
    
    # 1. Obtener versión base desde archivo VERSION (fuente de verdad)
    local version_file="${SCRIPT_DIR}/../VERSION"

    # --- FASE 1 (NUEVO): Preferir VERSION del repo actual (REPO_ROOT/VERSION) ---
    # Esto evita leer .devtools/VERSION cuando .devtools está embebido en apps/submódulos.
    local __resolved_version_file
    __resolved_version_file="$(resolve_repo_version_file)"
    if [[ -n "${__resolved_version_file:-}" ]]; then
        version_file="${__resolved_version_file}"
    fi

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

    # --- FASE 1 (NUEVO): GitHub es el dueño de la versión ---
    # Por defecto NO recalculamos versión en local (evita drift con release-please).
    # Si algún día quieres “solo sugerir” basado en commits, activa:
    #   DEVTOOLS_SUGGEST_VERSION_FROM_COMMITS=1
    if [[ "${DEVTOOLS_SUGGEST_VERSION_FROM_COMMITS:-0}" == "1" ]]; then
        if command -v calculate_next_version >/dev/null; then
            next_ver=$(calculate_next_version "$base_ver")
            if [[ "$next_ver" != "$base_ver" ]]; then
                log_info "🧠 Cálculo automático: $base_ver -> $next_ver (según commits)"
            else
                log_info "🧠 Cálculo automático: Sin cambios mayores detectados."
            fi
        fi
    else
        log_info "🤖 Versionado gestionado por GitHub: usando $base_ver desde VERSION (sin recalcular)."
    fi

    # 3. Calcular RC sobre la versión objetivo
    local rc_num
    rc_num="$(next_rc_number "$next_ver")"
    local suggested_tag="v${next_ver}-rc${rc_num}"
    
    # 4. Opción de Override Manual
    echo
    log_info "🔖 Tag sugerido: $suggested_tag"
    local rc_tag=""
    read -r -p "Presiona ENTER para usar '$suggested_tag' o escribe tu versión manual: " rc_tag
    rc_tag="${rc_tag:-$suggested_tag}"

    prepend_release_notes_header "$tmp_notes" "Release Notes - ${rc_tag} (Staging)"
    
    if ! ask_yes_no "¿Desplegar a STAGING con tag $rc_tag?"; then exit 0; fi

    resync_submodules_hard
    ensure_clean_git

    update_branch_from_remote "staging"
    git merge --ff-only dev

    # ==============================================================================
    # FASE 3 (NUEVO): Asegurar mismo SHA (staging == dev == golden)
    # ==============================================================================
    local staging_sha dev_sha
    staging_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    dev_sha="$(git rev-parse dev 2>/dev/null || true)"
    if [[ -n "${dev_sha:-}" && -n "${staging_sha:-}" && "$staging_sha" != "$dev_sha" ]]; then
        log_error "FF-only merge no resultó en el mismo SHA (staging != dev). Abortando."
        echo "   dev    : $dev_sha"
        echo "   staging: $staging_sha"
        exit 1
    fi

    git tag -a "$rc_tag" -F "$tmp_notes"
    git push origin staging
    git push origin "$rc_tag"
    log_success "✅ Staging actualizado ($rc_tag)."
}

promote_to_prod() {
    resync_submodules_hard
    ensure_clean_git
    local current
    current="$(git branch --show-current)"
    if [[ "$current" != "staging" ]]; then
        log_warn "No estás en 'staging'. Cambiando..."
        update_branch_from_remote "staging"
    fi

    # ==============================================================================
    # FASE 3 (NUEVO): Validar GOLDEN_SHA en STAGING antes de promover
    # ==============================================================================
    assert_golden_sha_matches_head_or_die "STAGING (antes de promover a MAIN)" || exit 1

    log_info "🚀 PROMOCIÓN A PRODUCCIÓN"
    generate_ai_prompt "staging" "origin/main"

    # ==============================================================================
    # FASE 2 (NUEVO): SI GITHUB TAGGEA EN MAIN, NO TAGGEAR LOCALMENTE
    # ==============================================================================
    # Si existe workflow tag-final-on-main.{yml,yaml} en este repo, GitHub será el dueño del tag final.
    # En ese caso, hacemos solo:
    #   staging -> main (ff-only) + push de main
    # y dejamos que GitHub cree el tag vX.Y.Z.
    if ! should_tag_locally_for_prod; then
        echo
        log_info "🏷️  Tagger detectado en GitHub (tag-final-on-main)."
        log_info "   Este repo delega la creación del tag final a GitHub Actions."
        log_info "   (Override: DEVTOOLS_FORCE_LOCAL_TAGS=1 para forzar tag local)"
        echo

        if ! ask_yes_no "¿Promover a PRODUCCIÓN (sin crear tag local)?"; then exit 0; fi
        ensure_clean_git
        update_branch_from_remote "main"
        git merge --ff-only staging

        # ==============================================================================
        # FASE 3 (NUEVO): Asegurar mismo SHA (main == staging == golden)
        # ==============================================================================
        local main_sha staging_sha
        main_sha="$(git rev-parse HEAD 2>/dev/null || true)"
        staging_sha="$(git rev-parse staging 2>/dev/null || true)"
        if [[ -n "${staging_sha:-}" && -n "${main_sha:-}" && "$main_sha" != "$staging_sha" ]]; then
            log_error "FF-only merge no resultó en el mismo SHA (main != staging). Abortando."
            echo "   staging: $staging_sha"
            echo "   main   : $main_sha"
            exit 1
        fi

        git push origin main
        log_success "✅ Producción actualizada. (Tag final lo creará GitHub Actions)"
        return 0
    fi
    
    # [FIX] Inicializar variable para evitar error 'unbound variable' en strict mode
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    
    capture_release_notes "$tmp_notes"
    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }
    
    # 1. Obtener versión base desde archivo
    local version_file="${SCRIPT_DIR}/../VERSION"

    # --- FASE 1 (NUEVO): Preferir VERSION del repo actual (REPO_ROOT/VERSION) ---
    local __resolved_version_file
    __resolved_version_file="$(resolve_repo_version_file)"
    if [[ -n "${__resolved_version_file:-}" ]]; then
        version_file="${__resolved_version_file}"
    fi

    local base_ver
    if [[ -f "$version_file" ]]; then
        base_ver=$(cat "$version_file" | tr -d '[:space:]')
    else
        base_ver=$(get_current_version)
    fi

    # 2. Calcular versión sugerida (generalmente en prod es la base, pero verificamos)
    local next_ver="$base_ver"

    # --- FASE 1 (NUEVO): GitHub es el dueño de la versión ---
    # Por defecto NO recalculamos versión en local (evita drift con release-please).
    if [[ "${DEVTOOLS_SUGGEST_VERSION_FROM_COMMITS:-0}" == "1" ]]; then
        if command -v calculate_next_version >/dev/null; then
            next_ver=$(calculate_next_version "$base_ver")
        fi
    else
        log_info "🤖 Versionado gestionado por GitHub: usando $base_ver desde VERSION (sin recalcular)."
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

    resync_submodules_hard
    ensure_clean_git

    update_branch_from_remote "main"
    git merge --ff-only staging

    # ==============================================================================
    # FASE 3 (NUEVO): Asegurar mismo SHA (main == staging == golden)
    # ==============================================================================
    local main_sha staging_sha
    main_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    staging_sha="$(git rev-parse staging 2>/dev/null || true)"
    if [[ -n "${staging_sha:-}" && -n "${main_sha:-}" && "$main_sha" != "$staging_sha" ]]; then
        log_error "FF-only merge no resultó en el mismo SHA (main != staging). Abortando."
        echo "   staging: $staging_sha"
        echo "   main   : $main_sha"
        exit 1
    fi

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

    resync_submodules_hard
    ensure_clean_git

    update_branch_from_remote "main"
    git checkout -b "$hf_branch"
    log_success "✅ Rama hotfix creada: $hf_branch"
}

finish_hotfix() {
    local current
    current="$(git branch --show-current)"
    [[ "$current" != hotfix/* ]] && { log_error "No estás en una rama hotfix."; exit 1; }

    resync_submodules_hard
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
