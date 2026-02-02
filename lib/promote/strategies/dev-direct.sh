#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/strategies/dev-direct.sh
#
# ⚠️ Seguridad: el modo directo/aplastante debe ser exclusivo de feature/dev-update.
# Estrategia de promoción DIRECTA a DEV.
# - promote_to_dev_direct: Aplasta (squash/reset) feature -> dev y hace push directo.
# - promote_dev_direct_monitor: Monitorea CI/CD y Release Please tras el push.
#
# Dependencias esperadas:
# - utils.sh, git-ops.sh (cargadas por el orquestador)
# - helpers/gh-interactions.sh (para __remote_head_sha, __watch_workflow_success..., etc.)

# ------------------------------------------------------------------------------
# Monitor: Post-Push Directo
# ------------------------------------------------------------------------------
promote_dev_direct_monitor() {
    # Args: pre_bot_sha (sha del push directo a dev), feature_branch (informativo)
    local pre_bot_sha="${1:-}"
    local feature_branch="${2:-}"

    [[ -n "${pre_bot_sha:-}" ]] || { log_error "dev-direct-monitor: falta SHA."; return 1; }

    log_info "🧠 DEV monitor (direct) iniciado (sha=${pre_bot_sha:0:7}${feature_branch:+, branch=$feature_branch})"

    # 1. Versionado (Bot) - Estado 2
    local rp_pr=""
    local rp_merge_sha=""
    local post_rp=0

    if repo_has_workflow_file "release-please"; then
        log_info "🤖 Release Please detectado. Esperando ejecución en GitHub Actions..."
        # Esperamos que el workflow de release-please corra sobre el commit que acabamos de pushear
        __watch_workflow_success_on_sha_or_die "release-please.yaml" "$pre_bot_sha" "dev" "Release Please" || return 1

        log_info "🤖 Verificando si el bot creó un PR de release..."
        rp_pr="$(wait_for_release_please_pr_number_optional || true)"

        if [[ "${rp_pr:-}" =~ ^[0-9]+$ ]]; then
            post_rp=1
            log_info "🤖 PR del bot detectado (#$rp_pr). Procesando..."
            
            # [CRITICAL] Merge sin borrar la rama (NO usamos --delete-branch)
            # La limpieza se hará únicamente en git promote staging.
            GH_PAGER=cat gh pr merge "$rp_pr" --auto --squash

            log_info "🔄 Esperando merge del PR del bot #$rp_pr..."
            rp_merge_sha="$(wait_for_pr_merge_and_get_sha "$rp_pr")"
            log_success "✅ PR bot mergeado. Nuevo SHA: ${rp_merge_sha:0:7}"
            
            # Avisar explícitamente que la rama queda viva
            log_info "ℹ️  La rama release-please--* se conserva hasta la promoción a Staging."
        else
            log_success "✅ Sin versionado pendiente (Bot no creó PR o no hay cambios de versión)."
        fi
    else
        log_success "✅ Este repo no usa release-please."
    fi

    # 2. Determinar el SHA Final (SHA final remoto)
    # Si hubo bot merge, el HEAD es nuevo (rp_merge_sha). Si no, es el pre_bot_sha.
    # Obtenemos la verdad absoluta desde el remoto.
    local final_dev_sha
    final_dev_sha="$(__remote_head_sha "dev" "origin")"
    
    if [[ -z "${final_dev_sha:-}" ]]; then
        log_error "No pude resolver origin/dev final para capturar SHA final."
        return 1
    fi

    # 3. Build (CI) - Estado 3
    # Ejecutamos build sobre el SHA final (sea el de feature o el del bot)
    if repo_has_workflow_file "build-push"; then
        log_info "🏗️  Verificando Build & Push para el SHA final: ${final_dev_sha:0:7}"
        __watch_workflow_success_on_sha_or_die "build-push.yaml" "$final_dev_sha" "dev" "Build and Push" || return 1
    else
        log_success "✅ Sin build: este repo no tiene workflow build-push."
    fi

    # GitOps (no invasivo)
    local changed_paths
    changed_paths="$(git diff --name-only "${final_dev_sha}~1..${final_dev_sha}" 2>/dev/null || true)"
    maybe_trigger_gitops_update "dev" "$final_dev_sha" "$changed_paths"

    echo
    log_success "✅ DEV listo. SHA final: ${final_dev_sha:0:7}"
    log_info "🔎 Confirmación visual (git ls-remote --heads origin dev):"
    git ls-remote --heads origin dev 2>/dev/null || true
    echo

    echo "👉 Siguiente paso: git promote staging"
    return 0
}

