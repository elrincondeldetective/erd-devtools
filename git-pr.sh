#!/usr/bin/env bash
set -euo pipefail
# /webapps/erd-ecosystem/.devtools/git-pr.sh
BASE="${BASE_BRANCH:-dev}"

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "❌ HEAD desacoplado. No puedo abrir PR."
  exit 1
fi

if [[ "$branch" != feature/* ]]; then
  echo "❌ Política ERD: PRs solo desde feature/*"
  echo "   Rama actual: $branch"
  exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "❌ Falta gh CLI"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ gh no autenticado. Ejecuta: gh auth login"; exit 1; }

# Si no hay PR abierto, créalo; si existe, muéstralo
count="$(GH_PAGER=cat gh pr list --state open --head "$branch" --base "$BASE" --json number --jq 'length' 2>/dev/null || echo 0)"
if [[ "$count" == "0" ]]; then
  echo "🚀 Creando PR: $branch -> $BASE"
  GH_PAGER=cat gh pr create --base "$BASE" --head "$branch" --fill
else
  echo "🟢 Ya existe PR abierto para $branch -> $BASE"
  GH_PAGER=cat gh pr list --state open --head "$branch" --base "$BASE"
fi
