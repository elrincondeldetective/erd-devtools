#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/core/config.sh

# ==============================================================================
# 1. DETECCIÓN DEL ENTORNO
# ==============================================================================

# --- FIX: DETECCIÓN ROBUSTA DE ROOT (Submódulos vs Superproyecto) ---
# Intentamos obtener la raíz del superproyecto (si esto es un submódulo .devtools).
# Si no, caemos al toplevel normal o al directorio actual.
PROJECT_ROOT="$(git rev-parse --show-superproject-working-tree 2>/dev/null || echo "")"
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# --- FASE 1 (NUEVO): ROOTS CANÓNICOS PARA VERSIONADO Y ORQUESTACIÓN ---
# Objetivo:
# - REPO_ROOT: raíz del repo actual (si estás en un submódulo, es la raíz del submódulo).
# - WORKSPACE_ROOT: raíz del superproyecto (si existe); si no, vacío.
# - PROJECT_ROOT (compat): se mantiene como “workspace” cuando hay superproyecto, o repo root si no.
#
# Esto permite que los scripts de versionado NO lean VERSION desde .devtools embebido por error,
# y en su lugar usen siempre $REPO_ROOT/VERSION como fuente de verdad del repo actual.
export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export WORKSPACE_ROOT="$(git rev-parse --show-superproject-working-tree 2>/dev/null || echo "")"
export PROJECT_ROOT

# Rutas de configuración con prioridad:
# 1. Específica del toolset (.devtools)
# 2. Local del repositorio (raíz)
# 3. Global de usuario (home)
DEVTOOLS_CONFIG="${PROJECT_ROOT}/.devtools/.git-acprc"
LOCAL_CONFIG="${PROJECT_ROOT}/.git-acprc"
USER_CONFIG="${HOME}/scripts/.git-acprc"

# ==============================================================================
# 2. CARGA DE CONFIGURACIÓN
# ==============================================================================
if [ -f "$DEVTOOLS_CONFIG" ]; then
  # shellcheck disable=SC1090
  source "$DEVTOOLS_CONFIG"
elif [ -f "$LOCAL_CONFIG" ]; then
  # shellcheck disable=SC1090
  source "$LOCAL_CONFIG"
elif [ -f "$USER_CONFIG" ]; then
  # shellcheck disable=SC1090
  source "$USER_CONFIG"
fi

# ==============================================================================
# 3. DEFINICIÓN DE DEFAULTS (Variables Globales)
# ==============================================================================

# --- Metricas y Gamificación ---
export DAY_START="${DAY_START:-00:00}"
export REFS_LABEL="${REFS_LABEL:-Conteo: commit}"
export DAILY_GOAL="${DAILY_GOAL:-10}"

# --- Identidades y GitHub ---
# Inicializamos el array de perfiles de forma segura
export PROFILES=("${PROFILES[@]:-}")
export GH_AUTO_CREATE="${GH_AUTO_CREATE:-false}"
export GH_DEFAULT_VISIBILITY="${GH_DEFAULT_VISIBILITY:-private}"

# --- Contrato de Perfil (Profile Schema) ---
export PROFILE_SCHEMA_VERSION=1
# Schema V1 Order:
# 0:display_name ; 1:git_name ; 2:git_email ; 3:signing_key ; 
# 4:push_target  ; 5:ssh_host ; 6:ssh_key_path ; 7:gh_owner

# --- Políticas de Git (Feature Branch Workflow) ---
export ENFORCE_FEATURE_BRANCH="${ENFORCE_FEATURE_BRANCH:-true}"   # exige feature/*
export AUTO_RENAME_TO_FEATURE="${AUTO_RENAME_TO_FEATURE:-true}"   # renombra si no cumple
export PR_BASE_BRANCH="${PR_BASE_BRANCH:-dev}"                    # PR siempre hacia dev

# --- Flujos CI/CD ---
export POST_PUSH_FLOW="${POST_PUSH_FLOW:-true}"

# ==============================================================================
# DEFAULTS PARA ESPERA DE MERGE DE PR (Polling)
# ==============================================================================
# Objetivo:
# - Parametrizar la espera/polling del merge automático del PR.
export DEVTOOLS_PR_MERGE_TIMEOUT_SECONDS="${DEVTOOLS_PR_MERGE_TIMEOUT_SECONDS:-900}"
export DEVTOOLS_PR_MERGE_POLL_SECONDS="${DEVTOOLS_PR_MERGE_POLL_SECONDS:-5}"

# ==============================================================================
# FASE 3.1 (NUEVO): DEFAULTS PARA ESPERA DE APROBACIÓN (Gate Humano)
# ==============================================================================
# Objetivo:
# - Permitir parametrizar la espera de aprobación de PR antes de habilitar auto-merge.
# - Evitar cuelgues por defecto: timeout=0 significa "sin timeout" (espera indefinida).
# - Mantener bypass explícito para casos de reparación.
export DEVTOOLS_PR_APPROVAL_TIMEOUT_SECONDS="${DEVTOOLS_PR_APPROVAL_TIMEOUT_SECONDS:-0}"
export DEVTOOLS_PR_APPROVAL_POLL_SECONDS="${DEVTOOLS_PR_APPROVAL_POLL_SECONDS:-10}"
export DEVTOOLS_SKIP_PR_APPROVAL_WAIT="${DEVTOOLS_SKIP_PR_APPROVAL_WAIT:-0}"

