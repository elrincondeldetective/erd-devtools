#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/setup-wizard.sh
set -e

# --- FIX: TRAP DE ERRORES (P2) ---
# Si falla algo inesperado, muestra la línea y el comando
trap 'echo "❌ ERROR FATAL en línea $LINENO. Código de salida: $?" >&2' ERR

# --- FIX: ACTIVA MODO WIZARD ---
# Esto avisa a lib/core/config.sh que no debe abortar si falta configuración.
export DEVTOOLS_WIZARD_MODE=true

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_BASE="${SCRIPT_DIR}/../lib"

# Core (Orden estricto)
source "${LIB_BASE}/core/utils.sh"
source "${LIB_BASE}/core/config.sh"
source "${LIB_BASE}/core/git-ops.sh"

# UI
source "${LIB_BASE}/ui/styles.sh"

# Módulos del Wizard
WIZARD_DIR="${LIB_BASE}/wizard"
source "${WIZARD_DIR}/step-01-auth.sh"
source "${WIZARD_DIR}/step-02-ssh.sh"
source "${WIZARD_DIR}/step-03-config.sh"
source "${WIZARD_DIR}/step-04-profile.sh"

# ==============================================================================
# 2. VALIDACIONES DE ENTORNO
# ==============================================================================
ensure_repo

# --- FIX: SOPORTE DE SUBMÓDULOS / SUPERPROYECTO (P1) ---
# Si estamos corriendo dentro del submódulo .devtools, queremos ir a la raíz real del proyecto
SUPER_ROOT="$(git rev-parse --show-superproject-working-tree 2>/dev/null || echo "")"
if [ -n "$SUPER_ROOT" ]; then
    cd "$SUPER_ROOT"
else
    cd "$(git rev-parse --show-toplevel)"
fi

# --- FIX: CHECK DE DEPENDENCIAS CRÍTICAS ---
# Fallar rápido si faltan herramientas esenciales antes de intentar usarlas
REQUIRED_TOOLS="git gh gum ssh ssh-keygen"
for tool in $REQUIRED_TOOLS; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Error Crítico: Falta la herramienta '$tool'."
        echo "   Por favor instálala (o entra en el devbox) antes de continuar."
        exit 1
    fi
done

MARKER_FILE=".devtools/.setup_completed"
# Asegurar que la carpeta del marker exista
mkdir -p "$(dirname "$MARKER_FILE")"

FORCE=false
VERIFY_ONLY=false

# Parseo de argumentos
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
        --verify-only|--verify) VERIFY_ONLY=true ;;
    esac
done

# --- FIX: MANEJO DE NO-TTY (P0) ---
# Si no hay terminal interactiva (CI/Script), forzamos verify-only o fallamos
if [ ! -t 0 ] && [ "$VERIFY_ONLY" != true ]; then
    echo "⚠️ No se detectó terminal interactiva (TTY)."
    echo "   Cambiando automáticamente a modo --verify-only."
    VERIFY_ONLY=true
fi

# Detección automática: Si ya existe el marker y no forzamos, pasamos a modo verificación
if [ -f "$MARKER_FILE" ] && [ "$FORCE" != true ]; then
    VERIFY_ONLY=true
fi

# ==============================================================================
# 3. MODO VERIFICACIÓN (FAST PATH)
# ==============================================================================
if [ "$VERIFY_ONLY" = true ]; then
    ui_step_header "🕵️‍♂️ MODO VERIFICACIÓN"
    ui_info "El setup ya se realizó anteriormente."
    
    # Check rápido de usuario
    CURRENT_NAME="$(git_get global user.name)"
    if [ -z "$CURRENT_NAME" ]; then CURRENT_NAME="$(git_get local user.name)"; fi
    
    # --- FIX: VERIFICAR TAMBIÉN GH AUTH (P2) ---
    ui_spinner "Verificando sesión GH CLI..." sleep 1
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        ui_error "GH CLI no autenticado."
        ui_info "Ejecuta './bin/setup-wizard.sh --force' para loguearte."
        exit 1
    else
        ui_success "GH CLI: Autenticado."
    fi

    # Check rápido de SSH
    # --- FIX: NO USAR SET -E CON PIPES QUE PUEDEN FALLAR ---
    # Usamos ui_spinner solo visualmente, y luego ejecutamos el comando dentro del if
    ui_spinner "Verificando conexión SSH..." sleep 1
    
    if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
        ui_success "Conexión a GitHub (SSH): OK"
    else
        ui_error "Conexión a GitHub (SSH): FALLÓ"
        ui_info "Esto puede ocurrir si expiró tu sesión o cambió tu llave."
        echo ""
        ui_warn "🔧 SOLUCIÓN: Ejecuta './bin/setup-wizard.sh --force' para reparar."
        exit 1
    fi

    echo ""
    ui_alert_box "✅ ESTADO SALUDABLE" \
        "Usuario: ${CURRENT_NAME:-Desconocido}" \
        "Modo: Verificación (Sin cambios)"
    
    echo "💡 Tip: Usa 'git feature <nombre>' para empezar."
    exit 0
fi

# ==============================================================================
# 4. EJECUCIÓN DEL WIZARD (FULL PATH)
# ==============================================================================

show_detective_banner

# PASO 1: Auth & 2FA
run_step_auth

# PASO 2: SSH Keys
run_step_ssh

# PASO 3: Git Config & Signing
run_step_git_config

# PASO 4: Profile, .env & Final Checks
run_step_profile_registration

# Final
echo ""
ui_alert_box "🎉 SETUP COMPLETADO 🎉" \
    "Usuario: $GIT_NAME" \
    "Todo listo para desarrollar."

echo "💡 Tip: Usa 'git feature <nombre>' para empezar."