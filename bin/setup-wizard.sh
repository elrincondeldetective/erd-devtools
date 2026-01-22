#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/setup-wizard.sh
set -e

MARKER_FILE=".devtools/.setup_completed"
# CAMBIO: Apuntamos al archivo correcto dentro de .devtools
ACPRC_FILE=".devtools/.git-acprc"

# ==============================================================================
# FIX: Asegurar ejecución desde la raíz del repo (evita marker/acprc duplicados por cwd)
# ==============================================================================
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "❌ Este script debe ejecutarse dentro de un repositorio git."
    exit 1
fi

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

# ==============================================================================
# FIX: Flags de ejecución (sin tocar identidad si ya existe)
#   --verify-only : solo verificación (no modifica identidad/firma/menú)
#   --force       : ignora el marker para re-ejecutar flujo (aun así NO modifica identidad/firma si ya existen)
# ==============================================================================
FORCE=false
VERIFY_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
        --verify-only|--verify) VERIFY_ONLY=true ;;
    esac
done

# --- Funciones Helpers ---
log_success() { gum style --foreground 76 "✅ $1"; }
log_warn()    { gum style --foreground 220 "⚠️  $1"; }
log_error()   { gum style --foreground 196 "❌ $1"; }
log_info()    { gum style --foreground 99 "ℹ️  $1"; }

# ==============================================================================
# FIX: Helpers para leer config por scope y detectar duplicados/estado parcial
# ==============================================================================
git_get() {
    # usage: git_get <local|global> <key>
    local scope="$1" key="$2"
    git config "--$scope" --get "$key" 2>/dev/null || true
}

git_get_all() {
    # usage: git_get_all <local|global> <key>
    local scope="$1" key="$2"
    git config "--$scope" --get-all "$key" 2>/dev/null || true
}

count_nonempty_lines() {
    # cuenta líneas no vacías
    awk 'NF{c++} END{print c+0}'
}

has_multiple_values() {
    # usage: has_multiple_values <local|global> <key>
    local scope="$1" key="$2"
    local all
    all="$(git_get_all "$scope" "$key")"
    [ "$(printf "%s\n" "$all" | count_nonempty_lines)" -gt 1 ]
}

any_set() {
    # true si alguno de los argumentos es no-vacío
    for v in "$@"; do
        if [ -n "$v" ]; then return 0; fi
    done
    return 1
}

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
# FIX: Si ya se corrió el setup, por defecto solo verifica (no re-escribe identidad/firma)
# ==============================================================================
if [ -f "$MARKER_FILE" ] && [ "$FORCE" != true ]; then
    VERIFY_ONLY=true
    log_info "Setup ya estaba completado. Ejecutando solo verificación (usa --force para re-ejecutar el flujo completo)."
fi

