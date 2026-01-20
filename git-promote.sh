#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/git-promote.sh
set -euo pipefail

# --- CONFIGURACIÓN ---
# Archivo donde release-please guarda la verdad
VERSION_FILE="apps/pmbok/.github/utils/.release-please-manifest.json"
# Servicio principal para versionar el repo (usualmente backend)
MAIN_SERVICE="backend"

# Colores
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

CURRENT_BRANCH=$(git branch --show-current)
TARGET_ENV="${1:-}"

# --- HELPERS ---

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        # Extrae la versión del backend (ej: 0.6.1) usando grep/sed para no depender de jq si no quieres
        grep "\"$MAIN_SERVICE\":" "$VERSION_FILE" | sed -E 's/.*: "(.*)".*/\1/'
    else
        echo "0.0.0"
    fi
}

generate_ai_prompt() {
    local from_branch=$1
    local to_branch=$2
    local diff_stat
    local commit_log
    
    echo -e "${BLUE}🤖 Generando prompt para Release Notes...${NC}"
    
    diff_stat=$(git diff --stat "$to_branch..$from_branch")
    commit_log=$(git log --pretty=format:"- %s (%an)" "$to_branch..$from_branch")
    
    cat <<EOF
--------------------------------------------------------------------------------
COPIA ESTE PROMPT PARA TU IA:
--------------------------------------------------------------------------------
Actúa como un Release Manager experto.
Genera unas Release Notes profesionales en Markdown para la versión que estamos desplegando.

Contexto:
- Origen: $from_branch
- Destino: $to_branch

Cambios (Commits):
$commit_log

Archivos afectados:
$diff_stat

Instrucciones:
1. Agrupa los cambios por tipo (Features, Fixes, Chore).
2. Destaca lo más importante para el usuario final.
3. Usa un tono técnico pero claro.
--------------------------------------------------------------------------------
EOF
    echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
    read -r -p "Presiona ENTER cuando hayas copiado el prompt para continuar..."
}

# --- SOLUCIONES AGREGADAS: VALIDACIÓN DE TAGS + CAPTURA SEGURA DE RELEASE NOTES + SUBMODULE SYNC ---

valid_tag() {
    local t="$1"
    # check-ref-format es la forma “oficial” de validar un tag; evita espacios y caracteres inválidos
    git check-ref-format --allow-onelevel "refs/tags/$t" >/dev/null 2>&1
}

capture_release_notes() {
    local outfile="$1"

    # Si tienes gum (devbox lo trae), esto es lo más cómodo para pegar sin romper nada
    if command -v gum >/dev/null 2>&1; then
        gum write \
            --width 120 \
            --height 25 \
            --placeholder "Pega aquí las Release Notes (Markdown). Guarda y cierra para continuar..." \
            > "$outfile"
        return 0
    fi

    # Fallback: editor
    if [[ -n "${EDITOR:-}" ]]; then
        "${EDITOR}" "$outfile"
        return 0
    fi

    # Fallback final: pegar hasta Ctrl-D (EOF)
    echo "Pega las Release Notes (Markdown). Termina con Ctrl-D:"
    cat > "$outfile"
}

sync_submodules_if_any() {
    # Si hay submódulos, los sincronizamos para evitar el clásico "M apps/pmbok" por puntero desfasado
    if [[ -f ".gitmodules" ]]; then
        git submodule update --init --recursive >/dev/null 2>&1 || true
    fi
}

ensure_clean_git() {
    # Solución: intenta sincronizar submódulos antes de validar limpio
    sync_submodules_if_any

    if [[ -n $(git status --porcelain) ]]; then
        echo -e "${RED}❌ Tienes cambios sin guardar. Haz commit o stash primero.${NC}"
        echo -e "${YELLOW}💡 Tip: si ves 'M apps/pmbok', suele ser un puntero de submódulo desfasado.${NC}"
        echo -e "${YELLOW}   Prueba: git submodule update --init --recursive${NC}"
        exit 1
    fi
}

# --- SOLUCIÓN AGREGADA: RC1/RC2... EN VEZ DE TIMESTAMP (y evita "orden no encontrada") ---

