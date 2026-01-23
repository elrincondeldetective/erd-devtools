#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-01-auth.sh

# Variable de Scopes (Mínimo Privilegio + Firma SSH)
# admin:public_key / write:public_key -> Para subir llaves SSH
# admin:ssh_signing_key -> Para subir llaves de firma
# user -> Para leer perfil y emails
DEVTOOLS_GH_SCOPES="admin:public_key write:public_key admin:ssh_signing_key user"

run_step_auth() {
    ui_step_header "1. Autenticación con GitHub"

    local needs_login=true

    # 1. Verificar estado actual (FIX: Host explícito para evitar ambigüedad)
    if gh auth status --hostname github.com >/dev/null 2>&1; then
        local current_user
        current_user=$(gh api user -q ".login")
        ui_success "Sesión activa detectada: $current_user"
        
        # Ofrecer opciones al usuario
        ui_info "¿Qué deseas hacer?"
        local action
        action=$(gum choose \
            "Continuar como $current_user" \
            "Refrescar credenciales (Reparar permisos)" \
            "Cerrar sesión y cambiar de cuenta")

        if [[ "$action" == "Continuar"* ]]; then
            needs_login=false
        elif [[ "$action" == "Refrescar"* ]]; then
            # --- FIX: INTENTO DE REFRESH REAL ---
            ui_spinner "Refrescando credenciales y scopes..." \
                gh auth refresh --hostname github.com -s "$DEVTOOLS_GH_SCOPES" 2>/dev/null
            
            # Chequeamos el código de salida del refresh
            if [ $? -eq 0 ]; then
                ui_success "Credenciales refrescadas correctamente."
                needs_login=false
            else
                ui_warn "No se pudo refrescar la sesión (posiblemente falta soporte en tu versión de gh)."
                ui_info "Procediendo a re-autenticación completa..."
                gh auth logout --hostname github.com >/dev/null 2>&1 || true
                needs_login=true
            fi
        else
            # Logout forzado para limpiar estado (FIX: Host explícito)
            gh auth logout --hostname github.com >/dev/null 2>&1 || true
            needs_login=true
        fi
    fi

    # 2. Flujo de Login (si es necesario)
    if [ "$needs_login" = true ]; then
        ui_warn "🔐 Iniciando autenticación web..."
        ui_info "Solicitaremos permisos de escritura para subir tu llave SSH automáticamente."
        
        if gum confirm "Presiona Enter para abrir el navegador y autorizar"; then
            # Login con scopes configurables
            if gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key -s "$DEVTOOLS_GH_SCOPES"; then
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
        # FIX: Capturamos error para no romper script con set -e y manejamos nulos
        is_2fa_enabled=$(gh api user -q ".two_factor_authentication" 2>/dev/null || echo "null")

        if [ "$is_2fa_enabled" == "true" ]; then
            ui_success "Autenticación de Dos Factores (2FA) detectada."
            break
        elif [ "$is_2fa_enabled" == "null" ] || [ -z "$is_2fa_enabled" ]; then
            # --- FIX: MANEJO DE CAMPO VACÍO/NULL ---
            ui_warn "⚠️ No pudimos verificar automáticamente el estado de 2FA."
            ui_info "Esto a veces pasa con ciertos tokens o redes corporativas."
            echo ""
            ui_info "Por favor, verifica manualmente en: https://github.com/settings/security"
            
            if gum confirm "¿Confirmas que tienes 2FA activado y quieres continuar?"; then
                ui_success "Continuando bajo responsabilidad del usuario."
                break
            else
                ui_error "Verificación cancelada."
                exit 1
            fi
        else
            # Caso: False explícito (Bloqueante)
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