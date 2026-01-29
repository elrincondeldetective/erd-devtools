#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/strategies/dev-pr-monitor.sh
#
# Estrategia: PR Monitor & Interactive Dashboard.
# FASES:
# 1. Discovery (Búsqueda de PRs)
# 2. Visualization (Dashboard de estado)
# 3. Interaction (Aprobación, Merge o FORCE PUSH)
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
    
    if [[ -n "$input_pr" ]]; then
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
        gh_get_pr_checks_summary "$pr_id" | sed 's/^/      /' | head -n 10
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
            echo "   [a] ✅ Aprobar y Mergear (Auto-Squash)"
            echo "   [f] ☢️  FORCE PUSH (Ignorar PR y Sobreescribir 'dev')"
            echo "   [s] ⏭️  Saltar (Ignorar por ahora)"
            echo "   [v] 📄 Ver detalles completos (gh view)"
            echo "   [q] 🚪 Cancelar y Salir"
            
            local choice
            choice="$(ui_read_option "   Opción [a/f/s/v/q] > ")"

            case "$choice" in
                a|A)
                    log_info "🚀 Procesando PR #$pr_id..."
                    
                    # 1. Aprobar (Review)
                    log_info "👍 Enviando aprobación (APPROVE)..."
                    if ! gh pr review "$pr_id" --approve; then
                        log_warn "⚠️  No se pudo aprobar (¿Quizás ya aprobaste o eres el autor?). Intentando continuar..."
                    fi

                    # 2. Habilitar Auto-Merge
                    log_info "🤖 Configurando Auto-Merge (Squash + Delete Branch)..."
                    if GH_PAGER=cat gh pr merge "$pr_id" --auto --squash --delete-branch; then
                        log_info "⏳ Esperando que GitHub complete el merge..."
                        
                        # STREAMING: Ver logs mientras se mergea
                        stream_branch_activity "dev" "Merge Check"
                        
                        # 3. Monitorear hasta que el merge ocurra (doble check)
                        local m_sha
                        m_sha="$(wait_for_pr_merge_and_get_sha "$pr_id")"
                        log_success "✅ Merge completado exitosamente: ${m_sha:0:7}"
                        
                        something_merged=1
                        break 
                    else
                        log_error "❌ Falló auto-merge. Revisa permisos/conflictos o usa [f] Force Push."
                    fi
                    ;;

                f|F)
                    # OPCIÓN NUCLEAR: Ignora el PR y fuerza el estado actual a dev
                    echo
                    log_warn "☢️  ALERTA NUCLEAR: FORCE PUSH"
                    echo "   Esto tomará tu rama actual (HEAD) y SOBREESCRIBIRÁ 'origin/dev'."
                    echo "   - Se ignorarán conflictos (tu código gana)."
                    echo "   - El PR se cerrará automáticamente."
                    echo
                    local confirm
                    confirm="$(ui_read_option "   ¿ESTÁS SEGURO? Escribe 'force' para proceder > ")"
                    
                    if [[ "$confirm" == "force" ]]; then
                        log_info "🔥 Ejecutando: git push origin HEAD:dev --force ..."
                        if git push origin HEAD:dev --force; then
                            log_success "✅ 'dev' ha sido aplastado con éxito."
                            
                            something_merged=1 
                            
                            # Limpieza: Cerramos el PR ya que hicimos bypass
                            # [FIX] Silenciamos output de error por si ya estaba cerrado
                            log_info "🧹 Limpiando PR #$pr_id..."
                            gh pr close "$pr_id" --delete-branch >/dev/null 2>&1 || true
                            
                            # STREAMING: Ver logs inmediatamente después del force push
                            stream_branch_activity "dev" "Post-Force-Push Build"
                            
                            break
                        else
                            log_error "❌ Falló el force push. Verifica tus permisos."
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
                    GH_PAGER=less gh pr view "$pr_id"
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