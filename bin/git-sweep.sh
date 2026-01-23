#!/usr/bin/env bash
# /webapps/erd-ecosystem/.devtools/bin/git-sweep.sh
set -euo pipefail

REMOTE="origin"
APPLY=0
FORCE=0
CLEAN_TAGS=1

KEEP_BRANCHES=("main" "dev" "staging" "feature/dev-update")

usage() {
  cat <<EOF
Uso:
  git-sweep.sh [--apply] [--force] [--no-tags] [--remote <name>]

Qué hace:
  - Borra TODAS las ramas locales excepto: ${KEEP_BRANCHES[*]}
  - Borra TODAS las ramas remotas en <remote> excepto: ${KEEP_BRANCHES[*]}
  - (Por defecto) Borra tags que NO estén contenidos en esas ramas

Flags:
  --apply     Ejecuta (sin esto, solo muestra lo que haría)
  --force     Fuerza borrado de ramas locales no mergeadas (usa -D)
  --no-tags   No toca tags
  --remote    Remote a usar (default: origin)
EOF
}

is_keep_branch() {
  local b="$1"
  for k in "${KEEP_BRANCHES[@]}"; do
    [[ "$b" == "$k" ]] && return 0
  done
  return 1
}

say() { echo "• $*"; }

while (( $# )); do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --no-tags) CLEAN_TAGS=0; shift ;;
    --remote) REMOTE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1"; usage; exit 2 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "No estás en un repo git."; exit 1; }

say "Remote: $REMOTE"
say "Keep branches: ${KEEP_BRANCHES[*]}"
say "Mode: $([[ "$APPLY" == "1" ]] && echo APPLY || echo DRY-RUN)"
say "Tags cleanup: $([[ "$CLEAN_TAGS" == "1" ]] && echo ON || echo OFF)"
echo

# 0) Sync/prune
if [[ "$APPLY" == "1" ]]; then
  git fetch "$REMOTE" --prune --tags >/dev/null 2>&1 || true
else
  say "[DRY] git fetch $REMOTE --prune --tags"
fi

# 1) Evitar estar parado en una rama que vamos a borrar
current="$(git branch --show-current 2>/dev/null || echo "")"
if [[ -n "$current" ]] && ! is_keep_branch "$current"; then
  target=""

  if git show-ref --verify --quiet refs/heads/main; then target="main"; fi
  if [[ -z "$target" ]] && git show-ref --verify --quiet refs/heads/dev; then target="dev"; fi

  # Si no existen localmente, intentamos crearlas desde el remoto
  if [[ -z "$target" ]] && git show-ref --verify --quiet "refs/remotes/$REMOTE/main"; then
    target="main"
    if [[ "$APPLY" == "1" ]]; then git checkout -B main "$REMOTE/main" >/dev/null 2>&1; else say "[DRY] git checkout -B main $REMOTE/main"; fi
  fi
  if [[ -z "$target" ]] && git show-ref --verify --quiet "refs/remotes/$REMOTE/dev"; then
    target="dev"
    if [[ "$APPLY" == "1" ]]; then git checkout -B dev "$REMOTE/dev" >/dev/null 2>&1; else say "[DRY] git checkout -B dev $REMOTE/dev"; fi
  fi

  if [[ -n "$target" ]] && [[ "$APPLY" == "1" ]]; then
    git checkout "$target" >/dev/null 2>&1 || true
  elif [[ -n "$target" ]]; then
    say "[DRY] git checkout $target"
  else
    echo "No encontré main/dev para hacer checkout antes de borrar. Abortando."
    exit 1
  fi
fi

# 2) Borrar ramas locales (excepto keep)
mapfile -t local_branches < <(git for-each-ref refs/heads --format='%(refname:short)')
for b in "${local_branches[@]}"; do
  is_keep_branch "$b" && continue

  if [[ "$APPLY" == "1" ]]; then
    if [[ "$FORCE" == "1" ]]; then
      git branch -D "$b" >/dev/null 2>&1 || true
      say "Deleted local branch (forced): $b"
    else
      git branch -d "$b" >/dev/null 2>&1 || true
      say "Deleted local branch: $b"
    fi
  else
    say "[DRY] delete local branch: $b"
  fi
done

# 3) Borrar ramas remotas (excepto keep) - robusto (solo heads reales)
mapfile -t remote_branches < <(git ls-remote --heads "$REMOTE" | awk '{print $2}' | sed 's#refs/heads/##')
for b in "${remote_branches[@]}"; do
  is_keep_branch "$b" && continue

  if [[ "$APPLY" == "1" ]]; then
    git push "$REMOTE" --delete "$b" >/dev/null 2>&1 || true
    say "Deleted remote branch: $REMOTE/$b"
  else
    say "[DRY] delete remote branch: $REMOTE/$b"
  fi
done

# 4) Borrar tags que NO están contenidos en ramas keep (opcional)
if [[ "$CLEAN_TAGS" == "1" ]]; then
  keep_refs=()
  for b in "${KEEP_BRANCHES[@]}"; do
    if git show-ref --verify --quiet "refs/remotes/$REMOTE/$b"; then
      keep_refs+=("refs/remotes/$REMOTE/$b")
    elif git show-ref --verify --quiet "refs/heads/$b"; then
      keep_refs+=("refs/heads/$b")
    fi
  done

  mapfile -t tags < <(git tag -l)
  for t in "${tags[@]}"; do
    sha="$(git rev-list -n1 "$t" 2>/dev/null || echo "")"
    [[ -z "$sha" ]] && continue

    keep=0
    for ref in "${keep_refs[@]}"; do
      if git merge-base --is-ancestor "$sha" "$ref" >/dev/null 2>&1; then
        keep=1
        break
      fi
    done

    [[ "$keep" == "1" ]] && continue

    if [[ "$APPLY" == "1" ]]; then
      git tag -d "$t" >/dev/null 2>&1 || true
      git push "$REMOTE" ":refs/tags/$t" >/dev/null 2>&1 || true
      say "Deleted tag (not in keep branches): $t"
    else
      say "[DRY] delete tag (not in keep branches): $t"
    fi
  done
fi

echo
say "Done."
