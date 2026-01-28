#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows.sh
#
# Este módulo contiene los flujos de trabajo principales:
# - promote_sync_all (Smart Sync)
# - promote_dev_update_squash
# - promote_to_dev (incluye auto-merge de PRs + Bot Release Please)
# - promote_to_staging
# - promote_to_prod
# - create_hotfix / finish_hotfix

# Dependencias implícitas (deben ser cargadas por el script principal):
# - utils.sh, config.sh, git-ops.sh, release-flow.sh
# - promote/version-strategy.sh
# - promote/golden-sha.sh
# - promote/gitops-integration.sh

# [FIX] Solución de raíz: re-sincronizar submódulos para evitar estados dirty falsos
resync_submodules_hard() {
  git submodule sync --recursive >/dev/null 2>&1 || true
  git submodule update --init --recursive >/dev/null 2>&1 || true
}

# Helper para limpieza de ramas de release-please (NUEVO)
cleanup_bot_branches() {
    local mode="${1:-prompt}" # prompt | auto
    
    log_info "🧹 Buscando ramas de 'release-please' fusionadas para limpiar..."
    
    # Fetch para asegurar que la lista remota está fresca
    git fetch origin --prune

    # Buscamos ramas remotas que cumplan:
    # 1. Estén totalmente fusionadas en HEAD (staging/dev)
    # 2. Coincidan con el patrón del bot
    local branches_to_clean
    branches_to_clean=$(git branch -r --merged HEAD | grep 'origin/release-please--' | sed 's/origin\///' || true)

    if [[ -z "$branches_to_clean" ]]; then
        log_info "✨ No hay ramas de bot pendientes de limpieza."
        return 0
    fi

    echo "🔍 Se encontraron las siguientes ramas de bot fusionadas:"
    echo "$branches_to_clean"
    echo

    # Modo automático (sin prompts): requerido para mantener el repo limpio al promover a staging
    if [[ "$mode" == "auto" ]]; then
        log_info "🧹 Limpieza automática activada (sin confirmación)."
        for branch in $branches_to_clean; do
            log_info "🔥 Eliminando remote: $branch"
            git push origin --delete "$branch" || log_warn "No se pudo borrar $branch (tal vez ya no existe)."
        done
        log_success "🧹 Limpieza completada."
        return 0
    fi

    if ask_yes_no "¿Eliminar estas ramas remotas para mantener la limpieza?"; then
        for branch in $branches_to_clean; do
            log_info "🔥 Eliminando remote: $branch"
            git push origin --delete "$branch" || log_warn "No se pudo borrar $branch (tal vez ya no existe)."
        done
        log_success "🧹 Limpieza completada."
    else
        log_warn "Omitiendo limpieza de ramas."
    fi
}

# ==============================================================================
# 1. SMART SYNC (Con Auto-Absorción)
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
        ensure_local_tracking_branch "$target" "origin" || {
            log_error "No pude preparar la rama '$target' desde 'origin/$target'."
            exit 1
        }
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
# 2. SQUASH MERGE HACIA feature/dev-update
# ==============================================================================
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
# 3. PROMOTE TO DEV
# ==============================================================================
promote_to_dev() {
    # [FIX] Resync de submódulos antes de cualquier validación (ensure_clean_git)
    resync_submodules_hard

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
                # FASE 3: Espera real a que el PR quede MERGED + captura mergeCommit SHA
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

                # ==============================================================================
                # FASE 4: Disparar update-gitops-manifests con el GOLDEN_SHA
                # ==============================================================================
                local changed_paths
                changed_paths="$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)"
                maybe_trigger_gitops_update "dev" "$dev_sha" "$changed_paths"

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
    ensure_clean_git

    # ==============================================================================
    # FASE 4: Capturar paths cambiados ANTES del reset destructivo
    # ==============================================================================
    local __gitops_changed_paths
    __gitops_changed_paths="$(git diff --name-only "origin/dev..${current_branch}" 2>/dev/null || true)"

    update_branch_from_remote "dev" "origin" "true"
    git reset --hard "$current_branch"
    git push origin dev --force
    log_success "✅ Dev actualizado."
    
    # [FIX] Ahora terminamos en DEV, no en la feature branch
    git checkout dev

    # ==============================================================================
    # FASE 3: Guardar GOLDEN_SHA en modo destructivo (dev = feature SHA)
    # ==============================================================================
    local dev_sha
    dev_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "${dev_sha:-}" ]]; then
        write_golden_sha "$dev_sha" "source=force_reset from=$current_branch" || true
        log_success "✅ GOLDEN_SHA capturado: $dev_sha"
    fi

    # ==============================================================================
    # FASE 4: Disparar update-gitops-manifests con el GOLDEN_SHA
    # ==============================================================================
    if [[ -n "${dev_sha:-}" ]]; then
        maybe_trigger_gitops_update "dev" "$dev_sha" "$__gitops_changed_paths"
    fi
}

