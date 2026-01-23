#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/git-profile.sh
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 0. BOOTSTRAP (Auto-discovery de paths)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_BASE="${SCRIPT_DIR}"

# Core
# shellcheck disable=SC1090
source "${LIB_BASE}/core/utils.sh"
# shellcheck disable=SC1090
source "${LIB_BASE}/core/git-ops.sh"
# shellcheck disable=SC1090
source "${LIB_BASE}/ui/styles.sh"
# shellcheck disable=SC1090
source "${LIB_BASE}/ssh-ident.sh"

# ==============================================================================
# 1. ROOT & RC FILE (Superproject-aware)
# ==============================================================================
detect_root() {
  if command -v detect_workspace_root >/dev/null 2>&1; then
    detect_workspace_root
    return 0
  fi

  local super=""
  super="$(git rev-parse --show-superproject-working-tree 2>/dev/null || echo "")"
  if [[ -n "$super" ]]; then
    echo "$super"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

ROOT="$(detect_root)"

# Preferimos la config “oficial” de devtools dentro del superproject
RC_FILE="${ROOT}/.devtools/.git-acprc"
ALT_RC_FILE="${ROOT}/.git-acprc"

ensure_rc_file_exists() {
  mkdir -p "$(dirname "$RC_FILE")"

  if [[ -f "$RC_FILE" ]]; then
    return 0
  fi

  if [[ -f "$ALT_RC_FILE" ]]; then
    # Si existe la del root, no la movemos automáticamente: solo la usamos como fallback.
    return 0
  fi

  # Si no existe ninguna, creamos la de .devtools (preferida)
  cat <<EOF > "$RC_FILE"
# Configuración generada por ERD Devtools (Profile Manager)
PROFILE_SCHEMA_VERSION=1
DAY_START="00:00"
REFS_LABEL="Conteo: commit"
DAILY_GOAL=10
PROFILES=()
EOF
}

ensure_schema_version_present() {
  local target="$1"
  [[ -f "$target" ]] || return 0

  if ! grep -qE '^[[:space:]]*PROFILE_SCHEMA_VERSION=' "$target"; then
    local tmp="${target}.schema.tmp"
    cp "$target" "$tmp"
    {
      echo "# Auto-agregado por git-profile ($(date +%F)): Schema Version"
      echo "PROFILE_SCHEMA_VERSION=1"
      echo ""
      cat "$tmp"
    } > "${tmp}.final"
    mv "${tmp}.final" "$target"
    rm -f "$tmp" 2>/dev/null || true
  fi
}

pick_rc_file() {
  # Preferimos .devtools/.git-acprc si existe; si no, usamos .git-acprc en root.
  if [[ -f "$RC_FILE" ]]; then
    echo "$RC_FILE"
  elif [[ -f "$ALT_RC_FILE" ]]; then
    echo "$ALT_RC_FILE"
  else
    # Si no existe, lo creamos en RC_FILE por defecto
    ensure_rc_file_exists
    echo "$RC_FILE"
  fi
}

# ==============================================================================
# 2. CARGA/RELOAD DE PROFILES (sourcing controlado)
# ==============================================================================
reload_profiles() {
  # Nos movemos al root para que config.sh resuelva rutas correctamente
  local prev="$PWD"
  cd "$ROOT"

  # shellcheck disable=SC1090
  source "${LIB_BASE}/core/config.sh"

  cd "$prev"
}

# ==============================================================================
# 3. UTILIDADES (Sanitización, helpers UI)
# ==============================================================================
sanitize_profile_field() {
  local v="$1"
  v="${v//$'\n'/ }"
  v="${v//$'\r'/ }"
  v="${v//;/,}"
  echo "$v"
}

shorten_key() {
  local k="$1"
  if [[ -z "$k" ]]; then
    echo "-"
    return 0
  fi
  if [[ "$k" == *".pub" ]]; then
    echo "$(basename "$k")"
    return 0
  fi
  if [[ ${#k} -gt 14 ]]; then
    echo "${k:0:6}…${k: -6}"
  else
    echo "$k"
  fi
}

profile_label() {
  # Recibe un entry del schema V1 (o compatible) y devuelve label humano
  local entry="$1"
  if ! parse_profile_entry_v1 "$entry"; then
    echo "INVALID_PROFILE"
    return 0
  fi

  local dn="${PROFILE_DISPLAY_NAME:-?}"
  local em="${PROFILE_GIT_EMAIL:-?}"
  local host="${PROFILE_SSH_HOST:-github.com}"
  local tgt="${PROFILE_PUSH_TARGET:-origin}"
  echo "${dn} <${em}>  [${host} | ${tgt}]"
}

choose_profile_index() {
  # Devuelve índice en PROFILES (0-based). Si cancela, devuelve vacío.
  if [[ ${#PROFILES[@]} -eq 0 ]]; then
    echo ""
    return 0
  fi

  local -a labels=()
  local i=0
  for p in "${PROFILES[@]}"; do
    labels+=("$(profile_label "$p")")
    ((i++))
  done

  # UI rica (gum) si está disponible
  if have_gum_ui; then
    local choice
    choice="$(gum choose --header "Selecciona un perfil:" "${labels[@]}" "Cancelar" || true)"
    [[ -z "$choice" || "$choice" == "Cancelar" ]] && { echo ""; return 0; }
    local idx=0
    for item in "${labels[@]}"; do
      if [[ "$item" == "$choice" ]]; then
        echo "$idx"
        return 0
      fi
      ((idx++))
    done
    echo ""
    return 0
  fi

  # Fallback: select de bash
  echo "Selecciona un perfil:"
  select opt in "${labels[@]}" "Cancelar"; do
    if [[ "$opt" == "Cancelar" ]]; then
      echo ""
      return 0
    fi
    if [[ -n "$opt" ]]; then
      local idx=0
      for item in "${labels[@]}"; do
        if [[ "$item" == "$opt" ]]; then
          echo "$idx"
          return 0
        fi
        ((idx++))
      done
      echo ""
      return 0
    fi
    echo "Opción inválida."
  done
}

# ==============================================================================
# 4. OPERACIONES DEL MODELO (LIST/ADD/REMOVE/DOCTOR)
# ==============================================================================
cmd_list() {
  reload_profiles

  ui_step_header "🧾 Perfiles configurados"

  if [[ ${#PROFILES[@]} -eq 0 ]]; then
    ui_warn "No hay perfiles configurados todavía."
    ui_info "Tip: corre el setup wizard o usa: git profile add"
    return 0
  fi

  local i=0
  for entry in "${PROFILES[@]}"; do
    if ! parse_profile_entry_v1 "$entry"; then
      ui_warn "[$i] Perfil inválido: $entry"
      ((i++))
      continue
    fi

    local dn="${PROFILE_DISPLAY_NAME}"
    local em="${PROFILE_GIT_EMAIL}"
    local sk="${PROFILE_SIGNING_KEY}"
    local tgt="${PROFILE_PUSH_TARGET}"
    local host="${PROFILE_SSH_HOST}"
    local keyp="${PROFILE_SSH_KEY_PATH}"
    local owner="${PROFILE_GH_OWNER}"

    echo "[$i] $dn <$em>"
    echo "     signing_key : $(shorten_key "$sk")"
    echo "     ssh_key_path: ${keyp:-"-"}"
    echo "     ssh_host    : ${host:-"-"}"
    echo "     push_target : ${tgt:-"-"}"
    echo "     gh_owner    : ${owner:-"-"}"
    echo
    ((i++))
  done
}

cmd_add() {
  ensure_rc_file_exists
  local target_rc
  target_rc="$(pick_rc_file)"
  ensure_schema_version_present "$target_rc"
  reload_profiles

  ui_step_header "➕ Agregar perfil"

  local default_login=""
  if command -v gh >/dev/null 2>&1; then
    default_login="$(gh api user -q ".login" 2>/dev/null || echo "")"
  fi
  [[ -z "$default_login" ]] && default_login="$(git config github.user 2>/dev/null || echo "")"

  local default_name=""
  default_name="$(git config --global user.name 2>/dev/null || echo "")"
  local default_email=""
  default_email="$(git config --global user.email 2>/dev/null || echo "")"
  local default_signing=""
  default_signing="$(git config --global user.signingkey 2>/dev/null || echo "")"

  local display_name git_name git_email signing_key push_target ssh_host ssh_key_path gh_owner

  if have_gum_ui; then
    display_name="$(gum input --header "Display Name (menú)" --value "${default_name:-${default_login:-perfil}}")"
    git_name="$(gum input --header "Git Name (commits)" --value "${default_name:-$display_name}")"
    git_email="$(gum input --header "Git Email" --value "${default_email}")"
    signing_key="$(gum input --header "Signing Key (SSH .pub o GPG key id)" --value "${default_signing}")"
    push_target="$(gum input --header "Push target (remote)" --value "origin")"
    ssh_host="$(gum input --header "SSH Host alias (github.com o github.com-ORG)" --value "github.com")"
    ssh_key_path="$(gum input --header "SSH private key path (para cargar en ssh-agent)" --value "${HOME}/.ssh/id_ed25519")"
    gh_owner="$(gum input --header "GitHub owner default (org o user)" --value "${default_login}")"
  else
    echo "Display Name (menú) [${default_name:-${default_login:-perfil}}]: "
    read -r display_name
    display_name="${display_name:-${default_name:-${default_login:-perfil}}}"

    echo "Git Name (commits) [${default_name:-$display_name}]: "
    read -r git_name
    git_name="${git_name:-${default_name:-$display_name}}"

    echo "Git Email [${default_email}]: "
    read -r git_email
    git_email="${git_email:-$default_email}"

    echo "Signing Key (SSH .pub o GPG key id) [${default_signing}]: "
    read -r signing_key
    signing_key="${signing_key:-$default_signing}"

    echo "Push target (remote) [origin]: "
    read -r push_target
    push_target="${push_target:-origin}"

    echo "SSH Host alias (github.com o github.com-ORG) [github.com]: "
    read -r ssh_host
    ssh_host="${ssh_host:-github.com}"

    echo "SSH private key path (para cargar en ssh-agent) [${HOME}/.ssh/id_ed25519]: "
    read -r ssh_key_path
    ssh_key_path="${ssh_key_path:-${HOME}/.ssh/id_ed25519}"

    echo "GitHub owner default (org o user) [${default_login}]: "
    read -r gh_owner
    gh_owner="${gh_owner:-$default_login}"
  fi

  # Validaciones mínimas
  if [[ -z "$git_email" ]]; then
    ui_error "El email es obligatorio."
    return 1
  fi

  # Sanitizar para no romper ';'
  display_name="$(sanitize_profile_field "$display_name")"
  git_name="$(sanitize_profile_field "$git_name")"
  git_email="$(sanitize_profile_field "$git_email")"
  signing_key="$(sanitize_profile_field "$signing_key")"
  push_target="$(sanitize_profile_field "$push_target")"
  ssh_host="$(sanitize_profile_field "$ssh_host")"
  ssh_key_path="$(sanitize_profile_field "$ssh_key_path")"
  gh_owner="$(sanitize_profile_field "$gh_owner")"

  local new_entry="${display_name};${git_name};${git_email};${signing_key};${push_target};${ssh_host};${ssh_key_path};${gh_owner}"

  # Dedup: email+signing+target+host
  local dedupe_sig=";${git_email};${signing_key};${push_target};${ssh_host};"
  if grep -Fq "$dedupe_sig" "$target_rc"; then
    ui_warn "Ya existe un perfil equivalente (mismo email/llave/host/remote). No se agregó."
    return 0
  fi

  local tmp="${target_rc}.tmp"
  cp "$target_rc" "$tmp"
  echo "" >> "$tmp"
  echo "# Auto-agregado por git-profile ($(date +%F))" >> "$tmp"
  echo "PROFILES+=(\"$new_entry\")" >> "$tmp"
  mv "$tmp" "$target_rc"

  ui_success "Perfil agregado en: $target_rc"
}

cmd_remove() {
  ensure_rc_file_exists
  local target_rc
  target_rc="$(pick_rc_file)"
  reload_profiles

  ui_step_header "🗑️ Eliminar perfil"

  if [[ ${#PROFILES[@]} -eq 0 ]]; then
    ui_warn "No hay perfiles para eliminar."
    return 0
  fi

  local idx
  idx="$(choose_profile_index)"
  [[ -z "$idx" ]] && { ui_info "Operación cancelada."; return 0; }

  local entry="${PROFILES[$idx]}"

  if ! parse_profile_entry_v1 "$entry"; then
    ui_warn "Perfil inválido seleccionado. Se intentará eliminar por coincidencia literal."
  fi

  local label
  label="$(profile_label "$entry")"
  ui_warn "Vas a eliminar: $label"

  if ! ask_yes_no "¿Confirmas eliminar este perfil del archivo?"; then
    ui_info "Cancelado."
    return 0
  fi

  local tmp="${target_rc}.tmp"
  cp "$target_rc" "$tmp"

  # Eliminamos la línea exacta PROFILES+=("entry")
  # (El entry no contiene ';' sin escape más allá del contrato; se guarda literal en el rc.)
  # Usamos grep -Fv para evitar regex.
  local line="PROFILES+=(\"$entry\")"
  if grep -Fq "$line" "$tmp"; then
    grep -Fv "$line" "$tmp" > "${tmp}.final"
    mv "${tmp}.final" "$target_rc"
    rm -f "$tmp" 2>/dev/null || true
    ui_success "Perfil eliminado."
  else
    # Fallback: borrar por email delimitado si no coincide literal (casos de sanitización)
    if [[ -n "${PROFILE_GIT_EMAIL:-}" ]]; then
      local sig=";${PROFILE_GIT_EMAIL};"
      grep -Fv "$sig" "$tmp" > "${tmp}.final" || true
      mv "${tmp}.final" "$target_rc"
      rm -f "$tmp" 2>/dev/null || true
      ui_warn "No se encontró match literal; se filtró por email (revisar el rc)."
    else
      ui_warn "No se encontró el perfil en el archivo. No se hizo nada."
      rm -f "$tmp" 2>/dev/null || true
    fi
  fi
}

cmd_doctor() {
  ensure_rc_file_exists
  local target_rc
  target_rc="$(pick_rc_file)"
  reload_profiles

  ui_step_header "🩺 Doctor de perfiles"

  ui_info "RC file: $target_rc"
  ui_info "Root   : $ROOT"
  echo ""

  if command -v gh >/dev/null 2>&1; then
    if gh auth status --hostname github.com >/dev/null 2>&1; then
      ui_success "gh auth: OK"
    else
      ui_warn "gh auth: NO autenticado (puede afectar creación de repos/keys)."
    fi
  else
    ui_warn "gh CLI no está instalado."
  fi

  if [[ ${#PROFILES[@]} -eq 0 ]]; then
    ui_warn "No hay perfiles para verificar."
    return 0
  fi

  local i=0
  for entry in "${PROFILES[@]}"; do
    echo "────────────────────────────────────────────────"
    echo "Perfil [$i]: $(profile_label "$entry")"
    if ! parse_profile_entry_v1 "$entry"; then
      ui_error "Perfil inválido: no cumple schema mínimo."
      echo "Entry: $entry"
      echo
      ((i++))
      continue
    fi

    # Chequeos de archivos
    if [[ -n "${PROFILE_SSH_KEY_PATH:-}" ]]; then
      if [[ -f "${PROFILE_SSH_KEY_PATH}" ]]; then
        ui_success "ssh_key_path existe: ${PROFILE_SSH_KEY_PATH}"
      else
        ui_warn "ssh_key_path NO existe: ${PROFILE_SSH_KEY_PATH}"
      fi
    else
      ui_warn "ssh_key_path vacío (se inferirá en runtime o fallará ssh-add)."
    fi

    if [[ -n "${PROFILE_SIGNING_KEY:-}" ]]; then
      if [[ "${PROFILE_SIGNING_KEY}" == /* || "${PROFILE_SIGNING_KEY}" == ~/* ]]; then
        # Ruta
        local k="${PROFILE_SIGNING_KEY}"
        [[ "$k" == "~/"* ]] && k="${HOME}/${k#~/}"
        if [[ -f "$k" ]]; then
          ui_success "signing_key (file) existe: $k"
        else
          ui_warn "signing_key (file) NO existe: $k"
        fi
      else
        ui_info "signing_key: $(shorten_key "${PROFILE_SIGNING_KEY}")"
      fi
    else
      ui_warn "signing_key vacío."
    fi

    # Test de SSH (suave)
    local host="${PROFILE_SSH_HOST:-github.com}"
    ui_info "Probando SSH: git@${host}"
    local out
    out="$(ssh -o StrictHostKeyChecking=accept-new -T "git@${host}" 2>&1 || true)"
    if echo "$out" | grep -qi "successfully authenticated"; then
      ui_success "SSH OK (auth)."
    else
      ui_warn "SSH no confirmó auth automáticamente."
      ui_info "Salida (resumen): $(echo "$out" | head -n 2 | tr '\n' ' ' )"
    fi

    echo ""
    ((i++))
  done
}

usage() {
  cat <<EOF
Uso:
  git profile <cmd>

Comandos:
  list        Lista perfiles cargados (PROFILES)
  add         Agrega un perfil al rc file (append atómico)
  remove      Elimina un perfil del rc file
  doctor      Diagnóstico de perfiles (keys/ssh/gh)

Variables útiles:
  DEVTOOLS_ASSUME_YES=1     (responde YES en no-TTY para confirmaciones)
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    list)   cmd_list "$@" ;;
    add)    cmd_add "$@" ;;
    remove|rm|delete) cmd_remove "$@" ;;
    doctor|check) cmd_doctor "$@" ;;
    -h|--help|"") usage ;;
    *) ui_error "Comando desconocido: $cmd"; usage; return 2 ;;
  esac
}

# Permite que esto funcione como script ejecutable o como librería sourceable
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
