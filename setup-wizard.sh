#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/setup-wizard.sh
set -e

MARKER_FILE=".devtools/.setup_completed"
[ -f "$MARKER_FILE" ] && exit 0

# --- Funciones Helpers ---
log_success() { gum style --foreground 76 "✅ $1"; }
log_warn()    { gum style --foreground 220 "⚠️  $1"; }
log_error()   { gum style --foreground 196 "❌ $1"; }
log_info()    { gum style --foreground 99 "ℹ️  $1"; }

clear
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	"🕵️‍♂️ BIENVENIDO A EL RINCÓN DEL DETECTIVE" \
	"Setup de Entorno PMBOK - Asistente Integral"

echo ""
gum style --foreground 99 "Vamos a configurar tu identidad y seguridad paso a paso."
echo ""

# ==============================================================================
# PASO 1: GESTIÓN DE CUENTA GITHUB
# ==============================================================================
gum style --foreground 212 "1. Autenticación con GitHub"

NEEDS_LOGIN=true

if gh auth status >/dev/null 2>&1; then
    CURRENT_USER=$(gh api user -q ".login")
    gum style --foreground 76 "👤 Sesión activa detectada: $CURRENT_USER"
    
    echo "¿Qué deseas hacer?"
    ACTION=$(gum choose \
        "Continuar como $CURRENT_USER" \
        "Cerrar sesión y cambiar de cuenta" \
        "Refrescar credenciales (Reparar permisos)")

    if [[ "$ACTION" == "Continuar"* ]]; then
        NEEDS_LOGIN=false
    else
        gh auth logout >/dev/null 2>&1 || true
        NEEDS_LOGIN=true
    fi
fi

if [ "$NEEDS_LOGIN" = true ]; then
    gum style --foreground 220 "🔐 Iniciando autenticación web..."
    log_info "Solicitaremos permisos de escritura para subir tu llave SSH automáticamente."
    gum style --foreground 99 "Presiona Enter para abrir el navegador y autorizar."
    gum confirm || exit 1
    
    if gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key -s "admin:public_key write:public_key admin:ssh_signing_key user"; then
        NEW_USER=$(gh api user -q ".login")
        log_success "Login exitoso. Conectado como: $NEW_USER"
    else
        log_error "Falló el login."
        exit 1
    fi
fi

# ==============================================================================
# PASO 1.5: BLOQUEO ESTRICTO POR 2FA
# ==============================================================================
gum style --foreground 212 "2. Verificación de Seguridad (2FA)"

while true; do
    IS_2FA_ENABLED=$(gh api user -q ".two_factor_authentication")

    if [ "$IS_2FA_ENABLED" == "true" ]; then
        log_success "Autenticación de Dos Factores (2FA) detectada."
        break
    else
        gum style --border double --border-foreground 196 --foreground 196 --align center \
            "⛔ ACCESO DENEGADO ⛔" \
            "Tu cuenta NO tiene activado el 2FA." \
            "Es obligatorio para trabajar en este ecosistema."

        echo ""
        gum style --foreground 220 "1. Ve a: https://github.com/settings/security"
        gum style --foreground 220 "2. Activa 'Two-factor authentication'."
        echo ""
        
        if gum confirm "¿Ya lo activaste? (Volver a comprobar)"; then
            gum spin --spinner dot --title "Reverificando..." -- sleep 2
        else
            log_error "No podemos continuar sin 2FA."
            exit 1
        fi
    fi
done

# ==============================================================================
# PASO 2: GESTIÓN DE LLAVES SSH
# ==============================================================================
gum style --foreground 212 "3. Configuración de Llaves de Seguridad"

EXISTING_KEYS=$(find "$HOME/.ssh" -maxdepth 1 -name "id_*.pub" 2>/dev/null || true)
SSH_KEY_FINAL=""
PUB_KEY_CONTENT=""

OPTIONS=("🔑 Generar NUEVA llave (Recomendado)")
if [ -n "$EXISTING_KEYS" ]; then
    OPTIONS+=("📂 Seleccionar llave existente")
fi

echo "Selecciona cómo quieres firmar y autenticarte:"
SSH_CHOICE=$(gum choose "${OPTIONS[@]}")

if [[ "$SSH_CHOICE" == "🔑 Generar"* ]]; then
    CURRENT_USER_SAFE=$(gh api user -q ".login" || echo "user")
    DEFAULT_NAME="id_ed25519_${CURRENT_USER_SAFE}"
    
    KEY_NAME=$(gum input --placeholder "Nombre del archivo" --value "$DEFAULT_NAME" --header "Nombre para la llave (sin .pub)")
    SSH_KEY_FINAL="$HOME/.ssh/$KEY_NAME"
    
    if [ -f "$SSH_KEY_FINAL" ]; then
        log_warn "El archivo '$KEY_NAME' ya existe."
        if gum confirm "¿Quieres sobrescribirlo? (La anterior se perderá)"; then
            rm -f "$SSH_KEY_FINAL" "$SSH_KEY_FINAL.pub"
        else
            log_error "Operación cancelada. Elige otro nombre."
            exit 1
        fi
    fi

    gum spin --spinner dot --title "Generando llave criptográfica..." -- \
        ssh-keygen -t ed25519 -C "devbox-${CURRENT_USER_SAFE}" -f "$SSH_KEY_FINAL" -N "" -q
    
    log_success "Llave creada en: $SSH_KEY_FINAL"
else
    KEY_LIST=$(echo "$EXISTING_KEYS")
    SELECTED_PUB=$(gum choose $KEY_LIST --header "Selecciona la llave pública a usar:")
    SSH_KEY_FINAL="${SELECTED_PUB%.pub}"
    log_success "Has seleccionado: $SSH_KEY_FINAL"