next_rc_number() {
    local base_ver="$1"
    local pattern="v${base_ver}-rc"
    local max=0

    # Asegura que vemos tags del remoto también
    git fetch origin --tags --force >/dev/null 2>&1 || true

    # lista tags existentes tipo v0.6.1-rc1, v0.6.1-rc2...
    while read -r t; do
        [[ -z "$t" ]] && continue
        local n="${t#${pattern}}"
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        (( n > max )) && max="$n"
    done < <(git tag -l "${pattern}[0-9]*")

    echo $((max + 1))
}

# --- SOLUCIÓN AGREGADA: ENCABEZADO FORZADO EN RELEASE NOTES (evita confusión de versión) ---

prepend_release_notes_header() {
    local outfile="$1"
    local header="$2"
    # Fuerza un encabezado consistente (evita que la IA se confunda con el número de versión)
    {
        echo "$header"
        echo ""
        cat "$outfile"
    } > "${outfile}.final"
    mv "${outfile}.final" "$outfile"
}

# --- NIVELES DE PROMOCIÓN ---

# 1. Feature -> DEV (La "Aplastadora")
promote_to_dev() {
    CURRENT_BRANCH=$(git branch --show-current)

    echo -e "${YELLOW}🚧 PROMOCIÓN A DEV (Destructiva)${NC}"
    read -r -p "¿Estás seguro de aplastar 'dev' con '$CURRENT_BRANCH'? [si/N]: " confirm
    [[ "$confirm" != "si" ]] && exit 0

    ensure_clean_git
    git fetch origin dev
    git checkout dev

    # Solución: sincroniza submódulos tras cambiar rama, para evitar quedar "sucio" por punteros
    sync_submodules_if_any

    # Reset duro para que dev sea idéntico a feature
    git reset --hard "$CURRENT_BRANCH"

    echo -e "${BLUE}☁️  Forzando push a dev...${NC}"
    git push origin dev --force

    echo -e "${GREEN}✅ Dev actualizado. El CI detectará cambios y desplegará.${NC}"

    # Opcional: Borrar feature
    read -r -p "¿Borrar rama '$CURRENT_BRANCH'? [S/n]: " del
    if [[ ! "$del" =~ ^[Nn]$ ]]; then
        git branch -D "$CURRENT_BRANCH"
        git push origin --delete "$CURRENT_BRANCH" 2>/dev/null || true
    fi
}

# 2. Dev -> STAGING (Release Candidate)
promote_to_staging() {
    CURRENT_BRANCH=$(git branch --show-current)

    [[ "$CURRENT_BRANCH" != "dev" ]] && { echo -e "${RED}❌ Ve a 'dev' primero.${NC}"; exit 1; }

    # Solución: valida limpio desde el inicio (incluye sync de submódulos)
    ensure_clean_git

    echo -e "${YELLOW}🔍 Comparando Dev -> Staging${NC}"
    git fetch origin staging

    # Mostrar cambios pendientes
    git log --oneline origin/staging..HEAD
    echo ""

    # Generar Prompt IA
    generate_ai_prompt "dev" "origin/staging"

    # Solución: Capturar Release Notes de forma segura (sin pegar en consola y sin que zsh ejecute el texto)
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT

    echo -e "${BLUE}📝 Ahora pega tus Release Notes de forma segura (Markdown).${NC}"
    capture_release_notes "$tmp_notes"

    if [[ ! -s "$tmp_notes" ]]; then
        echo -e "${RED}❌ No se recibieron Release Notes (archivo vacío). Cancelando.${NC}"
        exit 1
    fi

    # Calcular versión RC
    BASE_VER=$(get_current_version)
    RC_NUM=$(next_rc_number "$BASE_VER")
    RC_TAG="v${BASE_VER}-rc${RC_NUM}"

    echo -e "La versión base actual es: ${BLUE}$BASE_VER${NC}"

    # Solución: validar nombre de tag (evita espacios / caracteres inválidos)
    while true; do
        read -r -p "¿Nombre del tag RC? (Enter para '$RC_TAG'): " user_tag
        RC_TAG="${user_tag:-$RC_TAG}"

        if valid_tag "$RC_TAG"; then
            break
        fi

        echo -e "${RED}❌ Tag inválido: '$RC_TAG'${NC}"
        echo "Reglas rápidas: sin espacios, evita caracteres raros; usa algo como: v0.6.1-rc1"
    done

    # Solución: forzar encabezado consistente en las Release Notes (evita que la IA ponga otra versión)
    prepend_release_notes_header "$tmp_notes" "Release Notes - ${RC_TAG} (Staging)"

    echo -e "${YELLOW}🚀 Desplegando a STAGING con tag: $RC_TAG${NC}"
    read -r -p "Confirmar? [si/N]: " confirm
    [[ "$confirm" != "si" ]] && exit 0

    # Antes de mover ramas, aseguramos limpio (incluye submodule sync)
    ensure_clean_git

    git checkout staging
    git pull origin staging

    # Solución: sincroniza submódulos tras cambiar rama, para evitar quedar "sucio" por punteros
    sync_submodules_if_any

    git merge --ff-only dev

    # Solución: guardar Release Notes en el tag (multilínea) sin explotar la terminal
    git tag -a "$RC_TAG" -F "$tmp_notes"
    git push origin staging
    git push origin "$RC_TAG"

    echo -e "${GREEN}✅ Staging actualizado y taggeado ($RC_TAG).${NC}"
    git checkout dev

    # Solución: sincroniza submódulos tras volver a dev
    sync_submodules_if_any
}

