#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-devtools-update.sh
# Actualiza EXPLÍCITAMENTE el submódulo .devtools a remoto (opt-in).
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Reusar helpers existentes
# (log_* / ui_* / detect_workspace_root)
source "${LIB_DIR}/core/utils.sh"
source "${LIB_DIR}/core/git-ops.sh"

ROOT="$(detect_workspace_root)"
TARGET_PATH=".devtools"

MODE="checkout"   # checkout|merge
INIT_ONLY=0

usage() {
  echo "Uso: git devtools-update [--init-only] [--merge]"
  echo ""
  echo "  --init-only   Solo asegura que exista (sin --remote)."
  echo "  --merge       Usa --merge al actualizar remoto (si aplica)."
}

while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --init-only) INIT_ONLY=1; shift ;;
    --merge) MODE="merge"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1"; usage; exit 2 ;;
  esac
done

ui_header "🔧 devtools update (EXPLÍCITO)"
ui_info "Root: $ROOT"
ui_info "Submódulo: $TARGET_PATH"

# Siempre seguro: sync + init (no mueve commits)
git -C "$ROOT" submodule sync --recursive >/dev/null 2>&1 || true
git -C "$ROOT" submodule update --init --recursive "$TARGET_PATH" >/dev/null 2>&1 || true

if [[ "$INIT_ONLY" == "1" ]]; then
  ui_success "Init-only OK (sin remoto)."
  exit 0
fi

# Opt-in: mover a remoto SOLO aquí
ui_warn "Actualizando a remoto (esto PUEDE cambiar el SHA pineado en el repo padre)."
if [[ "$MODE" == "merge" ]]; then
  git -C "$ROOT" submodule update --remote --merge --recursive "$TARGET_PATH"
else
  git -C "$ROOT" submodule update --remote --recursive "$TARGET_PATH"
fi

ui_success "Update remoto completado."
ui_info "Siguiente paso (en el repo padre): revisa 'git status' y commitea el nuevo SHA del submódulo si corresponde."
