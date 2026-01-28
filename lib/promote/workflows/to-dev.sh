#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/to-dev.sh
#
# Este módulo maneja la promoción a DEV:
# - promote_to_dev: Crea/Mergea PRs, gestiona release-please y actualiza dev.
# - (Opcional) Modo directo: Squash local + Push directo a dev (sin PR).
#
# Dependencias: utils.sh, git-ops.sh, checks.sh (cargadas por el orquestador)

# ------------------------------------------------------------------------------
# Helpers NO invasivos (no hacen checkout/reset; safe para correr en background)
# ------------------------------------------------------------------------------
__remote_head_sha() {
    local branch="$1"
    local remote="${2:-origin}"
    git fetch "$remote" "$branch" >/dev/null 2>&1 || true
    git rev-parse "${remote}/${branch}" 2>/dev/null || true
}

__repo_name() { basename "${REPO_ROOT:-.}"; }

__resolve_promote_script() {
    # 1) Si viene del bin principal, SCRIPT_DIR existe y es confiable
    if [[ -n "${SCRIPT_DIR:-}" && -x "${SCRIPT_DIR}/git-promote.sh" ]]; then
        echo "${SCRIPT_DIR}/git-promote.sh"
        return 0
    fi

    # 2) Si estamos en un repo consumidor que tiene .devtools embebido
    if [[ -n "${REPO_ROOT:-}" && -x "${REPO_ROOT}/.devtools/bin/git-promote.sh" ]]; then
        echo "${REPO_ROOT}/.devtools/bin/git-promote.sh"
        return 0
    fi

    # 3) Si estamos dentro del repo .devtools (REPO_ROOT==.devtools)
    if [[ -n "${REPO_ROOT:-}" && -x "${REPO_ROOT}/bin/git-promote.sh" ]]; then
        echo "${REPO_ROOT}/bin/git-promote.sh"
        return 0
    fi

    # 4) Fallback
    echo "git-promote.sh"
}

# ------------------------------------------------------------------------------
# Helpers: encontrar y "ver" workflows en vivo (sin navegador)
# - Para TTY: usa gh run watch --exit-status
# - No-TTY: fallback al polling de checks.sh
# ------------------------------------------------------------------------------
__wait_for_workflow_run_id_for_sha() {
    # Args: workflow_file, sha_full, optional ref (branch/tag)
    local wf_file="$1"
    local sha_full="$2"
    local ref="${3:-}"

    local timeout="${DEVTOOLS_BUILD_WAIT_TIMEOUT_SECONDS:-1800}"
    local interval="${DEVTOOLS_BUILD_WAIT_POLL_SECONDS:-10}"
    local elapsed=0

    [[ -n "${wf_file:-}" && -n "${sha_full:-}" ]] || return 1

    while true; do
        local run_id=""

        if [[ -n "${ref:-}" ]]; then
            run_id="$(
              GH_PAGER=cat gh run list --workflow "$wf_file" --branch "$ref" -L 50 \
                --json databaseId,headSha,status,conclusion \
                --jq ".[] | select(.headSha==\"$sha_full\") | .databaseId" 2>/dev/null | head -n 1
            )"
        fi

        if [[ -z "${run_id:-}" ]]; then
            run_id="$(
              GH_PAGER=cat gh run list --workflow "$wf_file" -L 50 \
                --json databaseId,headSha,status,conclusion \
                --jq ".[] | select(.headSha==\"$sha_full\") | .databaseId" 2>/dev/null | head -n 1
            )"
        fi

        if [[ -n "${run_id:-}" ]]; then
            echo "$run_id"
            return 0
        fi

        if (( elapsed >= timeout )); then
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

