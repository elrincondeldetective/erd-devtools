#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/lib/utils.sh

# Colores
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

# Helpers de Log
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; >&2; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Helpers de UI (Gum wrapper)
confirm_action() {
    local msg="$1"
    if command -v gum >/dev/null 2>&1; then
        gum confirm "$msg" || return 1
    else
        read -r -p "$msg [y/N]: " response
        [[ "$response" =~ ^[yY]$ ]] || return 1
    fi
}