#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ui/prompts.sh

# Lee un carácter del usuario (o una cadena si no es modo raw)
# Uso: choice=$(ui_read_option "   Opción > ")
ui_read_option() {
    local prompt="${1:-> }"
    local input
    # Forzamos lectura desde /dev/tty para garantizar interactividad incluso dentro de pipes
    read -r -p "$prompt" input < /dev/tty
    echo "$input"
}