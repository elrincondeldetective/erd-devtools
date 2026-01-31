#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-sync.sh
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extraer -y/--yes en cualquier posición (para UX)
yes_args=()
rest=()
for a in "$@"; do
  case "$a" in
    -y|--yes) yes_args=(-y) ;;
    *) rest+=("$a") ;;
  esac
done

exec "${SCRIPT_DIR}/git-promote.sh" "${yes_args[@]}" sync "${rest[@]}"
