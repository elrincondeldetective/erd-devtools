#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-04-profile.sh

run_step_profile_registration() {
    ui_step_header "6. Finalización y Registro"

    local rc_file=".devtools/.git-acprc"
    local marker_file=".devtools/.setup_completed"

    # --- FIX (Modelo de Identidades): Asegurar carpeta .devtools ---
    mkdir -p "$(dirname "$rc_file")"
    mkdir -p "$(dirname "$marker_file")"

    # --- FIX (Modelo de Identidades): Sanitización de campos del perfil ---
    sanitize_profile_field() {
        local v="$1"
        v="${v//$'\n'/ }"
        v="${v//$'\r'/ }"
        v="${v//;/,}"
        echo "$v"
    }

    # ==========================================================================
    # 1. PREPARAR ARCHIVO DE CONFIGURACIÓN (.git-acprc)
    # ==========================================================================
    if [ ! -f "$rc_file" ]; then
        ui_info "Creando archivo de configuración inicial..."
        cat <<EOF > "$rc_file"
# Configuración generada por ERD Devtools Wizard
PROFILE_SCHEMA_VERSION=1
DAY_START="00:00"
REFS_LABEL="Conteo: commit"
DAILY_GOAL=10
PROFILES=()
EOF
    else
        # Backward-compat: Agregar version si falta
        if ! grep -qE '^[[:space:]]*PROFILE_SCHEMA_VERSION=' "$rc_file"; then
            local tmp_rc_schema="${rc_file}.schema.tmp"
            cp "$rc_file" "$tmp_rc_schema"
            {
                echo "# Auto-agregado por setup-wizard ($(date +%F)): Schema Version"
                echo "PROFILE_SCHEMA_VERSION=1"
                echo ""
                cat "$tmp_rc_schema"
            } > "${tmp_rc_schema}.final"
            mv "${tmp_rc_schema}.final" "$rc_file"
            rm -f "$tmp_rc_schema" 2>/dev/null || true
            ui_info "Se agregó PROFILE_SCHEMA_VERSION=1 a $rc_file."
        fi
    fi

    # ==========================================================================
    # 2. CONSTRUIR DATOS DEL PERFIL
    # ==========================================================================
    local gh_login
    gh_login=$(gh api user -q ".login" 2>/dev/null || echo "unknown")
    local gh_owner_default="$gh_login"
    
    # --- FIX: Display Name Personalizado (UX) ---
    local display_name_input
    if command -v gum >/dev/null 2>&1; then
        display_name_input=$(gum input --value "$GIT_NAME" --header "Nombre del Perfil (ej: Personal, Trabajo)")
    else
        display_name_input="$GIT_NAME"
    fi
    
    # --- FIX: Definir Host SSH ---
    # Por defecto github.com, pero si usáramos alias complejos, aquí se definiría.
    local ssh_host_target="github.com"

    # Sanitizar valores
    local safe_display_name safe_git_name safe_git_email safe_signing_key safe_ssh_key_final safe_gh_owner safe_ssh_host
    safe_display_name="$(sanitize_profile_field "$display_name_input")"
    safe_git_name="$(sanitize_profile_field "$GIT_NAME")"
    safe_git_email="$(sanitize_profile_field "$GIT_EMAIL")"
    safe_signing_key="$(sanitize_profile_field "$SIGNING_KEY")"
    safe_ssh_key_final="$(sanitize_profile_field "$SSH_KEY_FINAL")"
    safe_gh_owner="$(sanitize_profile_field "$gh_owner_default")"
    safe_ssh_host="$(sanitize_profile_field "$ssh_host_target")"

    # Schema V1: DisplayName;GitName;GitEmail;SigningKey;PushTarget;Host;SSHKey;GHOwner
    local profile_entry="$safe_display_name;$safe_git_name;$safe_git_email;$safe_signing_key;origin;$safe_ssh_host;$safe_ssh_key_final;$safe_gh_owner"

    # ==========================================================================
    # 3. GUARDAR PERFIL (DEDUPLICACIÓN)
    # ==========================================================================
    # Clave compuesta para detectar duplicados: ;email;signing_key;push_target;host;
    local dedupe_sig=";${safe_git_email};${safe_signing_key};origin;${safe_ssh_host};"
    local email_sig=";${safe_git_email};"

    if grep -Fq "$dedupe_sig" "$rc_file"; then
        ui_success "Tu perfil ya existía en el menú de identidades."
    elif grep -Fq "$email_sig" "$rc_file"; then
        ui_warn "Detectamos un perfil existente con el mismo email, pero datos distintos."
        if ask_yes_no "¿Quieres agregar este perfil como una entrada adicional?"; then
            echo "" >> "$rc_file"
            echo "PROFILES+=(\"$profile_entry\")" >> "$rc_file"
            ui_success "Perfil agregado (multi-perfil)."
        else
            ui_info "No se agregó el nuevo perfil."
        fi
    else
        # Escritura segura
        echo "" >> "$rc_file"
        echo "# Auto-agregado por setup-wizard ($(date +%F))" >> "$rc_file"
        echo "PROFILES+=(\"$profile_entry\")" >> "$rc_file"
        ui_success "Perfil agregado al menú."
    fi

    # ==========================================================================
    # 4. FIX: CAMBIAR REMOTE A SSH
    # ==========================================================================
    local current_url
    current_url=$(git remote get-url origin 2>/dev/null || true)

    if [[ "$current_url" == https://github.com/* ]]; then
        local new_url
        new_url=$(echo "$current_url" | sed -E 's/https:\/\/github.com\//git@github.com:/')

        if ! is_tty; then
            ui_warn "Entorno no interactivo: no se modificó 'origin' a SSH."
        else
            if ask_yes_no "¿Actualizar remote 'origin' de HTTPS a SSH?"; then
                git remote set-url origin "$new_url" 2>/dev/null || true
                ui_info "Remote actualizado a SSH."
            else
                ui_info "Se mantuvo el remote HTTPS."
            fi
        fi
    fi

    # ==========================================================================
    # 5. VALIDACIÓN DE CONECTIVIDAD FINAL
    # ==========================================================================
    # --- FIX: Usar variable de host en vez de hardcode ---
    ui_spinner "Validando conexión SSH final ($safe_ssh_host)..." sleep 1

    if ssh -T "git@$safe_ssh_host" -o StrictHostKeyChecking=accept-new 2>&1 | grep -qE "(successfully authenticated|Hi)"; then
        ui_success "Conexión SSH verificada: Acceso Correcto."
    else
        ui_warn "No pudimos validar la conexión automáticamente a $safe_ssh_host."
        ui_info "Prueba manual: ssh -T git@$safe_ssh_host"
    fi

    # ==========================================================================
    # 6. SETUP DE ENTORNO (.env) & MARKER
    # ==========================================================================
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            ui_success "Archivo .env creado desde .env.example."
        else
            touch .env
            ui_warn "Archivo .env creado (vacío)."
        fi
    fi

    mkdir -p "$(dirname "$marker_file")"
    touch "$marker_file"
}