# 3. Staging -> PROD (Release Oficial)
promote_to_prod() {
    CURRENT_BRANCH=$(git branch --show-current)

    [[ "$CURRENT_BRANCH" != "staging" ]] && { echo -e "${RED}❌ Ve a 'staging' primero.${NC}"; exit 1; }

    # Solución: valida limpio desde el inicio (incluye sync de submódulos)
    ensure_clean_git

    echo -e "${YELLOW}🚀 PROMOCIÓN A PRODUCCIÓN${NC}"
    git fetch origin main

    generate_ai_prompt "staging" "origin/main"

    # Solución: Capturar Release Notes de forma segura también para el release final
    tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
    trap 'rm -f "$tmp_notes"' EXIT

    echo -e "${BLUE}📝 Ahora pega tus Release Notes de forma segura (Markdown) para Producción.${NC}"
    capture_release_notes "$tmp_notes"

    if [[ ! -s "$tmp_notes" ]]; then
        echo -e "${RED}❌ No se recibieron Release Notes (archivo vacío). Cancelando.${NC}"
        exit 1
    fi

    BASE_VER=$(get_current_version)
    RELEASE_TAG="v${BASE_VER}"

    echo -e "Versión detectada (Release Please): ${BLUE}$BASE_VER${NC}"
    echo -e "Se creará el tag: ${BLUE}$RELEASE_TAG${NC} en main."

    # Solución: validar nombre de tag (aunque aquí viene “limpio”, esto protege cambios futuros)
    if ! valid_tag "$RELEASE_TAG"; then
        echo -e "${RED}❌ Tag inválido calculado: '$RELEASE_TAG'${NC}"
        exit 1
    fi

    # Solución: forzar encabezado consistente en las Release Notes (evita que la IA ponga otra versión)
    prepend_release_notes_header "$tmp_notes" "Release Notes - ${RELEASE_TAG} (Producción)"

    read -r -p "¿Confirmar pase a Producción? [si/N]: " confirm
    [[ "$confirm" != "si" ]] && exit 0

    # Antes de mover ramas, aseguramos limpio (incluye submodule sync)
    ensure_clean_git

    git checkout main
    git pull origin main

    # Solución: sincroniza submódulos tras cambiar rama, para evitar quedar "sucio" por punteros
    sync_submodules_if_any

    git merge --ff-only staging

    # Tag SemVer Oficial
    if git rev-parse "$RELEASE_TAG" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ El tag $RELEASE_TAG ya existe. ¿Es un re-deploy o hotfix sin cambio de versión?${NC}"
    else
        # Solución: guardar Release Notes reales en el tag (multilínea)
        git tag -a "$RELEASE_TAG" -F "$tmp_notes"
        git push origin "$RELEASE_TAG"
    fi

    git push origin main
    echo -e "${GREEN}✅ Producción actualizada ($RELEASE_TAG).${NC}"
    git checkout staging

    # Solución: sincroniza submódulos tras volver a staging
    sync_submodules_if_any
}

