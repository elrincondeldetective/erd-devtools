#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/strategies/dev-pr-monitor.sh
#
# Estrategia: PR Monitor & Interactive Dashboard.
# FASES:
# 1. Discovery (Búsqueda de PRs)
# 2. Visualization (Dashboard de estado)
# 3. Interaction (Aprobación, Merge o Skip)
# 4. Post-Processing (Release Please & Golden SHA)
#
# Dependencias: utils.sh, helpers/gh-interactions.sh, git-ops.sh

# Intentar cargar prompts UI si existen
if [[ -n "${_PROMOTE_LIB_ROOT:-}" && -f "${_PROMOTE_LIB_ROOT}/../ui/prompts.sh" ]]; then
    source "${_PROMOTE_LIB_ROOT}/../ui/prompts.sh"
elif [[ -f "lib/ui/prompts.sh" ]]; then
    source "lib/ui/prompts.sh"
fi

# ==============================================================================
# HELPER LOCAL: STREAMING DE LOGS (La "TV" de GitHub)
# ==============================================================================
stream_branch_activity() {
    local branch="$1"
    local context="$2"
    
    echo
    log_info "📺 [LIVE] Buscando actividad en rama '$branch' ($context)..."
    echo "   (Esperando 5s para que GitHub despierte...)"
    sleep 5

    # Buscamos el run más reciente en esta rama que esté en progreso o queued
    local run_id
    run_id="$(GH_PAGER=cat gh run list --branch "$branch" --limit 1 --json databaseId,status --jq '.[0] | select(.status != "completed") | .databaseId' 2>/dev/null)"

    if [[ -n "$run_id" ]]; then
        log_info "🎥 Conectando a logs en vivo (Run ID: $run_id)..."
        # --exit-status hace que el comando falle si el CI falla, lo cual es lo que queremos saber
        if GH_PAGER=cat gh run watch "$run_id" --exit-status; then
            log_success "✅ CI completado exitosamente."
        else
            log_error "❌ El CI falló. Revisa los logs arriba."
            # No matamos el script aquí, dejamos que el usuario decida o que el chequeo final falle
        fi
    else
        log_warn "ℹ️  No se detectaron workflows activos inmediatos en '$branch'."
    fi
    echo
}

