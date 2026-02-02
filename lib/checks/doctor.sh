
#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/checks/doctor.sh
#
# Doctor: diagnóstico rápido (no destructivo).
# Depende de: utils.sh, git-ops.sh (ya cargados por bin/git-promote.sh).

run_doctor() {
    ui_header "🩺 devtools doctor"

    if ! ensure_repo; then
        ui_error "No estás dentro de un repositorio Git."
        return 1
    fi

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
    ui_info "Repo root: ${repo_root:-unknown}"

    # Toolset branch (si aplica)
    local tool_branch tool_sha
    tool_branch="$(git -C "${DEVTOOLS_ROOT:-.}" branch --show-current 2>/dev/null || echo "(unknown)")"
    tool_sha="$(git -C "${DEVTOOLS_ROOT:-.}" rev-parse --short HEAD 2>/dev/null || echo "(unknown)")"
    ui_info "Devtools branch: ${tool_branch} @${tool_sha}"

    # Comandos útiles
    if have_cmd gh; then
        ui_info "GH CLI: instalado"
    else
        ui_warn "GH CLI: NO instalado"
    fi

    if have_cmd gum; then
        ui_info "GUM: instalado (UI visual disponible)"
    else
        ui_warn "GUM: NO instalado (fallback a menú numérico)"
    fi

    # Estado de working tree (info)
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        ui_warn "Working tree: DIRTY (hay cambios sin commit)"
    else
        ui_info "Working tree: limpio"
    fi

    ui_success "Doctor OK"
    return 0
}