# 4. Hotfix Flow
create_hotfix() {
    CURRENT_BRANCH=$(git branch --show-current)

    echo -e "${RED}🔥 HOTFIX MODE${NC}"
    read -r -p "Nombre del hotfix (ej: login-bug): " hf_name
    HF_BRANCH="hotfix/$hf_name"

    # Solución: valida limpio antes de cambiar ramas
    ensure_clean_git

    git checkout main
    git pull origin main

    # Solución: sincroniza submódulos tras cambiar rama
    sync_submodules_if_any

    git checkout -b "$HF_BRANCH"

    echo -e "${GREEN}✅ Estás en '$HF_BRANCH'. Haz tus cambios y commit.${NC}"
    echo "Cuando termines, ejecuta: git promote hotfix-finish"
}

finish_hotfix() {
    CURRENT_BRANCH=$(git branch --show-current)

    [[ "$CURRENT_BRANCH" != hotfix/* ]] && { echo -e "${RED}❌ No estás en una rama hotfix/.*${NC}"; exit 1; }

    # Solución: valida limpio antes de finalizar hotfix
    ensure_clean_git

    echo -e "${YELLOW}🩹 Finalizando Hotfix...${NC}"
    # 1. Merge a Main
    git checkout main
    git pull origin main

    # Solución: sincroniza submódulos tras cambiar rama
    sync_submodules_if_any

    git merge --no-ff "$CURRENT_BRANCH" -m "Merge hotfix: $CURRENT_BRANCH"
    git push origin main

    # 2. Merge a Dev (Para no perder el fix)
    git checkout dev
    git pull origin dev

    # Solución: sincroniza submódulos tras cambiar rama
    sync_submodules_if_any

    git merge --no-ff "$CURRENT_BRANCH" -m "Merge hotfix: $CURRENT_BRANCH"
    git push origin dev

    # 3. Taggear (Opcional, pide versión manual porque release-please puede no haber corrido)
    BASE_VER=$(get_current_version)
    echo -e "Versión base era: $BASE_VER. Sugerencia: Incrementa el PATCH."
    read -r -p "Nuevo Tag (ej: v0.6.2): " NEW_TAG

    if [[ -n "$NEW_TAG" ]]; then
        # Solución: validar nombre de tag antes de crear
        if ! valid_tag "$NEW_TAG"; then
            echo -e "${RED}❌ Tag inválido: '$NEW_TAG'${NC}"
            echo "Reglas rápidas: sin espacios, evita caracteres raros; usa algo como: v0.6.2"
            exit 1
        fi

        git checkout main
        # Solución: sincroniza submódulos tras cambiar rama
        sync_submodules_if_any

        # Solución: capturar release notes seguras para hotfix también (opcional, pero previene “explosión”)
        tmp_notes="$(mktemp -t release-notes.XXXXXX.md)"
        trap 'rm -f "$tmp_notes"' EXIT
        echo -e "${BLUE}📝 (Opcional) Pega Release Notes del Hotfix (Markdown). Guarda y cierra.${NC}"
        capture_release_notes "$tmp_notes"

        if [[ -s "$tmp_notes" ]]; then
            git tag -a "$NEW_TAG" -F "$tmp_notes"
        else
            git tag -a "$NEW_TAG" -m "Hotfix Release $NEW_TAG"
        fi

        git push origin "$NEW_TAG"
    fi

    echo -e "${GREEN}✅ Hotfix integrado en Main y Dev.${NC}"
}

# --- MENU PRINCIPAL ---

case "$TARGET_ENV" in
    dev) promote_to_dev ;;
    staging) promote_to_staging ;;
    prod) promote_to_prod ;;
    hotfix) create_hotfix ;;
    hotfix-finish) finish_hotfix ;;
    *) 
        echo "Uso: git promote [dev | staging | prod | hotfix | hotfix-finish]"
        exit 1
        ;;
esac
# --- FIN DEL SCRIPT ---
