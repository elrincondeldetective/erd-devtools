#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-01-auth.sh

run_step_auth() {
    ui_step_header "1. Autenticación con GitHub"

    local needs_login=true

    # 1. Verificar estado actual
    if gh auth status >/dev/null 2>&1; then
        local current_user
        current_user=$(gh api user -q ".login")
        ui_success "Sesión activa detectada: $current_user"
        
        # Ofrecer opciones al usuario
        ui_info "¿Qué deseas hacer?"
        local action
        action=$(gum choose \
            "Continuar como $current_user" \
            "Cerrar sesión y cambiar de cuenta" \
            "Refrescar credenciales (Reparar permisos)")

        if [[ "$action" == "Continuar"* ]]; then
            needs_login=false
        else
            # Logout forzado para limpiar estado
            gh auth logout >/dev/null 2>&1 || true
            needs_login=true
        fi
    fi

    # 2. Flujo de Login (si es necesario)
    if [ "$needs_login" = true ]; then
        ui_warn "🔐 Iniciando autenticación web..."
        ui_info "Solicitaremos permisos de escritura para subir tu llave SSH automáticamente."
        
        if gum confirm "Presiona Enter para abrir el navegador y autorizar"; then
            # Login con scopes específicos para llaves SSH y firma
            if gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key -s "admin:public_key write:public_key admin:ssh_signing_key user"; then
                local new_user
                new_user=$(gh api user -q ".login")
                ui_success "Login exitoso. Conectado como: $new_user"
            else
                ui_error "Falló el login. Inténtalo de nuevo."
                exit 1
            fi
        else
            ui_error "Cancelado por el usuario."
            exit 1
        fi
    fi

    # 3. Verificación de 2FA (Bloqueante)
    verify_2fa_enforcement
}

verify_2fa_enforcement() {
    ui_step_header "2. Verificación de Seguridad (2FA)"

    while true; do
        local is_2fa_enabled
        is_2fa_enabled=$(gh api user -q ".two_factor_authentication")

        if [ "$is_2fa_enabled" == "true" ]; then
            ui_success "Autenticación de Dos Factores (2FA) detectada."
            break
        else
            ui_alert_box "⛔ ACCESO DENEGADO ⛔" \
                "Tu cuenta NO tiene activado el 2FA." \
                "Es obligatorio para trabajar en este ecosistema."

            echo ""
            ui_info "1. Ve a: https://github.com/settings/security"
            ui_info "2. Activa 'Two-factor authentication'."
            echo ""
            
            if gum confirm "¿Ya lo activaste? (Volver a comprobar)"; then
                ui_spinner "Reverificando estado..." sleep 2
            else
                ui_error "No podemos continuar sin 2FA."
                exit 1
            fi
        fi
    done
}