__watch_workflow_success_on_sha_or_die() {
    # Args: workflow_file, sha_full, optional ref (branch/tag), label
    local wf_file="$1"
    local sha_full="$2"
    local ref="${3:-}"
    local label="${4:-workflow}"

    # Si el caller pide skip, respetamos (compat con checks.sh)
    if [[ "${DEVTOOLS_SKIP_WAIT_BUILD:-0}" == "1" ]]; then
        log_warn "DEVTOOLS_SKIP_WAIT_BUILD=1 -> Omitiendo espera de ${label}."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "No se encontró 'gh'. No puedo verificar ${label} en GitHub Actions."
        return 1
    fi

    # Modo TTY: progreso real en vivo
    if is_tty; then
        log_info "🏗️  Buscando run de ${label} (${wf_file}) para SHA ${sha_full:0:7}..."
        local run_id=""
        run_id="$(__wait_for_workflow_run_id_for_sha "$wf_file" "$sha_full" "$ref" || true)"
        if [[ -z "${run_id:-}" ]]; then
            log_error "Timeout esperando run de ${wf_file} para SHA ${sha_full:0:7}"
            return 1
        fi

        log_info "📺 Mostrando progreso en vivo: ${label} (run_id=$run_id)"
        if GH_PAGER=cat gh run watch "$run_id" --exit-status; then
            log_success "🏗️  ${label} OK (run_id=$run_id)"
            return 0
        fi

        log_error "${label} falló (run_id=$run_id)"
        return 1
    fi

    # No-TTY: fallback a polling centralizado
    wait_for_workflow_success_on_ref_or_sha_or_die "$wf_file" "$sha_full" "$ref" "$label"
}

# ------------------------------------------------------------------------------
# Modo DIRECTO (sin PR feature->dev):
# - Aplasta localmente (squash) feature -> dev, push directo a origin/dev
# - Observa release-please + build-push (si existen) y captura GOLDEN_SHA final
#
# Enable por repo (ej: PMBOK): DEVTOOLS_PROMOTE_DEV_DIRECT=1
# ------------------------------------------------------------------------------
promote_dev_direct_monitor() {
    # Args: pre_bot_sha (sha del push directo a dev), feature_branch (informativo)
    local pre_bot_sha="${1:-}"
    local feature_branch="${2:-}"

    [[ -n "${pre_bot_sha:-}" ]] || { log_error "dev-direct-monitor: falta SHA."; return 1; }

    log_info "🧠 DEV monitor (direct) iniciado (sha=${pre_bot_sha:0:7}${feature_branch:+, branch=$feature_branch})"

    # Estado 2: release-please (bot) si existe workflow
    local rp_pr=""
    local rp_merge_sha=""
    local post_rp=0

    if repo_has_workflow_file "release-please"; then
        log_info "🤖 Release Please detectado. Esperando ejecución en GitHub Actions..."
        __watch_workflow_success_on_sha_or_die "release-please.yaml" "$pre_bot_sha" "dev" "Release Please" || return 1

        log_info "🤖 Buscando PR del bot release-please hacia dev (opcional)..."
        rp_pr="$(wait_for_release_please_pr_number_optional || true)"

        if [[ "${rp_pr:-}" =~ ^[0-9]+$ ]]; then
            post_rp=1
            log_info "🤖 Habilitando auto-merge para PR del bot (#$rp_pr)..."
            GH_PAGER=cat gh pr merge "$rp_pr" --auto --squash

            log_info "🔄 Esperando merge del PR del bot #$rp_pr..."
            rp_merge_sha="$(wait_for_pr_merge_and_get_sha "$rp_pr")"
            log_success "PR bot mergeado: ${rp_merge_sha:0:7}"
        else
            log_success "✅ Sin versionado: no se detectó PR release-please--* (o timeout)."
        fi
    else
        log_success "✅ Sin versionado: este repo no tiene workflow release-please."
    fi

    # En este punto, el SHA “válido” es el HEAD remoto de dev (post-bot si existió)
    local dev_sha
    dev_sha="$(__remote_head_sha "dev" "origin")"
    if [[ -z "${dev_sha:-}" ]]; then
        log_error "No pude resolver origin/dev para capturar GOLDEN_SHA."
        return 1
    fi

    # Estado 3: build-push si existe
    if repo_has_workflow_file "build-push"; then
        __watch_workflow_success_on_sha_or_die "build-push.yaml" "$dev_sha" "dev" "Build and Push" || return 1
    else
        log_success "✅ Sin build: este repo no tiene workflow build-push."
    fi

    # Persistir GOLDEN_SHA (post-bot, y post-build si aplica)
    write_golden_sha "$dev_sha" "source=origin/dev post_release_please=${post_rp} feature_branch=${feature_branch:-none} rp_pr=${rp_pr:-none}" || true
    log_success "✅ GOLDEN_SHA capturado: $dev_sha"

    # GitOps (no invasivo)
    local changed_paths
    changed_paths="$(git diff --name-only "${dev_sha}~1..${dev_sha}" 2>/dev/null || true)"
    maybe_trigger_gitops_update "dev" "$dev_sha" "$changed_paths"

    # Issues pendientes (visibilidad)
    echo
    log_info "📌 Issues abiertos (top 10):"
    GH_PAGER=cat gh issue list --state open --limit 10 2>/dev/null || log_warn "No pude listar issues (¿gh auth?)."

    echo
    banner "✅ DEV LISTO"
    echo "SHA a promover: $dev_sha"
    echo "👉 Siguiente paso: git promote staging"
    return 0
}

