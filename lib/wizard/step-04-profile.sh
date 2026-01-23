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
    # Evita que caracteres como ';' o saltos de línea rompan el schema del Profile Entry.
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
        # Incluimos la versión del esquema en el archivo generado
        cat <<EOF > "$rc_file"
# Configuración generada por ERD Devtools Wizard
PROFILE_SCHEMA_VERSION=1
DAY_START="00:00"
REFS_LABEL="Conteo: commit"
DAILY_GOAL=10
PROFILES=()
EOF
    else
        # --- FIX (Modelo de Identidades): Backward-compat / migración suave ---
        # Si el archivo existe pero no tiene PROFILE_SCHEMA_VERSION, lo agregamos sin destruir contenido.
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
            ui_info "Se agregó PROFILE_SCHEMA_VERSION=1 a $rc_file (compatibilidad)."
        fi
    fi

    # ==========================================================================
    # 2. CONSTRUIR Y GUARDAR PERFIL
    # ==========================================================================
    local gh_login
    gh_login=$(gh api user -q ".login" 2>/dev/null || echo "unknown")

    # --- FIX (Modelo de Identidades): gh_owner semántica consistente ---
    # Contract V1 usa el último campo como GHOwner (owner por defecto). Por defecto lo alineamos con el login.
    local gh_owner_default
    gh_owner_default="$gh_login"

    # Contract V1: DisplayName;GitName;GitEmail;SigningKey;PushTarget;Host;SSHKey;GHOwner
    # --- FIX (Modelo de Identidades): Sanitizar valores antes de escribir ---
    local safe_git_name safe_git_email safe_signing_key safe_ssh_key_final safe_gh_owner
    safe_git_name="$(sanitize_profile_field "$GIT_NAME")"
    safe_git_email="$(sanitize_profile_field "$GIT_EMAIL")"
    safe_signing_key="$(sanitize_profile_field "$SIGNING_KEY")"
    safe_ssh_key_final="$(sanitize_profile_field "$SSH_KEY_FINAL")"
    safe_gh_owner="$(sanitize_profile_field "$gh_owner_default")"

    local profile_entry="$safe_git_name;$safe_git_name;$safe_git_email;$safe_signing_key;origin;github.com;$safe_ssh_key_final;$safe_gh_owner"

    # --- FIX (Modelo de Identidades): Deduplicación por clave compuesta (multi-perfil) ---
    # En lugar de solo email, usamos un patrón más específico:
    # ;email;signing_key;push_target;host;
    local dedupe_sig=";${safe_git_email};${safe_signing_key};origin;github.com;"
    local email_sig=";${safe_git_email};"

    # --- FIX: DEDUPLICACIÓN ROBUSTA Y ESCRITURA ATÓMICA (P1) ---
    if grep -Fq "$dedupe_sig" "$rc_file"; then
        ui_success "Tu perfil ya existía en el menú de identidades (misma llave/host)."
    elif grep -Fq "$email_sig" "$rc_file"; then
        # Caso: mismo email pero otra llave/host/entry. Ofrecemos decisión.
        ui_warn "Detectamos un perfil existente con el mismo email, pero con datos distintos."
        ui_info "Esto puede ser normal si usas varias llaves o varias organizaciones."
        if ask_yes_no "¿Quieres agregar este perfil como una entrada adicional?"; then
            local tmp_rc="${rc_file}.tmp"
            cp "$rc_file" "$tmp_rc"

            echo "" >> "$tmp_rc"
            echo "# Auto-agregado por setup-wizard ($(date +%F))" >> "$tmp_rc"
            echo "PROFILES+=(\"$profile_entry\")" >> "$tmp_rc"

            # Reemplazo atómico
            mv "$tmp_rc" "$rc_file"
            ui_success "Perfil agregado exitosamente al menú (multi-perfil)."
        else
            ui_info "No se agregó un nuevo perfil (se mantuvo el existente)."
        fi
    else
        # Escritura a archivo temporal para evitar corrupciones si se corta el proceso
        local tmp_rc="${rc_file}.tmp"
        cp "$rc_file" "$tmp_rc"

        echo "" >> "$tmp_rc"
        echo "# Auto-agregado por setup-wizard ($(date +%F))" >> "$tmp_rc"
        echo "PROFILES+=(\"$profile_entry\")" >> "$tmp_rc"

        # Reemplazo atómico
        mv "$tmp_rc" "$rc_file"
        ui_success "Perfil agregado exitosamente al menú."
    fi

    # ==========================================================================
    # 3. FIX: CAMBIAR REMOTE A SSH (Para evitar prompts de password https)
    # ==========================================================================
    local current_url
    current_url=$(git remote get-url origin 2>/dev/null || true)

    # --- FIX (Modelo de Identidades): No modificar remotos agresivamente ---
    # Solo convertimos si es GitHub HTTPS, y preferiblemente bajo confirmación.
    if [[ "$current_url" == https://github.com/* ]]; then
        local new_url
        new_url=$(echo "$current_url" | sed -E 's/https:\/\/github.com\//git@github.com:/')

        # Si no hay TTY, no tocamos el remote automáticamente (seguridad)
        if ! is_tty; then
            ui_warn "Entorno no interactivo: no se modificó el remote 'origin' (HTTPS->SSH)."
            ui_info "Si lo necesitas, ejecuta manualmente: git remote set-url origin \"$new_url\""
        else
            if ask_yes_no "¿Actualizar remote 'origin' de HTTPS a SSH para evitar prompts?"; then
                git remote set-url origin "$new_url" 2>/dev/null || true
                ui_info "Remote 'origin' actualizado de HTTPS a SSH."
            else
                ui_info "Se mantuvo el remote actual (sin cambios)."
            fi
        fi
    fi

    # ==========================================================================
    # 4. VALIDACIÓN DE CONECTIVIDAD FINAL
    # ==========================================================================
    ui_spinner "Validando conexión SSH final..." sleep 1

    if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
        ui_success "Conexión SSH verificada: Acceso Correcto."
    else
        ui_warn "No pudimos validar la conexión automáticamente (ssh -T git@github.com)."
        ui_info "Es posible que necesites reiniciar tu terminal o agente SSH."
    fi

    # ==========================================================================
    # 5. SETUP DE ENTORNO (.env)
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

    # ==========================================================================
    # 6. MARCAR COMO COMPLETADO
    # ==========================================================================
    # Aseguramos que el directorio exista (por si se corre aislado)
    mkdir -p "$(dirname "$marker_file")"
    touch "$marker_file"
}
