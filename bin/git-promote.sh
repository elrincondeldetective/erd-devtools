#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-promote.sh
#
# Punto de entrada principal para promociones de código.
# Orquesta la carga de librerías, validaciones de entorno y ejecución de workflows.

set -e

# ==============================================================================
# 0.0 DEFAULTS (set -u safe)
# ==============================================================================
# Si no está seteada, por defecto NO forzamos guard canónico extra
export DEVTOOLS_FORCE_CANONICAL_REFS="${DEVTOOLS_FORCE_CANONICAL_REFS:-0}"
export DEVTOOLS_SKIP_CANONICAL_CHECK="${DEVTOOLS_SKIP_CANONICAL_CHECK:-0}"

# ==============================================================================
# 0. BOOTSTRAP & CARGA DE LIBRERÍAS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Cargar utilidades core (logging, ui, guards)
source "${LIB_DIR}/core/utils.sh"
source "${LIB_DIR}/core/git-ops.sh"

# Definir ruta de librerías de promoción
PROMOTE_LIB="${LIB_DIR}/promote"

# Cargar estrategias de versión
source "${PROMOTE_LIB}/version-strategy.sh"

# Helpers comunes (incluye maybe_delete_source_branch)
# Nota: es seguro cargarlo aquí; usa log_* / ask_yes_no ya disponibles.
if [[ -f "${PROMOTE_LIB}/workflows/common.sh" ]]; then
  source "${PROMOTE_LIB}/workflows/common.sh"
fi

# NOTA: Se ha eliminado la dependencia de golden-sha.sh para reducir fricción.
# source "${PROMOTE_LIB}/golden-sha.sh"

# ==============================================================================
# 1. GUARDIA: TOOLSET CANÓNICO
# ==============================================================================
# Esto evita que desarrolladores ejecuten scripts desde una ubicación incorrecta
# o desde una rama que no tiene las últimas herramientas.

DEVTOOLS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

check_canonical_toolset() {
    # Si el comando es doctor (diagnóstico), NO bloqueamos por toolset canónico.
    # Debemos detectar el primer argumento no-flag.
    local first_nonflag=""
    local arg=""
    for arg in "$@"; do
        if [[ "$arg" == -* ]]; then
            continue
        fi
        first_nonflag="$arg"
        break
    done
    if [[ "${first_nonflag:-}" == "doctor" ]]; then
        return 0
    fi

    # Definir ramas canónicas permitidas para ejecutar herramientas
    # Ahora 'dev-update' es la norma, 'feature/dev-update' es legacy.
    local DEVTOOLS_CANONICAL_REFS
    local forced="${DEVTOOLS_FORCE_CANONICAL_REFS:-0}"
    if [[ -n "${forced:-}" && "${forced:-0}" != "0" ]]; then
        IFS=' ' read -r -a DEVTOOLS_CANONICAL_REFS <<< "$forced"
    else
        # Default refs
        DEVTOOLS_CANONICAL_REFS=(dev dev-update)
    fi

    local current_branch
    current_branch="$(git branch --show-current 2>/dev/null || echo "")"

    # Si estamos en modo CI o con flag de skip, saltamos
    if [[ "${DEVTOOLS_SKIP_CANONICAL_CHECK:-0}" == "1" ]]; then
        return 0
    fi

    # Validar si la rama actual está en la lista permitida
    local is_canonical=0
    for ref in "${DEVTOOLS_CANONICAL_REFS[@]}"; do
        if [[ "$current_branch" == "$ref" ]]; then
            is_canonical=1
            break
        fi
    done

    if [[ "$is_canonical" -eq 0 ]]; then
        ui_warn "Estás ejecutando devtools desde la rama '$current_branch'."
        echo "   Por seguridad y consistencia, se recomienda ejecutar promociones"
        echo "   desde una de las ramas canónicas de herramientas."
        echo "   ✅ Recomendado: usar ${DEVTOOLS_CANONICAL_REFS[*]} (nota: feature/dev-update está deprecada)"
        echo
        
        # Permitimos continuar si el usuario insiste, pero advertimos.
        # En modo estricto, esto podría ser un exit 1.
        ask_yes_no "⚠️  ¿Deseas continuar de todas formas bajo tu propio riesgo?" || exit 1
    fi
}

