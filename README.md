# Flujo simple (Dislexia Friendly)

Objetivo: cero friccion. Wrapper simple con `task`.
Este README solo usa lo definido en los 5 Taskfiles indicados.

**Reglas rapidas**
- Ejecuta `task` desde la raiz del repo, salvo cuando se indique otra ruta.
- Si no recuerdas un comando: `task --list`.
- Usa rutas cortas y comandos directos.

**Comandos en la raiz del repo**
- `task --list` — Lista todas las tareas.
- `task app:ci APP=pmbok-backend` — CI de una app.
- `task app:build APP=pmbok-frontend` — Build local de una app.
- `task ci` — CI local completo.
- `task ci:act` — CI local con Act.
- `task build:local` — Build de imagenes local.
- `task deploy:local` — Deploy local.
- `task smoke:local` — Smoke local.
- `task pipeline:local` — CI + Build + Deploy.
- `task pipeline:local:headless` — Pipeline sin UI.
- `task new:webapp APP=mi-app` — Crea nueva webapp.
- `task dev:up` — AWS dev: levantar.
- `task dev:down` — AWS dev: bajar.
- `task dev:connect` — AWS dev: tuneles.
- `task prod:up` — AWS prod: levantar.
- `task prod:connect` — AWS prod: tuneles.
- `task cluster:up` — Cluster local: levantar.
- `task cluster:connect` — Cluster local: reconectar.
- `task cluster:info` — Cluster local: info.
- `task cluster:down` — Cluster local: pausar.
- `task cluster:destroy` — Cluster local: borrar todo.
- `task ctx:local` — Contexto local (minikube).
- `task ctx:whoami` — Donde estoy conectado.
- `task ui:local` — UI local (K9s).
- `task cloud:up` — AWS compat: levantar.
- `task cloud:down` — AWS compat: bajar.
- `task cloud:deploy` — AWS compat: desplegar apps.
- `task cloud:connect` — AWS compat: tuneles.
- `task cloud:ctx` — AWS compat: kubeconfig.
- `task cloud:audit` — AWS compat: auditoria de costos.

**App: El Rincon del Detective (Next.js)**
Ruta: `apps/el-rincon-del-detective`
- `task --list` — Lista tareas de la app.
- `task ci` — Instala, lint y build.
- `task build` — Placeholder (Amplify hace el build real).
- `task start` — Dev server.

**App: PMBOK (nivel app)**
Ruta: `apps/pmbok`
- `task --list` — Lista tareas de la app.
- `task ci` — CI completo (backend + frontend).
- `task install-ci` — Instala dependencias (CI).
- `task test` — Pruebas de backend y frontend.

**PMBOK Backend**
Ruta: `apps/pmbok/backend`
- `task install` — Instala dependencias local.
- `task install-ci` — Instala dependencias CI.
- `task test` — Pytest con DB efimera.
- `task db:ensure` — Levanta DB efimera para CI.
- `task db:cleanup` — Borra DB efimera de CI.
- `task lint` — Linting.
- `task fmt` — Formateo.
- `task run` — Servidor de desarrollo.

**PMBOK Frontend**
Ruta: `apps/pmbok/frontend`
- `task install` — Instala dependencias local.
- `task install-ci` — Instala dependencias CI.
- `task lint` — Linting.
- `task build` — Build.
- `task test` — Lint + Build.
- `task run` — Dev server.

**Flujo rapido sugerido**
1. Desde la raiz: `task --list`.
2. Para PMBOK: entra a `apps/pmbok` y ejecuta `task ci`.
3. Para El Rincon: entra a `apps/el-rincon-del-detective` y ejecuta `task ci`.
4. Para desarrollo: entra al backend o frontend y ejecuta `task run`.