# ==============================================================================
# FIX: Modo verificación (NO toca identidad ni firma)
# ==============================================================================
if [ "$VERIFY_ONLY" = true ]; then
    gum style --foreground 212 "Verificación rápida (sin cambios)"

    gum spin --spinner dot --title "Validando conexión SSH final..." -- sleep 1

    CURRENT_URL=$(git remote get-url origin 2>/dev/null || true)
    if [ -n "$CURRENT_URL" ] && [[ "$CURRENT_URL" == https://* ]]; then
        NEW_URL=$(echo "$CURRENT_URL" | sed -E 's/https:\/\/github.com\//git@github.com:/')
        git remote set-url origin "$NEW_URL" 2>/dev/null || true
    fi

    if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
        log_success "Conexión verificada: Acceso Correcto."
    else
        log_warn "No pudimos validar la conexión automáticamente."
    fi

    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            log_success "Archivo .env creado."
        else
            touch .env
        fi
    fi

    # Mostrar usuario detectado sin modificar nada
    DETECTED_NAME="$(git config --get user.name 2>/dev/null || true)"
    if [ -z "$DETECTED_NAME" ]; then
        DETECTED_NAME="$(git_get global user.name)"
    fi
    if [ -z "$DETECTED_NAME" ]; then
        DETECTED_NAME="(sin definir)"
    fi

    gum style \
        --border double --margin "1 2" --padding "1 4" --border-foreground 212 --foreground 212 \
        "✅ VERIFICACIÓN COMPLETADA" \
        "Usuario detectado: $DETECTED_NAME" \
        "Modo: verify-only (sin cambios)"

    echo "💡 Tip: Usa 'git feature <nombre>' para empezar."
    exit 0
fi

# ==========================================
# PASO 1: GESTIÓN DE CUENTA GITHUB
# ==========================================
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
# PASO 4: CONFIGURACIÓN LOCAL
# ==============================================================================
gum style --foreground 212 "5. Configurando Identidad Local"

GH_NAME=$(gh api user -q ".name" 2>/dev/null || echo "")
GH_LOGIN=$(gh api user -q ".login" 2>/dev/null || echo "")
GH_EMAIL=$(gh api user -q ".email" 2>/dev/null || echo "")

# ==============================================================================
# FIX: Bloqueo estricto / idempotencia
# - Si ya existe identidad (local o global): NO se modifica, NO se pregunta.
# - Si ya existe firma (local o global): NO se modifica, NO se pregunta.
# - Si detecta config duplicada o parcial: aborta (por seguridad).
# - Si no hay nada, configura UNA sola vez en GLOBAL (para no duplicar por repo).
# ==============================================================================
LOCAL_NAME="$(git_get local user.name)"
LOCAL_EMAIL="$(git_get local user.email)"
GLOBAL_NAME="$(git_get global user.name)"
GLOBAL_EMAIL="$(git_get global user.email)"

LOCAL_FORMAT="$(git_get local gpg.format)"
LOCAL_SIGNKEY="$(git_get local user.signingkey)"
LOCAL_CGSIGN="$(git_get local commit.gpgsign)"
LOCAL_TGSIGN="$(git_get local tag.gpgsign)"

GLOBAL_FORMAT="$(git_get global gpg.format)"
GLOBAL_SIGNKEY="$(git_get global user.signingkey)"
GLOBAL_CGSIGN="$(git_get global commit.gpgsign)"
GLOBAL_TGSIGN="$(git_get global tag.gpgsign)"

IDENTITY_EXISTS=false
SIGNING_EXISTS=false
SIGNING_KEY=""
SIGNING_FORMAT=""

# Detectar duplicados en scopes (múltiples values) y abortar por seguridad
if has_multiple_values local user.name || has_multiple_values local user.email; then
    log_error "Identidad LOCAL duplicada detectada (múltiples values). Por seguridad no modifico nada."
    log_info "Solución: limpia el scope local del repo: git config --local --unset-all user.name && git config --local --unset-all user.email"
    exit 1
fi
if has_multiple_values global user.name || has_multiple_values global user.email; then
    log_error "Identidad GLOBAL duplicada detectada (múltiples values). Por seguridad no modifico nada."
    log_info "Solución: limpia tu global: git config --global --unset-all user.name && git config --global --unset-all user.email"
    exit 1
fi
if has_multiple_values local gpg.format || has_multiple_values local user.signingkey; then
    log_error "Firma LOCAL duplicada detectada (múltiples values). Por seguridad no modifico nada."
    log_info "Solución: limpia el scope local del repo: git config --local --unset-all gpg.format && git config --local --unset-all user.signingkey"
    exit 1
fi
if has_multiple_values global gpg.format || has_multiple_values global user.signingkey; then
    log_error "Firma GLOBAL duplicada detectada (múltiples values). Por seguridad no modifico nada."
    log_info "Solución: limpia tu global: git config --global --unset-all gpg.format && git config --global --unset-all user.signingkey"
    exit 1
fi

# Identidad existente (local tiene prioridad)
if any_set "$LOCAL_NAME" "$LOCAL_EMAIL"; then
    IDENTITY_EXISTS=true
    if [ -z "$LOCAL_NAME" ] || [ -z "$LOCAL_EMAIL" ]; then
        log_error "Identidad LOCAL parcial detectada (name/email incompletos). Por seguridad no la modifico."
        log_info "Corrige manualmente o limpia el scope local del repo (unset-all user.name/user.email)."
        exit 1
    fi
    GIT_NAME="$LOCAL_NAME"
    GIT_EMAIL="$LOCAL_EMAIL"
    log_success "Identidad LOCAL ya configurada: $GIT_NAME <$GIT_EMAIL>. No se harán cambios."
elif any_set "$GLOBAL_NAME" "$GLOBAL_EMAIL"; then
    IDENTITY_EXISTS=true
    if [ -z "$GLOBAL_NAME" ] || [ -z "$GLOBAL_EMAIL" ]; then
        log_error "Identidad GLOBAL parcial detectada (name/email incompletos). Por seguridad no la modifico."
        log_info "Completa esos datos manualmente en tu global antes de continuar."
        exit 1
    fi
    GIT_NAME="$GLOBAL_NAME"
    GIT_EMAIL="$GLOBAL_EMAIL"
    log_success "Identidad GLOBAL ya configurada: $GIT_NAME <$GIT_EMAIL>. No se harán cambios."
fi

# Firma existente (local tiene prioridad)
if any_set "$LOCAL_FORMAT" "$LOCAL_SIGNKEY" "$LOCAL_CGSIGN" "$LOCAL_TGSIGN"; then
    SIGNING_EXISTS=true
    if [ -z "$LOCAL_FORMAT" ] || [ -z "$LOCAL_SIGNKEY" ]; then
        log_error "Firma LOCAL parcial detectada (gpg.format/user.signingkey incompletos). Por seguridad no la modifico."
        log_info "Corrige manualmente o limpia el scope local del repo (unset-all gpg.format/user.signingkey)."
        exit 1
    fi
    SIGNING_FORMAT="$LOCAL_FORMAT"
    SIGNING_KEY="$LOCAL_SIGNKEY"
    log_success "Firma LOCAL ya configurada: format=$SIGNING_FORMAT, key=$SIGNING_KEY. No se harán cambios."
elif any_set "$GLOBAL_FORMAT" "$GLOBAL_SIGNKEY" "$GLOBAL_CGSIGN" "$GLOBAL_TGSIGN"; then
    SIGNING_EXISTS=true
    if [ -z "$GLOBAL_FORMAT" ] || [ -z "$GLOBAL_SIGNKEY" ]; then
        log_error "Firma GLOBAL parcial detectada (gpg.format/user.signingkey incompletos). Por seguridad no la modifico."
        log_info "Corrige manualmente o limpia esos keys en tu global."
        exit 1
    fi
    SIGNING_FORMAT="$GLOBAL_FORMAT"
    SIGNING_KEY="$GLOBAL_SIGNKEY"
    log_success "Firma GLOBAL ya configurada: format=$SIGNING_FORMAT, key=$SIGNING_KEY. No se harán cambios."
fi

# ------------------------------------------------------------------------------
# BLOQUE ORIGINAL (solo se ejecuta si NO hay identidad)
# ------------------------------------------------------------------------------
if [ -n "$GH_NAME" ]; then SUGGESTED_NAME="$GH_NAME";
elif [ -n "$GH_LOGIN" ]; then SUGGESTED_NAME="$GH_LOGIN";
else SUGGESTED_NAME=$(git config --global user.name || echo ""); fi

SUGGESTED_EMAIL="${GH_EMAIL:-$(git config --global user.email)}"

gum style "Confirma tu firma para los commits:"

if [ "$IDENTITY_EXISTS" = false ]; then
    GIT_NAME=$(gum input --placeholder "Tu Nombre" --value "$SUGGESTED_NAME" --header "Nombre")

    EMAIL_HEADER="Email"
    if [ -n "$SUGGESTED_EMAIL" ]; then
        EMAIL_HEADER="Email (Detectado: $SUGGESTED_EMAIL - Enter para confirmar o escribe otro)"
    fi
    GIT_EMAIL=$(gum input --placeholder "ej: usuario@empresa.com" --header "$EMAIL_HEADER")

    if [ -z "$GIT_EMAIL" ]; then
        if [ -n "$SUGGESTED_EMAIL" ]; then
            GIT_EMAIL="$SUGGESTED_EMAIL"
            log_info "Usando email detectado: $GIT_EMAIL"
        else
            log_error "El email no puede estar vacío."
            exit 1
        fi
    fi
fi

# ------------------------------------------------------------------------------
# FIX: Aplicar configuración SOLO si no existe ya (y siempre en GLOBAL para evitar duplicados)
# ------------------------------------------------------------------------------
if [ "$IDENTITY_EXISTS" = false ]; then
    git config --global --replace-all user.name "$GIT_NAME"
    git config --global --replace-all user.email "$GIT_EMAIL"
    log_success "Identidad configurada en GLOBAL."
fi

if [ "$SIGNING_EXISTS" = false ]; then
    git config --global --replace-all gpg.format ssh
    git config --global --replace-all user.signingkey "$SSH_KEY_FINAL.pub"
    git config --global --replace-all commit.gpgsign true
    git config --global --replace-all tag.gpgsign true
    SIGNING_FORMAT="ssh"
    SIGNING_KEY="$SSH_KEY_FINAL.pub"
    log_success "Firma configurada en GLOBAL (SSH signing)."
fi

# ------------------------------------------------------------------------------
# (Se mantienen las líneas originales, pero ahora el comportamiento es idempotente
#  porque la escritura real sucede SOLO cuando no existía config previa)
# ------------------------------------------------------------------------------
# git config user.name "$GIT_NAME"
# git config user.email "$GIT_EMAIL"
# git config gpg.format ssh
# git config user.signingkey "$SSH_KEY_FINAL.pub"
# git config commit.gpgsign true
# git config tag.gpgsign true

# ==============================================================================
# PASO 5: REGISTRO EN EL SELECTOR DE IDENTIDADES
# ==============================================================================
gum style --foreground 212 "6. Registrando en Selector de Identidades"

# Construimos la línea tal como la lee git-acp.sh
# DisplayName;GitName;GitEmail;SigningKey(Pub);Remote;Host;SSHKey(Priv);GHLogin
PROFILE_SIGNING_KEY="${SIGNING_KEY:-$SSH_KEY_FINAL.pub}"
PROFILE_ENTRY="$GIT_NAME;$GIT_NAME;$GIT_EMAIL;$PROFILE_SIGNING_KEY;origin;github.com;$SSH_KEY_FINAL;$GH_LOGIN"

if [ ! -f "$ACPRC_FILE" ]; then
    # Si no existe, lo creamos con defaults básicos
    echo "DAY_START=\"00:00\"" > "$ACPRC_FILE"
    echo "REFS_LABEL=\"Conteo: commit\"" >> "$ACPRC_FILE"
    echo "DAILY_GOAL=10" >> "$ACPRC_FILE"
    echo "PROFILES=()" >> "$ACPRC_FILE"
fi

# Buscamos si el email ya existe para no duplicar
if grep -q "$GIT_EMAIL" "$ACPRC_FILE"; then
    log_success "Tu perfil ya existía en el menú de identidades."
else
    echo "" >> "$ACPRC_FILE"
    echo "# Auto-agregado por setup-wizard" >> "$ACPRC_FILE"
    # Usamos sintaxis de bash append array: PROFILES+=("...")
    echo "PROFILES+=(\"$PROFILE_ENTRY\")" >> "$ACPRC_FILE"
    log_success "Perfil agregado exitosamente al menú."
fi

# ==============================================================================
# PASO 6: VALIDACIÓN FINAL Y BOOTSTRAP
# ==============================================================================
gum spin --spinner dot --title "Validando conexión SSH final..." -- sleep 1

CURRENT_URL=$(git remote get-url origin 2>/dev/null || true)
if [ -n "$CURRENT_URL" ] && [[ "$CURRENT_URL" == https://* ]]; then
    NEW_URL=$(echo "$CURRENT_URL" | sed -E 's/https:\/\/github.com\//git@github.com:/')
    git remote set-url origin "$NEW_URL" 2>/dev/null || true
fi

if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
    log_success "Conexión verificada: Acceso Correcto."
else
    log_warn "No pudimos validar la conexión automáticamente."
fi

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
    "Usuario: $GIT_NAME" \
    "Agregado al menú: SÍ"

echo "💡 Tip: Usa 'git feature <nombre>' para empezar."
