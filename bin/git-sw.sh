#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-sw.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/git-sweep.sh" "$@"
