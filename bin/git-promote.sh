#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-promote.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 1. BOOTSTRAP DE LIBRERÍAS.
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Definimos REPO_ROOT globalmente para que todas las libs lo puedan usar
if [[ -z "${REPO_ROOT:-}" ]]; then
    export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# --- Carga de Librerías Core ---
source "${LIB_DIR}/core/utils.sh"       # Logs, UI
source "${LIB_DIR}/core/config.sh"      # Config Global (SIMPLE_MODE)
source "${LIB_DIR}/core/git-ops.sh"     # Git Ops básicos
source "${LIB_DIR}/release-flow.sh"     # Versioning tools
source "${LIB_DIR}/ssh-ident.sh"        # Gestión de Identidad

# --- Carga de Módulos Refactorizados (Divide y Vencerás) ---
PROMOTE_LIB="${LIB_DIR}/promote"

# 1. Estrategia de Versionado (Fases 1 y 2)
source "${PROMOTE_LIB}/version-strategy.sh"

# 2. Integridad del Golden SHA (Fase 3)
source "${PROMOTE_LIB}/golden-sha.sh"

# 3. Integración con GitOps (Fase 4)
source "${PROMOTE_LIB}/gitops-integration.sh"

# 4. Flujos de Trabajo Principales (Lógica de Negocio)
source "${PROMOTE_LIB}/workflows.sh"

# ==============================================================================
# 0.1 PARSEO TEMPRANO DE FLAGS (antes de cualquier guardia)
# ==============================================================================
DEVTOOLS_AUTO_APPROVE=false
while (( $# )); do
  case "${1:-}" in
    -y|--yes)
      DEVTOOLS_AUTO_APPROVE=true
      export DEVTOOLS_ASSUME_YES=1
      shift
      ;;
    *) break ;;
  esac
done

TARGET_ENV="${1:-}"