# ------------------------------------------------------------------------------
# Main Strategy: Direct Promote
# ------------------------------------------------------------------------------
promote_to_dev_direct() {
    resync_submodules_hard
    ensure_clean_git_or_die

    # 🔒 HARDCODE: Solo permitido desde feature/dev-update (Lab -> Source of Truth)
    if [[ "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" != "feature/dev-update" ]]; then
        die "⛔ El modo directo/aplastante solo está permitido desde feature/dev-update."
    fi

    local feature_branch
    feature_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH}"

    if [[ -z "${feature_branch:-}" || "$feature_branch" == "(detached)" ]]; then
        feature_branch="$(git branch --show-current 2>/dev/null || echo "")"
    fi

    if [[ -z "${feature_branch:-}" ]]; then
        log_error "No pude detectar la rama actual."
        exit 1
    fi

    if [[ "$feature_branch" == "dev" || "$feature_branch" == "staging" || "$feature_branch" == "main" ]]; then
        log_error "Estás en '$feature_branch'. Debes estar en una feature branch."
        exit 1
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "Se requiere 'gh' para observar Actions/Issues en modo directo."
        exit 1
    fi

    banner "🧨 PROMOTE DEV (APLASTANTE / RESET HARD)"
    log_info "Fuente: $feature_branch"

    # Preparar dev local tracking + actualizar desde remoto
    ensure_local_tracking_branch "dev" "origin" || { log_error "No pude preparar 'dev' desde 'origin/dev'."; exit 1; }
    update_branch_from_remote "dev"

    local dev_before
    dev_before="$(git rev-parse HEAD 2>/dev/null || true)"

    # --- CAMBIO ESTRATÉGICO: Promoción Aplastante (Reset Hard) ---
    log_info "🧨 Aplicando reset hard: dev -> ${feature_branch}"
    if ! git reset --hard "$feature_branch"; then
        log_error "Fallo crítico al aplicar reset --hard. Restaurando dev..."
        git reset --hard "$dev_before" >/dev/null 2>&1 || true
        exit 1
    fi

    # Si por alguna razón el reset no generó diferencias con el remoto (raro en aplastante)
    if git diff origin/dev..HEAD --quiet; then
        log_warn "No hay cambios para promover (origin/dev ya coincide con la fuente)."

        local current_dev_sha
        current_dev_sha="$(__remote_head_sha "dev" "origin")"
        if [[ -z "${current_dev_sha:-}" ]]; then
            git fetch origin dev >/dev/null 2>&1 || true
            current_dev_sha="$(git rev-parse origin/dev 2>/dev/null || true)"
        fi

        echo
        log_info "🔎 Confirmación visual (git ls-remote --heads origin dev):"
        git ls-remote --heads origin dev 2>/dev/null || true
        echo

        [[ -n "${current_dev_sha:-}" ]] && log_info "✅ origin/dev @${current_dev_sha:0:7}"
        echo "👉 Siguiente paso: git promote staging"
        # Aterrizaje obligatorio en dev según requerimiento
        exit 0
    fi
    
    # --- NO-REGRESIÓN: Preservamos la creación de commit de integración si se desea ---
    # Nota: En reset --hard el commit ya existe, pero si el usuario quiere un commit de "promote" 
    # encima para trazabilidad, se puede hacer, aunque lo estándar en reset es usar el de la fuente.
    # Aquí cumplimos el landing en DESTINO.

    # Push directo a dev (con reintento de no-regresión)
    log_info "📡 Pusheando dev a origin (force-with-lease)..."
    if ! git push origin dev --force-with-lease; then
        log_warn "Push rechazado. Reintentando una vez (refetch + re-reset)..."
        git fetch origin dev >/dev/null 2>&1 || true
        git checkout dev >/dev/null 2>&1 || true
        git reset --hard "$feature_branch" || { log_error "Reintento falló. Revisa manualmente."; exit 1; }
        git push origin dev --force-with-lease || { log_error "No pude pushear dev (después de reintento)."; exit 1; }
    fi
    log_success "✅ Dev actualizado (push aplastante)."

    # --- NUEVA LÓGICA: Borrado opcional de fuente ---
    if declare -F maybe_delete_source_branch >/dev/null; then
        maybe_delete_source_branch "$feature_branch"
    fi

    # --- ATERRIZAJE: Quedamos en dev ---
    git checkout dev >/dev/null 2>&1 || true

    # Capturar SHA del push (pre-bot) y monitorear
    local pre_bot_sha
    pre_bot_sha="$(__remote_head_sha "dev" "origin")"
    [[ -n "${pre_bot_sha:-}" ]] || { log_error "No pude resolver origin/dev post-push."; exit 1; }

    promote_dev_direct_monitor "$pre_bot_sha" "$feature_branch"
    exit $?
}