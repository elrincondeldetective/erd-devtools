#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/utils.sh
set -u

# ==============================================================================
# 1. CONSTANTES Y COLORES
# ==============================================================================
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

# ==============================================================================
# 2. LOGGING HELPERS
# ==============================================================================
log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; >&2; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Termina la ejecución con error (Exit code 1)
die() {
    log_error "$1"
    exit 1
}

# ==============================================================================
# 3. SYSTEM & TERMINAL CHECKS
# ==============================================================================
is_tty() { 
    [[ -t 0 && -t 1 ]]
}

have_cmd() { 
    command -v "$1" >/dev/null 2>&1
}

# Check centralizado para saber si podemos usar GUM (TTY + instalado)
have_gum_ui() {
    if is_tty && have_cmd gum; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# 4. EJECUCIÓN SEGURA (PIPELINE SAFE)
# ==============================================================================

# Ejecuta un comando permitiendo que falle sin abortar el script (incluso con set -e)
# Uso: if try_cmd grep -q "foo" file; then ...
try_cmd() {
    # FIX: Preservar el estado original de `set -e` para no activarlo accidentalmente.
    # Esto evita "side effects" en scripts que NO usan errexit.
    local errexit_was_on=0
    case "$-" in
        *e*) errexit_was_on=1 ;;
    esac

    set +e
    "$@"
    local rc=$?
    set +e

    if [[ "$errexit_was_on" -eq 1 ]]; then
        set -e
    fi

    return $rc
}

# ==============================================================================
# 5. INTERACCIÓN CON EL USUARIO (UI)
# ==============================================================================

# 5.1 MENÚ VISUAL UNIVERSAL (PROMOTE STRATEGY)
# ------------------------------------------------------------------------------

__ui_choose_one() {
    local title="$1"; shift
    local options=("$@")

    # Gum (visual)
    if have_gum_ui; then
        gum choose --header "$title" "${options[@]}"
        return $?
    fi

    # Fallback TTY (numérico, simple)
    if is_tty; then
        echo
        echo "$title"
        echo
        local i=1
        for opt in "${options[@]}"; do
            echo "  $i) $opt"
            i=$((i+1))
        done
        echo
        local ans=""
        while true; do
            read -r -p "Elige opción [1-${#options[@]}]: " ans < /dev/tty
            [[ "$ans" =~ ^[0-9]+$ ]] || { echo "Opción inválida."; continue; }
            (( ans >= 1 && ans <= ${#options[@]} )) || { echo "Fuera de rango."; continue; }
            echo "${options[$((ans-1))]}"
            return 0
        done
    fi

    # No-tty: no decidimos por ti (sin sorpresas)
    return 2
}

promote_choose_strategy_or_die() {
    # Permite preconfigurar por entorno (ej. scripts), pero valida.
    local preset="${DEVTOOLS_PROMOTE_STRATEGY:-}"
    if [[ -n "${preset:-}" ]]; then
        case "$preset" in
            merge-theirs|ff-only|merge|force) echo "$preset"; return 0 ;;
            *) die "DEVTOOLS_PROMOTE_STRATEGY inválida: '$preset' (usa: merge-theirs|ff-only|merge|force)";;
        esac
    fi

    local title="🧯 MENÚ DE SEGURIDAD (Obligatorio) — Elige cómo actualizar ramas"
    local o1="🛡️ Mi Versión Gana (Merge Forzado -X theirs)"
    local o2="⏩ Solo mover puntero, opción segura (Fast-Forward)"
    local o3="🔀 Crear commit de unión para conservar historial (Merge)"
    local o4="☢️ Sobrescribir historia, opción destructiva (Force Update)"

    local choice=""
    choice="$(__ui_choose_one "$title" "$o1" "$o2" "$o3" "$o4")" || {
        [[ "$?" == "2" ]] && die "No hay TTY/UI. Define DEVTOOLS_PROMOTE_STRATEGY=merge-theirs|ff-only|merge|force."
        die "Cancelado."
    }

    case "$choice" in
        "$o1") echo "merge-theirs" ;;
        "$o2") echo "ff-only" ;;
        "$o3") echo "merge" ;;
        "$o4") echo "force" ;;
        *) die "Selección desconocida." ;;
    esac
}

# ------------------------------------------------------------------------------

