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
- `task pipeline:local:headless` — Ejecucion sin interfaz.
- `task new:webapp APP=mi-app` — Crea nueva app web.
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

**App: El Rincon del Detective (Next.js)**
Ruta: `apps/el-rincon-del-detective`
- `task --list` — Lista tareas de la app.
- `task ci` — Instala dependencias, valida estilo y compila.
- `task build` — Marcador (Amplify hace la compilacion real).
- `task start` — Servidor de desarrollo.

**App: PMBOK (nivel app)**
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
