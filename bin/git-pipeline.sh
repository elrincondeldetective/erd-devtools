#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-pipeline.sh
set -euo pipefail

# Bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
source "${LIB_DIR}/core/utils.sh"
# No cargamos config.sh entero para evitar logs innecesarios,
# pero cargamos el workflow que tiene la lógica de detección.
source "${LIB_DIR}/ci-workflow.sh"

echo "🚀 Iniciando Pipeline Local (via Git)..."

# Asegurar detección
detect_ci_tools

# CAMBIO FASE 1.1: Usar K8S_FULL_CMD en lugar de LOCAL_PIPELINE_CMD
if [[ -n "${K8S_FULL_CMD:-}" ]]; then
  echo "▶️  Ejecutando: $K8S_FULL_CMD"
  # Usamos eval para permitir comandos compuestos (ej. "task build && task deploy")
  eval "$K8S_FULL_CMD"
else
  log_error "No se detectó un contrato de pipeline local (task pipeline:local)."
  echo "   Asegúrate de tener un Taskfile.yaml con la tarea 'pipeline:local'."
  exit 1
fi