#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/tests/test_refactor.sh
#
# Script de prueba de integración para verificar la refactorización de 'promote_to_dev'.
# Valida que el orquestador (to-dev.sh) cargue correctamente sus submódulos
# (helpers y estrategias) usando rutas relativas.

set -e # Detener si hay errores críticos de bash

# ------------------------------------------------------------------------------
# 1. Configuración de Rutas
# ------------------------------------------------------------------------------
# Detectar dónde estamos para poder llamar al script objetivo correctamente
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVTOOLS_ROOT="$(dirname "$TEST_DIR")" # Subir un nivel (.devtools)
TARGET_FILE="$DEVTOOLS_ROOT/lib/promote/workflows/to-dev.sh"

echo "🧪 [TEST] Iniciando verificación de refactorización..."
echo "📂 [TEST] Raíz DevTools detectada: $DEVTOOLS_ROOT"
echo "📄 [TEST] Archivo objetivo: $TARGET_FILE"

# ------------------------------------------------------------------------------
# 2. Mocking de Dependencias (Simular entorno real)
# ------------------------------------------------------------------------------
# 'to-dev.sh' espera que funciones globales de utils.sh ya existan.
# Las definimos aquí vacías para que el 'source' no falle.

echo "🛠️  [TEST] Mockeando dependencias externas (utils, git-ops)..."

# Logs
log_info() { echo "   [MOCK-INFO] $1"; }
log_error() { echo "   [MOCK-ERROR] $1"; }
log_warn() { echo "   [MOCK-WARN] $1"; }
log_success() { echo "   [MOCK-SUCCESS] $1"; }
banner() { echo "   === [MOCK-BANNER] $1 ==="; }

# Git & System Checks
is_tty() { return 0; }
resync_submodules_hard() { :; }
ensure_clean_git() { :; }
ensure_clean_git_or_die() { :; }
repo_has_workflow_file() { return 1; } # Retornar falso por defecto

# GitOps / Writes
write_golden_sha() { :; }
maybe_trigger_gitops_update() { :; }
resolve_golden_sha_file() { echo ".last_golden_sha"; }

# GH Placeholders (por si se invocaran, aunque solo probamos carga)
wait_for_pr_merge_and_get_sha() { echo "mock_sha_123"; }

# Variables de entorno que suelen estar presentes
export REPO_ROOT="$DEVTOOLS_ROOT/.." 
export SCRIPT_DIR="$DEVTOOLS_ROOT/bin"

# ------------------------------------------------------------------------------
# 3. Carga del Módulo (La prueba real)
# ------------------------------------------------------------------------------

if [[ ! -f "$TARGET_FILE" ]]; then
    echo "❌ [FAIL] No se encontró el archivo: $TARGET_FILE"
    exit 1
fi

echo "🚀 [TEST] Intentando cargar (source) $TARGET_FILE..."
echo "-----------------------------------------------------"
# Aquí es donde ocurre la magia. Si las rutas relativas en to-dev.sh están mal, esto fallará.
source "$TARGET_FILE"
echo "-----------------------------------------------------"

# ------------------------------------------------------------------------------
# 4. Verificación de Funciones (Assertions)
# ------------------------------------------------------------------------------
echo "🔍 [TEST] Verificando disponibilidad de funciones en memoria..."

EXIT_CODE=0

check_function() {
    local func_name="$1"
    local origin="$2"
    
    if type -t "$func_name" >/dev/null; then
        echo "   ✅ OK: '$func_name' cargada correctamente. ($origin)"
    else
        echo "   ❌ ERROR: La función '$func_name' NO existe. Falló la carga de: $origin"
        EXIT_CODE=1
    fi
}

# A) Verificar Orquestador Principal
check_function "promote_to_dev" "workflows/to-dev.sh"

# B) Verificar Helper (gh-interactions.sh)
check_function "wait_for_pr_approval_or_die" "helpers/gh-interactions.sh"
check_function "__remote_head_sha" "helpers/gh-interactions.sh"

# C) Verificar Estrategia Directa (dev-direct.sh)
check_function "promote_to_dev_direct" "strategies/dev-direct.sh"

# D) Verificar Estrategia Monitor (dev-pr-monitor.sh)
check_function "promote_dev_monitor" "strategies/dev-pr-monitor.sh"

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "🎉 [SUCCESS] La refactorización es exitosa. Todos los módulos se vincularon correctamente."
else
    echo "💥 [FAIL] Faltan funciones críticas. Revisa las rutas en 'to-dev.sh'."
fi

exit $EXIT_CODE