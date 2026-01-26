#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ci-workflow.sh

# ==============================================================================
# 0. IMPORTS & BOOTSTRAP
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar módulos refactorizados
source "${SCRIPT_DIR}/ci/detection.sh"
source "${SCRIPT_DIR}/ci/ui.sh"
source "${SCRIPT_DIR}/ci/actions.sh"

# Ejecutar detección inicial al cargar
detect_ci_tools

# ==============================================================================
# 1. FLUJO POST-PUSH (Orquestador del Menú)
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
        ask_yes_no() {
            local prompt="$1"
            read -r -p "$prompt [y/N] " response
            [[ "$response" =~ ^[yY] ]]
        }
        # Helper simple para ejecutar comandos si run_cmd no existe
        if ! declare -F run_cmd >/dev/null 2>&1; then
            run_cmd() { eval "$@"; }
        fi
    fi

    # Dependencias de utils.sh (check de TTY)
    if ! command -v is_tty >/dev/null; then 
        is_tty() { [ -t 1 ]; }
    fi

    is_tty || return 0
    [[ "$POST_PUSH_FLOW" == "true" ]] || return 0
    
    # Solo ejecutar en ramas de trabajo
    if [[ "$head" != feature/* && "$head" != hotfix/* && "$head" != fix/* ]]; then return 0; fi

    # --- 1. Re-detectar herramientas (frescura) ---
    # Limpiamos variables para forzar re-evaluación en detection.sh
    unset NATIVE_CI_CMD ACT_CI_CMD COMPOSE_CI_CMD K8S_HEADLESS_CMD K8S_FULL_CMD
    detect_ci_tools

    # --- 2. Mostrar Dashboard (UI Module) ---
    render_env_status_panel

    echo
    ui_step_header "🕵️  RINCÓN DEL DETECTIVE: Calidad de Código"
    echo "   Rama actual: $head"
    echo

    # Variable para controlar si el usuario pasó los tests
    local gate_passed=0

    # --- 3. Definición de Opciones del Menú ---
    local OPT_GATE="✅ Gate Estándar (Nativo + Act)"
    local OPT_NATIVE="🔍 Solo Nativo (Rápido)"
    local OPT_ACT="🎬 Solo Act (GH Actions)"
    local OPT_COMPOSE="🐳 Compose Check (Integration)"
    local OPT_K8S="☸️  K8s Pro (Build -> Deploy -> Smoke)"
    local OPT_K8S_FULL="🚀 Pipeline Full (Interactivo)"
    local OPT_START_MINIKUBE="🟢 Activar Minikube (cluster:up)"
    local OPT_K9S="👀 Abrir K9s (ui:local)"
    local OPT_HELP="📘 ¿Qué hace cada opción?"
    local OPT_PR="📨 Finalizar y Crear PR"
    local OPT_SKIP="🚪 Salir (Seguir trabajando)"

    # --- 4. Construcción dinámica del menú ---
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

    # Acciones directas para devs (botones)
    if ! detect_minikube_active && task_exists "cluster:up"; then
        choices+=("$OPT_START_MINIKUBE")
    fi
    if task_exists "ui:local" || command -v k9s >/dev/null 2>&1; then
        choices+=("$OPT_K9S")
    fi

    choices+=("$OPT_HELP")
    choices+=("$OPT_PR")
    choices+=("$OPT_SKIP")

    # --- 5. Selección (Input) ---
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

    # --- 6. Ejecución (Router) ---
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
            
            # Bucle infinito opcional
            while ask_yes_no "¿Quieres volver a abrir los túneles ahora?"; do
                echo "🔌 Reconectando..."
                run_cmd "task cluster:connect"
                echo
                ui_warn "🔌 Túneles cerrados nuevamente."
            done
            ui_info "👌 Entendido. Túneles cerrados definitivamente."
            ;;

        "$OPT_START_MINIKUBE")
            run_cmd "task cluster:up"
            ;;

        "$OPT_K9S")
            if task_exists "ui:local"; then
                run_cmd "task ui:local"
            else
                run_cmd "k9s"
            fi
            ;;

        "$OPT_HELP")
            if have_gum_ui; then
                gum style --border rounded --padding "1 2" \
                    "📘 Ayuda rápida" \
                    "" \
                    "✅ Gate Estándar: corre CI nativo + CI con Act (recomendado antes de PR)" \
                    "🔍 Solo Nativo: corre tests rápidos sin simular GitHub Actions" \
                    "🎬 Solo Act: corre el workflow real de GitHub Actions en local" \
                    "🐳 Compose Check: valida que Compose/Traefik responde (runtime dev)" \
                    "☸️  K8s Pro: build+deploy+smoke en Minikube (sin túneles)" \
                    "🚀 Pipeline Full: despliega y abre túneles (Ctrl+C para salir)" \
                    "" \
                    "Tip: Usa 👀 K9s para ver pods/logs fácilmente."
            else
                echo "📘 Ayuda rápida:"
                echo "  - ✅ Gate Estándar: CI nativo + Act (recomendado antes de PR)"
                echo "  - 🔍 Solo Nativo: tests rápidos sin simular GH Actions"
                echo "  - 🎬 Solo Act: workflow real GH Actions en local"
                echo "  - 🐳 Compose Check: valida runtime Compose/Traefik"
                echo "  - ☸️  K8s Pro: build+deploy+smoke en Minikube (headless)"
                echo "  - 🚀 Pipeline Full: despliega y abre túneles (Ctrl+C para salir)"
                echo "  - Tip: usa K9s para logs/pods."
            fi
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

            # Llamada al módulo Actions
            do_create_pr_flow "$head" "$base"
            ;;
    esac
}