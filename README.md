# Flujo simple (amigable para dislexia)

Objetivo: cero friccion. Capa simple con `task`.
Este README solo usa lo definido en los 5 Taskfiles indicados.

**Reglas rapidas**
- Ejecuta `task` desde la raiz del repo, salvo cuando se indique otra ruta.
- Si no recuerdas un comando: `task --list`.
- Usa rutas cortas y comandos directos.
- Nota: CI = integracion continua.

**Versionado estandar (fuente unica: VERSION)**
- `VERSION` es la fuente unica por repo.
- Las etiquetas se crean con `git promote` y se basan en `VERSION`.
- Etiquetas: `vX.Y.Z` (final), `vX.Y.Z-rc.N` (staging), opcional `vX.Y.Z-beta.N` / `vX.Y.Z-alpha.N`.
- Flujo: `dev` -> `staging` genera RC; `staging` -> `main` (prod) genera final.
- `release-please` solo actualiza archivos (ej: `VERSION`, `CHANGELOG`, extras definidos).
- La publicacion en GitHub se crea al empujar etiquetas `v*`.
- `el-rincon-del-detective` ya no usa `semantic-release` y publica por etiquetas.

**Versionado estandar (fuente unica: VERSION)**
- `VERSION` es la fuente unica por repo.
- `release-please` solo actualiza archivos (ej: `VERSION`, `CHANGELOG` y extras definidos).
- Etiquetas: `vX.Y.Z` (final), `vX.Y.Z-rc.N` (staging), `vX.Y.Z-beta.N`, `vX.Y.Z-alpha.N`.
- Flujo: `dev` -> `staging` genera RC, `staging` -> `main` genera final.
- Las publicaciones en GitHub se crean al empujar etiquetas `v*`.
- `el-rincon-del-detective` publica por etiquetas y adjunta artefacto.

**Artefactos de release**
- Formato: `<app>-vX.Y.Z.zip` o `<app>-vX.Y.Z-rc.N.zip`.
- Ejemplo: `el-rincon-del-detective-v0.1.0-rc.1.zip`.
- Contenido: build `out` cuando aplique.
- Regla: el workflow de release adjunta el `.zip` al Release.

**Comandos en la raiz del repo**
- `task --list` — Lista todas las tareas.
- `task app:ci APP=pmbok-backend` — CI de una app.
- `task app:build APP=pmbok-frontend` — Compilacion local de una app.
- `task ci` — CI local completo.
- `task ci:act` — CI local con Act.
- `task build:local` — Compilacion de imagenes local.
- `task deploy:local` — Despliegue local.
- `task smoke:local` — Pruebas de humo locales.
- `task pipeline:local` — CI + compilacion + despliegue.
- `task pipeline:local:headless` — Flujo sin interfaz.
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
- `task ui:local` — Interfaz local (K9s).
- `task cloud:up` — AWS compat: levantar.
- `task cloud:down` — AWS compat: bajar.
- `task cloud:deploy` — AWS compat: desplegar apps.
- `task cloud:connect` — AWS compat: tuneles.
- `task cloud:ctx` — AWS compat: kubeconfig.
- `task cloud:audit` — AWS compat: auditoria de costos.

**Aplicacion: El Rincon del Detective (Next.js)**
Ruta: `apps/el-rincon-del-detective`
- `task --list` — Lista tareas de la app.
- `task ci` — Instala dependencias, valida estilo y compila.
- `task build` — Marcador (Amplify hace la compilacion real).
- `task start` — Servidor de desarrollo.

**Aplicacion: PMBOK (nivel app)**
Ruta: `apps/pmbok`
- `task --list` — Lista tareas de la app.
- `task ci` — CI completo (servidor + cliente).
- `task install-ci` — Instala dependencias (CI).
- `task test` — Pruebas de servidor y cliente.

**PMBOK servidor**
Ruta: `apps/pmbok/backend`
- `task install` — Instala dependencias local.
- `task install-ci` — Instala dependencias CI.
- `task test` — Pytest con DB efimera.
- `task db:ensure` — Levanta DB efimera para CI.
- `task db:cleanup` — Borra DB efimera de CI.
- `task lint` — Validacion de estilo.
- `task fmt` — Formateo.
- `task run` — Servidor de desarrollo.

**PMBOK cliente**
Ruta: `apps/pmbok/frontend`
- `task install` — Instala dependencias local.
- `task install-ci` — Instala dependencias CI.
- `task lint` — Validacion de estilo.
- `task build` — Compilacion.
- `task test` — Validacion de estilo + compilacion.
- `task run` — Servidor de desarrollo.

**Flujo rapido sugerido**
1. Desde la raiz: `task --list`.
2. Para PMBOK: entra a `apps/pmbok` y ejecuta `task ci`.
3. Para El Rincon: entra a `apps/el-rincon-del-detective` y ejecuta `task ci`.
4. Para desarrollo: entra al servidor o cliente y ejecuta `task run`.

**Workspace de apps (local)**
- `devtools apps sync` sincroniza clones en `apps/` usando `.devtools/config/apps.yaml` del repo actual.
- `DEVTOOLS_DRY_RUN=1 devtools apps sync` muestra acciones sin ejecutar `git clone/fetch/pull`.
- Está pensado para ejecutarse desde `erd-ecosystem`.
