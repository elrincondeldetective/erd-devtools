#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVTOOLS_BIN="${ROOT_DIR}/bin/devtools"

pass=0
fail=0

ok() {
  echo "✅ $1"
  pass=$((pass + 1))
}

ko() {
  echo "❌ $1" >&2
  fail=$((fail + 1))
}

mk_git_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.name "Test Bot"
  git -C "$dir" config user.email "test@example.com"
}

test_dry_run_no_git_side_effects() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mkdir -p "$tdir/.devtools/config" "$tdir/mockbin"
  mk_git_repo "$tdir"

  cat > "$tdir/.devtools/config/apps.yaml" <<'YAML'
apps:
  - name: pmbok
    repo: git@github.com:elrincondeldetective/pmbok.git
YAML

  cat > "$tdir/mockbin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--show-toplevel" ]]; then
  /usr/bin/git "$@"
  exit $?
fi
echo "UNEXPECTED_GIT:$*" >> "${MOCK_GIT_LOG:?}"
exit 99
EOF
  chmod +x "$tdir/mockbin/git"

  export MOCK_GIT_LOG="$tdir/unexpected_git_calls.log"
  : > "$MOCK_GIT_LOG"

  set +e
  (
    cd "$tdir"
    DEVTOOLS_DRY_RUN=1 PATH="$tdir/mockbin:$PATH" "$DEVTOOLS_BIN" apps sync > "$tdir/out.log" 2>&1
  )
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]] \
    && [[ ! -s "$MOCK_GIT_LOG" ]] \
    && rg -n "DRY-RUN" "$tdir/out.log" >/dev/null; then
    ok "DRY_RUN no ejecuta git clone/fetch/pull"
  else
    ko "DRY_RUN ejecutó git no esperado o falló"
  fi
}

test_missing_config_fails() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mk_git_repo "$tdir"

  set +e
  (
    cd "$tdir"
    "$DEVTOOLS_BIN" apps sync > "$tdir/out_missing.log" 2>&1
  )
  local rc=$?
  set -e

  if [[ "$rc" -ne 0 ]] \
    && rg -n "Falta \.devtools/config/apps\.yaml" "$tdir/out_missing.log" >/dev/null; then
    ok "falla claro cuando falta config"
  else
    ko "missing config no devolvió error esperado"
  fi
}

test_parse_basico_dry_run() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mkdir -p "$tdir/.devtools/config"
  mk_git_repo "$tdir"

  cat > "$tdir/.devtools/config/apps.yaml" <<'YAML'
apps:
  - name: pmbok
    repo: git@github.com:elrincondeldetective/pmbok.git
  - name: erd
    repo: git@github.com:elrincondeldetective/erd.git
YAML

  (
    cd "$tdir"
    DEVTOOLS_DRY_RUN=1 "$DEVTOOLS_BIN" apps sync > "$tdir/out_parse.log" 2>&1
  )

  local clones
  clones="$(rg -n "DRY-RUN: clone" "$tdir/out_parse.log" | wc -l | tr -d ' ')"

  if [[ "$clones" == "2" ]] \
    && rg -n "pmbok" "$tdir/out_parse.log" >/dev/null \
    && rg -n "erd" "$tdir/out_parse.log" >/dev/null; then
    ok "parse básico reconoce 2 apps y reporta acciones"
  else
    ko "parse básico no detectó apps esperadas"
  fi
}

test_dry_run_no_git_side_effects
test_missing_config_fails
test_parse_basico_dry_run

echo "---"
echo "RESULTADO: pass=${pass} fail=${fail}"
[[ "$fail" -eq 0 ]]
