#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVTOOLS_BIN="${ROOT_DIR}/devtools"

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

test_profile_basic_and_full() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mkdir -p "$tdir/devops/k8s" "$tdir/bin"
  mk_git_repo "$tdir"
  : > "$tdir/devops/k8s/bootstrap-local-basic.yaml"
  : > "$tdir/devops/k8s/bootstrap-local.yaml"

  cat > "$tdir/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${MOCK_KUBECTL_LOG:?}"
EOF
  chmod +x "$tdir/bin/kubectl"

  export MOCK_KUBECTL_LOG="$tdir/kubectl.log"
  : > "$MOCK_KUBECTL_LOG"

  (
    cd "$tdir"
    PATH="$tdir/bin:$PATH" "$DEVTOOLS_BIN" local up --profile basic >"$tdir/out-basic.log"
    PATH="$tdir/bin:$PATH" "$DEVTOOLS_BIN" local up --profile full >"$tdir/out-full.log"
  )

  if rg -n "bootstrap-local-basic\.yaml" "$tdir/out-basic.log" >/dev/null \
    && rg -n "bootstrap-local\.yaml" "$tdir/out-full.log" >/dev/null \
    && rg -n "apply -f .*bootstrap-local-basic\.yaml" "$MOCK_KUBECTL_LOG" >/dev/null \
    && rg -n "apply -f .*bootstrap-local\.yaml" "$MOCK_KUBECTL_LOG" >/dev/null; then
    ok "--profile basic/full resuelve bootstrap correcto"
  else
    ko "--profile basic/full no resolvió bootstrap como se esperaba"
  fi
}

test_dry_run_no_kubectl() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mkdir -p "$tdir/devops/k8s" "$tdir/bin"
  mk_git_repo "$tdir"
  : > "$tdir/devops/k8s/bootstrap-local-basic.yaml"

  cat > "$tdir/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "KUBECTL_NO_DEBERIA_EJECUTARSE" >&2
exit 99
EOF
  chmod +x "$tdir/bin/kubectl"

  (
    cd "$tdir"
    DEVTOOLS_DRY_RUN=1 PATH="$tdir/bin:$PATH" "$DEVTOOLS_BIN" local up --profile basic >"$tdir/out-dry.log"
  )

  if rg -n "DEVTOOLS_DRY_RUN=1" "$tdir/out-dry.log" >/dev/null \
    && rg -n "bootstrap-local-basic\.yaml" "$tdir/out-dry.log" >/dev/null; then
    ok "DEVTOOLS_DRY_RUN=1 evita kubectl apply"
  else
    ko "DEVTOOLS_DRY_RUN=1 no reportó comportamiento esperado"
  fi
}

test_missing_bootstrap_fails() {
  local tdir
  tdir="$(mktemp -d)"
  trap 'rm -rf "$tdir"' RETURN

  mkdir -p "$tdir" "$tdir/bin"
  mk_git_repo "$tdir"

  set +e
  (
    cd "$tdir"
    PATH="$tdir/bin:$PATH" "$DEVTOOLS_BIN" local up --profile basic >"$tdir/out-missing.log" 2>&1
  )
  local rc=$?
  set -e

  if [[ "$rc" -ne 0 ]] && rg -n "Pendiente soportar app-repos" "$tdir/out-missing.log" >/dev/null; then
    ok "falla con error claro cuando no existe bootstrap"
  else
    ko "no falló como se esperaba en repo sin bootstrap"
  fi
}

test_profile_basic_and_full
test_dry_run_no_kubectl
test_missing_bootstrap_fails

echo "---"
echo "RESULTADO: pass=${pass} fail=${fail}"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
