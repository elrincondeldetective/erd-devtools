#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/git-flow.sh

# ==============================================================================
# 1. VALIDACIONES DE RAMAS
# ==============================================================================

# Verifica si una rama está protegida (no se debe commitear directo)
is_protected_branch() {
  case "$1" in 
    main|master|dev|staging|prod) return 0 ;; 
    *) return 1 ;; 
  esac
}

# Limpia un string para que sea válido en una rama (quita espacios, slashes, etc.)
sanitize_feature_suffix() {
  local b="$1"
  b="${b//\//-}"           # Slash -> guion
  b="${b// /-}"            # Espacio -> guion
  b="${b//[^a-zA-Z0-9._-]/-}" # Caracteres raros -> guion
  b="$(echo "$b" | sed -E 's/-+/-/g')" # Guiones duplicados -> uno solo
  echo "$b"
}

# Sugiere el nombre feature/xxx
suggest_feature_branch() { 
    echo "feature/$(sanitize_feature_suffix "$1")" 
}

# Genera un nombre único si la rama ya existe (añade -1, -2, etc.)
unique_branch_name() {
  local name="$1"
  if ! git show-ref --verify --quiet "refs/heads/$name"; then 
      echo "$name"
      return 0
  fi
  
  local i=1
  while git show-ref --verify --quiet "refs/heads/${name}-${i}"; do 
      ((i++))
  done
  echo "${name}-${i}"
}

# ==============================================================================
# 2. POLÍTICAS DE ENFORCEMENT (Feature Branch Workflow)
# ==============================================================================

ensure_feature_branch_or_rename() {
  local branch="$1"
  
  # Si ya cumple el patrón, salimos
  if [[ "$branch" == feature/* ]]; then return 0; fi
  
  # Si la política está desactivada, salimos
  # (Se asume que la variable ENFORCE_FEATURE_BRANCH viene de config.sh)
  if [[ "${ENFORCE_FEATURE_BRANCH:-true}" != "true" ]]; then return 0; fi
  
  # Si es protegida, se maneja en la función _before_commit, aquí ignoramos
  if is_protected_branch "$branch"; then return 0; fi

  local new_branch
  new_branch="$(suggest_feature_branch "$branch")"
  
  echo "⚠️  Tu rama actual NO cumple la política feature/**"
  echo "   Rama actual: $branch"
  echo "   Sugerencia : $new_branch"

  # Variable AUTO_RENAME_TO_FEATURE viene de config.sh
  if [[ "${AUTO_RENAME_TO_FEATURE:-true}" == "true" ]]; then
    # Usamos is_tty y ask_yes_no definidos en utils.sh (se asume cargado)
    if is_tty; then
      if ! ask_yes_no "¿Renombrar automáticamente a '$new_branch'?"; then
         echo "✋ Cancelado."; exit 2
      fi
    fi
    
    git branch -m "$branch" "$new_branch"
    echo "✅ Rama renombrada localmente: $branch -> $new_branch"
  else
    echo "✋ Abortado. Crea una rama feature/* con: git feature <nombre>"
    exit 2
  fi
}

ensure_feature_branch_before_commit() {
  local branch
  branch="$(git branch --show-current 2>/dev/null || echo "")"

  # Caso: Head desacoplado (Detached HEAD)
  if [[ -z "$branch" ]]; then
    echo "⚠️ HEAD desacoplado. Creando una rama feature/* para commitear..."
    local short_sha
    short_sha="$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
    git checkout -b "feature/detached-${short_sha}"
    return 0
  fi

  # Check rápido de política desactivada
  [[ "${ENFORCE_FEATURE_BRANCH:-true}" == "true" ]] || return 0
  
  # Si ya es feature, todo OK
  [[ "$branch" == feature/* ]] && return 0
  # Permitimos rama de laboratorio (nuevo nombre canónico)
  [[ "$branch" == "dev-update" ]] && return 0
  # Compat (deprecado)
  [[ "$branch" == "feature/dev-update" ]] && return 0
  [[ "$branch" == hotfix/* ]] && return 0 # Permitimos hotfix también
  [[ "$branch" == fix/* ]] && return 0    # Permitimos fix también

  # Caso: Rama protegida (main, dev...) -> Migrar trabajo a nueva rama
  if is_protected_branch "$branch"; then
    local short_sha new_branch
    
    # Capturar upstream ANTES de movernos de rama (para limpiar bien la protegida)
    local protected_upstream=""
    protected_upstream="$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)"

    short_sha="$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
    # FIX: normalizar por seguridad (evita casos como "-c79fd03")
    short_sha="$(echo "$short_sha" | tr -cd '0-9a-f')"
    [[ -n "$short_sha" ]] || short_sha="$(date +%Y%m%d%H%M%S)"
    
    # Creamos nombre único basado en la rama original
    new_branch="$(unique_branch_name "$(sanitize_feature_suffix "${branch}-${short_sha}")")"

    ui_header "🧹 Seguridad: Rama protegida detectada"
    ui_warn "Estabas en '$branch' (protegida)."
    ui_info "✅ Para evitar commits en ramas protegidas, tu trabajo se moverá a:"
    ui_success "➡️  $new_branch"
    echo

    git checkout -b "$new_branch"
    
    # Limpieza local de la rama protegida: alinearla a su upstream (solo puntero local)
    if [[ -n "${protected_upstream:-}" ]]; then
        git branch -f "$branch" "$protected_upstream" >/dev/null 2>&1 || true
        ui_info "🧼 Rama protegida '$branch' alineada a '$protected_upstream' (solo local)."
    else
        ui_warn "No se detectó upstream para '$branch'. No se limpió el puntero local."
    fi
    ui_info "📌 Tu commit se hará en '$new_branch'. No perdiste cambios."
    return 0
  fi

  # Caso: Rama normal pero mal nombrada (ej: "mi-cambio" -> "feature/mi-cambio")
  ensure_feature_branch_or_rename "$branch"
}
