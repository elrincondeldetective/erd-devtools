#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows/hotfix.sh
#
# Este módulo gestiona los flujos de trabajo de Hotfix:
# - create_hotfix: Crea una rama de hotfix desde main.
# - finish_hotfix: Fusiona el hotfix en main y dev (backport).
#
# Dependencias: utils.sh, git-ops.sh (cargadas por el orquestador)

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