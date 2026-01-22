#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-03-config.sh

run_step_git_config() {
    ui_step_header "5. Configuración de Identidad Local"

    # ==========================================================================
    # 1. DETECCIÓN DE CONFLICTOS (Safety Checks)
    # ==========================================================================
    # Usamos los helpers de git-ops.sh para detectar si hay múltiples valores
    if has_multiple_values local user.name || has_multiple_values local user.email; then
        ui_error "Identidad LOCAL duplicada detectada. Por seguridad no modifico nada."
        ui_info "Solución: git config --local --unset-all user.name"
        exit 1
    fi

    if has_multiple_values global user.name || has_multiple_values global user.email; then
        ui_error "Identidad GLOBAL duplicada detectada. Por seguridad no modifico nada."
        ui_info "Solución: git config --global --unset-all user.name"
        exit 1
    fi

    # ==========================================================================
    # 2. LECTURA DE ESTADO ACTUAL
    # ==========================================================================
    # Prioridad: Local > Global
    local local_name="$(git_get local user.name)"
    local local_email="$(git_get local user.email)"
    local global_name="$(git_get global user.name)"
    local global_email="$(git_get global user.email)"

    # Variables que exportaremos para el Step 04
    export GIT_NAME=""
    export GIT_EMAIL=""
    export SIGNING_KEY="${SSH_KEY_FINAL}.pub" # Viene del Step 02

    local identity_configured=false

    # Caso A: Existe identidad Local
    if any_set "$local_name" "$local_email"; then
        if [ -z "$local_name" ] || [ -z "$local_email" ]; then
            ui_error "Identidad LOCAL incompleta. Corrígela manualmente."
            exit 1
        fi
        GIT_NAME="$local_name"
        GIT_EMAIL="$local_email"
        ui_success "Identidad LOCAL ya configurada: $GIT_NAME <$GIT_EMAIL>"
        identity_configured=true
    
    # Caso B: Existe identidad Global
    elif any_set "$global_name" "$global_email"; then
        if [ -z "$global_name" ] || [ -z "$global_email" ]; then
            ui_error "Identidad GLOBAL incompleta. Corrígela manualmente."
            exit 1
        fi
        GIT_NAME="$global_name"
        GIT_EMAIL="$global_email"
        ui_success "Identidad GLOBAL ya configurada: $GIT_NAME <$GIT_EMAIL>"
        identity_configured=true
    fi

    # ==========================================================================
    # 3. CONFIGURACIÓN DE IDENTIDAD (Si faltaba)
    # ==========================================================================
    if [ "$identity_configured" = false ]; then
        ui_info "Configurando identidad por primera vez..."
        
        # Intentar adivinar datos desde GitHub API
        local gh_name
        gh_name=$(gh api user -q ".name" 2>/dev/null || gh api user -q ".login" 2>/dev/null || echo "")
        local gh_email
        gh_email=$(gh api user -q ".email" 2>/dev/null || echo "")

        # Inputs interactivos
        gum style "Confirma tus datos para los commits:"
        GIT_NAME=$(gum input --value "$gh_name" --header "Tu Nombre Completo")
        GIT_EMAIL=$(gum input --value "$gh_email" --header "Tu Email (ej: usuario@empresa.com)")

        if [ -z "$GIT_EMAIL" ]; then
            ui_error "El email es obligatorio."
            exit 1
        fi

        # Escribir en GLOBAL (Política: Devbox configura el user globalmente)
        git config --global --replace-all user.name "$GIT_NAME"
        git config --global --replace-all user.email "$GIT_EMAIL"
        ui_success "Identidad configurada en GLOBAL."
    fi

    # ==========================================================================
    # 4. CONFIGURACIÓN DE FIRMA (SSH SIGNING)
    # ==========================================================================
    
    if [ -n "$SSH_KEY_FINAL" ]; then
        # --- FIX: CONFIRMACIÓN ANTES DE PISAR (P2) ---
        local current_key
        current_key=$(git_get global user.signingkey)
        local do_configure=true

        # Si ya existe una llave y es distinta a la nueva, preguntamos.
        if [ -n "$current_key" ] && [ "$current_key" != "$SIGNING_KEY" ]; then
            ui_warn "⚠️ Detectamos otra llave de firma configurada globalmente."
            echo "   Actual: $current_key"
            echo "   Nueva:  $SIGNING_KEY"
            
            if ! gum confirm "¿Deseas reemplazarla por la nueva?"; then
                ui_info "Manteniendo configuración anterior. (No se modificó git config global)."
                # Ajustamos la variable para que el perfil (Step 04) sea consistente con lo que quedó en git
                SIGNING_KEY="$current_key"
                do_configure=false
            fi
        fi

        if [ "$do_configure" = true ]; then
            ui_info "Activando firma de commits con SSH..."
            
            git config --global --replace-all gpg.format ssh
            git config --global --replace-all user.signingkey "$SIGNING_KEY"
            git config --global --replace-all commit.gpgsign true
            git config --global --replace-all tag.gpgsign true
            
            ui_success "Firma configurada en GLOBAL (Key: $SIGNING_KEY)."
        fi
    else
        # Fallback por si este script se corre aislado (sin paso 2)
        local current_key
        current_key=$(git_get global user.signingkey)
        if [ -n "$current_key" ]; then
            ui_success "Firma SSH ya configurada previamente (Key: $current_key)."
            SIGNING_KEY="$current_key"
        else
            ui_warn "No se seleccionó llave nueva y no hay configuración previa. Saltando firma."
        fi
    fi
}