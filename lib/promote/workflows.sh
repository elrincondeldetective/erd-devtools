#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/promote/workflows.sh
#
# Este módulo es el punto de entrada (Facade) para los flujos de trabajo.
#
# REFACTORIZACIÓN "DIVIDE Y VENCERÁS":
# La lógica monolítica se ha dividido en módulos independientes dentro de
# la carpeta 'workflows/'. Este archivo se encarga de cargarlos en orden.
#
# Módulos cargados:
# - common.sh: Helpers de limpieza y compatibilidad.
# - checks.sh: Funciones de espera y polling (Github/Tags).
# - sync.sh: promote_sync_all
# - dev-update.sh: promote_dev_update_squash
# - to-dev.sh: promote_to_dev
# - to-staging.sh: promote_to_staging
# - to-prod.sh: promote_to_prod
# - hotfix.sh: create_hotfix / finish_hotfix

# Dependencias implícitas (deben ser cargadas por el script principal antes de este):
# - utils.sh, config.sh, git-ops.sh, release-flow.sh
# - promote/version-strategy.sh
# - promote/golden-sha.sh
# - promote/gitops-integration.sh

# ==============================================================================
# CARGA DE SUB-MÓDULOS
# ==============================================================================

# Obtener el directorio actual de este script para realizar sources relativos seguros
__WORKFLOWS_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workflows"

# 1. Cargar utilidades base y verificaciones
source "${__WORKFLOWS_DIR__}/common.sh"
source "${__WORKFLOWS_DIR__}/checks.sh"

# 2. Cargar lógica de negocio (Flujos)
source "${__WORKFLOWS_DIR__}/sync.sh"
source "${__WORKFLOWS_DIR__}/dev-update.sh"
source "${__WORKFLOWS_DIR__}/to-dev.sh"
source "${__WORKFLOWS_DIR__}/to-staging.sh"
source "${__WORKFLOWS_DIR__}/to-prod.sh"
source "${__WORKFLOWS_DIR__}/hotfix.sh"