# Pregunta Sí/No robusta (soporta gum, fallback a read y modo CI)
# Uso: ask_yes_no "¿Quieres continuar?"
ask_yes_no() {
    local q="$1"
    
    # 1. Si hay UI rica, usamos Gum
    if have_gum_ui; then 
        gum confirm "$q"
        return $?
    fi
    
    # 2. Si es TTY simple, usamos read
    if is_tty; then 
        local ans
        read -r -p "$q [S/n]: " ans
        ans="${ans:-S}"
        [[ "$ans" =~ ^[Ss]$ ]]
        return $?
    fi
    
    # 3. Modo No-Interactivo (CI/Scripts)
    # Por defecto asumimos NO, salvo que se active flag explícito
    if [[ "${DEVTOOLS_ASSUME_YES:-0}" == "1" ]]; then
        return 0 # YES
    fi
    
    # Default safe
    return 1
}

# Wrapper para mantener compatibilidad con scripts anteriores
confirm_action() {
    ask_yes_no "$1"
}

# ==============================================================================
# 6. EJECUCIÓN DE COMANDOS
# ==============================================================================

# Ejecuta un comando mostrando qué se está haciendo y controlando errores
# Uso: run_cmd "ls -la"
run_cmd() {
    local cmd="$1"
    [[ -n "$cmd" ]] || return 2
    echo; echo "▶️ Ejecutando: $cmd"
    
    # Usamos try_cmd para manejar set -e de forma segura
    try_cmd eval "$cmd"
}

# ==============================================================================
# 7. SUPERREPO GUARD (Protección contra ejecución en raíz de monorepo)
# ==============================================================================

# Verifica si existe el archivo .no-acp-here y bloquea la ejecución
# Uso: check_superrepo_guard "$0" "$@"
check_superrepo_guard() {
    # Si la variable de entorno está en 1, saltamos el chequeo (bypass)
    [[ "${DISABLE_NO_ACP_GUARD:-0}" == "1" ]] && return 0

    local script_path="$1"
    shift
    local original_args=("$@")
    
    local top
    top="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
    
    if [[ -n "$top" && -f "$top/.no-acp-here" ]]; then
        echo
        echo "🛑 SUPERREPO (NO ACP)"
        echo "🔴 Aquí NO se usa este comando (marcado con .no-acp-here)."
        echo
        echo "✅ Usa en su lugar:"
        echo "   • make rel"
        echo "   • make rel-auto"
        echo "   • git rel"
        echo
        
        if is_tty; then
            echo
            echo "¿Qué quieres hacer ahora?"
            export COLUMNS=1
            PS3="Elige opción: "
            select opt in "make rel" "make rel-auto" "git rel" "Continuar (forzar)" "Salir"; do
                case "$REPLY" in
                    1) exec make rel ;;
                    2) exec make rel-auto ;;
                    3) exec git rel ;;
                    4) 
                        # Relanzamos el script actual con una flag de entorno para saltar el guard
                        exec env DISABLE_NO_ACP_GUARD=1 "$script_path" "${original_args[@]}" 
                        ;;
                    5) echo "✋ Cancelado."; exit 2 ;;
                    *) echo "Opción inválida."; continue ;;
                esac
            done
        else
            exit 2
        fi
    fi
}

# ==============================================================================
# 8. VISUALIZACIÓN (Progress Bar)
# ==============================================================================

# Muestra la barra de progreso de commits diarios
# Uso: show_daily_progress <commits_hechos> <meta_diaria> [dry_run_bool]
show_daily_progress() {
    local current="${1:-0}"
    local goal="${2:-10}"
    local is_dry_run="${3:-false}"
    local remain
    local percent
    local bar_length=30
    local filled
    local empty
    local bar=""
    
    # Cálculos
    remain=$(( goal - current ))
    (( remain < 0 )) && remain=0
    
    if (( goal > 0 )); then
        percent=$(( current * 100 / goal ))
    else
        percent=100
    fi
    (( percent > 100 )) && percent=100

    filled=$(( percent * bar_length / 100 ))
    empty=$(( bar_length - filled ))

    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty;  i++)); do bar+="-"; done

    echo
    echo -e "${GREEN}┌─────────────────────────────────────────────"
    echo -e "│ 📊 Commits hoy: ${current}/${goal} (${percent}%)"
    echo -e "│ Progress : |${bar}|"
    echo -e "│ Faltan   : ${remain} commit(s) para la meta diaria"
    echo -e "└─────────────────────────────────────────────${NC}"
    
    if [[ "$is_dry_run" == "true" ]]; then 
        echo -e "${GREEN}⚗️  Simulación (--dry-run).${NC}"
    fi
}