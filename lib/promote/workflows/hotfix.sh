#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/hotfix.sh
#
# Hotfix estandarizado:
# - promote_hotfix_start: entrypoint compatible con el router
# - create_hotfix: crea hotfix/<name> desde main (base canónica)
# - finish_hotfix: promueve el SHA del hotfix hacia main y dev usando:
#     update_branch_to_sha_with_strategy (ff-only | merge | merge-theirs | force)
#
# Dependencias: utils.sh, git-ops.sh (cargadas por el orquestador)

# ==============================================================================
# 6. HOTFIX WORKFLOWS (ESTÁNDAR)
# ==============================================================================

promote_hotfix_start() {
    # Uso:
    #   git promote hotfix                 -> si estás en hotfix/*: finaliza; si no: crea (pide nombre)
    #   git promote hotfix <name>          -> crea hotfix/<name>
    #   git promote hotfix finish          -> finaliza (requiere estar en hotfix/*)

    # Best-effort: resync submodules si existe el helper (common.sh)
    if declare -F resync_submodules_hard >/dev/null 2>&1; then
        resync_submodules_hard
    fi

    local action="${1:-}"
    local current
    current="$(git branch --show-current 2>/dev/null || echo "")"

    if [[ "$action" == "finish" ]]; then
        finish_hotfix
        return $?
    fi

    if [[ "$current" == hotfix/* ]]; then
        finish_hotfix
        return $?
    fi

    # Si viene nombre, crear con ese nombre. Si no, crear pidiendo nombre.
    create_hotfix "${action:-}"
}

create_hotfix() {
    local hf_name="${1:-}"

    # Evitar sorpresas en no-tty
    if [[ -z "${hf_name:-}" ]]; then
        if declare -F can_prompt >/dev/null 2>&1 && can_prompt; then
            printf "Nombre del hotfix: " > /dev/tty
            read -r hf_name < /dev/tty
        else
            die "⛔ No hay TTY/UI. Usa: git promote hotfix <nombre>"
        fi
    fi

    hf_name="$(echo "${hf_name:-}" | tr -d '[:space:]')"
    [[ -n "${hf_name:-}" ]] || die "⛔ Nombre de hotfix vacío."

    local hf_branch="hotfix/${hf_name}"

    ensure_clean_git

    # Base canónica: main desde origin
    ensure_local_tracking_branch "main" "origin" || die "No pude preparar 'main' desde 'origin/main'."
    update_branch_from_remote "main"

    # Crear rama hotfix desde main actualizado
    git checkout -b "$hf_branch" >/dev/null 2>&1 || die "No pude crear la rama ${hf_branch}."

    # Aterrizaje final: quedarnos en el hotfix tras crear
    export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="$hf_branch"

    log_success "✅ Rama hotfix creada: $hf_branch (base: main)"
    log_info "👉 Haz tus commits y luego ejecuta: git promote hotfix"
}

finish_hotfix() {
    local current
    current="$(git branch --show-current 2>/dev/null || echo "")"
    [[ "$current" == hotfix/* ]] || die "⛔ No estás en una rama hotfix/*."

    ensure_clean_git

    local hotfix_sha
    hotfix_sha="$(git rev-parse HEAD 2>/dev/null || true)"
    [[ -n "${hotfix_sha:-}" ]] || die "No pude resolver SHA del hotfix."

    echo
    banner "🩹 FINALIZANDO HOTFIX (Estandarizado)"
    log_info "Fuente : ${current} @${hotfix_sha:0:7}"
    log_info "Targets: main + dev"
    echo

    # Estrategia (Menú Universal): debería venir del bin, pero mantenemos fallback seguro.
    local strategy="${DEVTOOLS_PROMOTE_STRATEGY:-}"
    if [[ -z "${strategy:-}" ]]; then
        strategy="$(promote_choose_strategy_or_die)"
        export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
    fi

    # 1) MAIN
    log_info "1/2 🚀 Actualizando 'main' desde hotfix..."
    local main_sha="" rc=0
    while true; do
        main_sha="$(update_branch_to_sha_with_strategy "main" "$hotfix_sha" "origin" "$strategy")"
        rc=$?
        if [[ "$rc" -eq 3 ]]; then
            log_warn "⚠️ Fast-Forward NO es posible en main. Elige otra estrategia."
            strategy="$(promote_choose_strategy_or_die)"
            export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
            continue
        fi
        [[ "$rc" -eq 0 ]] || die "No pude actualizar 'main' (strategy=${strategy}, rc=${rc})."
        break
    done
    log_success "✅ MAIN OK: origin/main @${main_sha:0:7}"

    # 2) DEV (backport)
    log_info "2/2 🚀 Backport a 'dev' desde hotfix..."
    local dev_sha="" rc2=0
    while true; do
        dev_sha="$(update_branch_to_sha_with_strategy "dev" "$hotfix_sha" "origin" "$strategy")"
        rc2=$?
        if [[ "$rc2" -eq 3 ]]; then
            log_warn "⚠️ Fast-Forward NO es posible en dev. Elige otra estrategia."
            strategy="$(promote_choose_strategy_or_die)"
            export DEVTOOLS_PROMOTE_STRATEGY="$strategy"
            continue
        fi
        [[ "$rc2" -eq 0 ]] || die "No pude actualizar 'dev' (strategy=${strategy}, rc=${rc2})."
        break
    done
    log_success "✅ DEV OK: origin/dev @${dev_sha:0:7}"

    echo
    log_info "🔎 Confirmación visual:"
    log_info "   git ls-remote --heads origin main"
    git ls-remote --heads origin main 2>/dev/null || true
    log_info "   git ls-remote --heads origin dev"
    git ls-remote --heads origin dev 2>/dev/null || true
    echo

    # Aterrizaje final: quedarnos en main (por ser “producción” del hotfix)
    export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="main"

    log_success "✅ Hotfix integrado (estándar): ${current} -> main + dev (strategy=${strategy})"
    return 0
}
