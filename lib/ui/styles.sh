#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/ui/styles.sh

# ==============================================================================
# PALETA DE COLORES (Basado en tu script original)
# ==============================================================================
COLOR_PRIMARY="212"    # Rosa/Magenta (Títulos, Bordes)
COLOR_SUCCESS="76"     # Verde (Éxito)
COLOR_WARN="220"       # Amarillo (Advertencias, Info importante)
COLOR_ERROR="196"      # Rojo (Errores, Alertas críticas)
COLOR_INFO="99"        # Púrpura (Información general, instrucciones)

# ==============================================================================
# 1. ELEMENTOS ESTRUCTURALES (Banners y Headers)
# ==============================================================================

# El banner principal del "Rincón del Detective"
show_detective_banner() {
    clear
    gum style \
        --foreground "$COLOR_PRIMARY" --border-foreground "$COLOR_PRIMARY" --border double \
        --align center --width 50 --margin "1 2" --padding "2 4" \
        "🕵️‍♂️ BIENVENIDO A EL RINCÓN DEL DETECTIVE" \
        "Setup de Entorno PMBOK - Asistente Integral"
    echo ""
    gum style --foreground "$COLOR_INFO" "Vamos a configurar tu identidad y seguridad paso a paso."
    echo ""
}

# Títulos de pasos (Ej: "1. Autenticación con GitHub")
ui_step_header() {
    echo ""
    gum style --foreground "$COLOR_PRIMARY" --bold "$1"
}

# Cajas de Alerta (Ej: "ACCESO DENEGADO" o "TODO LISTO")
# Uso: ui_alert_box "TÍTULO" "Mensaje línea 1" "Mensaje línea 2" ...
ui_alert_box() {
    local title="$1"
    shift
    local color="${1:-$COLOR_PRIMARY}" # Si el primer argumento es un código de color, úsalo, si no, default
    
    # Detección inteligente: si el primer argumento parece un color (número), lo extraemos
    if [[ "$title" =~ ^[0-9]+$ ]]; then
        color="$title"
        title="$1"
        shift
    else
        # Si es un error/alerta crítica (detectado por palabras clave), usamos rojo
        if [[ "$title" == *"DENEGADO"* || "$title" == *"ERROR"* ]]; then
            color="$COLOR_ERROR"
        elif [[ "$title" == *"LISTO"* || "$title" == *"COMPLETADA"* ]]; then
            color="$COLOR_PRIMARY"
        fi
    fi

    gum style \
        --border double --border-foreground "$color" --foreground "$color" \
        --padding "1 2" --align center \
        "$title" "$@"
}

# ==============================================================================
# 2. MENSAJES DE LOGGING (Reemplazan a log_success, log_warn, etc.)
# ==============================================================================

ui_success() { gum style --foreground "$COLOR_SUCCESS" "✅ $1"; }
ui_warn()    { gum style --foreground "$COLOR_WARN"    "⚠️  $1"; }
ui_error()   { gum style --foreground "$COLOR_ERROR"   "❌ $1"; }
ui_info()    { gum style --foreground "$COLOR_INFO"    "ℹ️  $1"; }

# Texto resaltado simple (para instrucciones como URLs)
ui_text_highlight() { gum style --foreground "$COLOR_WARN" "$1"; }

# Link o texto primario (Ej: "👉 https://...")
ui_link() { gum style --foreground "$COLOR_PRIMARY" "$1"; }

# ==============================================================================
# 3. COMPONENTES INTERACTIVOS Y UTILIDADES
# ==============================================================================

# Spinner para procesos largos
# Uso: ui_spinner "Texto de carga..." comando_a_ejecutar
ui_spinner() {
    local title="$1"
    shift
    gum spin --spinner dot --title "$title" -- "$@"
}

# Mostrar bloque de código (para la llave pública)
# Uso: echo "contenido" | ui_code_block
ui_code_block() {
    gum format -t code
}

# Línea divisoria (opcional, para separar secciones visualmente)
ui_separator() {
    gum style --foreground "$COLOR_INFO" "────────────────────────────────────────"
}