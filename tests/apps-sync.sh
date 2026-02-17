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

test_only_limita_a_una_app() {
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
    DEVTOOLS_DRY_RUN=1 "$DEVTOOLS_BIN" apps sync --only pmbok > "$tdir/out_only.log" 2>&1
  )

  if rg -n "pmbok" "$tdir/out_only.log" >/dev/null \
    && ! rg -n "erd" "$tdir/out_only.log" >/dev/null \
    && rg -n "completado \(1 apps\)" "$tdir/out_only.log" >/dev/null; then
    ok "--only limita la sincronización a una app"
  else
    ko "--only no limitó la salida a una app"
  fi
}

test_only_app_inexistente_falla() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mkdir -p "$tdir/.devtools/config"
  mk_git_repo "$tdir"

  cat > "$tdir/.devtools/config/apps.yaml" <<'YAML'
apps:
  - name: pmbok
    repo: git@github.com:elrincondeldetective/pmbok.git
YAML

  set +e
  (
    cd "$tdir"
    DEVTOOLS_DRY_RUN=1 "$DEVTOOLS_BIN" apps sync --only no-existe > "$tdir/out_missing.log" 2>&1
  )
  local rc=$?
  set -e

  if [[ "$rc" -ne 0 ]] \
    && rg -n "no existe" "$tdir/out_missing.log" >/dev/null; then
    ok "--only con app inexistente falla claro"
  else
    ko "--only app inexistente no falló como esperado"
  fi
}

test_parsea_shape_real_monorepo() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mkdir -p "$tdir/.devtools/config"
  mk_git_repo "$tdir"

  cat > "$tdir/.devtools/config/apps.yaml" <<'YAML'
apps:
  - id: pmbok
    path: apps/pmbok
    build_mode: native
  - id: erd
    path: apps/erd/mobile
    build_mode: native
YAML

  (
    cd "$tdir"
    DEVTOOLS_DRY_RUN=1 "$DEVTOOLS_BIN" apps sync --only pmbok > "$tdir/out_shape_real.log" 2>&1
  )

  if rg -n "pmbok" "$tdir/out_shape_real.log" >/dev/null \
    && ! rg -n "erd" "$tdir/out_shape_real.log" >/dev/null \
    && rg -n "git@github.com:elrincondeldetective/pmbok.git" "$tdir/out_shape_real.log" >/dev/null \
    && rg -n "completado \(1 apps\)" "$tdir/out_shape_real.log" >/dev/null; then
    ok "parsea shape real del monorepo (id/path) y resuelve --only"
  else
    ko "no parseó correctamente el shape real del monorepo"
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
    "$DEVTOOLS_BIN" apps sync > "$tdir/out_missing_cfg.log" 2>&1
  )
  local rc=$?
  set -e

  if [[ "$rc" -ne 0 ]] \
    && rg -n "Falta \.devtools/config/apps\.yaml" "$tdir/out_missing_cfg.log" >/dev/null; then
    ok "falla claro cuando falta config"
  else
    ko "missing config no devolvió error esperado"
  fi
}

test_dry_run_no_git_side_effects
test_only_limita_a_una_app
test_only_app_inexistente_falla
test_parsea_shape_real_monorepo
test_missing_config_fails

echo "---"
echo "RESULTADO: pass=${pass} fail=${fail}"
[[ "$fail" -eq 0 ]]
