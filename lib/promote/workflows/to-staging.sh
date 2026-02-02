#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-staging.sh
#
# Helper local: respeta -y/--yes (DEVTOOLS_ASSUME_YES=1) para prompts humanos.
# Gates técnicos (Golden / waits / releases) NO se saltan.
__confirm_or_yes() {
    [[ "${DEVTOOLS_ASSUME_YES:-0}" == "1" ]] && return 0
    ask_yes_no "$1"
}

# Este módulo maneja la promoción a STAGING:
# - promote_to_staging: Fusiona dev -> staging.
# - Valida Golden SHA.
# - Gestiona tagging (RC) automático o manual.
# - Limpia ramas de bots.
#
# Dependencias: utils.sh, git-ops.sh, checks.sh, common.sh

# ==============================================================================
# 4. PROMOTE TO STAGING
# ==============================================================================
promote_to_staging() {
    # [FIX] Resync de submódulos antes de cualquier validación (ensure_clean_git)
    resync_submodules_hard
    ensure_clean_git

    local current
    current="$(git branch --show-current)"
    # Siempre trabajamos sobre un dev actualizado desde origin (HEAD real)
    ensure_local_tracking_branch "dev" "origin" || { log_error "No pude preparar la rama 'dev' desde 'origin/dev'."; exit 1; }
    if [[ "$(git branch --show-current)" != "dev" ]]; then
        log_warn "No estás en 'dev'. Cambiando..."
        git checkout dev >/dev/null 2>&1 || exit 1
    fi
    update_branch_from_remote "dev"

    print_golden_sha_report "Antes de promover a STAGING (en DEV)"
    # ==============================================================================
    # FASE 3: Validar GOLDEN_SHA en DEV antes de promover
    # ==============================================================================
    assert_golden_sha_matches_head_or_die "DEV (antes de promover a STAGING)" || exit 1

    # Capturamos SHA actual para el Build Inmutable
    local golden_sha
    golden_sha="$(git rev-parse HEAD)"
    log_info "✅ SHA canónico (DEV HEAD): ${golden_sha:0:7}"
    local short_sha="${golden_sha:0:7}"

    log_info "🔍 Comparando Dev -> Staging"
    generate_ai_prompt "dev" "origin/staging"

    # ==============================================================================
    # FASE EXTRA (CORREGIDA): Esperar build en CI del repo si existe (PMBOK sí, erd-ecosystem no)
    # ==============================================================================
    if repo_has_workflow_file "build-push"; then
        wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$golden_sha" "dev" "Build and Push"
    fi

    # ==============================================================================
    # FASE 4 (MEJORA): Capturar paths cambiados completos (dev -> origin/staging)
    # ==============================================================================
    # Esto evita perder cambios cuando dev avanzó >1 commit (HEAD~1..HEAD sería incompleto).
    git fetch origin staging >/dev/null 2>&1 || true
    local __gitops_changed_paths
    __gitops_changed_paths="$(git diff --name-only "origin/staging..dev" 2>/dev/null || true)"

    # ==============================================================================
    # FASE 2 (CORREGIDA): Tags por defecto SOLO por GitHub Actions (si existe tagger).
    # - Si NO hay tagger en el repo actual, por defecto NO se crean tags (consumer mode).
    # - Para permitir tags locales manuales (legacy): DEVTOOLS_ALLOW_LOCAL_TAGS=1
    # ==============================================================================
    local allow_local_tags="${DEVTOOLS_ALLOW_LOCAL_TAGS:-0}"
    local enforce_gh_tags="${DEVTOOLS_ENFORCE_GH_TAGS:-1}"
    local use_remote_tagger=0
    
    if ! should_tag_locally_for_staging; then
        # Tagger detectado en GitHub
        echo
        log_info "🤖 Se detectó automatización en GitHub (tag-rc-on-staging)."
        if [[ "$enforce_gh_tags" == "1" ]]; then
            log_info "🔒 Modo estricto: SOLO GitHub creará el tag RC (sin tagging local)."
            use_remote_tagger=1
        else
            echo "   Opciones:"
            echo "     [Y] Sí (Auto):    Solo empujar cambios. GitHub crea el tag (vX.Y.Z-rcN)."
            echo "     [N] No (Manual): Quiero definir el tag yo mismo ahora."
            echo
            # [FIX] Usar helper que respeta --yes
            if __confirm_or_yes "¿Delegar el tagging a GitHub?"; then
                use_remote_tagger=1
            else
                log_warn "🖐️  Modo Manual activado: Tú tienes el control."
                use_remote_tagger=0
            fi
        fi
    else
        # No hay tagger: por defecto NO tageamos (consumer mode)
        if [[ "$allow_local_tags" == "1" && "$enforce_gh_tags" != "1" ]]; then
            log_warn "🖐️  No hay tagger en GitHub. DEVTOOLS_ALLOW_LOCAL_TAGS=1 -> habilitando tagging manual local."
            use_remote_tagger=0
        else
            log_warn "🏷️  No se detectó tagger (tag-rc-on-staging). Continuando SIN tags (consumer mode)."
            log_warn "     (Override legacy: DEVTOOLS_ALLOW_LOCAL_TAGS=1 y DEVTOOLS_ENFORCE_GH_TAGS=0)"
            use_remote_tagger=1
        fi
    fi

    # --- CAMINO A: AUTOMÁTICO (Solo Push, tags por bot si existen) / O SIN TAGS (consumer mode) ---
    if [[ "$use_remote_tagger" == "1" ]]; then
        local from_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$current}"
        local strategy="${DEVTOOLS_PROMOTE_STRATEGY:-ff-only}"
        log_info "📍 Estás en '${from_branch}'. Estrategia: ${strategy}"

        local staging_sha=""
        local rc=0
        while true; do
            staging_sha="$(update_branch_to_sha_with_strategy "staging" "$golden_sha" "origin" "$strategy")"
            rc=$?
            if [[ "$rc" -eq 3 ]]; then
                log_warn "⚠️ Fast-Forward no es posible (hay divergencia en staging). Debes elegir otra opción."
                strategy="$(promote_choose_strategy_or_die)"
                export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
                continue
            fi
            [[ "$rc" -eq 0 ]] || { log_error "No pude actualizar 'staging' con estrategia ${strategy}."; exit 1; }
            break
        done

        log_success "✅ Staging actualizado. SHA final: ${staging_sha:0:7}"

        # Compat GOLDEN_SHA: si existe el módulo, lo actualizamos al SHA real desplegado en staging
        if declare -F write_golden_sha >/dev/null 2>&1; then
            write_golden_sha "$staging_sha" "auto: promote_to_staging strategy=${strategy} source=${golden_sha}" || true
        fi


        # Verificación explícita: origin/staging == staging_sha (sea FF/merge/force)
        git fetch origin staging >/dev/null 2>&1 || true
        local origin_staging
        origin_staging="$(git rev-parse origin/staging 2>/dev/null || true)"
        if [[ "$origin_staging" != "$staging_sha" ]]; then
            log_error "staging mismatch: origin/staging=${origin_staging:0:7} != local=${staging_sha:0:7}"
            exit 1
        fi
        log_success "✅ Confirmado: origin/staging == ${staging_sha:0:7}"
        print_tags_at_sha "$staging_sha" "tags@origin/staging(${staging_sha:0:7})"

        # Esperar RC tag + build del tag (solo si este repo tiene el tagger)
        if repo_has_workflow_file "tag-rc-on-staging"; then
            local ver
            ver="$(__read_repo_version 2>/dev/null || true)"
            if [[ -n "${ver:-}" ]]; then
                local rc_pattern="^v${ver}-rc[0-9]+$"
                local rc_tag
                rc_tag="$(wait_for_tag_on_sha_or_die "$staging_sha" "$rc_pattern" "RC tag")"
                # En este punto ya existe el tag sobre el SHA
                print_tags_at_sha "$staging_sha" "tags@sha (post RC)"
                if repo_has_workflow_file "build-push"; then
                    wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$staging_sha" "$rc_tag" "Build and Push (tag RC)"
                fi

                # Esperar GitHub Release (solo si este repo tiene release-on-tag)
                if repo_has_workflow_file "release-on-tag"; then
                    local timeout="${DEVTOOLS_RELEASE_WAIT_TIMEOUT_SECONDS:-900}"
                    local interval="${DEVTOOLS_RELEASE_WAIT_POLL_SECONDS:-5}"
                    local elapsed=0

                    log_info "🚀 Esperando GitHub Release para tag ${rc_tag}..."
                    while true; do
                        if GH_PAGER=cat gh release view "$rc_tag" --json url --jq '.url' >/dev/null 2>&1; then
                            local url
                            url="$(GH_PAGER=cat gh release view "$rc_tag" --json url --jq '.url' 2>/dev/null || true)"
                            [[ -n "${url:-}" && "${url:-null}" != "null" ]] && log_info "🔗 Release URL: ${url}"
                            log_success "✅ GitHub Release publicado para ${rc_tag}"
                            break
                        fi

                        if (( elapsed >= timeout )); then
                            log_error "Timeout esperando GitHub Release para ${rc_tag}."
                            log_error "⛔ Despliegue incompleto: el workflow release-on-tag no publicó el release."
                            return 1
                        fi

                        sleep "$interval"
                        elapsed=$((elapsed + interval))
                    done
                fi
            fi
        fi

        # ==============================================================================
        # FASE 5: LIMPIEZA DE RAMAS DEL BOT (Auto)
        # ==============================================================================
        cleanup_bot_branches auto

        # ==============================================================================
        # FASE EXTRA: Prompt para registrar cambios incluidos en esta integración a STAGING
        # (Se guarda en .git para NO ensuciar el working tree)
        # ==============================================================================
        if is_tty; then
            log_info "📝 Registra/Anota los cambios incluidos en esta integración a STAGING..."
            local gd
            gd="$(git rev-parse --git-dir 2>/dev/null || echo ".git")"
            [[ "$gd" != /* ]] && gd="${REPO_ROOT}/${gd}"
            mkdir -p "${gd}/devtools/staging-notes" >/dev/null 2>&1 || true
            local notes_file="${gd}/devtools/staging-notes/${staging_sha:0:7}-$(date -u '+%Y%m%dT%H%M%SZ').md"
            capture_release_notes "$notes_file"
            log_success "📝 Notas guardadas en: $notes_file"
        fi

        # Disparar GitOps
        local changed_paths
        changed_paths="${__gitops_changed_paths:-$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)}"
        maybe_trigger_gitops_update "staging" "$staging_sha" "$changed_paths"

        return 0
    fi
    
    # --- CAMINO B: MANUAL (Legacy / solo si está permitido) ---
    
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
    
    # [FIX] Usar helper que respeta --yes
    if ! __confirm_or_yes "¿Desplegar a STAGING con tag $rc_tag?"; then 
        # Si el usuario cancela, limpiamos el trap para no borrar archivos random
        rm -f "$tmp_notes"
        trap - EXIT
        exit 0
    fi

    local from_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$current}"
    local strategy="${DEVTOOLS_PROMOTE_STRATEGY:-ff-only}"
    log_info "📍 Estás en '${from_branch}'. Estrategia: ${strategy}"

    local staging_sha=""
    local rc=0
    while true; do
        staging_sha="$(update_branch_to_sha_with_strategy "staging" "$golden_sha" "origin" "$strategy")"
        rc=$?
        if [[ "$rc" -eq 3 ]]; then
            log_warn "⚠️ Fast-Forward no es posible (hay divergencia en staging). Debes elegir otra opción."
            strategy="$(promote_choose_strategy_or_die)"
            export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
            continue
        fi
        [[ "$rc" -eq 0 ]] || { log_error "No pude actualizar 'staging' con estrategia ${strategy}."; exit 1; }
        break
    done
    log_success "✅ Staging actualizado. SHA final: ${staging_sha:0:7}"

    if declare -F write_golden_sha >/dev/null 2>&1; then
        write_golden_sha "$staging_sha" "auto: promote_to_staging(strategy=${strategy}) source=${golden_sha}" || true
    fi

    # Esperar RC tag + build del tag (solo si este repo tiene el tagger)
    if repo_has_workflow_file "tag-rc-on-staging"; then
        local ver
        ver="$(__read_repo_version 2>/dev/null || true)"
        if [[ -n "${ver:-}" ]]; then
            local rc_pattern="^v${ver}-rc[0-9]+$"
            local rc_tag
            rc_tag="$(wait_for_tag_on_sha_or_die "$staging_sha" "$rc_pattern" "RC tag")"
            if repo_has_workflow_file "build-push"; then
                wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$staging_sha" "$rc_tag" "Build and Push (tag RC)"
            fi
        fi
    fi

    # ==============================================================================
    # FASE 5: LIMPIEZA DE RAMAS DEL BOT (Auto)
    # ==============================================================================
    cleanup_bot_branches auto

    # ==============================================================================
    # FASE EXTRA: Prompt para registrar cambios incluidos en esta integración a STAGING
    # (Se guarda en .git para NO ensuciar el working tree)
    # ==============================================================================
    if is_tty; then
        log_info "📝 Registra/Anota los cambios incluidos en esta integración a STAGING..."
        local gd
        gd="$(git rev-parse --git-dir 2>/dev/null || echo ".git")"
        [[ "$gd" != /* ]] && gd="${REPO_ROOT}/${gd}"
        mkdir -p "${gd}/devtools/staging-notes" >/dev/null 2>&1 || true
        local notes_file="${gd}/devtools/staging-notes/${staging_sha:0:7}-$(date -u '+%Y%m%dT%H%M%SZ').md"
        capture_release_notes "$notes_file"
        log_success "📝 Notas guardadas en: $notes_file"
    fi

    # Disparar GitOps
    local changed_paths
    changed_paths="${__gitops_changed_paths:-$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)}"
    maybe_trigger_gitops_update "staging" "$staging_sha" "$changed_paths"

    return 0
}