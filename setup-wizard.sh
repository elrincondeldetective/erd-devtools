#!/usr/bin/env bash
# /webapps/erd-ecosystem/devops/scripts/setup-wizard.sh
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
	"Setup de Entorno PMBOK"

echo ""
gum style --foreground 99 "Vamos a configurar tu identidad y seguridad en 3 pasos."
echo ""

# --- PASO 1: Identidad Git ---
gum style --foreground 212 "1. ¿Cuál es tu nombre completo?"
CURRENT_NAME=$(git config --global user.name || echo "")
GIT_NAME=$(gum input --placeholder "Ej: Esteban Lemus" --value "$CURRENT_NAME")

gum style --foreground 212 "2. ¿Cuál es tu email de GitHub?"
CURRENT_EMAIL=$(git config --global user.email || echo "")
GIT_EMAIL=$(gum input --placeholder "elemusc613@ejemplo.com" --value "$CURRENT_EMAIL")

# Configurar Git localmente (solo para este repo si se prefiere, o global)
git config user.name "$GIT_NAME"
git config user.email "$GIT_EMAIL"

# --- PASO 2: Seguridad SSH y Firma ---
gum style --foreground 212 "3. Configurando Seguridad SSH..."
SSH_KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY" ]; then
    gum spin --spinner dot --title "Generando llave SSH..." -- \
        ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N "" -q
    gum style --foreground 76 "✅ Llave generada."
else
    gum style --foreground 76 "✅ Llave SSH existente detectada."
fi

# Configurar firma automática SSH
git config gpg.format ssh
git config user.signingkey "$SSH_KEY.pub"
git config commit.gpgsign true
git config tag.gpgsign true

# --- PASO 3: Vincular con GitHub ---
PUB_KEY=$(cat "$SSH_KEY.pub")

gum style \
	--border normal --margin "1 0" --padding "1 2" --border-foreground 212 \
	"ACCIÓN REQUERIDA EN GITHUB" \
	"Copia esta llave y agrégala en: GitHub -> Settings -> SSH and GPG Keys"

echo "$PUB_KEY" | gum format -t code

# Intentar copiar al portapapeles (Linux/Mac)
if command -v xclip >/dev/null; then echo "$PUB_KEY" | xclip -sel clip; fi
if command -v pbcopy >/dev/null; then echo "$PUB_KEY" | pbcopy; fi

gum confirm "👉 ¿Ya agregaste la llave a GitHub?" || exit 1

# --- PASO 4: Switch a SSH ---
# Cambiamos el remoto a SSH para que pueda hacer push
gum spin --spinner dot --title "Configurando conexión remota..." -- sleep 1
CURRENT_URL=$(git remote get-url origin)

if [[ "$CURRENT_URL" == https://* ]]; then
    # Convertir https://github.com/org/repo a git@github.com:org/repo.git
    NEW_URL=$(echo "$CURRENT_URL" | sed -E 's/https:\/\/github.com\//git@github.com:/')
    git remote set-url origin "$NEW_URL"
    gum style --foreground 76 "🔄 Conexión actualizada a SSH."
fi

# Prueba final de conexión
if ssh -T git@github.com -o StrictHostKeyChecking=accept-new 2>&1 | grep -q "successfully authenticated"; then
    gum style --foreground 76 "✅ Conexión con GitHub EXITOSA."
else
    gum style --foreground 196 "⚠️  No pudimos autenticarte automáticamente. Verifica tu llave en GitHub."
fi

# Marcar como completado
touch "$MARKER_FILE"
gum style --foreground 212 "🎉 ¡Todo listo! Usa 'git feature <nombre>' para empezar."