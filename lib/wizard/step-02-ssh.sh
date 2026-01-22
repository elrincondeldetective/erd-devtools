#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-02-ssh.sh

run_step_ssh() {
    ui_step_header "3. Configuración de Llaves de Seguridad"

    # Variable global que exportaremos para los siguientes pasos
    export SSH_KEY_FINAL=""
    
    local existing_keys
    existing_keys=$(find "$HOME/.ssh" -maxdepth 1 -name "id_*.pub" 2>/dev/null || true)
    
    local choice_gen="🔑 Generar NUEVA llave (Recomendado)"
    local choice_sel="📂 Seleccionar llave existente"
    local ssh_choice

    # 1. Decisión: Generar vs Seleccionar
    if [ -n "$existing_keys" ]; then
        ui_info "Selecciona cómo quieres firmar y autenticarte:"
        ssh_choice=$(gum choose "$choice_gen" "$choice_sel")
    else
        ssh_choice="$choice_gen"
    fi

    # 2. Ejecución de la decisión
    if [[ "$ssh_choice" == "$choice_gen" ]]; then
        generate_new_ssh_key
    else
        select_existing_ssh_key "$existing_keys"
    fi

    # 3. Subida a GitHub
    sync_ssh_key_to_github
}

generate_new_ssh_key() {
    local current_user_safe
    current_user_safe=$(gh api user -q ".login" || echo "user")
    
    local default_name="id_ed25519_${current_user_safe}"
    local key_name
    
    key_name=$(gum input --placeholder "Nombre del archivo" --value "$default_name" --header "Nombre para la llave (sin .pub)")
    SSH_KEY_FINAL="$HOME/.ssh/$key_name"
    
    # Validar si existe para no sobrescribir accidentalmente
    if [ -f "$SSH_KEY_FINAL" ]; then
        ui_warn "El archivo '$key_name' ya existe."
        if gum confirm "¿Quieres sobrescribirlo? (La anterior se perderá)"; then
            rm -f "$SSH_KEY_FINAL" "$SSH_KEY_FINAL.pub"
        else
            ui_error "Operación cancelada. Elige otro nombre."
            exit 1
        fi
    fi

    ui_spinner "Generando llave criptográfica..." \
        ssh-keygen -t ed25519 -C "devbox-${current_user_safe}" -f "$SSH_KEY_FINAL" -N "" -q
    
    ui_success "Llave creada en: $SSH_KEY_FINAL"
}

select_existing_ssh_key() {
    local keys="$1"
    local selected_pub
    
    selected_pub=$(gum choose $keys --header "Selecciona la llave pública a usar:")
    SSH_KEY_FINAL="${selected_pub%.pub}"
    
    ui_success "Has seleccionado: $SSH_KEY_FINAL"
}

sync_ssh_key_to_github() {
    ui_step_header "4. Sincronizando Seguridad con GitHub"

    local key_title="Devbox-Key-$(date +%Y%m%d-%H%M)"
    local pub_key_content
    pub_key_content=$(cat "$SSH_KEY_FINAL.pub")
    local auth_uploaded=false
    # Variable para trackear si la firma se subió (aunque no bloquea el flujo principal)
    local sign_uploaded=false

    ui_spinner "Intentando subir llaves automáticamente..." sleep 2

    # --------------------------------------------------------------------------
    # FASE 1: Subida como Llave de AUTENTICACIÓN (Lectura/Escritura de repo)
    # --------------------------------------------------------------------------
    if gh ssh-key add "$SSH_KEY_FINAL.pub" --title "$key_title (Auth)" --type authentication >/dev/null 2>&1; then
        auth_uploaded=true
        ui_success "✅ Llave de Autenticación subida (git push/pull habilitado)."
    else
        # Verificación: ¿Ya existía?
        local key_body
        key_body=$(echo "$pub_key_content" | cut -d' ' -f2)
        
        if gh ssh-key list | grep -q "$key_body"; then
            auth_uploaded=true
            ui_success "ℹ️ La llave ya estaba configurada para Autenticación."
        else
            ui_warn "⚠️ Falló la subida de la llave de Autenticación."
        fi
    fi

    # --------------------------------------------------------------------------
    # FASE 2: Subida como Llave de FIRMA (Verified Commits) - FIX
    # --------------------------------------------------------------------------
    # Intentamos registrar la misma llave explícitamente para signing.
    if gh ssh-key add "$SSH_KEY_FINAL.pub" --title "$key_title (Signing)" --type signing >/dev/null 2>&1; then
        sign_uploaded=true
        ui_success "✅ Llave de Firma subida (Tus commits saldrán como 'Verified')."
    else
        # Verificación silenciosa para signing
        local key_body
        key_body=$(echo "$pub_key_content" | cut -d' ' -f2)
        
        # Nota: gh ssh-key list por defecto muestra auth keys, usamos --type signing si la versión lo soporta
        # o simplemente ignoramos el error si no es crítico.
        if gh ssh-key list --type signing 2>/dev/null | grep -q "$key_body"; then
                ui_success "ℹ️ La llave ya estaba configurada para Firma."
                sign_uploaded=true
        else
                ui_warn "⚠️ No se pudo registrar como llave de Firma (Signing Key)."
                ui_info "Podrás hacer commits, pero quizás no aparezcan como 'Verified'."
        fi
    fi

    # --------------------------------------------------------------------------
    # FASE 3: Fallback Manual (Solo si falló Auth, que es lo crítico)
    # --------------------------------------------------------------------------
    if [ "$auth_uploaded" = false ]; then
        ui_alert_box "⚠️ NO PUDIMOS SUBIR LA LLAVE DE AUTENTICACIÓN" \
            "Esto es normal si faltan permisos de admin (write:public_key)." \
            "Vamos a hacerlo manualmente."

        echo ""
        ui_info "1. Copia tu llave pública:"
        echo "$pub_key_content" | ui_code_block
        
        if command -v xclip >/dev/null; then 
            echo "$pub_key_content" | xclip -sel clip
            ui_info "(Copiado al portapapeles automáticamente)"
        fi
        
        echo ""
        ui_info "2. Abre este link:"
        ui_link "   👉 https://github.com/settings/ssh/new"
        echo ""
        ui_info "3. Pega la llave, ponle título y guarda."
        
        if gum confirm "Presiona Enter cuando la hayas guardado en GitHub"; then
            ui_success "Confirmado por el usuario."
        else
            ui_error "Cancelado."
            exit 1
        fi
    fi
}