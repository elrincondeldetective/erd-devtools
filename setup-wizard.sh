#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/setup-wizard.sh
set -e

# Archivo marcador para saber si ya se ejecutó
MARKER_FILE=".devtools/.setup_completed"
[ -f "$MARKER_FILE" ] && exit 0

# Limpiar pantalla y mostrar bienvenida
clear
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	"🕵️‍♂️ BIENVENIDO A EL RINCÓN DEL DETECTIVE" \
	"Setup de Entorno PMBOK - Automatizado"

echo ""
gum style --foreground 99 "Vamos a configurar tu identidad, seguridad y entorno en 5 pasos."
echo ""

# --- PASO 0: Autenticación GitHub CLI (NUEVO) ---
# Necesario para poder subir la llave automáticamente después
gum style --foreground 212 "1. Verificando conexión con GitHub..."

if ! gh auth status >/dev/null 2>&1; then
    gum style --foreground 220 "⚠️  No has iniciado sesión en GitHub CLI."
    gum style --foreground 99 "Se abrirá el navegador para autorizar este Devbox."
    
    # Login interactivo vía web, forzando protocolo SSH
    if gh auth login --hostname github.com --git-protocol ssh --web; then
        gum style --foreground 76 "✅ Login exitoso."
    else
        gum style --foreground 196 "❌ Falló el login. Revisa tu conexión."
        exit 1
    fi
else
    gum style --foreground 76 "✅ GitHub CLI ya está autenticado."
fi

# --- PASO 1: Identidad Git ---
gum style --foreground 212 "2. Configurando Identidad Local"

# Intentamos obtener datos de GitHub si están disponibles, si no, usamos vacíos
GH_NAME=$(gh api user -q ".name" 2>/dev/null || echo "")
GH_EMAIL=$(gh api user -q ".email" 2>/dev/null || echo "")
CURRENT_NAME=$(git config --global user.name || echo "$GH_NAME")
CURRENT_EMAIL=$(git config --global user.email || echo "$GH_EMAIL")

gum style "Confirma tus datos para los commits:"
GIT_NAME=$(gum input --placeholder "Tu Nombre" --value "$CURRENT_NAME" --header "Nombre")
GIT_EMAIL=$(gum input --placeholder "tu@email.com" --value "$CURRENT_EMAIL" --header "Email")

# Configurar Git localmente
git config user.name "$GIT_NAME"
git config user.email "$GIT_EMAIL"

# --- PASO 2: Seguridad SSH y Firma ---
gum style --foreground 212 "3. Generando Llave SSH..."
SSH_KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY" ]; then
    gum spin --spinner dot --title "Creando par de llaves..." -- \
        ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N "" -q
    gum style --foreground 76 "✅ Llave generada en $SSH_KEY"
else
    gum style --foreground 76 "✅ Llave SSH existente detectada."
fi

# Configurar firma automática SSH en Git
git config gpg.format ssh
git config user.signingkey "$SSH_KEY.pub"
git config commit.gpgsign true
git config tag.gpgsign true

# --- PASO 3: Vincular con GitHub (AUTOMATIZADO) ---
gum style --foreground 212 "4. Subiendo llave a GitHub..."
PUB_KEY_PATH="$SSH_KEY.pub"

# Título único para la llave para evitar colisiones
KEY_TITLE="Devbox-ERD-$(date +%Y%m%d-%H%M)"

if gh ssh-key add "$PUB_KEY_PATH" --title "$KEY_TITLE" --type authentication; then
    gum style --foreground 76 "✅ Llave SSH subida a GitHub exitosamente."
else
    # Si falla, suele ser porque la llave ya existe. Verificamos.
    if gh ssh-key list | grep -q "$(cat "$PUB_KEY_PATH" | cut -d' ' -f2)"; then
         gum style --foreground 76 "✅ La llave ya existía en tu cuenta de GitHub."
    else
         gum style --foreground 220 "⚠️  Hubo un problema subiendo la llave. Revisa 'gh ssh-key list'."
    fi
fi

# --- PASO 4: Switch a SSH y Validación ---
gum spin --spinner dot --title "Verificando conexión remota..." -- sleep 1
CURRENT_URL=$(git remote get-url origin)

if [[ "$CURRENT_URL" == https://* ]]; then
    NEW_URL=$(echo "$CURRENT_URL" | sed -E 's/https:\/\/github.com\//git@github.com:/')
    git remote set-url origin "$NEW_URL"
    gum style --foreground 76 "🔄 Origen actualizado a SSH."
fi

# Prueba final de conexión
if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
    gum style --foreground 76 "✅ Conexión verificada: Tienes acceso Write."
else
    gum style --foreground 196 "⚠️  Advertencia: No pudimos verificar la conexión SSH final."
fi

# --- PASO 5: Workspace Bootstrap (NUEVO) ---
gum style --foreground 212 "5. Inicializando Entorno (.env)"

if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        gum style --foreground 76 "✅ Archivo .env creado desde .env.example"
    else
        touch .env
        gum style --foreground 220 "⚠️  No se encontró .env.example, se creó un .env vacío."
    fi
else
    gum style --foreground 76 "✅ El archivo .env ya existe."
fi

# Marcar como completado
touch "$MARKER_FILE"

gum style \
    --border double --margin "1 2" --padding "1 4" --border-foreground 212 --foreground 212 \
    "🎉 ¡SETUP COMPLETADO!" \
    "Tu entorno está seguro, firmado y conectado."

echo "💡 Tip: Usa 'git feature <nombre>' para empezar a trabajar."