promote_to_dev_direct() {
    resync_submodules_hard
    ensure_clean_git

    local feature_branch
    feature_branch="$(git branch --show-current 2>/dev/null || echo "")"

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

    banner "🧨 PROMOTE DEV (DIRECTO / SQUASH LOCAL)"
    log_info "Fuente: $feature_branch"

    # Preparar dev local tracking + actualizar desde remoto
    ensure_local_tracking_branch "dev" "origin" || { log_error "No pude preparar 'dev' desde 'origin/dev'."; exit 1; }
    update_branch_from_remote "dev"

    local dev_before
    dev_before="$(git rev-parse HEAD 2>/dev/null || true)"

    # Hacer squash merge de feature -> dev (sin PR)
    log_info "🧨 Aplicando squash local: ${feature_branch} -> dev"
    if ! git merge --squash -X theirs "$feature_branch"; then
        log_error "Conflictos en squash merge. Abortando."
        git merge --abort >/dev/null 2>&1 || true
        exit 1
    fi

    # Si no hay cambios staged, no hacemos commit/push; igual registramos golden como HEAD(dev).
    if git diff --cached --quiet; then
        log_warn "No hay cambios para promover (feature ya está reflejada en dev)."
        local current_dev_sha
        current_dev_sha="$(__remote_head_sha "dev" "origin")"
        if [[ -z "${current_dev_sha:-}" ]]; then
            log_error "No pude resolver origin/dev."
            exit 1
        fi
        write_golden_sha "$current_dev_sha" "source=origin/dev post_release_please=0 feature_branch=${feature_branch} note=no_changes" || true
        log_success "✅ GOLDEN_SHA capturado (sin cambios): $current_dev_sha"
        echo "👉 Siguiente paso: git promote staging"
        git checkout "$feature_branch" >/dev/null 2>&1 || true
        exit 0
    fi

    # Commit squash
    local title body
    title="promote(dev): squash ${feature_branch}"
    body="$(
      git log --pretty=format:'- %s (%h)' "${dev_before}..${feature_branch}" 2>/dev/null | head -n 50 || true
    )"
    [[ -n "${body:-}" ]] || body="(no commit list available)"

    git commit -m "$title" -m "$body"

    # Push directo a dev (sin prompts)
    log_info "📡 Pusheando dev a origin..."
    if ! git push origin dev; then
        log_warn "Push rechazado. Reintentando una vez (refetch + re-squash)..."
        git fetch origin dev >/dev/null 2>&1 || true
        git reset --hard origin/dev >/dev/null 2>&1 || true
        git merge --squash -X theirs "$feature_branch" || { log_error "Reintento falló. Revisa manualmente."; exit 1; }
        git commit -m "$title" -m "$body"
        git push origin dev || { log_error "No pude pushear dev (después de reintento)."; exit 1; }
    fi
    log_success "✅ Dev actualizado (push directo)."

    # Volver a la feature para que el dev pueda seguir trabajando
    git checkout "$feature_branch" >/dev/null 2>&1 || true

    # Capturar SHA del push (pre-bot) y monitorear bot/build hasta GOLDEN_SHA final
    local pre_bot_sha
    pre_bot_sha="$(__remote_head_sha "dev" "origin")"
    [[ -n "${pre_bot_sha:-}" ]] || { log_error "No pude resolver origin/dev post-push."; exit 1; }

    promote_dev_direct_monitor "$pre_bot_sha" "$feature_branch"
    exit $?
}