# ==============================================================================
# FASE 3.2 (NUEVO): DEFAULTS PARA ESPERA DE PR DE RELEASE-PLEASE (OPCIONAL)
# ==============================================================================
# Objetivo:
# - Evitar que el flujo se quede bloqueado cuando release-please NO abre PR (caso común).
# - Por defecto, esperamos un "grace window" corto; 0 = no esperar nunca.
export DEVTOOLS_RP_PR_WAIT_TIMEOUT_SECONDS="${DEVTOOLS_RP_PR_WAIT_TIMEOUT_SECONDS:-60}"
export DEVTOOLS_RP_PR_WAIT_POLL_SECONDS="${DEVTOOLS_RP_PR_WAIT_POLL_SECONDS:-2}"

# ==============================================================================
# 4. DETERMINICIÓN DE MODO (SIMPLE vs PRO)
# ==============================================================================

# Variable para guardar a dónde hacer push (en modo simple es origin por defecto)
export push_target="origin"
export SIMPLE_MODE=false

# 4.1) Asegura main como rama por defecto para futuros repos
# (Lo ponemos antes de las validaciones para asegurar que se ejecute siempre)
git config --global init.defaultBranch main >/dev/null 2>&1 || true

# Si no hay perfiles definidos en la config, activamos modo simple
if [ ${#PROFILES[@]} -eq 0 ]; then
  SIMPLE_MODE=true
  
  # --- FIX: BYPASS PARA EL SETUP WIZARD ---
  # Si estamos corriendo el wizard (setup-wizard.sh), no bloqueamos la ejecución 
  # si falta user.name, porque el wizard es quien se encargará de configurarlo.
  if [ "${DEVTOOLS_WIZARD_MODE:-false}" == "true" ]; then
      # FIX: Return seguro que funciona tanto si se hace source como si se ejecuta
      return 0 2>/dev/null || exit 0
  fi

  # Validación de seguridad mínima para modo simple
  if [ -z "$(git config user.name)" ]; then
    echo "❌ Error de Configuración: Git user.name no está configurado globalmente."
    echo "   Como no hay perfiles definidos en .git-acprc, git usa tu config global."
    echo "   Ejecuta: git config --global user.name 'Tu Nombre'"
    exit 1
  fi
fi

# ==============================================================================
# 5. NORMALIZACIÓN / BACKWARD COMPAT DE PROFILES (Modelo de Identidades)
# ==============================================================================
# Objetivo:
# - Soportar perfiles viejos (menos campos) rellenando defaults.
# - Tolerar entradas inválidas sin romper todo el toolset.
# - Garantizar que el runtime (ssh-ident.sh) reciba entradas consistentes.
#
# Nota: Bash no exporta arrays a subshells como variables de entorno “reales”,
# pero esto igual sirve para estandarizar el array dentro del proceso actual.

normalize_profiles_v1() {
  # Si no hay perfiles, no hacemos nada.
  if [ ${#PROFILES[@]} -eq 0 ]; then
    return 0
  fi

  local -a normalized=()

  local p
  for p in "${PROFILES[@]}"; do
    # Ignorar entradas vacías (por seguridad)
    if [ -z "$p" ]; then
      continue
    fi

    # Split por ';' según el contrato (V1).
    local IFS=';'
    local -a parts=()
    # shellcheck disable=SC2206
    parts=($p)
    local n="${#parts[@]}"

    # Reglas mínimas: al menos display_name, git_name, git_email
    if [ "$n" -lt 3 ]; then
      echo "⚠️  Perfil inválido (muy corto), se ignora: $p" >&2
      continue
    fi

    # Si tiene menos campos que el schema V1, rellenamos con strings vacíos
    # para evitar lecturas fuera de rango en otros scripts.
    while [ "${#parts[@]}" -lt 8 ]; do
      parts+=("")
    done

    # Si tiene más campos que V1, truncamos (no rompemos el menú)
    if [ "$n" -gt 8 ]; then
      echo "⚠️  Perfil con campos extra (se truncará a V1): ${parts[0]}" >&2
      parts=("${parts[@]:0:8}")
    fi

    # Defaults razonables para evitar valores vacíos críticos:
    # - push_target: origin
    # - ssh_host: github.com
    if [ -z "${parts[4]}" ]; then parts[4]="origin"; fi
    if [ -z "${parts[5]}" ]; then parts[5]="github.com"; fi

    # Recomponer entry normalizada
    normalized+=("$(IFS=';'; echo "${parts[*]}")")
  done

  # Reemplazamos PROFILES por la versión normalizada
  export PROFILES=("${normalized[@]}")
}

# Ejecutamos normalización al cargar config (para todo el runtime)
normalize_profiles_v1

