#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/wizard/step-04-profile.sh

run_step_profile_registration() {
    ui_step_header "6. Finalización y Registro"

    local rc_file=".devtools/.git-acprc"
    local marker_file=".devtools/.setup_completed"

    # --- FIX (Modelo de Identidades): Asegurar carpeta .devtools ---
    mkdir -p "$(dirname "$rc_file")"
    mkdir -p "$(dirname "$marker_file")"

    # --- FIX (Modelo de Identidades): Sanitización de campos del perfil ---
    # Evita que caracteres como ';' o saltos de línea rompan el schema del Profile Entry.
    sanitize_profile_field() {
        local v="$1"
        v="${v//$'\n'/ }"
        v="${v//$'\r'/ }"
        v="${v//;/,}"
        echo "$v"
    }

    # ==========================================================================
    # 1. PREPARAR ARCHIVO DE CONFIGURACIÓN (.git-acprc)
    # ==========================================================================
    if [ ! -f "$rc_file" ]; then
        ui_info "Creando archivo de configuración inicial..."
        # Incluimos la versión del esquema en el archivo generado
        cat <<EOF > "$rc_file"
# Configuración generada por ERD Devtools Wizard
PROFILE_SCHEMA_VERSION=1
DAY_START="00:00"
REFS_LABEL="Conteo: commit"
DAILY_GOAL=10
PROFILES=()
EOF
    else
        # --- FIX (Modelo de Identidades): Backward-compat / migración suave ---
        # Si el archivo existe pero no tiene PROFILE_SCHEMA_VERSION, lo agregamos sin destruir contenido.
        if ! grep -qE '^[[:space:]]*PROFILE_SCHEMA_VERSION=' "$rc_file"; then
            local tmp_rc_schema="${rc_file}.schema.tmp"
            cp "$rc_file" "$tmp_rc_schema"
            {
                echo "# Auto-agregado por setup-wizard ($(date +%F)): Schema Version"
                echo "PROFILE_SCHEMA_VERSION=1"
                echo ""
                cat "$tmp_rc_schema"
            } > "${tmp_rc_schema}.final"
            mv "${tmp_rc_schema}.final" "$rc_file"
            rm -f "$tmp_rc_schema" 2>/dev/null || true
            ui_info "Se agregó PROFILE_SCHEMA_VERSION=1 a $rc_file (compatibilidad)."
        fi
    fi

    # ==========================================================================
    # 2. CONSTRUIR Y GUARDAR PERFIL
    # ==========================================================================
    local gh_login
    gh_login=$(gh api user -q ".login" 2>/dev/null || echo "unknown")

    # --- FIX (Modelo de Identidades): gh_owner semántica consistente ---
    # Contract V1 usa el último campo como GHOwner
