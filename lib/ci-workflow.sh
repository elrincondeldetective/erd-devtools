#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ci-workflow.sh

# ==============================================================================
# 1. CONFIGURACIÓN Y DETECCIÓN (Auto-Discovery)
# ==============================================================================

detect_ci_tools() {
    root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

    : "${POST_PUSH_FLOW:=true}"

    # --- Nivel 1: CI Nativo (Prioridad: Contrato 'task ci') ---
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

    # --- Nivel 2: Act (GitHub Actions Local) ---
    if [[ -z "${ACT_CI_CMD:-}" ]]; then
        # 1. Si existe 'task ci:act' (estricto)
        if [[ -f "${root}/Taskfile.yaml" ]] && grep -qE '^[[:space:]]*ci:act:[[:space:]]*$' "${root}/Taskfile.yaml"; then
            export ACT_CI_CMD="task ci:act"
        # 2. Fallback antiguo
        elif [[ -f "${root}/.github/workflows/test/Taskfile.yaml" ]]; then
            export ACT_CI_CMD="task -t .github/workflows/test/Taskfile.yaml trigger"
        # 3. Fallback directo a 'act' si existe la carpeta workflows
        elif command -v act >/dev/null && [ -d "${root}/.github/workflows" ]; then
            export ACT_CI_CMD="act"
        else
            export ACT_CI_CMD=""
        fi
    fi

    # --- Nivel 3: Compose (Runtime Dev / Smoke) ---
    if [[ -z "${COMPOSE_CI_CMD:-}" ]]; then
        # 1. Buscamos 'task local:check' (alias root)
        if [[ -f "${root}/Taskfile.yaml" ]] && grep -q "local:check" "${root}/Taskfile.yaml"; then
             export COMPOSE_CI_CMD="task local:check"
        # 2. Buscamos la definición real en el módulo local (check:)
        elif [[ -f "${root}/devops/tasks/local.yaml" ]] && grep -qE '^[[:space:]]*check:[[:space:]]*$' "${root}/devops/tasks/local.yaml"; then
             # Asumimos que está incluido como "local" en el root
             export COMPOSE_CI_CMD="task local:check"
        elif [[ -f "${root}/Taskfile.yaml" ]] && grep -q "local:up" "${root}/Taskfile.yaml"; then
             export COMPOSE_CI_CMD="task local:up"
        else
             export COMPOSE_CI_CMD=""
        fi
    fi

    # --- Nivel 4: K8s Headless (Build -> Deploy -> Smoke) ---
    # Detectamos si tienes los bloques para hacer un deploy "pro" sin interactividad
    if [[ -z "${K8S_HEADLESS_CMD:-}" ]]; then
        if [[ -f "${root}/Taskfile.yaml" ]]; then
            # Verificamos que existan los 3 componentes clave en el Taskfile raíz
            has_build=$(grep -q "build:local" "${root}/Taskfile.yaml" && echo "yes")
            has_deploy=$(grep -q "deploy:local" "${root}/Taskfile.yaml" && echo "yes")
            has_smoke=$(grep -q "smoke:local" "${root}/Taskfile.yaml" && echo "yes")
            
            if [[ "$has_build" == "yes" && "$has_deploy" == "yes" && "$has_smoke" == "yes" ]]; then
                # Ejecución en cadena
                export K8S_HEADLESS_CMD="task build:local && task deploy:local && task smoke:local"
            fi
        fi
    fi

    # --- Nivel 5: K8s Full (Interactivo/Pipeline completo) ---
    if [[ -z "${K8S_FULL_CMD:-}" ]]; then
        if [[ -f "${root}/Taskfile.yaml" ]]; then
            # Prioridad: Contrato 'pipeline:local'
            if grep -qE '^[[:space:]]*pipeline:local:[[:space:]]*$' "${root}/Taskfile.yaml"; then
                export K8S_FULL_CMD="task pipeline:local"
            # Fallback a detección legacy
            elif [[ -n "${LOCAL_PIPELINE_CMD:-}" ]]; then
                 export K8S_FULL_CMD="$LOCAL_PIPELINE_CMD"
            fi
        fi
    fi
}


# Ejecutamos la detección al cargar la librería para tener las vars listas
detect_ci_tools

# ==============================================================================
# 2. FLUJO POST-PUSH (Menu Interactivo por Niveles)
# ==============================================================================

run_post_push_flow() {
    local head="$1"
    local base="$2"
    
    # [FIX 1/3] Fallback de UI para robustez (si styles.sh no existe o no se cargó)
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
    
    # Solo activar flujo si estamos en una rama feature (o fix/hotfix)
    if [[ "$head" != feature/* && "$head" != hotfix/* && "$head" != fix/* ]]; then return 0; fi

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

    # --- Construcción dinámica del menú según herramientas detectadas ---
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
            
            # [FIX 2/3] Manejo de Ctrl+C (130) como salida normal
            run_cmd "$K8S_FULL_CMD"
            local rc=$?
            
            if [[ "$rc" != "0" && "$rc" != "130" && "$rc" != "143" ]]; then
                ui_error "❌ Pipeline full falló con código $rc"
                # Podrías hacer return aquí, pero dejamos caer al menú de reconexión por si acaso
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
            # [FIX 3/3] Enforzar Gate antes de PR
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

# ==============================================================================
# 3. HELPER: CREACIÓN DE PR
# ==============================================================================

# Extraído a función auxiliar para poder llamarlo desde el menú o tras el éxito del Gate
do_create_pr_flow() {
    local head="$1"
    local base="$2"
    
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
        return 1
    fi
    
    echo "⚠️ Hubo un problema creando el PR."
    return 1
}