# erd-devtools

Toolkit de productividad para Git y flujos de promoción (DEV → STAGING → PROD) dentro del ecosistema.

## `git promote` — Promoción segura de ramas

### Targets
- `git promote dev` → actualiza `origin/dev` con tu código (SHA capturado al invocar).
- `git promote staging` → promueve lo que está en `dev` hacia `origin/staging`.
- `git promote prod` → promueve lo que está en `staging` hacia `origin/main`.
- `git promote dev-update [rama]` → integra una rama hacia `origin/dev-update` usando la estrategia elegida.
- `git promote sync` → macro: `dev-update -> dev -> staging -> prod` (requiere estar en `dev-update`).
- `git promote hotfix <name>` → crea `hotfix/<name>` desde `main`.
- `git promote hotfix` (estando en `hotfix/*`) o `git promote hotfix finish` → finaliza hotfix y actualiza `main` + `dev`.

### 🧯 Menú de seguridad (obligatorio)
Antes de modificar ramas (excepto `doctor`), `git promote` obliga a escoger una estrategia:

1. **🛡️ Mi Versión Gana** → `merge-theirs`
2. **⏩ Fast-Forward** → `ff-only`
3. **🔀 Merge con commit** → `merge`
4. **☢️ Force Update** → `force` (destructivo, usa `--force-with-lease`)

> Si `ff-only` no es posible (historia divergida), el flujo devuelve `rc=3` y vuelve a pedir estrategia.

### Preflight (seguridad primero)
Para comandos que promueven ramas (no `doctor`):
- Verifica que estás dentro de un repo Git.
- Verifica que `origin` exista y apunte a GitHub `github.com` (se permite alias SSH si resuelve a `HostName github.com`).
- Ejecuta `git fetch origin --prune` de forma estricta (si falla red/credenciales, aborta).
- Requiere working tree limpio (sin cambios sin commit).

### Variables útiles
- `DEVTOOLS_PROMOTE_STRATEGY=merge-theirs|ff-only|merge|force`  
  Requerida si no hay TTY/UI (CI/no-interactivo).
- `DEVTOOLS_ASSUME_YES=1`  
  Salta confirmaciones humanas (pero no elimina gates técnicos).
- `DEVTOOLS_SYNC_DEV_DIRECT=1`  
  (Opcional) habilita modo directo en el paso DEV dentro de `git promote sync`.
- `DEVTOOLS_FORCE_PUSH_MODE=with-lease|force`  
  Controla el modo de push destructivo (default: `with-lease`).

### Ejemplos rápidos
```bash
# Promover tu rama actual a DEV (elige estrategia en el menú)
git promote dev

# CI/no-tty: define estrategia por env
DEVTOOLS_PROMOTE_STRATEGY=ff-only git promote staging

# Sync completo (desde dev-update)
git checkout dev-update
git promote sync

# Hotfix
git promote hotfix corregir-login
# ...commits...
git promote hotfix