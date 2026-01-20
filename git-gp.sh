#!/usr/bin/env bash
# /webapps/erd-ecosystem/devops/scripts/git-gp.sh
set -euo pipefail

# 1. Obtener contexto de Git
BRANCH_NAME=$(git branch --show-current)
CHANGES=$(git diff --word-diff)

# 2. INTELIGENCIA: Leer archivos NUEVOS (que git diff no ve)
UNTRACKED_FILES=$(git ls-files --others --exclude-standard)

if [ -n "$UNTRACKED_FILES" ]; then
    CHANGES+=$'\n\n==================================================\n'
    CHANGES+=$'⚠️  ARCHIVOS NUEVOS (AÚN NO RASTREADOS):\n'
    CHANGES+=$'==================================================\n'
    
    # Iteramos sobre cada archivo nuevo
    # shellcheck disable=SC2068
    for file in $UNTRACKED_FILES; do
        # Solo leemos si es texto (evitamos imágenes o binarios)
        if grep -qI . "$file" 2>/dev/null; then
            CHANGES+=$"\n--- CONTENIDO DE: $file ---\n"
            CHANGES+=$(cat "$file")
            CHANGES+=$"\n----------------------------------\n"
        else
            CHANGES+=$"\n--- ARCHIVO BINARIO: $file ---\n"
        fi
    done
fi

# 3. Detectar número de Ticket/Issue automáticamente (Silencioso)
# Busca números en la rama (ej: feature/45-login -> detecta 45)
DETECTED_ISSUE=$(echo "$BRANCH_NAME" | grep -oE '[0-9]+' | head -n1 || echo "")

# 4. Mensajes para ti (En Español)
echo "🤖 La IA está analizando tus cambios y archivos nuevos..."

if [ -n "$DETECTED_ISSUE" ]; then
    echo "ℹ️  Detecté el Ticket #$DETECTED_ISSUE en el nombre de tu rama."
fi

# 5. El Prompt para la IA (Instrucción en Español)
cat <<EOF

Actúa como un experto en DevOps y Conventional Commits.
Tu objetivo es ayudarme a guardar mi trabajo con un mensaje claro y profesional EN ESPAÑOL.

Analiza el código que te paso abajo (diferencias y archivos nuevos).

CONTEXTO:
- Rama actual: $BRANCH_NAME
- Ticket/Issue ID: ${DETECTED_ISSUE:-"Ninguno"}

TU TAREA:
1. Entiende qué hice en el código.
2. Detecta automáticamente si hay cambios peligrosos (BREAKING CHANGES) que rompan compatibilidad.
3. Si hay un ID de Ticket, agrégalo al final como "Refs: #Numero".
4. Escribe el mensaje del commit TOTALMENTE EN ESPAÑOL.

FORMATO DEL MENSAJE:
tipo(ámbito): descripción corta y clara en español

[Cuerpo opcional: explica brevemente el porqué de los cambios, solo si es necesario]

[Footer opcional: BREAKING CHANGE o Refs]

SALIDA REQUERIDA:
Dame SOLAMENTE el comando final para copiar y pegar en mi terminal.
Usa mi alias 'git acp'. Ejemplo:

git acp "feat(usuario): agrega validación en el formulario de registro"

CÓDIGO A ANALIZAR:
==================================================
$CHANGES
==================================================
EOF