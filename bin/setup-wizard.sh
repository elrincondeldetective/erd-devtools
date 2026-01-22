#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/auth-wizard.sh

# ==============================================================================
# 1. GESTIÓN DE FIRMA (GPG - "VERIFIED")
# ==============================================================================

setup_gpg_signing() {
    log_header "🔐 CONFIGURACIÓN DE FIRMA (GPG)"

    # 1. Detectar llaves GPG privadas importadas
    # Buscamos 'sec' (secreta) y extraemos el ID largo
    local gpg_keys
    gpg_keys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep "sec" | awk '{print $2}' | cut -d'/' -f2)

    if [[ -z "$gpg_keys" ]]; then
        log_warn "⚠️  No detecté llaves GPG. Tus commits no estarán verificados."
        return
    fi

    # 2. Selección Automática
    # Si hay varias, tomamos la primera (normalmente la más reciente o principal)
    local selected_key=$(echo "$gpg_keys" | head -n1)
    
    log_info "✅ Llave GPG detectada para firmar: $selected_key"
    
    # 3. Configurar Git para FIRMAR (Signing)
    git config --global user.signingkey "$selected_key"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    
    # Asegurar que GPG no falle en terminales sin GUI
    export GPG_TTY=$(tty)
    
    log_success "✅ Git configurado para firmar commits con GPG."
}

# ==============================================================================
# 2. GESTIÓN DE TRANSPORTE (SSH - "CONEXIÓN")
# ==============================================================================

setup_ssh_transport() {
    log_header "🔑 CONFIGURACIÓN DE CONEXIÓN (SSH)"

    # 1. Buscar llaves SSH locales (incluyendo nombres personalizados como _reydem)
    # Buscamos cualquier archivo que empiece por id_ed25519 y no sea .pub
    local ssh_files
    ssh_files=$(find ~/.ssh -maxdepth 1 -name "id_ed25519*" -not -name "*.pub" 2>/dev/null)

    if [[ -z "$ssh_files" ]]; then
        log_error "❌ No encontré llaves SSH tipo ed25519 en ~/.ssh/"
        echo "   (El script espera encontrar archivos como id_ed25519_reydem)"
        exit 1
    fi

    # 2. Seleccionar la llave
    # Tomamos la primera encontrada. Dado que acabas de limpiar, debería ser la correcta.
    local selected_ssh
    selected_ssh=$(echo "$ssh_files" | head -n1)
    local key_name=$(basename "$selected_ssh")
    
    log_info "🔍 Llave SSH detectada para conexión: $key_name"

    # 3. Validar con GitHub (¿Ya la subiste?)
    log_info "📡 Verificando si GitHub autoriza esta llave..."
    
    # Calculamos la huella digital local
    local local_fingerprint
    local_fingerprint=$(ssh-keygen -lf "$selected_ssh.pub" | awk '{print $2}')
    
    # Consultamos tus llaves en GitHub
    if gh ssh-key list | grep -Fq "$local_fingerprint"; then
        log_success "✅ GitHub reconoce esta llave. Conexión autorizada."
    else
        log_warn "⚠️  GitHub NO conoce esta llave (la borraste de la web)."
        if ask_yes_no "¿Quieres subirla a GitHub ahora?"; then
            gh ssh-key add "$selected_ssh.pub" --title "Devbox-$key_name-$(date +%Y%m%d)"
            log_success "✅ Llave subida y vinculada."
        else
            log_warn "Omitiendo subida. Git push/pull fallará si no la subes manualmente."
        fi
    fi

    # 4. Configurar Agente SSH (Para no pedir frase de paso a cada rato)
    eval "$(ssh-agent -s)" >/dev/null
    ssh-add "$selected_ssh" 2>/dev/null

    # 5. Configurar Git para usar SSH en lugar de HTTPS
    # Esto fuerza a que todos los comandos 'git' usen la llave SSH detectada
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    
    log_success "✅ Git configurado para usar SSH como transporte."
}

# ==============================================================================
# 3. ORQUESTADOR PRINCIPAL
# ==============================================================================

wizard_auth_flow() {
    # Asegurar sesión de GH CLI primero
    if ! gh auth status >/dev/null 2>&1; then
        echo "Iniciando sesión en GitHub CLI..."
        gh auth login -p ssh -w
    fi

    local user=$(gh api user -q .login)
    log_info "👤 Configurando identidad para: $user"
    echo

    # PASO 1: Configurar FIRMA (GPG)
    setup_gpg_signing
    echo

    # PASO 2: Configurar TRANSPORTE (SSH)
    setup_ssh_transport
}