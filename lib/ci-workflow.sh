#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ci-workflow.sh

# ==============================================================================
# 1. CONFIGURACIÓN Y DETECCIÓN (Auto-Discovery Robusto)
# ==============================================================================

# Helper: Verifica si una tarea existe realmente en el Taskfile (incluso importada)
task_exists() {
    local task_name="$1"
    command -v task >/dev/null || return 1

    task --list 2>/dev/null | awk '
        /^task:/ {next}          # ignora encabezados tipo "task: Available tasks..."
        NF==0 {next}             # ignora líneas vacías
        {
            name=$1
            gsub(/^[*+-]+/, "", name)  # quita bullets: *, -, +
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

# Ejecutamos la detección al cargar la librería para tener las vars listas
detect_ci_tools

# ==============================================================================
# 1.1. DETECCIÓN DE ENTORNO ACTIVO (DevX: Runtime + Alternativas)
# ==============================================================================

# Detecta si Docker Compose (Traefik) está activo (stack runtime)
detect_compose_active() {
    command -v docker >/dev/null || return 1
    # Indicador principal del stack: traefik (gateway único)
    docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "pmbok-traefik"
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

# Render “bonito” del estado de entorno (activo + alternativas)
render_env_status_panel() {
    local -a active_envs=()
    local -a runtime_suggestions=()
    local -a validation_suggestions=()

    # Activos
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

    # Sugerencias de validación (no-runtime, pero útiles para “probar build/calidad”)
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

# ==============================================================================
# 2. FLUJO POST-PUSH (Menu Interactivo por Niveles)
# ==============================================================================

run_post_push_flow() {
    local head="$1"
    local base="$2"
    
    # [SAFETY] Fallback de UI: Define funciones dummy si styles.sh no cargó
    if ! declare -F ui_step_header >/dev/null 2>&1; then
        ui_step_header() { echo -e "\n>>> $1"; }
        ui_success() { echo "✅ $1"; }
        ui_error() { echo "❌ $1"; }
        ui_warn() { echo "⚠️  $1"; }
        ui_info() { echo "ℹ️  $1"; }
        have_gum_ui() { command -v gum >/dev/null; }
        ask_yes_no() {
            local prompt="$1"
            read -r -p "$prompt [y/N] " response
            [[ "$response" =~ ^[yY] ]]
        }
    fi

    # Dependencias de utils.sh
    if ! command -v is_tty >/dev/null; then 
        # Fallback simple para is_tty si utils.sh falló
        is_tty() { [ -t 1 ]; }
    fi

    is_tty || return 0
    [[ "$POST_PUSH_FLOW" == "true" ]] || return 0
    
    if [[ "$head" != feature/* && "$head" != hotfix/* && "$head" != fix/* ]]; then return 0; fi

    # --- FIX: Re-detectar SIEMPRE (evita variables cacheadas / estado viejo) ---
    unset NATIVE_CI_CMD ACT_CI_CMD COMPOSE_CI_CMD K8S_HEADLESS_CMD K8S_FULL_CMD
    detect_ci_tools

    # --- DevX: Mostrar entorno activo + alternativas (runtime + validaciones) ---
    render_env_status_panel

    echo
    ui_step_header "🕵️  RINCÓN DEL DETECTIVE: Calidad de Código"
    echo "   Rama actual: $head"
    echo

    # Variable para controlar si el usuario pasó los tests
    local gate_passed=0

    # --- Definición de Opciones del Menú ---
    local OPT_GATE="✅ Gate Estándar (Nativo + Act)"
    local OPT_NATIVE="🔍 Solo Nativo (Rápido)"
    local OPT_ACT="🎬 Solo Act (GH Actions)"
    local OPT_COMPOSE="🐳 Compose Check (Integration)"
    local OPT_K8S="☸️  K8s Pro (Build -> Deploy -> Smoke)"
    local OPT_K8S_FULL="🚀 Pipeline Full (Interactivo)"
    local OPT_PR="📨 Finalizar y Crear PR"
    local OPT_SKIP="🚪 Salir (Seguir trabajando)"

    # --- Construcción dinámica del menú (FIX: Uso de ${VAR:-} para evitar crash con set -u) ---
    local choices=()
    
    # Gate estándar siempre disponible si hay comandos básicos
    if [[ -n "${NATIVE_CI_CMD:-}" && -n "${ACT_CI_CMD:-}" ]]; then
        choices+=("$OPT_GATE")
    fi

    [[ -n "${NATIVE_CI_CMD:-}" ]] && choices+=("$OPT_NATIVE")
    [[ -n "${ACT_CI_CMD:-}" ]]    && choices+=("$OPT_ACT")
    [[ -n "${COMPOSE_CI_CMD:-}" ]] && choices+=("$OPT_COMPOSE")
    [[ -n "${K8S_HEADLESS_CMD:-}" ]] && choices+=("$OPT_K8S")
    [[ -n "${K8S_FULL_CMD:-}" ]] && choices+=("$OPT_K8S_FULL")
    
    choices+=("$OPT_PR")
    choices+=("$OPT_SKIP")

    # --- Selección ---
    local selected
    if have_gum_ui; then
        selected=$(gum choose --header "Selecciona un nivel de validación:" "${choices[@]}")
    else
        echo "Selecciona opción:"
        select opt in "${choices[@]}"; do selected="$opt"; break; done
    fi

    if [[ -z "$selected" || "$selected" == "$OPT_SKIP" ]]; then
        echo "👌 Omitido."
        return 0
    fi

    # --- Ejecución ---
    case "$selected" in
        "$OPT_GATE")
            echo "▶️  Ejecutando Gate Estándar..."
            if run_cmd "$NATIVE_CI_CMD"; then
                echo
                if run_cmd "$ACT_CI_CMD"; then
                    ui_success "✅ Gate completado."
                    gate_passed=1
                    # Sugerir PR automáticamente si pasa el gate
                    echo
                    if ask_yes_no "¿Quieres crear el PR ahora?"; then
                        do_create_pr_flow "$head" "$base"
                    fi
                else
                    ui_error "❌ Falló CI Act."
                    return 1
                fi
            else
                ui_error "❌ Falló CI Nativo."
                return 1
            fi
            ;;
            
        "$OPT_NATIVE")
            run_cmd "$NATIVE_CI_CMD"
            ;;

        "$OPT_ACT")
            run_cmd "$ACT_CI_CMD"
            ;;

        "$OPT_COMPOSE")
            echo "▶️  Verificando entorno Compose..."
            run_cmd "$COMPOSE_CI_CMD"
            ;;

        "$OPT_K8S")
            echo "▶️  Ejecutando Pipeline K8s Local (Headless)..."
            run_cmd "$K8S_HEADLESS_CMD"
            ;;
        
        "$OPT_K8S_FULL")
            echo "▶️  Ejecutando Pipeline Full (Bloqueará la terminal)..."
            
            # [UX] Manejo de Ctrl+C (130) como salida normal
            run_cmd "$K8S_FULL_CMD"
            local rc=$?
            
            if [[ "$rc" != "0" && "$rc" != "130" && "$rc" != "143" ]]; then
                ui_error "❌ Pipeline full falló con código $rc"
            else
                    # Si fue Ctrl+C (130) o éxito (0), lo tratamos amigablemente
                    echo
                    ui_info "🛑 Pipeline finalizado/interrumpido (rc=$rc)."
            fi
            
            # === MENSAJE DE RECONEXIÓN AMIGABLE ===
            echo
            ui_warn "🔌 Has desconectado los túneles del Pipeline."
            echo
            ui_info "Si cerraste por error o quieres seguir navegando, puedo reabrirlos por ti."
            ui_info "Comando manual: task cluster:connect"
            echo
            
            # Bucle infinito opcional: permite reabrir tantas veces como quiera
            while ask_yes_no "¿Quieres volver a abrir los túneles ahora?"; do
                echo "🔌 Reconectando..."
                run_cmd "task cluster:connect"
                echo
                ui_warn "🔌 Túneles cerrados nuevamente."
            done
            ui_info "👌 Entendido. Túneles cerrados definitivamente."
            ;;

        "$OPT_PR")
            # [PROCESS] Enforzar Gate antes de PR
            if [[ "${REQUIRE_GATE_BEFORE_PR:-true}" == "true" && "${gate_passed:-0}" != "1" && "${DEVTOOLS_ALLOW_PR_WITHOUT_GATE:-0}" != "1" ]]; then
                ui_warn "🔒 Para crear PR debes pasar el Gate (Nativo + Act)."
                echo "   Esto asegura que no subamos código roto."
                echo 
                if ask_yes_no "¿Ejecutar Gate ahora?"; then
                    if run_cmd "$NATIVE_CI_CMD" && run_cmd "$ACT_CI_CMD"; then
                        gate_passed=1
                        ui_success "Gate superado. Procediendo al PR..."
                    else
                        ui_error "No se pasó el Gate. PR abortado."
                        return 1
                    fi
                else
                    ui_info "PR cancelado. (Usa DEVTOOLS_ALLOW_PR_WITHOUT_GATE=1 si es urgente)."
                    return 1
                fi
            fi

            do_create_pr_flow "$head" "$base"
            ;;
    esac
}

# Helper: Creación de PR
do_create_pr_flow() {
    local head="$1"
    local base="$2"
    
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local pr_script="${lib_dir}/../bin/git-pr.sh"

    if [[ -f "$pr_script" ]]; then
        if "$pr_script"; then
            echo "Gracias por el trabajo, en breve se revisa."
            return 0
        fi
    elif command -v git-pr >/dev/null; then
        if git-pr; then return 0; fi
    else
        echo "❌ No encuentro el script git-pr.sh en $pr_script ni en el PATH."
        return 1
    fi
    
    echo "⚠️ Hubo un problema creando el PR."
    return 1
}
