#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/setup-wizard.sh
set -e

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
# Nos aseguramos de ejecutar desde la raíz para que las rutas relativas funcionen
cd "$(git rev-parse --show-toplevel)"

MARKER_FILE=".devtools/.setup_completed"
FORCE=false
VERIFY_ONLY=false

# Parseo de argumentos
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
        --verify-only|--verify) VERIFY_ONLY=true ;;
    esac
done

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
    
    # Check rápido de SSH
    ui_spinner "Verificando conexión SSH..." ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"
    
    if [ $? -eq 0 ]; then
        ui_success "Conexión a GitHub: OK"
    else
        ui_error "Conexión a GitHub: FALLÓ"
        ui_info "Ejecuta './bin/setup-wizard.sh --force' para reparar."
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