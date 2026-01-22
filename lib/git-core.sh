#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/git-core.sh

ensure_clean_git() {
    # Tu lógica de sync_submodules va aquí
    if [[ -n $(git status --porcelain) ]]; then
        log_error "Tienes cambios sin guardar."
        exit 1
    fi
}

get_current_branch() {
    git branch --show-current
}