# ------------------------------------------------------------------------------
# Espera aprobación del PR (control humano)
# - Requiere al menos 1 review "APPROVED" (reviewDecision=APPROVED).
#
# Overrides:
# - DEVTOOLS_PR_APPROVAL_TIMEOUT_SECONDS=0  -> 0 = sin timeout (default).
# - DEVTOOLS_PR_APPROVAL_POLL_SECONDS=10    -> intervalo polling.
# - DEVTOOLS_SKIP_PR_APPROVAL_WAIT=1        -> bypass (no recomendado).
# ------------------------------------------------------------------------------
wait_for_pr_approval_or_die() {
    local pr_number="$1"
    local timeout="${DEVTOOLS_PR_APPROVAL_TIMEOUT_SECONDS:-0}"
    local interval="${DEVTOOLS_PR_APPROVAL_POLL_SECONDS:-10}"
    local elapsed=0

    if [[ "${DEVTOOLS_SKIP_PR_APPROVAL_WAIT:-0}" == "1" ]]; then
        log_warn "DEVTOOLS_SKIP_PR_APPROVAL_WAIT=1 -> Omitiendo espera de aprobación del PR."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "Se requiere 'gh' para verificar aprobación del PR."
        return 1
    fi

    log_info "⏳ Esperando aprobación del PR #$pr_number (reviewDecision=APPROVED)..."

    while true; do
        local state decision merged_at
        state="$(GH_PAGER=cat gh pr view "$pr_number" --json state --jq '.state // ""' 2>/dev/null || echo "")"
        decision="$(GH_PAGER=cat gh pr view "$pr_number" --json reviewDecision --jq '.reviewDecision // ""' 2>/dev/null || echo "")"
        merged_at="$(GH_PAGER=cat gh pr view "$pr_number" --json mergedAt --jq '.mergedAt // ""' 2>/dev/null || echo "")"

        # ✅ Si ya está mergeado, no tiene sentido esperar aprobación.
        if [[ -n "${merged_at:-}" && "${merged_at:-null}" != "null" ]]; then
            log_success "✅ PR #$pr_number ya está MERGED (mergedAt=$merged_at)."
            return 0
        fi

        if [[ "$decision" == "APPROVED" ]]; then
            log_success "✅ PR #$pr_number aprobado."
            return 0
        fi

        if [[ "$state" == "CLOSED" ]]; then
            log_error "El PR #$pr_number está CLOSED y no fue aprobado/mergeado. Abortando."
            return 1
        fi

        if (( timeout > 0 && elapsed >= timeout )); then
            log_error "Timeout esperando aprobación del PR #$pr_number."
            return 1
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

# ------------------------------------------------------------------------------
# Espera opcional por PR de release-please.
# - Devuelve el PR number si aparece.
# - Devuelve vacío si no aparece (sin error fatal).
#
# Overrides:
# - DEVTOOLS_RP_PR_WAIT_TIMEOUT_SECONDS=60  -> tiempo máximo de espera (0 = no esperar).
# - DEVTOOLS_RP_PR_WAIT_POLL_SECONDS=2      -> intervalo polling.
# ------------------------------------------------------------------------------
wait_for_release_please_pr_number_optional() {
    local timeout="${DEVTOOLS_RP_PR_WAIT_TIMEOUT_SECONDS:-60}"
    local interval="${DEVTOOLS_RP_PR_WAIT_POLL_SECONDS:-2}"
    local elapsed=0

    # 0 = no esperar, retorno vacío
    if [[ "${timeout}" == "0" ]]; then
        echo ""
        return 0
    fi

    while true; do
        local pr_number
        pr_number="$(
            GH_PAGER=cat gh pr list --base dev --state open --json number,headRefName --jq \
            '.[] | select(.headRefName | startswith("release-please--")) | .number' 2>/dev/null | head -n 1
        )"

        if [[ "${pr_number:-}" =~ ^[0-9]+$ ]]; then
            echo "$pr_number"
            return 0
        fi

        if (( elapsed >= timeout )); then
            echo ""
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
}

