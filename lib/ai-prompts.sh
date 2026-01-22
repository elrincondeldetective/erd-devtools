#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ai-prompts.sh

# ==============================================================================
# GENERADOR DE PROMPTS PARA IA (GIT-GP)
# ==============================================================================

generate_gp_prompt() {
    local branch="$1"
    local issue="$2"
    local changes="$3"
    
    # Usamos cat <<EOF para imprimir el bloque de texto limpio
    cat <<EOF

Actúa como un Senior DevOps Engineer experto en Conventional Commits 1.0.0.
Tu tarea es generar un comando de commit listo para ejecutar en mi terminal Linux.

INFORMACIÓN DEL CAMBIO:
- Rama actual: $branch
- Ticket/Issue ID: ${issue:-"No detectado"}

INSTRUCCIONES ESTRICTAS DE FORMATO (CRÍTICO):
1. Usa el formato 'git acp' (mi alias para add+commit+push).
2. ENCIERRA TODO EL MENSAJE EN COMILLAS SIMPLES (' '). 
    - Correcto: git acp 'feat: mensaje'
    - Incorrecto: git acp "feat: mensaje"
    (Esto es vital para evitar que mi terminal expanda variables como \$var).
3. Usa BACKTICKS (\`) dentro del mensaje para:
    - Nombres de archivos.
    - Variables de código.
    - Referencias técnicas.
4. Si referencias un commit anterior, usa SOLO los primeros 7 caracteres del SHA (ej: a96e203).

ESTRUCTURA DEL MENSAJE (Dentro de las comillas simples):
tipo(ámbito): descripción imperativa corta en español

[Cuerpo opcional: Contexto técnico detallado. Separa párrafos con doble salto de línea]

[Footer: Refs #$issue (si existe) o BREAKING CHANGE]

SALIDA REQUERIDA:
Dame UNICAMENTE el bloque de código del comando final. No escribas nada más antes ni después.

CÓDIGO A ANALIZAR:
==================================================
$changes
==================================================
EOF
}