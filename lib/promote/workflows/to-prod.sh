#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-prod.sh
#
# Este módulo maneja la promoción a PRODUCCIÓN:
# - promote_to_prod: Fusiona staging -> main.
# - Maneja 3 estrategias de tagging:
#   1. Remote (GitHub Actions crea el tag).
#   2. Consumer (Sin tag, solo despliegue).
#   3. Manual (Tag local legacy).
#
# Dependencias: utils.sh, git-ops.sh, checks.sh, common.sh

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
    print_golden_sha_report "Antes de promover a MAIN (en STAGING)"

    local staging_sha
    staging_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    if [[ -z "${staging_sha:-}" ]]; then
        log_error "No pude resolver SHA de STAGING (HEAD)."
        exit 1
    fi

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
        
        local from_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$current}"
        log_info "📍 Estás en '${from_branch}'. 🧨 Sobrescribiendo historia de 'main' con 'staging' (${staging_sha})..."
        force_update_branch_to_sha "main" "$staging_sha" "origin" || { log_error "No pude sobrescribir 'main' con SHA ${staging_sha:0:7}."; exit 1; }
        local main_sha="$staging_sha"
        log_success "✅ Producción actualizada (overwrite)."

        # Verificación explícita: origin/main == staging_sha (== GOLDEN_SHA)
        git fetch origin main >/dev/null 2>&1 || true
        local origin_main
        origin_main="$(git rev-parse origin/main 2>/dev/null || true)"
        if [[ "$origin_main" != "$staging_sha" ]]; then
            log_error "main mismatch: origin/main=${origin_main:0:7} != staging=${staging_sha:0:7}"
            exit 1
        fi
        log_success "✅ Confirmado: origin/main == STAGING_SHA == GOLDEN_SHA (${staging_sha:0:7})"
        print_tags_at_sha "$main_sha" "tags@origin/main(${main_sha:0:7})"

        # Esperar tag final + build del tag (solo si este repo tiene el tagger)
        if repo_has_workflow_file "tag-final-on-main"; then
            local ver
            ver="$(__read_repo_version 2>/dev/null || true)"
            if [[ -n "${ver:-}" ]]; then
                local final_pattern="^v${ver}$"
                local final_tag
                final_tag="$(wait_for_tag_on_sha_or_die "$main_sha" "$final_pattern" "Final tag")"
                print_tags_at_sha "$main_sha" "tags@sha (post final)"
                if repo_has_workflow_file "build-push"; then
                    wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$main_sha" "$final_tag" "Build and Push (tag final)"
                fi
            fi
        fi

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
        
        local from_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$current}"
        log_info "📍 Estás en '${from_branch}'. 🧨 Sobrescribiendo historia de 'main' con 'staging' (${staging_sha})..."
        force_update_branch_to_sha "main" "$staging_sha" "origin" || { log_error "No pude sobrescribir 'main' con SHA ${staging_sha:0:7}."; exit 1; }
        local main_sha="$staging_sha"
        log_success "✅ Producción actualizada (overwrite, sin tag final)."
        print_tags_at_sha "$main_sha" "tags@origin/main(${main_sha:0:7})"

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
    local from_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$current}"
    log_info "📍 Estás en '${from_branch}'. 🧨 Sobrescribiendo historia de 'main' con 'staging' (${staging_sha})..."
    force_update_branch_to_sha "main" "$staging_sha" "origin" || { rm -f "$tmp_notes"; trap - EXIT; log_error "No pude sobrescribir 'main' con SHA ${staging_sha:0:7}."; exit 1; }
    local main_sha="$staging_sha"

    if git rev-parse "$release_tag" >/dev/null 2>&1; then
        log_warn "Tag $release_tag ya existe."
    else
        git tag -a "$release_tag" -F "$tmp_notes"
        git push origin "$release_tag"
    fi
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