# ==============================================================================
# 4. PROMOTE TO STAGING
# ==============================================================================
promote_to_staging() {
    # [FIX] Resync de submódulos antes de cualquier validación (ensure_clean_git)
    resync_submodules_hard
    ensure_clean_git

    local current
    current="$(git branch --show-current)"
    if [[ "$current" != "dev" ]]; then
        log_warn "No estás en 'dev'. Cambiando..."
        ensure_local_tracking_branch "dev" "origin" || { log_error "No pude preparar la rama 'dev' desde 'origin/dev'."; exit 1; }
        update_branch_from_remote "dev"
    fi

    # ==============================================================================
    # FASE 3: Validar GOLDEN_SHA en DEV antes de promover
    # ==============================================================================
    assert_golden_sha_matches_head_or_die "DEV (antes de promover a STAGING)" || exit 1

    # Capturamos SHA actual para el Build Inmutable
    local golden_sha
    golden_sha="$(git rev-parse HEAD)"
    local short_sha="${golden_sha:0:7}"

    log_info "🔍 Comparando Dev -> Staging"
    generate_ai_prompt "dev" "origin/staging"

    # ==============================================================================
    # FASE EXTRA: BUILD LOCAL DEL GOLDEN SHA (Para garantizar el artefacto)
    # ==============================================================================
    # Intentamos encontrar el Taskfile raíz, priorizando el WORKSPACE_ROOT (superproyecto)
    local root_taskfile=""
    if [[ -n "${WORKSPACE_ROOT:-}" && -f "${WORKSPACE_ROOT}/Taskfile.yaml" ]]; then
        root_taskfile="${WORKSPACE_ROOT}/Taskfile.yaml"
    elif [[ -f "${REPO_ROOT}/Taskfile.yaml" ]]; then
        root_taskfile="${REPO_ROOT}/Taskfile.yaml"
    elif [[ -f "${REPO_ROOT}/../Taskfile.yaml" ]]; then
        root_taskfile="${REPO_ROOT}/../Taskfile.yaml"
    fi

    if [[ -n "$root_taskfile" ]]; then
        echo
        log_info "🏗️  Generando BUILD local para asegurar Golden SHA (sha-$short_sha)..."
        local task_dir
        task_dir="$(dirname "$root_taskfile")"
        
        # Ejecutamos el build específicamente para este SHA usando el Taskfile encontrado
        # Usamos subshell para no cambiar el directorio actual del script
        (cd "$task_dir" && task app:build APP=pmbok-backend TAG="sha-$short_sha") || exit 1
        (cd "$task_dir" && task app:build APP=pmbok-frontend TAG="sha-$short_sha") || exit 1
        
        log_success "✅ Builds generados con tag: sha-$short_sha"
    else
        log_warn "⚠️ No se encontró Taskfile.yaml en la raíz. Omitiendo Build local."
    fi

    # ==============================================================================
    # FASE 4 (MEJORA): Capturar paths cambiados completos (dev -> origin/staging)
    # ==============================================================================
    git fetch origin staging >/dev/null 2>&1 || true
    local __gitops_changed_paths
    __gitops_changed_paths="$(git diff --name-only "origin/staging..dev" 2>/dev/null || true)"

    # ==============================================================================
    # FASE 2 (HÍBRIDA): DECISIÓN MANUAL VS AUTOMÁTICA
    # ==============================================================================
    local use_remote_tagger=0
    
    # Verificamos si existe el workflow en GitHub
    if ! should_tag_locally_for_staging; then
        echo
        log_info "🤖 Se detectó automatización en GitHub (tag-rc-on-staging)."
        echo "   El sistema puede calcular el siguiente RC automáticamente."
        echo
        echo "   Opciones:"
        echo "     [Y] Sí (Auto):   Solo empujar cambios. GitHub crea el tag (vX.Y.Z-rcN)."
        echo "     [N] No (Manual): Quiero definir el tag yo mismo ahora."
        echo
        
        if ask_yes_no "¿Delegar el tagging a GitHub?"; then
            use_remote_tagger=1
        else
            log_warn "🖐️  Modo Manual activado: Tú tienes el control."
            use_remote_tagger=0
        fi
    fi

    # --- CAMINO A: AUTOMÁTICO (Solo Push) ---
    if [[ "$use_remote_tagger" == "1" ]]; then
        ensure_clean_git
        ensure_local_tracking_branch "staging" "origin" || { log_error "No pude preparar la rama 'staging' desde 'origin/staging'."; exit 1; }
        update_branch_from_remote "staging"
        git merge --ff-only dev

        # Validar SHA
        local staging_sha dev_sha
        staging_sha="$(git rev-parse HEAD 2>/dev/null || true)"
        dev_sha="$(git rev-parse dev 2>/dev/null || true)"
        if [[ -n "${dev_sha:-}" && -n "${staging_sha:-}" && "$staging_sha" != "$dev_sha" ]]; then
            log_error "FF-only merge no resultó en el mismo SHA (staging != dev). Abortando."
            exit 1
        fi

        git push origin staging
        log_success "✅ Staging actualizado. (GitHub Actions creará el tag RC en breve)."

        # ==============================================================================
        # FASE 5: LIMPIEZA DE RAMAS DEL BOT (Auto)
        # ==============================================================================
        cleanup_bot_branches auto

        # Disparar GitOps
        local changed_paths
        changed_paths="${__gitops_changed_paths:-$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)}"
        maybe_trigger_gitops_update "staging" "$staging_sha" "$changed_paths"

        return 0
    fi
    
    # --- CAMINO B: MANUAL (El código original continúa aquí abajo) ---
    
    local tmp_notes
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    
    capture_release_notes "$tmp_notes"
    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }
    
    # 1. Obtener versión base desde archivo VERSION (fuente de verdad)
    local version_file
    version_file="$(resolve_repo_version_file)"

    local base_ver
    if [[ -f "$version_file" ]]; then
        base_ver=$(cat "$version_file" | tr -d '[:space:]')
        log_info "📄 Versión actual en archivo: $base_ver"
    else
        base_ver=$(get_current_version) # Fallback
    fi

    # 2. Calcular SIGUIENTE versión basada en commits
    local next_ver="$base_ver"
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
    
    if ! ask_yes_no "¿Desplegar a STAGING con tag $rc_tag?"; then 
        # Si el usuario cancela, limpiamos el trap para no borrar archivos random
        rm -f "$tmp_notes"
        trap - EXIT
        exit 0
    fi

    ensure_clean_git
    update_branch_from_remote "staging"
    git merge --ff-only dev

    # ==============================================================================
    # FASE 3: Asegurar mismo SHA (staging == dev == golden)
    # ==============================================================================
    local staging_sha dev_sha
    staging_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    dev_sha="$(git rev-parse dev 2>/dev/null || true)"
    if [[ -n "${dev_sha:-}" && -n "${staging_sha:-}" && "$staging_sha" != "$dev_sha" ]]; then
        # Limpieza antes de salir por error
        rm -f "$tmp_notes"
        trap - EXIT
        log_error "FF-only merge no resultó en el mismo SHA (staging != dev). Abortando."
        echo "   dev    : $dev_sha"
        echo "   staging: $staging_sha"
        exit 1
    fi

    git tag -a "$rc_tag" -F "$tmp_notes"
    git push origin staging
    git push origin "$rc_tag"
    log_success "✅ Staging actualizado ($rc_tag)."

    # [FIX] CRASH FIX: Limpiamos archivo y quitamos trap ANTES de que la variable local muera
    rm -f "$tmp_notes"
    trap - EXIT

    # ==============================================================================
    # FASE 5: LIMPIEZA DE RAMAS DEL BOT (Manual)
    # ==============================================================================
    cleanup_bot_branches auto

    # ==============================================================================
    # FASE 4: Disparar update-gitops-manifests para STAGING
    # ==============================================================================
    local changed_paths
    changed_paths="${__gitops_changed_paths:-$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)}"
    maybe_trigger_gitops_update "staging" "$staging_sha" "$changed_paths"
}

