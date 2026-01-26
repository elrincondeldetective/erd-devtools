#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ci/ui.sh

# ==============================================================================
# LÓGICA DE UI (Renderizado del Dashboard)
# ==============================================================================

# Helper de seguridad: detecta si gum está disponible si no se cargó utils.sh
if ! declare -F have_gum_ui >/dev/null 2>&1; then
    have_gum_ui() { command -v gum >/dev/null; }
fi

# Render “bonito” del estado de entorno (activo + alternativas)
render_env_status_panel() {
    local -a active_envs=()
    local -a runtime_suggestions=()
    local -a validation_suggestions=()

    # Activos (Funciones vienen de detection.sh)
    if detect_devbox_active; then
        active_envs+=("🧰 Devbox (toolchain)")
    fi
    if detect_compose_active; then
        active_envs+=("🐳 Docker Compose (Traefik)")
    fi
    if detect_minikube_active; then
        active_envs+=("☸️  Minikube GitOps")
    fi

    # Sugerencias de activación (runtime)
    if ! detect_compose_active; then
        if task_exists "local:up"; then
            runtime_suggestions+=("🐳 Activar Compose:   task local:up")
        elif task_exists "local:check"; then
            runtime_suggestions+=("🐳 Compose (check):   task local:check")
        fi
    fi

    if ! detect_minikube_active; then
        # Preferimos el alias “cluster:up” porque es el contrato del root Taskfile
        if task_exists "cluster:up"; then
            runtime_suggestions+=("☸️  Activar Minikube:  task cluster:up")
        elif task_exists "local:cluster:up"; then
            runtime_suggestions+=("☸️  Activar Minikube:  task local:cluster:up")
        fi
    fi

    # Sugerencias rápidas de logs cuando Compose está activo (Traefik/runtime)
    if detect_compose_active; then
        if task_exists "local:logs:traefik"; then
            runtime_suggestions+=("📄 Logs Traefik:       task local:logs:traefik")
        fi
        if task_exists "local:logs"; then
            runtime_suggestions+=("📄 Logs Compose:       task local:logs")
        fi
        if task_exists "local:logs:backend"; then
            runtime_suggestions+=("📄 Logs Backend:       task local:logs:backend")
        fi
        if task_exists "local:logs:frontend"; then
            runtime_suggestions+=("📄 Logs Frontend:      task local:logs:frontend")
        fi
        if task_exists "local:logs:db"; then
            runtime_suggestions+=("📄 Logs DB:            task local:logs:db")
        fi

        # Fallback manual (por si no existe local:logs:traefik todavía)
        if ! task_exists "local:logs:traefik" && command -v docker >/dev/null 2>&1; then
            runtime_suggestions+=("📄 Logs Traefik:       docker compose -f devops/local/compose.yml logs -f --tail=200 traefik")
        fi
    fi

    # Sugerencia de observabilidad (k9s) para ver logs / pods
    if task_exists "ui:local"; then
        runtime_suggestions+=("👀 Ver logs en K9s:   task ui:local")
    elif command -v k9s >/dev/null 2>&1; then
        runtime_suggestions+=("👀 Ver logs en K9s:   k9s")
    fi

    # Sugerencias de validación (no-runtime, pero útiles para “probar build/calidad”)
    # Las variables NATIVE_CI_CMD, etc., se setean en detection.sh
    [[ -n "${NATIVE_CI_CMD:-}" ]] && validation_suggestions+=("🔍 CI nativo:         ${NATIVE_CI_CMD}")
    [[ -n "${ACT_CI_CMD:-}" ]]    && validation_suggestions+=("🎬 CI con Act:        ${ACT_CI_CMD}")
    [[ -n "${K8S_HEADLESS_CMD:-}" ]] && validation_suggestions+=("🤖 K8s headless:      ${K8S_HEADLESS_CMD}")
    [[ -n "${K8S_FULL_CMD:-}" ]]     && validation_suggestions+=("🚀 K8s full:          ${K8S_FULL_CMD}")

    # Construir strings
    local active_txt
    if [[ "${#active_envs[@]}" -gt 0 ]]; then
        active_txt="$(printf "%s\n" "${active_envs[@]}")"
    else
        active_txt="(Ninguno)"
    fi

    local runtime_txt
    if [[ "${#runtime_suggestions[@]}" -gt 0 ]]; then
        runtime_txt="$(printf "%s\n" "${runtime_suggestions[@]}")"
    else
        runtime_txt="(No hay sugerencias de runtime detectables)"
    fi

    local validation_txt
    if [[ "${#validation_suggestions[@]}" -gt 0 ]]; then
        validation_txt="$(printf "%s\n" "${validation_suggestions[@]}")"
    else
        validation_txt="(No se detectaron comandos de validación)"
    fi

    # Render UI (gum si está disponible, fallback texto)
    if have_gum_ui; then
        echo
        gum style \
            --border rounded --padding "1 2" --margin "0 0" \
            "🧭 Entornos de trabajo" \
            "" \
            "Activo(s):" \
            "$active_txt" \
            "" \
            "Puedes activar:" \
            "$runtime_txt" \
            "" \
            "Validaciones disponibles:" \
            "$validation_txt"
        echo
    else
        echo
        echo "════════════════════════════════════════════════════"
        echo "🧭 Entornos de trabajo"
        echo "════════════════════════════════════════════════════"
        echo "Activo(s):"
        echo "$active_txt" | sed 's/^/  - /'
        echo
        # Si no hay runtime activo, mostramos mensaje claro
        if ! detect_compose_active && ! detect_minikube_active; then
            echo "⚠️  No tienes un entorno de runtime activo para probar build/smoke."
            echo "   Activa uno para continuar:"
            echo "$runtime_txt" | sed 's/^/  • /'
        else
            echo "Puedes activar:"
            echo "$runtime_txt" | sed 's/^/  • /'
        fi
        echo
        echo "Validaciones disponibles:"
        echo "$validation_txt" | sed 's/^/  • /'
        echo "════════════════════════════════════════════════════"
        echo
    fi
}