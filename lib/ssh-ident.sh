#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ssh-ident.sh

# ==============================================================================
# 1. GESTIÓN DEL AGENTE SSH
# ==============================================================================

AGENT_ENV="${HOME}/.ssh/agent.env"

start_agent() {
  eval "$(ssh-agent -s)" >/dev/null
  mkdir -p "${HOME}/.ssh"
  {
    echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}"
    echo "export SSH_AGENT_PID=${SSH_AGENT_PID}"
  } > "${AGENT_ENV}"
  chmod 600 "${AGENT_ENV}"
}

load_or_start_agent() {
  if [[ -f "${AGENT_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${AGENT_ENV}"
    if ! kill -0 "${SSH_AGENT_PID:-0}" 2>/dev/null; then
      start_agent
    fi
  else
    start_agent
  fi
}

# ==============================================================================
# 2. GESTIÓN DE LLAVES Y HUELLAS
# ==============================================================================

fingerprint_of() { 
    ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'; 
}

ensure_key_added() {
  local key="$1"
  # Expansión de tilde si es necesario
  case "$key" in
     "~/"*) key="${HOME}/${key#~/}" ;;
  esac
  key="${key/#$HOME\/~\//$HOME/}"

  if [[ ! -f "$key" ]]; then
    # Si no es archivo, quizás es una llave GPG legacy, ignoramos error SSH
    return 1
  fi

  local fp
  fp="$(fingerprint_of "$key")" || return 1

  if ! ssh-add -l 2>/dev/null | grep -q "$fp"; then
    ssh-add "$key" >/dev/null
    echo "🔑 ssh-add: $key"
  fi
}

test_github_ssh() {
  local host_alias="$1"
  ssh -o StrictHostKeyChecking=accept-new -T "git@${host_alias}" 2>&1 || true
}

# ==============================================================================
# 3. GESTIÓN DE REMOTOS Y URLs
# ==============================================================================

normalize_url_to_alias() {
  local alias="$1"
  local url owner repo
  read -r url || { echo ""; return 0; }

  if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git@([^:]+):([^/]+)/([^/]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[2]}"
    repo="${BASH_REMATCH[3]}"
  else
    echo "$url"
    return 0
  fi
  repo="${repo%.git}"
  repo="${repo%.git}"
  echo "git@${alias}:${owner}/${repo}.git"
}

ensure_remote_exists_and_points_to_alias() {
  local remote="$1" alias="$2" owner="$3"
  local top repo url newurl
  top="$(git rev-parse --show-toplevel)"
  repo="$(basename "$top")"

  if git remote | grep -q "^${remote}$"; then
    url="$(git remote get-url "$remote")"
    newurl="$(echo "$url" | normalize_url_to_alias "$alias")"
    if [[ "$newurl" != "$url" && -n "$newurl" ]]; then
      git remote set-url "$remote" "$newurl"
      echo "🔧 Remote actualizado → $remote = $newurl"
    else
      echo "🟢 Remote OK → $remote = $url"
    fi
  else
    local ssh_url="git@${alias}:${owner}/${repo}.git"
    git remote add "$remote" "$ssh_url"
    echo "➕ Remote agregado → $remote = $ssh_url"
  fi
}

remote_repo_or_create() {
  local remote="$1" alias="$2" owner="$3"
  local url repo r
  url="$(git remote get-url "$remote")"
  repo="$(basename -s .git "$(git rev-parse --show-toplevel)")"
  r="${owner}/${repo}"

  if git ls-remote "$remote" &>/dev/null; then
    return 0
  fi

  echo "ℹ️  No se pudo consultar $remote ($url). ¿Existe el repo? Intentando crear..."
  
  # Usamos las variables globales GH_AUTO_CREATE y GH_DEFAULT_VISIBILITY definidas en config
  local auto_create="${GH_AUTO_CREATE:-false}"
  local visibility="${GH_DEFAULT_VISIBILITY:-private}"

  if [[ "${auto_create}" == "true" ]] && command -v gh >/dev/null 2>&1; then
    if gh repo view "$r" &>/dev/null; then
      echo "🟡 El repo $r ya existe. Probablemente es un tema de permisos o llave."
      return 0
    fi
    if gh repo create "$r" --"${visibility}" -y; then
      echo "✅ Repo creado en GitHub: $r"
      return 0
    else
      echo "🔴 Falló 'gh repo create $r'. Revisa GH_TOKEN o 'gh auth login'."
      return 0
    fi
  else
    echo "🔴 No se creó automáticamente (GH_AUTO_CREATE=${auto_create}, gh CLI no disponible o sin login)."
    return 0
  fi
}

# ==============================================================================
# 4. SELECTOR DE IDENTIDAD (MAIN FUNCTION)
# ==============================================================================

setup_git_identity() {
  # Recibe el array de perfiles como argumentos, o usa la global PROFILES
  # Nota: En bash pasar arrays a funciones es truculento, asumimos acceso a PROFILES global
  # pero verificamos si hay perfiles.
  
  if [ ${#PROFILES[@]} -eq 0 ]; then
     return 0
  fi

  echo "🎩 ¿Con qué sombrero quieres hacer este commit?"
  
  local display_names=()
  for profile in "${PROFILES[@]}"; do
    display_names+=("$(echo "$profile" | cut -d';' -f1)")
  done
  
  export COLUMNS=1
  PS3="Selecciona una identidad: "
  
  select opt in "${display_names[@]}" "Cancelar"; do
    if [[ "$opt" == "Cancelar" ]]; then
      echo "❌ Commit cancelado."
      exit 0
    elif [[ -z "$opt" ]]; then
      echo "Opción inválida. Inténtalo de nuevo."
      continue
    else
      local selected_profile_config=""
      for profile in "${PROFILES[@]}"; do
        if [[ "$(echo "$profile" | cut -d';' -f1)" == "$opt" ]]; then
          selected_profile_config="$profile"
          break
        fi
      done
      
      [[ -z "${selected_profile_config:-}" ]] && { echo "❌ Perfil no encontrado."; exit 1; }

      # --- FIX: Parseo robusto con Backward Compatibility (V1 Schema) ---
      # Schema: display_name;git_name;git_email;signing_key;push_target;ssh_host;ssh_key_path;gh_owner
      
      # Convertimos a array para manejar campos faltantes
      local -a p_fields
      IFS=';' read -r -a p_fields <<< "$selected_profile_config"
      
      local display_name="${p_fields[0]}"
      local git_name="${p_fields[1]}"
      local git_email="${p_fields[2]}"
      local gpg_key="${p_fields[3]}"
      # Aplicamos defaults si faltan campos (backward-compat)
      local target="${p_fields[4]:-origin}"
      local ssh_host_alias="${p_fields[5]:-github.com}"
      local ssh_key_path="${p_fields[6]:-}"
      local gh_owner="${p_fields[7]:-}"

      # Exportamos el target para que el script principal lo vea
      export push_target="$target"

      echo "✅ Usando la identidad de '$display_name' (firmado como '$git_name')."
      git config user.name "$git_name"
      git config user.email "$git_email"

      # --- FIX: Detección inteligente de formato de firma (GPG vs SSH) ---
      local IdentityFile=""
      if [[ "$gpg_key" == *".pub" ]] || [[ "$gpg_key" == "ssh-"* ]] || [[ "$gpg_key" == "/"* ]]; then
          git config gpg.format ssh
          
          if [[ -n "$ssh_key_path" ]]; then
             IdentityFile="${ssh_key_path}"
             ensure_key_added "$IdentityFile" || true
          elif [[ "$gpg_key" == "/"* ]]; then
             IdentityFile="${gpg_key%.pub}"
             ensure_key_added "$IdentityFile" || true
          fi
      else
          git config gpg.format openpgp
      fi
      
      git config commit.gpgsign true
      git config user.signingkey "${gpg_key:-}" 2>/dev/null || true

      # --- Inferencia de valores faltantes (Si el perfil venía incompleto) ---
      if [[ -z "${ssh_host_alias:-}" ]] || [[ "$ssh_host_alias" == "github.com" ]]; then
        # Intento de inferencia desde ~/.ssh/config si no vino explícito
        local inferred
        inferred="$(grep -E '^[[:space:]]*Host github\.com-' -A0 -h ~/.ssh/config 2>/dev/null | awk '{print $2}' | head -n1 || true)"
        if [[ -n "$inferred" ]]; then ssh_host_alias="$inferred"; fi
      fi
      
      if [[ -z "${gh_owner:-}" ]]; then
        if [[ "$ssh_host_alias" =~ ^github\.com-(.+)$ ]]; then 
            gh_owner="${BASH_REMATCH[1]}"
        else 
            gh_owner="$(git config github.user || true)"
        fi
        [[ -z "$gh_owner" ]] && gh_owner="${git_name%% *}"
      fi
      
      if [[ -z "${ssh_key_path:-}" ]]; then
        if [[ "$ssh_host_alias" =~ ^github\.com-(.+)$ ]]; then
          ssh_key_path="${HOME}/.ssh/id_ed25519_${BASH_REMATCH[1]}"
        else
          ssh_key_path="${HOME}/.ssh/id_ed25519"
        fi
      fi

      # --- Ejecución de configuración SSH ---
      load_or_start_agent
      ensure_key_added "$ssh_key_path" || true
      test_github_ssh "$ssh_host_alias" || true
      ensure_remote_exists_and_points_to_alias "$push_target" "$ssh_host_alias" "$gh_owner"
      remote_repo_or_create "$push_target" "$ssh_host_alias" "$gh_owner"

      echo "🟢 Remoto listo → '${push_target}' (host: ${ssh_host_alias}, owner: ${gh_owner})"
      echo "✅ El commit se enviará a '${push_target}'."
      break
    fi
  done
}