# Ejecutar validación (pasando argumentos para detectar 'doctor')
check_canonical_toolset "$@"

# ==============================================================================
# 1.1 CONTEXTO + LANDING TRAP (restaurar o aterrizar + borrar rama fuente)
# ==============================================================================
export DEVTOOLS_PROMOTE_FROM_BRANCH="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$(git branch --show-current 2>/dev/null || echo "")}"
export DEVTOOLS_PROMOTE_FROM_BRANCH="$(echo "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" | tr -d '[:space:]')"
[[ -n "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" ]] || export DEVTOOLS_PROMOTE_FROM_BRANCH="(detached)"
export DEVTOOLS_PROMOTE_FROM_SHA="${DEVTOOLS_PROMOTE_FROM_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"

# Landing override (vacío = restaurar rama original)
export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="${DEVTOOLS_LAND_ON_SUCCESS_BRANCH:-}"

cleanup_on_exit() {
    local exit_code=$?
    trap - EXIT INT TERM

    # Doctor no debe intentar borrar ramas ni aterrizar raro
    if [[ "${TARGET_ENV:-}" == "doctor" ]]; then
        exit "$exit_code"
    fi

    # ÉXITO: 1) preguntar borrado de rama fuente (solo aplica a feature/*)
    if [[ "$exit_code" -eq 0 ]]; then
        if declare -F maybe_delete_source_branch >/dev/null 2>&1; then
            maybe_delete_source_branch "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}"
        fi

        # ÉXITO: 2) aterrizar en la rama objetivo si está definida
        if [[ -n "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH:-}" ]]; then
            ui_info "🛬 Finalizando flujo (éxito): quedando en '${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}'..."
            git checkout "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}" >/dev/null 2>&1 || true
            exit 0
        fi
    fi

    # FALLO/CANCEL: restaurar rama inicial
    if declare -F git_restore_branch_safely >/dev/null 2>&1; then
        git_restore_branch_safely "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}"
    else
        ui_warn "Finalizando script. Volviendo a ${DEVTOOLS_PROMOTE_FROM_BRANCH:-}..."
        git checkout "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" >/dev/null 2>&1 || true
    fi

    exit "$exit_code"
}

trap 'cleanup_on_exit' EXIT INT TERM

# ==============================================================================
# 2. PARSEO DE ARGUMENTOS
# ==============================================================================
# Soporte simple para flags globales antes del comando
while [[ "$1" == -* ]]; do
    case "$1" in
        -y|--yes)
            export DEVTOOLS_ASSUME_YES=1
            shift
            ;;
        --debug)
            export DEVTOOLS_DEBUG=1
            set -x
            shift
            ;;
        *)
            echo "Opción desconocida: $1"
            exit 1
            ;;
    esac
done

TARGET_ENV="$1"

# Validar argumento requerido
if [[ -z "$TARGET_ENV" ]]; then
    ui_header "Git Promote - Gestor de Ciclo de Vida"
    echo "Uso: git promote [-y | --yes] [TARGET]"
    echo ""
    echo "Targets disponibles:"
    echo "  dev                 : Promocionar a DEV (Lab)"
    echo "  staging             : Promocionar a STAGING (Release Candidate)"
    echo "  prod                : Promocionar a PROD (Live)"
    echo "  sync                : Sincronización inteligente (Smart Sync)"
    echo "  dev-update          : Aplasta (squash) una rama dentro de dev-update"
    echo "  feature/dev-update  : (DEPRECADO) alias de dev-update"
    echo "  hotfix              : Iniciar flujo de hotfix"
    echo "  doctor              : Verificar estado del repo"
    exit 1
fi

