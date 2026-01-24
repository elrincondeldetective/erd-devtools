#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ci-workflow.sh

# ==============================================================================
# 1. CONFIGURACIÓN Y DETECCIÓN (Auto-Discovery)
# ==============================================================================

detect_ci_tools() {
    root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

    : "${POST_PUSH_FLOW:=true}"

    # --- Detección de CI Nativo (Prioridad: Contrato 'task ci') ---
    if [[ -z "${NATIVE_CI_CMD:-}" ]]; then
        # 1. Si existe 'task ci' (estricto) en el Taskfile raíz, ÚSALO.
        if [[ -f "${root}/Taskfile.yaml" ]] && grep -qE '^[[:space:]]*ci:[[:space:]]*$' "${root}/Taskfile.yaml"; then
        export NATIVE_CI_CMD="task ci"
        # 2. Fallback antiguo (estructura monorepo PMBOK)
        elif [[ -f "${root}/apps/pmbok/Taskfile.yaml" ]]; then
        export NATIVE_CI_CMD="task -d apps/pmbok test"
        else
        # Default genérico
        export NATIVE_CI_CMD="task test"
        fi
    fi

    # --- Detección de Pipeline Local (Nuevo) ---
    if [[ -z "${LOCAL_PIPELINE_CMD:-}" ]]; then
        # Busca 'pipeline:local:' de forma estricta al inicio de línea
        if [[ -f "${root}/Taskfile.yaml" ]] && grep -qE '^[[:space:]]*pipeline:local:[[:space:]]*$' "${root}/Taskfile.yaml"; then
        export LOCAL_PIPELINE_CMD="task pipeline:local"
        fi
    fi

    # --- Detección de Act (GitHub Actions Local) ---
    if [[ -z "${ACT_CI_CMD:-}" ]]; then
        # 1. Si existe 'task ci:act' (estricto)
        if [[ -f "${root}/Taskfile.yaml" ]] && grep -qE '^[[:space:]]*ci:act:[[:space:]]*$' "${root}/Taskfile.yaml"; then
        export ACT_CI_CMD="task ci:act"
        # 2. Fallback antiguo
        elif [[ -f "${root}/.github/workflows/test/Taskfile.yaml" ]]; then
        export ACT_CI_CMD="task -t .github/workflows/test/Taskfile.yaml trigger"
        else
        # Default
        export ACT_CI_CMD="act"
        fi
    fi
}


# Ejecutamos la detección al cargar la librería para tener las vars listas
detect_ci_tools

# ==============================================================================
# 2. FLUJO POST-PUSH (Interactive CI & PR)
# ==============================================================================

run_post_push_flow() {
    local head="$1"
    local base="$2"
    
    # Dependencias de utils.sh
    if ! command -v is_tty >/dev/null; then 
        echo "❌ Error: utils.sh no cargado (falta is_tty)"
        return 1
    fi

    is_tty || return 0
    [[ "$POST_PUSH_FLOW" == "true" ]] || return 0
    
    # Solo activar flujo si estamos en una rama feature
    if [[ "$head" != feature/* ]]; then return 0; fi

    local native_ok="skip"
    
    # --------------------------------------------------------------------------
    # PASO 1: CI NATIVO (Unit Tests / Fast Checks)
    # --------------------------------------------------------------------------
    echo
    if ask_yes_no "¿Quieres correr en local el CI ‘nativo’ del commit que acabas de subir a GitHub?"; then
        if [[ -z "$NATIVE_CI_CMD" ]]; then
            echo "❌ No tengo comando para CI Nativo. Configura NATIVE_CI_CMD."
            return 1
        fi
        
        # Nota: Ya no exportamos DB_HOST/PORT aquí porque 'task ci' maneja su propio entorno.
        
        if run_cmd "$NATIVE_CI_CMD"; then
            native_ok="ok"
        else
            echo "❌ CI nativo falló. Se aborta el flujo (no se ofrece PR)."
            return 1
        fi
    fi

    # --------------------------------------------------------------------------
    # PASO 2: CI CON ACT (Simulación GitHub Actions)
    # --------------------------------------------------------------------------
    # Solo si el nativo pasó o se saltó
    if [[ "$native_ok" == "ok" || "$native_ok" == "skip" ]]; then
        echo
        if ask_yes_no "¿Quieres correr el CI con act (GitHub Actions en local)?"; then
                if [[ -z "$ACT_CI_CMD" ]]; then
                    echo "❌ No encontré configuración para 'act'."
                    return 1
                fi
                if ! run_cmd "$ACT_CI_CMD"; then
                    echo "❌ CI con act falló. Se aborta el flujo (no se ofrece PR)."
                    return 1
                fi
        fi
    fi

    # --------------------------------------------------------------------------
    # PASO 3: CREACIÓN DE PR
    # --------------------------------------------------------------------------
    echo
    if ask_yes_no "¿Quieres crear un PR para finalizar el trabajo y enviarlo a revisión?"; then
        # Buscamos git-pr.sh relativo a esta librería (lib/../bin/git-pr.sh)
        local lib_dir
        lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local pr_script="${lib_dir}/../bin/git-pr.sh"

        if [[ -f "$pr_script" ]]; then
            if "$pr_script"; then
                echo "Gracias por el trabajo, en breve se revisa."
                return 0
            fi
        elif command -v git-pr >/dev/null; then
            # Fallback si está en el PATH
            if git-pr; then return 0; fi
        else
            echo "❌ No encuentro el script git-pr.sh en $pr_script ni en el PATH."
        fi
        
        echo "⚠️ Hubo un problema creando el PR."
        return 1
    else
        echo "Listo, sigue trabajando en más funcionalidades."
    fi
}