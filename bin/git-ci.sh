#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-ci.sh
set -euo pipefail

# 1. Bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Cargar librerías necesarias
source "${LIB_DIR}/core/utils.sh"
source "${LIB_DIR}/ui/styles.sh"
source "${LIB_DIR}/ci-workflow.sh"  # Aquí es donde ocurre la magia

# 2. Diagnóstico (Para que veas qué detectamos)
ui_step_header "🔍 Diagnóstico de Herramientas CI"

echo "Proyecto raíz: $(git rev-parse --show-toplevel)"
echo "---------------------------------------------------"
echo " NATIVE_CI_CMD     : ${NATIVE_CI_CMD:-❌ No detectado}"
echo " ACT_CI_CMD        : ${ACT_CI_CMD:-❌ No detectado}"
echo " COMPOSE_CI_CMD    : ${COMPOSE_CI_CMD:-❌ No detectado}"
echo " K8S_HEADLESS_CMD  : ${K8S_HEADLESS_CMD:-❌ No detectado}"
echo " K8S_FULL_CMD      : ${K8S_FULL_CMD:-❌ No detectado}"
echo "---------------------------------------------------"

# 3. Simulación de Post-Push
echo
ui_info "Invocando menú de CI (Simulando post-push)..."
echo "(Nota: Esto ejecutará los comandos reales si seleccionas una opción)"
echo

# Detectar rama actual para pasarla al menú
CURRENT_BRANCH="$(git branch --show-current)"
BASE_BRANCH="${PR_BASE_BRANCH:-dev}"

# Forzamos ejecución incluso si no es feature/* para probar,
# pero avisamos.
if [[ "$CURRENT_BRANCH" != feature/* ]]; then
    ui_warn "Estás en '$CURRENT_BRANCH', normalmente el menú solo sale en feature/**."
    if ! ask_yes_no "¿Quieres forzar la prueba del menú?"; then
        exit 0
    fi
fi

# Llamada a la función principal
run_post_push_flow "$CURRENT_BRANCH" "$BASE_BRANCH"