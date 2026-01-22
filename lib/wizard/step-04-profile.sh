#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-04-profile.sh

run_step_profile_registration() {
    ui_step_header "6. Finalización y Registro"

    local rc_file=".devtools/.git-acprc"
    local marker_file=".devtools/.setup_completed"

    # ==========================================================================
    # 1. PREPARAR ARCHIVO DE CONFIGURACIÓN (.git-acprc)
    # ==========================================================================
    if [ ! -f "$rc_file" ]; then
        ui_info "Creando archivo de configuración inicial..."
        cat <<EOF > "$rc_file"
# Configuración generada por ERD Devtools Wizard
DAY_START="00:00"
REFS_LABEL="Conteo: commit"
DAILY_GOAL=10
PROFILES=()
EOF
    fi

    # ==========================================================================
    # 2. CONSTRUIR Y GUARDAR PERFIL
    # ==========================================================================
    local gh_login
    gh_login=$(gh api user -q ".login" 2>/dev/null || echo "unknown")
    
    # Formato esperado por git-acp.sh:
    # DisplayName;GitName;GitEmail;SigningKey(Pub);Remote;Host;SSHKey(Priv);GHLogin
    local profile_entry="$GIT_NAME;$GIT_NAME;$GIT_EMAIL;$SIGNING_KEY;origin;github.com;$SSH_KEY_FINAL;$gh_login"

    # Verificamos si este email ya existe para evitar duplicados infinitos
    if grep -q "$GIT_EMAIL" "$rc_file"; then
        ui_success "Tu perfil ya existía en el menú de identidades."
    else
        # Usamos append seguro
        echo "" >> "$rc_file"
        echo "# Auto-agregado por setup-wizard ($(date +%F))" >> "$rc_file"
        echo "PROFILES+=(\"$profile_entry\")" >> "$rc_file"
        ui_success "Perfil agregado exitosamente al menú."
    fi

    # ==========================================================================
    # 3. FIX: CAMBIAR REMOTE A SSH (Para evitar prompts de password https)
    # ==========================================================================
    local current_url
    current_url=$(git remote get-url origin 2>/dev/null || true)
    
    if [[ "$current_url" == https://* ]]; then
        local new_url
        new_url=$(echo "$current_url" | sed -E 's/https:\/\/github.com\//git@github.com:/')
        git remote set-url origin "$new_url" 2>/dev/null || true
        ui_info "Remote 'origin' actualizado de HTTPS a SSH."
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
    touch "$marker_file"
}