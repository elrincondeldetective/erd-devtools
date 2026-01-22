#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/core/config.sh

# ==============================================================================
# 1. DETECCIÓN DEL ENTORNO
# ==============================================================================
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

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

# --- Políticas de Git (Feature Branch Workflow) ---
export ENFORCE_FEATURE_BRANCH="${ENFORCE_FEATURE_BRANCH:-true}"   # exige feature/*
export AUTO_RENAME_TO_FEATURE="${AUTO_RENAME_TO_FEATURE:-true}"   # renombra si no cumple
export PR_BASE_BRANCH="${PR_BASE_BRANCH:-dev}"                    # PR siempre hacia dev

# --- Flujos CI/CD ---
export POST_PUSH_FLOW="${POST_PUSH_FLOW:-true}"

# ==============================================================================
# 4. DETERMINACIÓN DE MODO (SIMPLE vs PRO)
# ==============================================================================

# Variable para guardar a dónde hacer push (en modo simple es origin por defecto)
export push_target="origin"
export SIMPLE_MODE=false

# Si no hay perfiles definidos en la config, activamos modo simple
if [ ${#PROFILES[@]} -eq 0 ]; then
  SIMPLE_MODE=true
  
  # --- FIX: BYPASS PARA EL SETUP WIZARD ---
  # Si estamos corriendo el wizard (setup-wizard.sh), no bloqueamos la ejecución 
  # si falta user.name, porque el wizard es quien se encargará de configurarlo.
  if [ "${DEVTOOLS_WIZARD_MODE:-false}" == "true" ]; then
      return 0
  fi

  # Validación de seguridad mínima para modo simple
  if [ -z "$(git config user.name)" ]; then
    echo "❌ Error de Configuración: Git user.name no está configurado globalmente."
    echo "   Como no hay perfiles definidos en .git-acprc, git usa tu config global."
    echo "   Ejecuta: git config --global user.name 'Tu Nombre'"
    exit 1
  fi
fi

# 2.1) Asegura main como rama por defecto para futuros repos (Side effect útil)
git config --global init.defaultBranch main >/dev/null