# ==============================================================================
# 0. GUARDIA: TOOLSET CANÓNICO (evita "se arregla y vuelve" por rama del submódulo)
# ==============================================================================
DEVTOOLS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ ${#DEVTOOLS_CANONICAL_REFS[@]:-0} -eq 0 ]]; then
  DEVTOOLS_CANONICAL_REFS=(dev feature/dev-update)
fi
DEVTOOLS_BYPASS_CANONICAL_GUARD="${DEVTOOLS_BYPASS_CANONICAL_GUARD:-0}"

if [[ "$DEVTOOLS_BYPASS_CANONICAL_GUARD" != "1" ]] && git -C "$DEVTOOLS_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tool_branch="$(git -C "$DEVTOOLS_ROOT" branch --show-current 2>/dev/null || echo "")"
  tool_sha="$(git -C "$DEVTOOLS_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  tool_ver="$(cat "$DEVTOOLS_ROOT/lib/core/version.sh" 2>/dev/null || echo "unknown")"

  allowed=0
  for ref in "${DEVTOOLS_CANONICAL_REFS[@]}"; do
    [[ "$tool_branch" == "$ref" ]] && allowed=1 && break
  done

  # Excepción: main permitido solo para hotfix explícito o si estás en hotfix/*
  __cmd="${1:-}"
  if [[ "$tool_branch" == "main" ]]; then
    if [[ "$__cmd" == "hotfix" || "$__cmd" == "hotfix-finish" || "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" == hotfix/* ]]; then
      allowed=1
    fi
  fi

  if [[ "$allowed" -ne 1 ]]; then
    echo
    log_warn "🧭 Toolset NO canónico detectado: branch='${tool_branch:-detached}' sha=${tool_sha} (devtools ${tool_ver})"
    log_warn "Este repo .devtools es versionado por rama: el comportamiento cambia según tu working tree."
    echo "✅ Recomendado: usar ${DEVTOOLS_CANONICAL_REFS[*]}"
    echo

    # Repo sucio => no tocamos nada
    if [[ -n "$(git -C "$DEVTOOLS_ROOT" status --porcelain 2>/dev/null)" ]]; then
      die "El toolset tiene cambios locales. Haz commit/stash o exporta DEVTOOLS_BYPASS_CANONICAL_GUARD=1."
    fi

    # En --yes asumimos switch automático al primer canónico
    if [[ "${DEVTOOLS_ASSUME_YES:-0}" == "1" ]] || ask_yes_no "¿Cambiar el toolset a '${DEVTOOLS_CANONICAL_REFS[0]}' y re-ejecutar?"; then
      git -C "$DEVTOOLS_ROOT" fetch origin --prune >/dev/null 2>&1 || true
      git -C "$DEVTOOLS_ROOT" checkout "${DEVTOOLS_CANONICAL_REFS[0]}" >/dev/null 2>&1 || die "No pude cambiar a rama canónica."
      exec "$DEVTOOLS_ROOT/bin/git-promote.sh" "$@"
    else
      die "Abortado para evitar ejecutar un toolset desalineado. Cambia a una rama canónica y reintenta."
    fi
  fi
fi

# ==============================================================================
# 1.1 CONTEXTO: rama desde la que se invoca (antes de cualquier checkout)
# ==============================================================================
# ✅ FIX: siempre inicializar estas vars (set -u no perdona)
export DEVTOOLS_PROMOTE_FROM_BRANCH="${DEVTOOLS_PROMOTE_FROM_BRANCH:-$(git branch --show-current 2>/dev/null || true)}"
export DEVTOOLS_PROMOTE_FROM_BRANCH="$(echo "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" | tr -d '[:space:]')"

if [[ -z "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" ]]; then
  export DEVTOOLS_PROMOTE_FROM_BRANCH="(detached)"
fi

export DEVTOOLS_PROMOTE_FROM_SHA="${DEVTOOLS_PROMOTE_FROM_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"

# Landing override (solo en éxito). Vacío = comportamiento antiguo (restaurar).
export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="${DEVTOOLS_LAND_ON_SUCCESS_BRANCH:-}"

# ==============================================================================
# 1.2 SEGURIDAD DE RAMAS (LANDING TRAP) - [NUEVO]
# ==============================================================================
# Esta función se ejecuta automáticamente al salir (EXIT) o al cancelar (Ctrl+C).
# Garantiza que el usuario siempre regrese a su rama original o aterrice en la destino si hubo éxito.
cleanup_on_exit() {
    local exit_code=$?
    trap - EXIT INT TERM

    if [[ "${TARGET_ENV:-}" != "_dev-monitor" ]]; then
        # ÉXITO: obedecer landing override si existe
        if [[ "$exit_code" -eq 0 && -n "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH:-}" ]]; then
            local cur
            cur="$(git branch --show-current 2>/dev/null || true)"
            if [[ "$cur" != "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}" ]]; then
                echo "🛬 Finalizando flujo (éxito): quedando en '${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}'..."
                git checkout "${DEVTOOLS_LAND_ON_SUCCESS_BRANCH}" >/dev/null 2>&1 || true
            fi
            exit 0
        fi

        # FALLO/CANCEL: restaurar rama inicial
        if declare -F git_restore_branch_safely >/dev/null; then
            git_restore_branch_safely "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}"
        else
            echo "⚠️  Finalizando script. Volviendo a ${DEVTOOLS_PROMOTE_FROM_BRANCH:-}..."
            git checkout "${DEVTOOLS_PROMOTE_FROM_BRANCH:-}" >/dev/null 2>&1 || true
        fi
    fi
    exit $exit_code
}
# Registramos el trap
trap 'cleanup_on_exit' EXIT INT TERM

# ==============================================================================
# 2. PARSEO DE FLAGS Y SETUP DE IDENTIDAD
# ==============================================================================

# Nota: El parseo de -y/--yes ya se realizó en la sección 0.1 y se hizo shift.
# Mantenemos este bloque por si hay lógica adicional o para setup de SSH.

# Si no estamos en modo simple, cargamos las llaves SSH antes de empezar
# EXCEPCIÓN: `_dev-monitor` debe ser no-interactivo (puede correr con nohup/sin TTY).
if [[ "${SIMPLE_MODE:-false}" == "false" && "${1:-}" != "_dev-monitor" ]]; then
    setup_git_identity
fi

# ==============================================================================
# 3. PARSEO DE COMANDOS (ROUTER)
# ==============================================================================

TARGET_ENV="${1:-}"

# Landing policy por comando (opcional, legacy police mode)
if [[ "$TARGET_ENV" == "dev" ]]; then
    # Policía: siempre caer en dev aunque exit!=0 (si se requiere lógica estricta antigua)
    # Nota: La nueva cleanup_on_exit prioriza éxito/fallo genérico,
    # pero dev puede configurarse aquí si fuera necesario.
    export DEVTOOLS_LAND_ON_EXIT_BRANCH="dev"
fi

# --- Guardias de Seguridad y Confirmación ---
if [[ -n "$TARGET_ENV" && "$TARGET_ENV" != "_dev-monitor" ]]; then

    # Dev monitor (admin) no requiere repo limpio (solo observación), salvo modo directo
    if [[ "$TARGET_ENV" == "dev" && "${DEVTOOLS_PROMOTE_DEV_DIRECT:-0}" != "1" ]]; then
        :
    # Doctor no requiere confirmación ni guardias
    elif [[ "$TARGET_ENV" == "doctor" ]]; then
        :
    else
    
    # 1. Validar que el working tree esté limpio antes de cualquier operación destructiva
    if declare -F ensure_clean_git_or_die >/dev/null; then
        ensure_clean_git_or_die
    else
        ensure_clean_git # Fallback a git-ops.sh si checks.sh no está cargado
    fi
    fi

    # 2. Confirmación Obligatoria (Anti-errores)
    # Dev monitor (admin) NO es destructivo por defecto → no mostrar warning global
    if [[ "$TARGET_ENV" == "dev" && "${DEVTOOLS_PROMOTE_DEV_DIRECT:-0}" != "1" ]]; then
        :
    elif [[ "$TARGET_ENV" == "doctor" ]]; then
        :
    elif [[ "$DEVTOOLS_AUTO_APPROVE" == "false" ]]; then
        echo
        log_warn "⚠️  OPERACIÓN DE PROMOCIÓN APLASTANTE (Destructive Promotion)"
        echo "Contenido de la rama destino '$TARGET_ENV' será reemplazado por '${DEVTOOLS_PROMOTE_FROM_BRANCH:-}'."
        echo "Esto ejecutará un 'reset --hard' y 'push --force-with-lease' en el remoto."
        echo
        if ! ask_yes_no "¿Estás seguro de que deseas continuar?"; then
            log_info "Operación cancelada. No se realizaron cambios."
            exit 0
        fi
    fi
fi

case "$TARGET_ENV" in
    doctor)
        # Doctor: checks rápidos de coherencia (no destructivo)
        failures=0
        strict="${DEVTOOLS_DOCTOR_STRICT:-0}"
        echo
        echo "🩺 devtools doctor"

        # A) dev-update: no debe tener el log viejo
        du="${DEVTOOLS_ROOT}/lib/promote/workflows/dev-update.sh"
        if [[ -f "$du" ]] && grep -q "Limpiando rama fuente ya integrada" "$du"; then
            echo "❌ dev-update.sh: aún contiene limpieza vieja"
            failures=$((failures+1))
        else
            echo "✅ dev-update.sh: OK (sin limpieza vieja)"
        fi

        # B) dev-update: debe invocar maybe_delete_source_branch
        if [[ -f "$du" ]] && ! grep -q "maybe_delete_source_branch" "$du"; then
            echo "❌ dev-update.sh: NO invoca maybe_delete_source_branch"
            failures=$((failures+1))
        else
            echo "✅ dev-update.sh: usa maybe_delete_source_branch"
        fi

        # C) promote: landing override presente
        if ! grep -q "DEVTOOLS_LAND_ON_SUCCESS_BRANCH" "$0"; then
            echo "❌ git-promote: falta DEVTOOLS_LAND_ON_SUCCESS_BRANCH"
            failures=$((failures+1))
        else
            echo "✅ git-promote: landing override OK"
        fi

        # D) --yes => assume yes
        if ! grep -q "export DEVTOOLS_ASSUME_YES=1" "$0"; then
            echo "❌ git-promote: --yes no propaga DEVTOOLS_ASSUME_YES=1"
            failures=$((failures+1))
        else
            echo "✅ git-promote: --yes non-interactive OK"
        fi

        # E) guard canónico default correcto
        if grep -q 'DEVTOOLS_CANONICAL_REFS=.*main' "$0"; then
            echo "❌ guard canónico: main aún está en defaults"
            failures=$((failures+1))
        else
            echo "✅ guard canónico: defaults sin main (dev + feature/dev-update)"
        fi

        echo
        if [[ "$failures" -eq 0 ]]; then
            echo "✅ Doctor OK"
            exit 0
        fi
        echo "⚠️  Doctor encontró $failures problema(s)."
        [[ "$strict" == "1" ]] && exit 1 || exit 0
        ;;
    dev)
        # ✅ Si `git promote dev` termina en éxito, aterrizamos en dev
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="dev"
        promote_to_dev
        ;;
    _dev-monitor)
        promote_dev_monitor "${2:-}" "${3:-}"
        ;;
    staging)
        promote_to_staging
        ;;
    prod)
        promote_to_prod
        ;;
    sync)
        promote_sync_all
        ;;
    dev-update|feature/dev-update)
        # Permite pasar una rama opcional como segundo argumento
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="feature/dev-update"
        promote_dev_update_squash "${2:-}"
        ;;
    feature/*)
        # UX: permitir "git promote feature/mi-rama" para aplastar esa rama
        # dentro de feature/dev-update (y pushear el resultado al remoto).
        export DEVTOOLS_LAND_ON_SUCCESS_BRANCH="feature/dev-update"
        promote_dev_update_squash "$TARGET_ENV"
        ;;
    hotfix)
        create_hotfix
        ;;
    hotfix-finish)
        finish_hotfix
        ;;
    *) 
        echo "Uso: git promote [-y | --yes] [dev | staging | prod | sync | feature/dev-update | hotfix | hotfix-finish | doctor]"
        echo
        echo "Comandos disponibles:"
        echo "  dev                 : Monitor estricto (admin) del estado de 'dev' (PRs/CI). No crea PR."
        echo "                        Bypass: DEVTOOLS_BYPASS_STRICT=1 (emergencia)."
        echo "                        Modo directo (destructivo): DEVTOOLS_PROMOTE_DEV_DIRECT=1"
        echo "  staging             : Promueve dev -> staging (gestiona Tags/RC)"
        echo "  prod                : Promueve staging -> main (gestiona Release Tags)"
        echo "  sync                : Sincronización inteligente (Smart Sync)"
        echo "  feature/dev-update  : Aplasta (squash) una rama dentro de feature/dev-update"
        echo "  feature/<rama>      : Alias de lo anterior (squash + push a feature/dev-update)"
        echo "  hotfix              : Crea una rama de hotfix desde main"
        echo "  hotfix-finish       : Finaliza e integra el hotfix"
        echo "  doctor              : Verifica la salud y coherencia del toolset"
        echo
        echo "Opciones:"
        echo "  -y, --yes           : Salta las confirmaciones de seguridad (Modo no-interactivo)"
        exit 1
        ;;
esac