promote_dev_monitor() {
    local input_pr="${1:-}"      # PR sugerido por to-dev.sh (si existe)
    local input_branch="${2:-}"  # Rama origen

    banner "🕵️  MONITOR DE INTEGRACIÓN (Interactivo)"

    # --------------------------------------------------------------------------
    # 1. Fase de Descubrimiento (Discovery)
    # --------------------------------------------------------------------------
    local pr_candidates=()
    
    if [[ -n "${DEVTOOLS_TARGET_PRS:-}" ]]; then
        for p in $DEVTOOLS_TARGET_PRS; do pr_candidates+=("$p"); done
    elif [[ -n "$input_pr" ]]; then
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
        # A) Data Gathering profundo
        local json_details
        json_details="$(gh_get_pr_rich_details "$pr_id")"
        
        # B) Renderizado visual
        ui_render_pr_card "$json_details"
        
        # C) Detalle de checks resumido
        echo "   🔎 Detalles de CI/Checks:"
        gh_get_pr_checks_summary "$pr_id" | sed 's/^/      /'
        echo ""
    done

    # --------------------------------------------------------------------------
    # 3. BUCLE INTERACTIVO (ACTION LOOP)
    # --------------------------------------------------------------------------
    local something_merged=0
    
    # Definimos fallback de lectura si prompts.sh no cargó
    if ! declare -F ui_read_option >/dev/null; then
        ui_read_option() { read -r -p "$1" val </dev/tty; echo "$val"; }
    fi

    echo "────────────────────────────────────────────────────────────────────────────────"
    log_info "🕹️  INICIO DE MODO INTERACTIVO"
    
    for pr_id in "${pr_candidates[@]}"; do
        while true; do
            echo
            echo "👉 ACCIÓN REQUERIDA para PR #$pr_id:"
            echo "   [a] ✅ Aprobar (solo review)"
            echo "   [m] 🤖 Merge (Auto-Squash)  ← dispara CI en dev"
            echo "   [f] ☢️  Reset --hard + Force Push a dev  ← admin bypass"
            echo "   [s] ⏭️  Saltar"
            echo "   [v] 📄 Ver detalles completos (checks/jobs/runners)"
            echo "   [r] 🔄 Refrescar estado"
            echo "   [q] 🚪 Cancelar y Salir"
            
            local choice
            choice="$(ui_read_option "   Opción [a/m/f/s/v/r/q] > ")"

            case "$choice" in
                a|A)
                    if gh_approve_pr_and_validate "$pr_id"; then
                        # Solo intentamos watch si existe CI en PR (si no hay, no colgarse)
                        gh_watch_pr_ci "$pr_id" "Post-Approve CI" || true
                    else
                        log_warn "ℹ️ No se pudo aprobar (posible: no puedes aprobar tu propio PR). Usa [m] o [f]."
                    fi
                    break
                    ;;

                m|M)
                    log_info "🤖 Configurando Auto-Merge (Squash + Delete Branch)..."
                    # Si eres admin y necesitas bypass de reglas: export DEVTOOLS_MERGE_ADMIN_BYPASS=1
                    local merge_cmd=(pr merge "$pr_id" --auto --squash --delete-branch)
                    [[ "${DEVTOOLS_MERGE_ADMIN_BYPASS:-0}" == "1" ]] && merge_cmd+=(--admin)
                    if GH_PAGER=cat gh "${merge_cmd[@]}" 2>&1; then
                        log_info "⏳ Esperando que GitHub complete el merge..."
                        stream_branch_activity "dev" "Merge Check"
                        local m_sha
                        m_sha="$(wait_for_pr_merge_and_get_sha "$pr_id")"
                        log_success "✅ Merge completado: ${m_sha:0:7}"
                        something_merged=1
                        break
                    else
                        log_error "❌ Falló auto-merge. Revisa permisos/reglas. Alternativa: [f] Force Push."
                    fi
                    ;;

                f|F)
                    echo
                    log_warn "☢️  FORCE PUSH (Reset --hard + Push) a origin/dev"
                    echo "   Esto sobreescribe dev con el SHA de tu rama actual."
                    local confirm
                    confirm="$(ui_read_option "   Escribe 'force' para proceder > ")"
                    if [[ "$confirm" == "force" ]]; then
                        local sha
                        sha="$(git rev-parse HEAD)"
                        log_info "🔥 Forzando dev => ${sha:0:7}"
                        if force_update_branch_to_sha "dev" "$sha" "origin"; then
                            log_success "✅ dev actualizado por force push."
                            log_info "🧹 Cerrando PR #$pr_id (opcional)..."
                            GH_PAGER=cat gh pr close "$pr_id" --delete-branch 2>&1 || true
                            stream_branch_activity "dev" "Post-Force-Push Build"
                            something_merged=1
                            break
                        else
                            log_error "❌ Falló el force push. Verifica permisos/branch protection."
                        fi
                    else
                        log_info "🧯 Operación cancelada."
                    fi
                    ;;
                    
                s|S)
                    log_info "⏭️  PR #$pr_id Saltado."
                    break 
                    ;;
                    
                v|V)
                    ui_show_pr_details_full "$pr_id"
                    ;;

                r|R)
                    log_info "🔄 Refrescando PR #$pr_id..."
                    local fresh; fresh="$(gh_get_pr_rich_details "$pr_id")"
                    ui_render_pr_card "$fresh"
                    echo "   🔎 Detalles de CI/Checks:"
                    gh_get_pr_checks_summary "$pr_id" | sed 's/^/      /'
                    ;;
                    
                q|Q)
                    log_warn "👋 Operación cancelada por el usuario. Saliendo."
                    return 0
                    ;;
                    
                *)
                    echo "❌ Opción no válida."
                    ;;
            esac
        done
    done

    # --------------------------------------------------------------------------
    # 4. POST-PROCESAMIENTO (BOT & GOLDEN SHA)
    # --------------------------------------------------------------------------

    if [[ "$something_merged" == "0" ]]; then
        log_info "ℹ️  No se realizaron cambios en dev. Finalizando."
        return 0
    fi

    log_info "🔄 Actualizando referencias post-merge..."

    # A) Gestión del Bot Release Please (Opcional)
    local rp_pr=""
    local post_rp=0

    if repo_has_workflow_file "release-please"; then
        log_info "🤖 Escaneando actividad de 'release-please'..."

        # Intentamos ver si el workflow arrancó para mostrar logs
        local rp_wf_id
        rp_wf_id="$(GH_PAGER=cat gh run list --workflow release-please.yml --limit 1 --json databaseId,status --jq '.[0] | select(.status != "completed") | .databaseId' 2>/dev/null)"
        
        if [[ -n "$rp_wf_id" ]]; then
             log_info "📺 Viendo logs de Release Please (ID: $rp_wf_id)..."
             GH_PAGER=cat gh run watch "$rp_wf_id"
        fi

        # Buscar el PR resultante
        rp_pr="$(wait_for_release_please_pr_number_optional)"
        
        if [[ "${rp_pr:-}" =~ ^[0-9]+$ ]]; then
            post_rp=1
            banner "🤖 PR DE RELEASE DETECTADO: #$rp_pr"
            
            # Verificamos estado del PR del bot antes de preguntar
            local rp_status
            rp_status="$(gh_get_pr_rich_details "$rp_pr")"
            ui_render_pr_card "$rp_status"
            
            local bot_choice
            bot_choice="$(ui_read_option "   ¿Auto-mergear PR del bot #$rp_pr ahora? [Y/n] > ")"
            if [[ "$bot_choice" =~ ^[Yy] || -z "$bot_choice" ]]; then
                log_info "🤖 Auto-mergeando bot (release-please)..."
                GH_PAGER=cat gh pr merge "$rp_pr" --auto --squash
                
                # Streaming del merge del bot
                stream_branch_activity "dev" "Release Please Merge"
                
                wait_for_pr_merge_and_get_sha "$rp_pr" >/dev/null
                log_success "✅ Bot mergeado."
            else
                log_info "⏭️  Bot saltado."
            fi
        else
            log_info "ℹ️  No se detectó PR de release-please (o timeout). Continuando."
        fi
    fi

    # B) Captura del GOLDEN SHA (Estado final de Dev)
    local dev_sha
    dev_sha="$(__remote_head_sha "dev" "origin")"
    
    if [[ -z "${dev_sha:-}" ]]; then
        # Fallback de seguridad
        git fetch origin dev >/dev/null 2>&1
        dev_sha="$(git rev-parse origin/dev)"
    fi

    if [[ -z "${dev_sha:-}" ]]; then
        log_error "❌ No pude resolver 'origin/dev'. No se puede actualizar Golden SHA."
        return 1
    fi

    # C) Verificar Build Final en Dev (Critical Safety Check)
    if repo_has_workflow_file "build-push"; then
            # El streaming ya debió mostrarnos los logs, pero esto asegura éxito rotundo
            wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$dev_sha" "dev" "Build Final (Dev)"
    fi

    # D) Escribir Golden SHA
    write_golden_sha "$dev_sha" "source=origin/dev interactive=true post_rp=${post_rp}" || true
    log_success "✅ GOLDEN_SHA actualizado: $dev_sha"
    
    # E) Trigger GitOps (Si aplica)
    local changed_paths
    changed_paths="$(git diff --name-only "${dev_sha}~1..${dev_sha}" 2>/dev/null || true)"
    maybe_trigger_gitops_update "dev" "$dev_sha" "$changed_paths"

    banner "✨ PROMOCIÓN A DEV FINALIZADA CON ÉXITO"
    echo "👉 Siguiente paso recomendado: git promote staging"
    
    return 0
}