fi

PUB_KEY_CONTENT=$(cat "$SSH_KEY_FINAL.pub")

# ==============================================================================
# PASO 3: SINCRONIZACIÓN
# ==============================================================================
gum style --foreground 212 "4. Sincronizando Seguridad con GitHub"

KEY_TITLE="Devbox-Key-$(date +%Y%m%d-%H%M)"
UPLOAD_SUCCESS=false

gum spin --spinner dot --title "Intentando subir llave automáticamente..." -- sleep 2

if gh ssh-key add "$SSH_KEY_FINAL.pub" --title "$KEY_TITLE" --type authentication >/dev/null 2>&1; then
    UPLOAD_SUCCESS=true
    log_success "¡Éxito! La llave se subió automáticamente."
else
    if gh ssh-key list | grep -q "$(echo "$PUB_KEY_CONTENT" | cut -d' ' -f2)"; then
        UPLOAD_SUCCESS=true
        log_success "La llave ya estaba configurada en tu cuenta."
    fi
fi

if [ "$UPLOAD_SUCCESS" = false ]; then
    gum style --border double --border-foreground 196 --foreground 220 --padding "1 2" \
        "⚠️  NO PUDIMOS SUBIR LA LLAVE AUTOMÁTICAMENTE" \
        "Esto es normal si faltan permisos de admin." \
        "Vamos a hacerlo manualmente."

    echo ""
    gum style --foreground 99 "1. Copia tu llave pública:"
    echo "$PUB_KEY_CONTENT" | gum format -t code
    
    if command -v xclip >/dev/null; then echo "$PUB_KEY_CONTENT" | xclip -sel clip; fi
    
    echo ""
    gum style --foreground 99 "2. Abre este link:"
    gum style --foreground 212 "   👉 https://github.com/settings/ssh/new"
    echo ""
    gum style --foreground 99 "3. Pega la llave, ponle título y guarda."
    
    if gum confirm "Presiona Enter cuando la hayas guardado en GitHub"; then
        log_success "Confirmado por el usuario."
    else
        log_error "Cancelado."
        exit 1
    fi
fi

# ==============================================================================
# PASO 4: CONFIGURACIÓN LOCAL (CORREGIDO: EMAIL EN BLANCO)
# ==============================================================================
gum style --foreground 212 "5. Configurando Identidad Local"

# Datos de GitHub
GH_NAME=$(gh api user -q ".name" 2>/dev/null || echo "")
GH_LOGIN=$(gh api user -q ".login" 2>/dev/null || echo "")
GH_EMAIL=$(gh api user -q ".email" 2>/dev/null || echo "")

# Lógica Nombre
if [ -n "$GH_NAME" ]; then SUGGESTED_NAME="$GH_NAME";
elif [ -n "$GH_LOGIN" ]; then SUGGESTED_NAME="$GH_LOGIN";
else SUGGESTED_NAME=$(git config --global user.name || echo ""); fi

# Lógica Email (Solo sugerencia visual)
SUGGESTED_EMAIL="${GH_EMAIL:-$(git config --global user.email)}"

gum style "Confirma tu firma para los commits:"

# Input Nombre (Con valor por defecto)
GIT_NAME=$(gum input --placeholder "Tu Nombre" --value "$SUGGESTED_NAME" --header "Nombre")

# Input Email (CAMBIO: SIN valor por defecto, limpio para escribir)
EMAIL_HEADER="Email"
if [ -n "$SUGGESTED_EMAIL" ]; then
    EMAIL_HEADER="Email (Detectado: $SUGGESTED_EMAIL - Enter para confirmar o escribe otro)"
fi

GIT_EMAIL=$(gum input --placeholder "ej: usuario@empresa.com" --header "$EMAIL_HEADER")

# Si el usuario lo dejó vacío, usamos el sugerido como fallback
if [ -z "$GIT_EMAIL" ]; then
    if [ -n "$SUGGESTED_EMAIL" ]; then
        GIT_EMAIL="$SUGGESTED_EMAIL"
        log_info "Usando email detectado: $GIT_EMAIL"
    else
        log_error "El email no puede estar vacío."
        exit 1
    fi
fi

git config user.name "$GIT_NAME"
git config user.email "$GIT_EMAIL"
git config gpg.format ssh
git config user.signingkey "$SSH_KEY_FINAL.pub"
git config commit.gpgsign true
git config tag.gpgsign true

# ==============================================================================
# PASO 5: VALIDACIÓN FINAL
# ==============================================================================
gum spin --spinner dot --title "Validando conexión SSH final..." -- sleep 1

CURRENT_URL=$(git remote get-url origin)
if [[ "$CURRENT_URL" == https://* ]]; then
    NEW_URL=$(echo "$CURRENT_URL" | sed -E 's/https:\/\/github.com\//git@github.com:/')
    git remote set-url origin "$NEW_URL"
fi

if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
    log_success "Conexión verificada: Acceso Correcto."
else
    log_warn "No pudimos validar la conexión automáticamente."
    log_info "Si acabas de subir la llave, espera unos segundos y prueba 'ssh -T git@github.com'."
fi

# Bootstrap .env
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        log_success "Archivo .env creado."
    else
        touch .env
    fi
fi

touch "$MARKER_FILE"

gum style \
    --border double --margin "1 2" --padding "1 4" --border-foreground 212 --foreground 212 \
    "🎉 ¡TODO LISTO!" \
    "Usuario: $GIT_NAME"

echo "💡 Tip: Usa 'git feature <nombre>' para empezar."