# ==============================================================================
# 3. MENÚ DE SEGURIDAD UNIVERSAL (OBLIGATORIO)
# ==============================================================================
# Regla: "Ante la duda, pregunta".
# Este menú aparece SIEMPRE (excepto en doctor/diagnóstico), obligando a elegir
# entre Fast-Forward, Merge o Force.
# Esto define la variable DEVTOOLS_PROMOTE_STRATEGY que usarán los workflows.

if [[ "${TARGET_ENV:-}" != "doctor" ]]; then
    export DEVTOOLS_PROMOTE_STRATEGY
    
    # Función definida en lib/core/utils.sh que muestra el menú A/B/C con emojis
    DEVTOOLS_PROMOTE_STRATEGY="$(promote_choose_strategy_or_die)"

    # Confirmación extra para la opción ☢️ (Solo si no estamos en modo --yes)
    if [[ "$DEVTOOLS_PROMOTE_STRATEGY" == "force" && "${DEVTOOLS_ASSUME_YES:-0}" != "1" ]]; then
        echo
        log_warn "☢️ Elegiste FORCE UPDATE. Esto puede reescribir historia en ramas remotas."
        if ! ask_yes_no "¿Confirmas continuar con FORCE UPDATE?"; then
            die "Abortado por seguridad."
        fi
    fi
    
    # Feedback visual de la elección
    if [[ "${DEVTOOLS_ASSUME_YES:-0}" != "1" ]]; then
        log_info "✅ Estrategia seleccionada: $DEVTOOLS_PROMOTE_STRATEGY"
    fi
fi

# ==============================================================================
# 4. ENRUTAMIENTO (Router)
# ==============================================================================

case "$TARGET_ENV" in
    dev)
        # Cargar módulo to-dev
        source "${PROMOTE_LIB}/workflows/to-dev.sh"
        promote_to_dev
        ;;

    staging)
        # Cargar módulo to-staging
        source "${PROMOTE_LIB}/workflows/to-staging.sh"
        promote_to_staging
        ;;

    prod)
        # Cargar módulo to-prod
        source "${PROMOTE_LIB}/workflows/to-prod.sh"
        promote_to_prod
        ;;

    sync)
        # Cargar módulo sync (macro)
        source "${PROMOTE_LIB}/workflows/sync.sh"
        promote_sync_all
        ;;

    dev-update|feature/dev-update)
        # Workflow de utilidad para squash local hacia la rama de integración
        # Cargar módulo dev-update (asumimos que existe o está en to-dev utils)
        source "${PROMOTE_LIB}/workflows/dev-update.sh"
        
        # En éxito: aterrizar en dev-update (rama promovida)
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="dev-update"
        
        # Si NO se pasó rama fuente, usamos la rama actual (DEVTOOLS_PROMOTE_FROM_BRANCH)
        # Esto hace que: `git promote dev-update` (o `git promote feature/dev-update`) funcione sin sorpresas.
        src_branch="${2:-}"
        if [[ -z "${src_branch:-}" ]]; then
            src_branch="${DEVTOOLS_PROMOTE_FROM_BRANCH:-}"
            log_info "ℹ️  No se indicó rama fuente. Usando rama actual: ${src_branch}"
        fi

        # Guardias: evitar intentos absurdos (fuente inválida)
        case "${src_branch:-}" in
            ""|"(detached)"|dev-update|feature/dev-update|dev|main|staging|prod)
                die "⛔ Rama fuente inválida para dev-update: '${src_branch}'. Usa: git promote dev-update feature/<rama>"
                ;;
        esac

        promote_dev_update_squash "${src_branch}"
        ;;

    feature/*)
        # Alias directo para squashear una feature
        source "${PROMOTE_LIB}/workflows/dev-update.sh"
        # En éxito: aterrizar en dev-update (rama promovida)
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="dev-update"
        promote_dev_update_squash "$TARGET_ENV"
        ;;

    hotfix)
        source "${PROMOTE_LIB}/workflows/hotfix.sh"
        promote_hotfix_start "${2:-}"
        ;;

    doctor)
        source "${LIB_DIR}/checks/doctor.sh"
        run_doctor
        ;;

    *)
        ui_error "Target no reconocido: $TARGET_ENV"
        exit 1
        ;;
esac

exit 0