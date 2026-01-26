#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ci/detection.sh

# ==============================================================================
# LÓGICA DE DETECCIÓN (Auto-Discovery Robusto)
# ==============================================================================

# Helper: Verifica si una tarea existe realmente en el Taskfile (incluso importada)
task_exists() {
    local task_name="$1"
    command -v task >/dev/null || return 1

    task --list 2>/dev/null | awk '
        /^task:/ {next}          # ignora encabezados tipo "task: Available tasks..."
        NF==0 {next}             # ignora líneas vacías
        {
            # Formatos comunes:
            # 1) "* ci:      desc"      -> $1="*"  $2="ci:"
            # 2) "ci:        desc"      -> $1="ci:"
            # 3) "- ci:      desc"      -> $1="-"  $2="ci:"
            # 4) "ci         desc"      -> $1="ci"
            if ($1 ~ /^[*+-]$/) { name=$2 } else { name=$1 }
            gsub(/^[*+-]+/, "", name)   # quita bullets pegados: *, -, +
            gsub(/:$/, "", name)        # quita ":" final si existe
            print name
        }
    ' | grep -Fxq "$task_name"
}

detect_ci_tools() {
    root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

    : "${POST_PUSH_FLOW:=true}"

    # --- Nivel 1: CI Nativo (Prioridad: Contrato 'task ci') ---
    if [[ -z "${NATIVE_CI_CMD:-}" ]]; then
        if task_exists "ci"; then
            export NATIVE_CI_CMD="task ci"
        elif task_exists "test"; then
            export NATIVE_CI_CMD="task test"
        elif [[ -f "${root}/apps/pmbok/Taskfile.yaml" ]]; then
            export NATIVE_CI_CMD="task -d apps/pmbok test"
        fi
    fi

    # --- Nivel 2: Act (GitHub Actions Local) ---
    if [[ -z "${ACT_CI_CMD:-}" ]]; then
        if task_exists "ci:act"; then
            export ACT_CI_CMD="task ci:act"
        # FIX: fallback seguro (NO usar `act` pelado). Si existe el wrapper Taskfile, úsalo.
        elif [[ -f "${root}/.github/workflows/test/Taskfile.yaml" ]]; then
            export ACT_CI_CMD="task -t .github/workflows/test/Taskfile.yaml trigger"
        fi
    fi

    # --- Nivel 3: Compose (Runtime Dev / Smoke) ---
    if [[ -z "${COMPOSE_CI_CMD:-}" ]]; then
        # Gracias a task_exists, esto detecta 'local:check' aunque venga de un include
        if task_exists "local:check"; then
                export COMPOSE_CI_CMD="task local:check"
        elif task_exists "local:up"; then
                export COMPOSE_CI_CMD="task local:up"
        fi
    fi

    # --- Nivel 4: K8s Headless (Build -> Deploy -> Smoke) ---
    if [[ -z "${K8S_HEADLESS_CMD:-}" ]]; then
        # 1. Preferencia: Alias explícito si existiera (Future-proof)
        if task_exists "pipeline:local:headless"; then
            export K8S_HEADLESS_CMD="task pipeline:local:headless"
        # 2. Composición dinámica: Si existen las 3 piezas clave
        elif task_exists "build:local" && task_exists "deploy:local" && task_exists "smoke:local"; then
            export K8S_HEADLESS_CMD="task build:local && task deploy:local && task smoke:local"
        fi
    fi

    # --- Nivel 5: K8s Full (Pipeline Interactivo) ---
    if [[ -z "${K8S_FULL_CMD:-}" ]]; then
        if task_exists "pipeline:local"; then
            export K8S_FULL_CMD="task pipeline:local"
        fi
    fi
}

# ==============================================================================
# DETECCIÓN DE ENTORNO ACTIVO (DevX: Runtime + Alternativas)
# ==============================================================================

# Detecta si Docker Compose (Traefik) está activo (stack runtime)
detect_compose_active() {
    command -v docker >/dev/null || return 1
    # Indicador principal del stack: traefik (gateway único)
    # MODIFICADO (1.4): Usar variable configurable en lugar de hardcode
    local gateway="${COMPOSE_GATEWAY_CONTAINER:-pmbok-traefik}"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$gateway"
}

# Detecta si Minikube/K8s local está activo (runtime prod-like)
detect_minikube_active() {
    # Contexto actual
    if command -v kubectl >/dev/null; then
        local ctx
        ctx="$(kubectl config current-context 2>/dev/null || echo "")"
        if [[ "$ctx" == "minikube" ]]; then
            # Si minikube está instalado, verificamos que esté corriendo
            if command -v minikube >/dev/null; then
                minikube status 2>/dev/null | grep -q "Running"
                return $?
            fi
            # Si no está minikube, pero el contexto es minikube, asumimos activo.
            return 0
        fi
    fi

    # Fallback: minikube status (si kubectl no está o el contexto no está configurado)
    if command -v minikube >/dev/null; then
        minikube status 2>/dev/null | grep -q "Running"
        return $?
    fi

    return 1
}

# Detecta si estamos dentro de Devbox (toolchain / shell)
detect_devbox_active() {
    # Devbox suele exportar DEVBOX_ENV_NAME, pero no es garantía universal.
    [[ -n "${DEVBOX_ENV_NAME:-}" ]] && return 0
    [[ -n "${DEVBOX_SHELL_ENABLED:-}" ]] && return 0
    [[ -n "${IN_DEVBOX_SHELL:-}" ]] && return 0
    return 1
}