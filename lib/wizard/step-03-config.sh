#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-03-config.sh

run_step_git_config() {
    ui_step_header "5. Configuración de Identidad Local"

    # ==========================================================================
    # 1. DETECCIÓN DE CONFLICTOS (Safety Checks)
    # ==========================================================================
    # Usamos los helpers de git-ops.sh para detectar si hay múltiples valores
    # que puedan confundir a git.
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
    # Usamos el helper git_get para evitar errores si las llaves no existen
    local local_name="$(git_get local user.name)"
    local local_email="$(git_get local user.email)"
    local global_name="$(git_get global user.name)"
    local global_email="$(git_get global user.email)"

    # Variables que exportaremos para el Step 04
    export GIT_NAME=""
    export GIT_EMAIL=""
    # SSH_KEY_FINAL viene exportada del Step 02
    export SIGNING_KEY="${SSH_KEY_FINAL}.pub" 

    local identity_configured=false

    # Caso A: Existe identidad Local (Prioridad Máxima)
    if any_set "$local_name" "$local_email"; then
        if [ -z "$local_name" ] || [ -z "$local_email" ]; then
            ui_error "Identidad LOCAL incompleta. Corrígela manualmente."
            exit 1
        fi
        GIT_NAME="$local_name"
        GIT_EMAIL="$local_email"
        ui_success "Identidad LOCAL ya configurada: $GIT_NAME <$GIT_EMAIL>"
        identity_configured=true
    
    # Caso B: Existe identidad Global (Fallback común)
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

    # --- FIX (Modelo de Identidades): Preferir configuración LOCAL por repo (opcional) ---
    # Esto ayuda cuando el usuario maneja múltiples perfiles/cuentas.
    # Si tomamos identidad desde GLOBAL y el repo no tiene identidad LOCAL, ofrecemos aplicarla.
    if [ "$identity_configured" = true ]; then
        if [ -z "$local_name" ] && [ -z "$local_email" ] && [ -n "$global_name" ] && [ -n "$global_email" ]; then
            ui_info "Detectamos identidad GLOBAL pero este repo no tiene identidad LOCAL."
            ui_info "Recomendación (multi-perfil): guardar identity local en este repo."
            
            if ask_yes_no "¿Quieres aplicar '$GIT_NAME <$GIT_EMAIL>' también a nivel LOCAL (solo este repo)?"; then
                git config --local --replace-all user.name "$GIT_NAME"
                git config --local --replace-all user.email "$GIT_EMAIL"
                ui_success "Identidad aplicada en LOCAL para este repo."
            else
                ui_info "Se mantuvo solo identidad GLOBAL (sin cambios locales)."
            fi
        fi
    fi

    # ==========================================================================
    # 3. CONFIGURACIÓN DE IDENTIDAD (Si faltaba)
    # ==========================================================================
    if [ "$identity_configured" = false ]; then
        ui_info "Configurando identidad por primera vez..."
        
        # Intentar adivinar datos desde GitHub API para mejorar UX
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

        # Escribir en GLOBAL (Política: Devbox configura el user globalmente por defecto)
        git config --global --replace-all user.name "$GIT_NAME"
        git config --global --replace-all user.email "$GIT_EMAIL"
        ui_success "Identidad configurada en GLOBAL."

        # --- FIX (Modelo de Identidades): también ofrecer identidad LOCAL al crear por primera vez ---
        ui_info "Sugerencia: para multi-perfil, es mejor fijar también identidad LOCAL en este repo."
        if ask_yes_no "¿Quieres aplicar esta identidad también a nivel LOCAL (solo este repo)?"; then
            git config --local --replace-all user.name "$GIT_NAME"
            git config --local --replace-all user.email "$GIT_EMAIL"
            ui_success "Identidad aplicada en LOCAL para este repo."
        else
            ui_info "Se mantuvo solo identidad GLOBAL (sin cambios locales)."
        fi
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
            
            # FIX: confirm robusto con fallback
            local replace_ok=false
            if command -v gum >/dev/null 2>&1; then
                if gum confirm "¿Deseas reemplazarla por la nueva?"; then
                    replace_ok=true
                fi
            else
                if ask_yes_no "¿Deseas reemplazarla por la nueva?"; then
                    replace_ok=true
                fi
            fi

            if [ "$replace_ok" != true ]; then
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

            # --- FIX (Modelo de Identidades): recomendar firma LOCAL por repo ---
            ui_info "Sugerencia: para multi-perfil, es mejor fijar la firma también en LOCAL en este repo."
            if ask_yes_no "¿Quieres aplicar la firma SSH también a nivel LOCAL (solo este repo)?"; then
                git config --local --replace-all gpg.format ssh
                git config --local --replace-all user.signingkey "$SIGNING_KEY"
                git config --local --replace-all commit.gpgsign true
                git config --local --replace-all tag.gpgsign true
                ui_success "Firma aplicada en LOCAL para este repo."
            else
                ui_info "Se mantuvo firma solo en GLOBAL (sin cambios locales)."
            fi
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