# ------------------------------------------------------------------------------
# Monitor: espera merges/builds y captura GOLDEN_SHA sin tocar tu worktree
# Uso interno: git promote _dev-monitor <feature_pr_number> [feature_branch]
# ------------------------------------------------------------------------------
promote_dev_monitor() {
    local feature_pr="${1:-}"
    local feature_branch="${2:-}"

    [[ -n "${feature_pr:-}" ]] || { log_error "dev-monitor: falta PR number."; return 1; }

    log_info "🧠 DEV monitor iniciado (PR #${feature_pr}${feature_branch:+, branch=$feature_branch})"

    # 0) Esperar aprobación humana antes de permitir merge
    wait_for_pr_approval_or_die "$feature_pr" || return 1

    # 1) Habilitar auto-merge SOLO cuando ya está aprobado
    log_info "🤖 PR aprobado. Habilitando auto-merge (checks + merge)..."
    GH_PAGER=cat gh pr merge "$feature_pr" --auto --squash --delete-branch

    # 2) Esperar merge real
    log_info "🔄 Esperando merge del PR #$feature_pr..."
    local merge_sha
    merge_sha="$(wait_for_pr_merge_and_get_sha "$feature_pr")"
    log_success "PR feature mergeado: ${merge_sha:0:7}"

    local rp_pr=""
    local rp_merge_sha=""
    local post_rp=0

    # Esperar PR del bot (release-please) si existe el workflow.
    # Importante: release-please puede decidir NO abrir PR si no hay bump; en ese caso seguimos.
    if repo_has_workflow_file "release-please"; then
        log_info "🤖 Esperando PR del bot release-please hacia dev (opcional)..."
        rp_pr="$(wait_for_release_please_pr_number_optional)"

        # ✅ SOLO si es numérico
        if [[ "${rp_pr:-}" =~ ^[0-9]+$ ]]; then
            post_rp=1
            log_info "🤖 Habilitando auto-merge para PR del bot (#$rp_pr)..."
            GH_PAGER=cat gh pr merge "$rp_pr" --auto --squash

            log_info "🔄 Esperando merge del PR del bot #$rp_pr..."
            rp_merge_sha="$(wait_for_pr_merge_and_get_sha "$rp_pr")"
            log_success "PR bot mergeado: ${rp_merge_sha:0:7}"
        else
            log_warn "🤷 No se detectó PR release-please--* (o timeout). Continuando."
        fi
    fi

    # En este punto, el SHA “válido” es el HEAD remoto de dev (post-bot si existió)
    local dev_sha
    dev_sha="$(__remote_head_sha "dev" "origin")"
    if [[ -z "${dev_sha:-}" ]]; then
        log_error "No pude resolver origin/dev para capturar GOLDEN_SHA."
        return 1
    fi

    # Esperar build-push en dev si existe en este repo
    if repo_has_workflow_file "build-push"; then
        wait_for_workflow_success_on_ref_or_sha_or_die "build-push.yaml" "$dev_sha" "dev" "Build and Push"
    fi

    write_golden_sha "$dev_sha" "source=origin/dev post_release_please=${post_rp} feature_pr=${feature_pr} rp_pr=${rp_pr:-none}" || true
    log_success "✅ GOLDEN_SHA (post-bot) capturado: $dev_sha"

    # GitOps (no invasivo): igual al comportamiento anterior (último commit), pero sin checkout
    local changed_paths
    changed_paths="$(git diff --name-only "${dev_sha}~1..${dev_sha}" 2>/dev/null || true)"
    maybe_trigger_gitops_update "dev" "$dev_sha" "$changed_paths"

    banner "✅ DEV LISTO (monitor finalizado)"
    echo "👉 Siguiente paso: git promote staging"
    return 0
}