# ==============================================================================
# 5. PROMOTE TO PROD
# ==============================================================================
promote_to_prod() {
    # [FIX] Resync de submódulos antes de cualquier validación (ensure_clean_git)
    resync_submodules_hard
    ensure_clean_git

    local current
    current="$(git branch --show-current)"
    if [[ "$current" != "staging" ]]; then
        log_warn "No estás en 'staging'. Cambiando..."
        ensure_local_tracking_branch "staging" "origin" || { log_error "No pude preparar la rama 'staging' desde 'origin/staging'."; exit 1; }
        update_branch_from_remote "staging"
    fi

    # Capturar paths completos para GitOps (staging -> origin/main)
    git fetch origin main >/dev/null 2>&1 || true
    local __gitops_changed_paths
    __gitops_changed_paths="$(git diff --name-only "origin/main..staging" 2>/dev/null || true)"

    # ==============================================================================
    # FASE 3: Validar GOLDEN_SHA en STAGING antes de promover
    # ==============================================================================
    assert_golden_sha_matches_head_or_die "STAGING (antes de promover a MAIN)" || exit 1

    log_info "🚀 PROMOCIÓN A PRODUCCIÓN"
    generate_ai_prompt "staging" "origin/main"

    # ==============================================================================
    # FASE 2 (CORREGIDA): Tags por defecto SOLO por GitHub Actions (si existe tagger).
    # - Si NO hay tagger en el repo actual, por defecto NO se crea tag final (consumer mode).
    # - Para permitir tag local manual (legacy): DEVTOOLS_ALLOW_LOCAL_TAGS=1 y DEVTOOLS_ENFORCE_GH_TAGS=0
    # ==============================================================================
    local allow_local_tags="${DEVTOOLS_ALLOW_LOCAL_TAGS:-0}"
    local enforce_gh_tags="${DEVTOOLS_ENFORCE_GH_TAGS:-1}"

    # Si hay tagger en GitHub (tag-final-on-main), no taggeamos localmente
    if ! should_tag_locally_for_prod; then
        echo
        log_info "🏷️  Tagger detectado en GitHub (tag-final-on-main)."
        log_info "   Este repo delega la creación del tag final a GitHub Actions."
        echo

        if ! ask_yes_no "¿Promover a PRODUCCIÓN (sin crear tag local)?"; then exit 0; fi
        ensure_clean_git
        ensure_local_tracking_branch "main" "origin" || { log_error "No pude preparar la rama 'main' desde 'origin/main'."; exit 1; }
        update_branch_from_remote "main"
        git merge --ff-only staging

        # ==============================================================================
        # FASE 3: Asegurar mismo SHA (main == staging == golden)
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

        # ==============================================================================
        # FASE 4: Disparar update-gitops-manifests para MAIN
        # ==============================================================================
        local changed_paths
        changed_paths="${__gitops_changed_paths:-$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)}"
        maybe_trigger_gitops_update "main" "$main_sha" "$changed_paths"

        return 0
    fi

    # Si NO hay tagger, por defecto NO tageamos (consumer mode), salvo legacy override
    if [[ "$allow_local_tags" != "1" || "$enforce_gh_tags" == "1" ]]; then
        log_warn "🏷️  No se detectó tagger (tag-final-on-main). Continuando SIN tag final (consumer mode)."
        log_warn "     (Override legacy: DEVTOOLS_ALLOW_LOCAL_TAGS=1 y DEVTOOLS_ENFORCE_GH_TAGS=0)"
        ensure_clean_git
        ensure_local_tracking_branch "main" "origin" || { log_error "No pude preparar la rama 'main' desde 'origin/main'."; exit 1; }
        update_branch_from_remote "main"
        git merge --ff-only staging

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
        log_success "✅ Producción actualizada (sin tag final)."

        local changed_paths
        changed_paths="${__gitops_changed_paths:-$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)}"
        maybe_trigger_gitops_update "main" "$main_sha" "$changed_paths"

        return 0
    fi
    
    # --- CAMINO LEGACY: TAG LOCAL MANUAL (solo si está permitido) ---
    # [FIX] Inicializar variable para evitar error 'unbound variable' en strict mode
    local tmp_notes
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT
    
    capture_release_notes "$tmp_notes"
    [[ ! -s "$tmp_notes" ]] && { log_error "Notas vacías."; exit 1; }
    
    # 1. Obtener versión base desde archivo
    local version_file
    version_file="$(resolve_repo_version_file)"

    local base_ver
    if [[ -f "$version_file" ]]; then
        base_ver=$(cat "$version_file" | tr -d '[:space:]')
    else
        base_ver=$(get_current_version)
    fi

    # 2. Calcular versión sugerida
    local next_ver="$base_ver"

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
    if ! ask_yes_no "¿Confirmar pase a Producción ($release_tag)?"; then 
        rm -f "$tmp_notes"
        trap - EXIT
        exit 0
    fi

    ensure_clean_git
    ensure_local_tracking_branch "main" "origin" || { log_error "No pude preparar la rama 'main' desde 'origin/main'."; exit 1; }
    update_branch_from_remote "main"
    git merge --ff-only staging

    # ==============================================================================
    # FASE 3: Asegurar mismo SHA (main == staging == golden)
    # ==============================================================================
    local main_sha staging_sha
    main_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    staging_sha="$(git rev-parse staging 2>/dev/null || true)"
    if [[ -n "${staging_sha:-}" && -n "${main_sha:-}" && "$main_sha" != "$staging_sha" ]]; then
        rm -f "$tmp_notes"
        trap - EXIT
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
    
    # [FIX] CRASH FIX para Prod también
    rm -f "$tmp_notes"
    trap - EXIT

    # ==============================================================================
    # FASE 4: Disparar update-gitops-manifests para MAIN
    # ==============================================================================
    local changed_paths
    changed_paths="${__gitops_changed_paths:-$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)}"
    maybe_trigger_gitops_update "main" "$main_sha" "$changed_paths"
}

# ==============================================================================
# 6. HOTFIX WORKFLOWS
# ==============================================================================
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
    local current
    current="$(git branch --show-current)"
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