# ==============================================================================
# 3. PROMOTE TO DEV
# ==============================================================================
promote_to_dev() {
    # [FIX] Resync de submódulos antes de cualquier validación (ensure_clean_git)
    resync_submodules_hard

    # Modo DIRECTO (sin PR): squash local feature->dev + push directo + monitor bloqueante
    if [[ "${DEVTOOLS_PROMOTE_DEV_DIRECT:-0}" == "1" ]]; then
        promote_to_dev_direct
        exit $?
    fi

    local current_branch
    current_branch="$(git branch --show-current)"

    if [[ "$current_branch" == "dev" || "$current_branch" == "staging" || "$current_branch" == "main" ]]; then
        log_error "Estás en '$current_branch'. Debes estar en una feature branch."
        exit 1
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_error "Se requiere 'gh' para el flujo PR-based (git promote dev crea el PR)."
        exit 1
    fi

    echo "🔍 Buscando (o creando) PR para '$current_branch' -> dev..."
    local pr_number
    pr_number="$(GH_PAGER=cat gh pr list --head "$current_branch" --base dev --state open --json number --jq '.[0].number' 2>/dev/null || true)"

    if [[ -z "${pr_number:-}" ]]; then
        ensure_clean_git
        GH_PAGER=cat gh pr create --base dev --head "$current_branch" --fill
        pr_number="$(GH_PAGER=cat gh pr list --head "$current_branch" --base dev --state open --json number --jq '.[0].number' 2>/dev/null || true)"
    fi

    if [[ -z "${pr_number:-}" ]]; then
        log_error "No pude resolver el PR para '$current_branch' -> dev."
        exit 1
    fi

    banner "🤖 PR LISTO (#$pr_number) -> dev"

    # Default: async (libera terminal).
    # Compat: DEVTOOLS_PROMOTE_DEV_SYNC=1 vuelve al modo bloqueante.
    local sync="${DEVTOOLS_PROMOTE_DEV_SYNC:-0}"
    if [[ "$sync" == "1" ]]; then
        promote_dev_monitor "$pr_number" "$current_branch"
        exit $?
    fi

    # Lanzar monitor en background SIN tocar tu working tree.
    local promote_cmd
    promote_cmd="$(__resolve_promote_script)"

    local repo_name log_file golden_file
    repo_name="$(basename "${REPO_ROOT:-.}")"
    log_file="${TMPDIR:-/tmp}/devtools-promote-dev-${repo_name}-pr${pr_number}.log"
    golden_file="$(resolve_golden_sha_file 2>/dev/null || echo ".last_golden_sha")"

    if command -v nohup >/dev/null 2>&1; then
        nohup "$promote_cmd" _dev-monitor "$pr_number" "$current_branch" >"$log_file" 2>&1 &
    else
        ( "$promote_cmd" _dev-monitor "$pr_number" "$current_branch" >"$log_file" 2>&1 ) &
    fi

    local pr_url
    pr_url="$(GH_PAGER=cat gh pr view "$pr_number" --json url --jq '.url // ""' 2>/dev/null || echo "")"

    banner "✅ PR CREADO (pendiente de aprobación)"
    [[ -n "${pr_url:-}" ]] && echo "🔗 PR: $pr_url"
    echo

    banner "✅ DEV EN PROCESO (monitor en background)"
    echo "📄 Log del monitor: $log_file"
    echo "🔒 GOLDEN_SHA se escribirá en: $golden_file"
    echo

    log_info "📌 Issues abiertos (top 10):"
    if command -v gh >/dev/null 2>&1; then
        GH_PAGER=cat gh issue list --state open --limit 10 2>/dev/null || log_warn "No pude listar issues (¿gh auth?)."
    else
        log_warn "No se encontró 'gh'. No puedo listar issues."
    fi

    echo
    echo "👉 Cuando el monitor termine: git promote staging"
    exit 0
}