# Changelog

## [Unreleased]

### Features
- **git-promote(dev):** modo monitor “policía estricto” para PRs hacia `dev` (CI+review+mergeable) con bypass `DEVTOOLS_BYPASS_STRICT=1`.
- **git-promote:** política de aterrizaje por comando (override): `dev` cae en `dev` al salir; `feature/dev-update` cae en `feature/dev-update` en éxito.

### Bug Fixes
- **git-promote(feature/dev-update):** el trap ya no pisa el aterrizaje del workflow (landing override en éxito).

## [3.0.0](https://github.com/elrincondeldetective/erd-devtools/compare/erd-devtools-v2.0.0...erd-devtools-v3.0.0) (2026-01-27)


### ⚠ BREAKING CHANGES

* **setup:** se eliminó el script monolítico `_old_setup-wizard` y cambió la estructura del wizard a módulos en `lib/wizard/`; cualquier automatización que dependía de funciones inline debe actualizarse.
* **devtools:** los imports y rutas de librerías cambiaron de `lib/*.sh` a `lib/core/*.sh`; cualquier script externo que `source`e `lib/config.sh`, `lib/utils.sh` o `lib/git-core.sh` debe actualizarse.
* **setup:** `setup-wizard` deja de generar llaves SSH y de registrar perfiles en `.devtools/.git-acprc`; ahora asume llaves GPG/SSH existentes y solo configura firma y transporte.
* **devbox:** los comandos ahora dependen de `find` para localizar scripts; si hay múltiples coincidencias o `find` no está disponible en el entorno, los alias/comandos pueden apuntar a un script inesperado o fallar.
* **devtools:** se retiraron los comandos/atajos provistos por esos scripts (p. ej., `git acp`, `git feature`, `git gp`, `git pr`, `git promote`, `git rp` y `setup-wizard`); actualiza tus alias, documentación y pipelines.

### Features

* **ci:** añadir menú por niveles para ejecutar CI local y exponer `git-ci` ([aeb3afc](https://github.com/elrincondeldetective/erd-devtools/commit/aeb3afc93c4d1e9459de9525aa721aae5b955af3))
* **ci:** detectar `task ci`/`task ci:act`/`task pipeline:local` de forma estricta y añadir `git-pipeline` ([8453a9d](https://github.com/elrincondeldetective/erd-devtools/commit/8453a9d1b2db0c5491491bf749a60b1dc5818607))
* **ci:** detectar contrato `task ci`/`task ci:act` y añadir `git-pipeline` para ejecutar `task pipeline:local` ([863f07b](https://github.com/elrincondeldetective/erd-devtools/commit/863f07b569d2f3e625af22af80c258852b723a57))
* **ci:** enriquecer menú post-push con acciones rápidas y ayuda ([e2d0eca](https://github.com/elrincondeldetective/erd-devtools/commit/e2d0ecaeed66badcf2e2e8996d72e927c3667659))
* **ci:** mejora detección de CI y flujo post-push ([773afa3](https://github.com/elrincondeldetective/erd-devtools/commit/773afa3c0405d6b32e70d24aa20e3bc4cfe25bf8))
* **ci:** mostrar panel de entorno y añadir fallback seguro para `act` ([1bc9156](https://github.com/elrincondeldetective/erd-devtools/commit/1bc91568def4b2190772b36cf49f76bbc6570acf))
* **devbox:** autodetecta scripts de .devtools y actualiza alias automáticamente ([9973764](https://github.com/elrincondeldetective/erd-devtools/commit/9973764c51a3a1db0701ebac40c25153bbd818d7))
* **devtools:** agrega `git-profile` y refuerza modelo de identidades V1 ([4196fb6](https://github.com/elrincondeldetective/erd-devtools/commit/4196fb697208e78827254b06efcead0af7b8cc4b))
* **devtools:** agrega `github-core` para gestionar PRs con `gh` ([0c686c5](https://github.com/elrincondeldetective/erd-devtools/commit/0c686c5692805ff02bb686d0b27c51014f6f497a))
* **devtools:** agrega herramientas git y automatiza versionado con release-please ([f406e39](https://github.com/elrincondeldetective/erd-devtools/commit/f406e39bd39c1f4576a3d8c2348bedcf3361ff21))
* **devtools:** agrega modo `sync` y refactoriza `git-promote` con `release-flow` ([280b6cf](https://github.com/elrincondeldetective/erd-devtools/commit/280b6cf7ede98cb8036754a7561ee230e78716dc))
* **devtools:** refuerza `git promote sync` con identidad y absorción automática ([748d8da](https://github.com/elrincondeldetective/erd-devtools/commit/748d8da393c24e6d71f708048f9163bd1e27ecdc))
* **devtools:** versiona el esquema de perfiles y endurece el parseo en `ssh-ident` ([b3e4882](https://github.com/elrincondeldetective/erd-devtools/commit/b3e488295dc0377a3b7e53c57aa5e4b33b22cb77))
* **devx:** sugerir comandos de logs cuando Compose está activo ([9780523](https://github.com/elrincondeldetective/erd-devtools/commit/9780523fbac6b22e56f3e18effcdc6834e7d3041))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([353f90e](https://github.com/elrincondeldetective/erd-devtools/commit/353f90e31467f1cb2a7819e8744c3a1e1c5627d6))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([f98b40f](https://github.com/elrincondeldetective/erd-devtools/commit/f98b40fb8ad2e6c825f1aed68feaba5f1b80d5c2))
* **git-promote:** mejorar flujo de trabajo con cambios automáticos de rama y validaciones ([8817579](https://github.com/elrincondeldetective/erd-devtools/commit/88175794a00671b1535b78d70c0a360fd65fb217))
* **git-tools:** añadir `git-sweep` para limpiar ramas/tags y exponer alias `git-sw`/`git-lim` ([976e6d8](https://github.com/elrincondeldetective/erd-devtools/commit/976e6d85a22b8601c739cb0e49d93a999a5a3053))
* **promote:** habilitar sync aplastante con `--force-with-lease` en `bin/git-promote.sh` ([40c449c](https://github.com/elrincondeldetective/erd-devtools/commit/40c449cf677ec21d5da49d0910c3399947afc991))
* **scripts:** automatizar migración de trabajo desde ramas protegidas a feature/* ([ed3cad2](https://github.com/elrincondeldetective/erd-devtools/commit/ed3cad26fb1755b2f072922c9b6af62e17322738))
* **scripts:** implementar política estricta de ramas feature y PR automáticos ([e82cf77](https://github.com/elrincondeldetective/erd-devtools/commit/e82cf77c707d51e1cfa5118c07dcd86d127b02e4))
* **setup:** automatizar configuración de identidad, SSH y entorno en el wizard ([ce7acdd](https://github.com/elrincondeldetective/erd-devtools/commit/ce7acdd00d40d7eafec79236c9f45375806b5932)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** separa firma GPG y conexión SSH en `setup-wizard` ([17f64cb](https://github.com/elrincondeldetective/erd-devtools/commit/17f64cbc95a48b53e1f3334fad70d693f26774e1))
* **wizard:** refuerza `setup-wizard` para submódulos y mejora flujo SSH/GitHub ([ef1bed8](https://github.com/elrincondeldetective/erd-devtools/commit/ef1bed8328668a3a746c79876ebd176e17f6ad8a))


### Bug Fixes

* **acp:** cargar `ui/styles.sh` antes de `git-flow.sh` en `bin/git-acp.sh` ([edb2db3](https://github.com/elrincondeldetective/erd-devtools/commit/edb2db37bfc976041b0e32a77236345acf8d4775))
* **ci:** endurecer flujo post-push con fallbacks de UI y gate obligatorio ([6f8cd35](https://github.com/elrincondeldetective/erd-devtools/commit/6f8cd358649a7a1128b8b43d949866a94bd647d4))
* **ci:** evitar comandos de CI cacheados y desactivar fallback a `act` ([6516e72](https://github.com/elrincondeldetective/erd-devtools/commit/6516e724171535948f6fe5a3d7ac6ad8f78efc56))
* **ci:** evitar fallos por variables no definidas y robustecer detección en `lib/ci-workflow.sh` ([975bbbf](https://github.com/elrincondeldetective/erd-devtools/commit/975bbbf2cbcd5303b3a8996a9fcd3d6495de1083))
* **ci:** hacer `task_exists` más confiable al parsear `task --list` ([f9837e6](https://github.com/elrincondeldetective/erd-devtools/commit/f9837e6d7b9da8890d76c33cb8c1103ee666090f))
* **ci:** robustecer detección de comandos y evitar fallos con `set -u` en `lib/ci-workflow.sh` ([269085c](https://github.com/elrincondeldetective/erd-devtools/commit/269085cfadec847749d5a4ff903344cf88fea12c))
* **devbox:** actualiza alias y comandos para usar .devtools/bin ([168ebd4](https://github.com/elrincondeldetective/erd-devtools/commit/168ebd48f3c3fe79b6a4b174610aa959bb595998))
* **devbox:** corregir rutas de scripts y simplificar configuración del entorno ([2fde055](https://github.com/elrincondeldetective/erd-devtools/commit/2fde055349c08a805758e221382c0414509ab65d))
* **devbox:** hace más robusto el auto-discovery de scripts en .devtools ([a96e203](https://github.com/elrincondeldetective/erd-devtools/commit/a96e203ca2f3a22ae82e9cb3d34e92d7912107b1))
* **devbox:** revertir variables de starship y mejorar detección de ruta raíz para configuración ([581e6b4](https://github.com/elrincondeldetective/erd-devtools/commit/581e6b4cfebb48b715da0308d3a65cd68b15ba08))
* **git-acp:** corregir detección de formato de firma y manejo de llaves SSH ([46d8e0f](https://github.com/elrincondeldetective/erd-devtools/commit/46d8e0ffc79d535995db6624a4063ab582435e95))
* **promote:** asegura tracking de ramas y calcula diffs completos para GitOps en `lib/promote/workflows.sh` ([ed7b585](https://github.com/elrincondeldetective/erd-devtools/commit/ed7b585be752c4b2b683434ea07670e089813690))
* **promote:** busca `Taskfile.yaml` en raíz y evita crashes por `trap` en `lib/promote/workflows.sh` ([84806ad](https://github.com/elrincondeldetective/erd-devtools/commit/84806ad696f58e4c9dcdab888e5675ff4ed8da45))
* **promote:** evitar `unbound variable` y permitir tags manuales leyendo `VERSION` ([6529bfb](https://github.com/elrincondeldetective/erd-devtools/commit/6529bfbeff5997e064a150a3f1d4fb16f4ec5b99))
* **promote:** prioriza `WORKSPACE_ROOT` y habilita limpieza `auto` de ramas `release-please` ([f71f352](https://github.com/elrincondeldetective/erd-devtools/commit/f71f352ae0839a92ce747b311455f98705c45642))
* **promote:** valida SHA consistente en promociones y registra SHA canónico ([66456aa](https://github.com/elrincondeldetective/erd-devtools/commit/66456aa24361b2f97131d2405e4ad9b19fbd6268))
* **scripts:** corregir el valor de la variable MODE en git-feature.sh ([6d4633f](https://github.com/elrincondeldetective/erd-devtools/commit/6d4633f9cb33f7754a0e40666b47f107a196e8ed)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** hace idempotente `setup-wizard` y añade modo `--verify-only` ([5caf7ab](https://github.com/elrincondeldetective/erd-devtools/commit/5caf7ab61f5623b1ac6449e2b235bfbda4bc7be5))
* **wizard:** corrige detección TTY y endurece manejo de `set -e` y `ssh-add` ([6f11d1c](https://github.com/elrincondeldetective/erd-devtools/commit/6f11d1ccb2059eb105d77bc00e7159fc1beffbd4))
* **wizard:** endurece `setup-wizard` con bypass y verificaciones seguras ([459c0dc](https://github.com/elrincondeldetective/erd-devtools/commit/459c0dc48d52595b73d08c487a9dfa0ba10cdb4e))
* **wizard:** endurece `setup-wizard` para submódulos, CI y firma SSH ([1477db8](https://github.com/elrincondeldetective/erd-devtools/commit/1477db8e714763a8c14414fcef219b6210a146a5))
* **wizard:** endurece helpers y asegura escrituras atómicas de perfiles ([4e635f6](https://github.com/elrincondeldetective/erd-devtools/commit/4e635f605808c96ca5265d5a85529b11f944a2f3))
* **wizard:** evita fallo en `--verify-only` cuando falta `git_get` ([36e33ed](https://github.com/elrincondeldetective/erd-devtools/commit/36e33edf80130408dd0facef8c218fafd571a1b9))
* **wizard:** mejora registro de perfiles y protege cambio de remote a SSH ([cacccee](https://github.com/elrincondeldetective/erd-devtools/commit/cacccee7441b47072af68e2125bdc1bac92bebd4))


### Miscellaneous Chores

* **devtools:** elimina scripts de automatización de Git ([848c6b7](https://github.com/elrincondeldetective/erd-devtools/commit/848c6b71c84a5c77684d3aee2082303389619150))


### Code Refactoring

* **devtools:** reorganiza librerías en `lib/core` y modulariza `setup-wizard` ([4ff3483](https://github.com/elrincondeldetective/erd-devtools/commit/4ff3483a046bb4334baf02146c4735c1bd56cabe))
* **setup:** divide `setup-wizard` en pasos y añade modo de verificación ([059d3c5](https://github.com/elrincondeldetective/erd-devtools/commit/059d3c5f97ab2358973a7212a9394f14739e4fb3))

## [2.0.0](https://github.com/elrincondeldetective/erd-devtools/compare/erd-devtools-v1.0.0...erd-devtools-v2.0.0) (2026-01-27)


### ⚠ BREAKING CHANGES

* **setup:** se eliminó el script monolítico `_old_setup-wizard` y cambió la estructura del wizard a módulos en `lib/wizard/`; cualquier automatización que dependía de funciones inline debe actualizarse.
* **devtools:** los imports y rutas de librerías cambiaron de `lib/*.sh` a `lib/core/*.sh`; cualquier script externo que `source`e `lib/config.sh`, `lib/utils.sh` o `lib/git-core.sh` debe actualizarse.
* **setup:** `setup-wizard` deja de generar llaves SSH y de registrar perfiles en `.devtools/.git-acprc`; ahora asume llaves GPG/SSH existentes y solo configura firma y transporte.
* **devbox:** los comandos ahora dependen de `find` para localizar scripts; si hay múltiples coincidencias o `find` no está disponible en el entorno, los alias/comandos pueden apuntar a un script inesperado o fallar.
* **devtools:** se retiraron los comandos/atajos provistos por esos scripts (p. ej., `git acp`, `git feature`, `git gp`, `git pr`, `git promote`, `git rp` y `setup-wizard`); actualiza tus alias, documentación y pipelines.

### Features

* **ci:** añadir menú por niveles para ejecutar CI local y exponer `git-ci` ([aeb3afc](https://github.com/elrincondeldetective/erd-devtools/commit/aeb3afc93c4d1e9459de9525aa721aae5b955af3))
* **ci:** detectar `task ci`/`task ci:act`/`task pipeline:local` de forma estricta y añadir `git-pipeline` ([8453a9d](https://github.com/elrincondeldetective/erd-devtools/commit/8453a9d1b2db0c5491491bf749a60b1dc5818607))
* **ci:** detectar contrato `task ci`/`task ci:act` y añadir `git-pipeline` para ejecutar `task pipeline:local` ([863f07b](https://github.com/elrincondeldetective/erd-devtools/commit/863f07b569d2f3e625af22af80c258852b723a57))
* **ci:** enriquecer menú post-push con acciones rápidas y ayuda ([e2d0eca](https://github.com/elrincondeldetective/erd-devtools/commit/e2d0ecaeed66badcf2e2e8996d72e927c3667659))
* **ci:** mejora detección de CI y flujo post-push ([773afa3](https://github.com/elrincondeldetective/erd-devtools/commit/773afa3c0405d6b32e70d24aa20e3bc4cfe25bf8))
* **ci:** mostrar panel de entorno y añadir fallback seguro para `act` ([1bc9156](https://github.com/elrincondeldetective/erd-devtools/commit/1bc91568def4b2190772b36cf49f76bbc6570acf))
* **devbox:** autodetecta scripts de .devtools y actualiza alias automáticamente ([9973764](https://github.com/elrincondeldetective/erd-devtools/commit/9973764c51a3a1db0701ebac40c25153bbd818d7))
* **devtools:** agrega `git-profile` y refuerza modelo de identidades V1 ([4196fb6](https://github.com/elrincondeldetective/erd-devtools/commit/4196fb697208e78827254b06efcead0af7b8cc4b))
* **devtools:** agrega `github-core` para gestionar PRs con `gh` ([0c686c5](https://github.com/elrincondeldetective/erd-devtools/commit/0c686c5692805ff02bb686d0b27c51014f6f497a))
* **devtools:** agrega herramientas git y automatiza versionado con release-please ([f406e39](https://github.com/elrincondeldetective/erd-devtools/commit/f406e39bd39c1f4576a3d8c2348bedcf3361ff21))
* **devtools:** agrega modo `sync` y refactoriza `git-promote` con `release-flow` ([280b6cf](https://github.com/elrincondeldetective/erd-devtools/commit/280b6cf7ede98cb8036754a7561ee230e78716dc))
* **devtools:** refuerza `git promote sync` con identidad y absorción automática ([748d8da](https://github.com/elrincondeldetective/erd-devtools/commit/748d8da393c24e6d71f708048f9163bd1e27ecdc))
* **devtools:** versiona el esquema de perfiles y endurece el parseo en `ssh-ident` ([b3e4882](https://github.com/elrincondeldetective/erd-devtools/commit/b3e488295dc0377a3b7e53c57aa5e4b33b22cb77))
* **devx:** sugerir comandos de logs cuando Compose está activo ([9780523](https://github.com/elrincondeldetective/erd-devtools/commit/9780523fbac6b22e56f3e18effcdc6834e7d3041))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([353f90e](https://github.com/elrincondeldetective/erd-devtools/commit/353f90e31467f1cb2a7819e8744c3a1e1c5627d6))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([f98b40f](https://github.com/elrincondeldetective/erd-devtools/commit/f98b40fb8ad2e6c825f1aed68feaba5f1b80d5c2))
* **git-promote:** mejorar flujo de trabajo con cambios automáticos de rama y validaciones ([8817579](https://github.com/elrincondeldetective/erd-devtools/commit/88175794a00671b1535b78d70c0a360fd65fb217))
* **git-tools:** añadir `git-sweep` para limpiar ramas/tags y exponer alias `git-sw`/`git-lim` ([976e6d8](https://github.com/elrincondeldetective/erd-devtools/commit/976e6d85a22b8601c739cb0e49d93a999a5a3053))
* **promote:** habilitar sync aplastante con `--force-with-lease` en `bin/git-promote.sh` ([40c449c](https://github.com/elrincondeldetective/erd-devtools/commit/40c449cf677ec21d5da49d0910c3399947afc991))
* **scripts:** automatizar migración de trabajo desde ramas protegidas a feature/* ([ed3cad2](https://github.com/elrincondeldetective/erd-devtools/commit/ed3cad26fb1755b2f072922c9b6af62e17322738))
* **scripts:** implementar política estricta de ramas feature y PR automáticos ([e82cf77](https://github.com/elrincondeldetective/erd-devtools/commit/e82cf77c707d51e1cfa5118c07dcd86d127b02e4))
* **setup:** automatizar configuración de identidad, SSH y entorno en el wizard ([ce7acdd](https://github.com/elrincondeldetective/erd-devtools/commit/ce7acdd00d40d7eafec79236c9f45375806b5932)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** separa firma GPG y conexión SSH en `setup-wizard` ([17f64cb](https://github.com/elrincondeldetective/erd-devtools/commit/17f64cbc95a48b53e1f3334fad70d693f26774e1))
* **wizard:** refuerza `setup-wizard` para submódulos y mejora flujo SSH/GitHub ([ef1bed8](https://github.com/elrincondeldetective/erd-devtools/commit/ef1bed8328668a3a746c79876ebd176e17f6ad8a))


### Bug Fixes

* **acp:** cargar `ui/styles.sh` antes de `git-flow.sh` en `bin/git-acp.sh` ([edb2db3](https://github.com/elrincondeldetective/erd-devtools/commit/edb2db37bfc976041b0e32a77236345acf8d4775))
* **ci:** endurecer flujo post-push con fallbacks de UI y gate obligatorio ([6f8cd35](https://github.com/elrincondeldetective/erd-devtools/commit/6f8cd358649a7a1128b8b43d949866a94bd647d4))
* **ci:** evitar comandos de CI cacheados y desactivar fallback a `act` ([6516e72](https://github.com/elrincondeldetective/erd-devtools/commit/6516e724171535948f6fe5a3d7ac6ad8f78efc56))
* **ci:** evitar fallos por variables no definidas y robustecer detección en `lib/ci-workflow.sh` ([975bbbf](https://github.com/elrincondeldetective/erd-devtools/commit/975bbbf2cbcd5303b3a8996a9fcd3d6495de1083))
* **ci:** hacer `task_exists` más confiable al parsear `task --list` ([f9837e6](https://github.com/elrincondeldetective/erd-devtools/commit/f9837e6d7b9da8890d76c33cb8c1103ee666090f))
* **ci:** robustecer detección de comandos y evitar fallos con `set -u` en `lib/ci-workflow.sh` ([269085c](https://github.com/elrincondeldetective/erd-devtools/commit/269085cfadec847749d5a4ff903344cf88fea12c))
* **devbox:** actualiza alias y comandos para usar .devtools/bin ([168ebd4](https://github.com/elrincondeldetective/erd-devtools/commit/168ebd48f3c3fe79b6a4b174610aa959bb595998))
* **devbox:** corregir rutas de scripts y simplificar configuración del entorno ([2fde055](https://github.com/elrincondeldetective/erd-devtools/commit/2fde055349c08a805758e221382c0414509ab65d))
* **devbox:** hace más robusto el auto-discovery de scripts en .devtools ([a96e203](https://github.com/elrincondeldetective/erd-devtools/commit/a96e203ca2f3a22ae82e9cb3d34e92d7912107b1))
* **devbox:** revertir variables de starship y mejorar detección de ruta raíz para configuración ([581e6b4](https://github.com/elrincondeldetective/erd-devtools/commit/581e6b4cfebb48b715da0308d3a65cd68b15ba08))
* **git-acp:** corregir detección de formato de firma y manejo de llaves SSH ([46d8e0f](https://github.com/elrincondeldetective/erd-devtools/commit/46d8e0ffc79d535995db6624a4063ab582435e95))
* **promote:** evitar `unbound variable` y permitir tags manuales leyendo `VERSION` ([6529bfb](https://github.com/elrincondeldetective/erd-devtools/commit/6529bfbeff5997e064a150a3f1d4fb16f4ec5b99))
* **promote:** valida SHA consistente en promociones y registra `golden` ([66456aa](https://github.com/elrincondeldetective/erd-devtools/commit/66456aa24361b2f97131d2405e4ad9b19fbd6268))
* **scripts:** corregir el valor de la variable MODE en git-feature.sh ([6d4633f](https://github.com/elrincondeldetective/erd-devtools/commit/6d4633f9cb33f7754a0e40666b47f107a196e8ed)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** hace idempotente `setup-wizard` y añade modo `--verify-only` ([5caf7ab](https://github.com/elrincondeldetective/erd-devtools/commit/5caf7ab61f5623b1ac6449e2b235bfbda4bc7be5))
* **wizard:** corrige detección TTY y endurece manejo de `set -e` y `ssh-add` ([6f11d1c](https://github.com/elrincondeldetective/erd-devtools/commit/6f11d1ccb2059eb105d77bc00e7159fc1beffbd4))
* **wizard:** endurece `setup-wizard` con bypass y verificaciones seguras ([459c0dc](https://github.com/elrincondeldetective/erd-devtools/commit/459c0dc48d52595b73d08c487a9dfa0ba10cdb4e))
* **wizard:** endurece `setup-wizard` para submódulos, CI y firma SSH ([1477db8](https://github.com/elrincondeldetective/erd-devtools/commit/1477db8e714763a8c14414fcef219b6210a146a5))
* **wizard:** endurece helpers y asegura escrituras atómicas de perfiles ([4e635f6](https://github.com/elrincondeldetective/erd-devtools/commit/4e635f605808c96ca5265d5a85529b11f944a2f3))
* **wizard:** evita fallo en `--verify-only` cuando falta `git_get` ([36e33ed](https://github.com/elrincondeldetective/erd-devtools/commit/36e33edf80130408dd0facef8c218fafd571a1b9))
* **wizard:** mejora registro de perfiles y protege cambio de remote a SSH ([cacccee](https://github.com/elrincondeldetective/erd-devtools/commit/cacccee7441b47072af68e2125bdc1bac92bebd4))


### Miscellaneous Chores

* **devtools:** elimina scripts de automatización de Git ([848c6b7](https://github.com/elrincondeldetective/erd-devtools/commit/848c6b71c84a5c77684d3aee2082303389619150))


### Code Refactoring

* **devtools:** reorganiza librerías en `lib/core` y modulariza `setup-wizard` ([4ff3483](https://github.com/elrincondeldetective/erd-devtools/commit/4ff3483a046bb4334baf02146c4735c1bd56cabe))
* **setup:** divide `setup-wizard` en pasos y añade modo de verificación ([059d3c5](https://github.com/elrincondeldetective/erd-devtools/commit/059d3c5f97ab2358973a7212a9394f14739e4fb3))

## 1.0.0 (2026-01-27)


### ⚠ BREAKING CHANGES

* **setup:** se eliminó el script monolítico `_old_setup-wizard` y cambió la estructura del wizard a módulos en `lib/wizard/`; cualquier automatización que dependía de funciones inline debe actualizarse.
* **devtools:** los imports y rutas de librerías cambiaron de `lib/*.sh` a `lib/core/*.sh`; cualquier script externo que `source`e `lib/config.sh`, `lib/utils.sh` o `lib/git-core.sh` debe actualizarse.
* **setup:** `setup-wizard` deja de generar llaves SSH y de registrar perfiles en `.devtools/.git-acprc`; ahora asume llaves GPG/SSH existentes y solo configura firma y transporte.
* **devbox:** los comandos ahora dependen de `find` para localizar scripts; si hay múltiples coincidencias o `find` no está disponible en el entorno, los alias/comandos pueden apuntar a un script inesperado o fallar.
* **devtools:** se retiraron los comandos/atajos provistos por esos scripts (p. ej., `git acp`, `git feature`, `git gp`, `git pr`, `git promote`, `git rp` y `setup-wizard`); actualiza tus alias, documentación y pipelines.

### Features

* **ci:** añadir menú por niveles para ejecutar CI local y exponer `git-ci` ([aeb3afc](https://github.com/elrincondeldetective/erd-devtools/commit/aeb3afc93c4d1e9459de9525aa721aae5b955af3))
* **ci:** detectar `task ci`/`task ci:act`/`task pipeline:local` de forma estricta y añadir `git-pipeline` ([8453a9d](https://github.com/elrincondeldetective/erd-devtools/commit/8453a9d1b2db0c5491491bf749a60b1dc5818607))
* **ci:** detectar contrato `task ci`/`task ci:act` y añadir `git-pipeline` para ejecutar `task pipeline:local` ([863f07b](https://github.com/elrincondeldetective/erd-devtools/commit/863f07b569d2f3e625af22af80c258852b723a57))
* **ci:** enriquecer menú post-push con acciones rápidas y ayuda ([e2d0eca](https://github.com/elrincondeldetective/erd-devtools/commit/e2d0ecaeed66badcf2e2e8996d72e927c3667659))
* **ci:** mejora detección de CI y flujo post-push ([773afa3](https://github.com/elrincondeldetective/erd-devtools/commit/773afa3c0405d6b32e70d24aa20e3bc4cfe25bf8))
* **ci:** mostrar panel de entorno y añadir fallback seguro para `act` ([1bc9156](https://github.com/elrincondeldetective/erd-devtools/commit/1bc91568def4b2190772b36cf49f76bbc6570acf))
* **devbox:** autodetecta scripts de .devtools y actualiza alias automáticamente ([9973764](https://github.com/elrincondeldetective/erd-devtools/commit/9973764c51a3a1db0701ebac40c25153bbd818d7))
* **devtools:** agrega `git-profile` y refuerza modelo de identidades V1 ([4196fb6](https://github.com/elrincondeldetective/erd-devtools/commit/4196fb697208e78827254b06efcead0af7b8cc4b))
* **devtools:** agrega `github-core` para gestionar PRs con `gh` ([0c686c5](https://github.com/elrincondeldetective/erd-devtools/commit/0c686c5692805ff02bb686d0b27c51014f6f497a))
* **devtools:** agrega herramientas git y automatiza versionado con release-please ([f406e39](https://github.com/elrincondeldetective/erd-devtools/commit/f406e39bd39c1f4576a3d8c2348bedcf3361ff21))
* **devtools:** agrega modo `sync` y refactoriza `git-promote` con `release-flow` ([280b6cf](https://github.com/elrincondeldetective/erd-devtools/commit/280b6cf7ede98cb8036754a7561ee230e78716dc))
* **devtools:** refuerza `git promote sync` con identidad y absorción automática ([748d8da](https://github.com/elrincondeldetective/erd-devtools/commit/748d8da393c24e6d71f708048f9163bd1e27ecdc))
* **devtools:** versiona el esquema de perfiles y endurece el parseo en `ssh-ident` ([b3e4882](https://github.com/elrincondeldetective/erd-devtools/commit/b3e488295dc0377a3b7e53c57aa5e4b33b22cb77))
* **devx:** sugerir comandos de logs cuando Compose está activo ([9780523](https://github.com/elrincondeldetective/erd-devtools/commit/9780523fbac6b22e56f3e18effcdc6834e7d3041))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([353f90e](https://github.com/elrincondeldetective/erd-devtools/commit/353f90e31467f1cb2a7819e8744c3a1e1c5627d6))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([f98b40f](https://github.com/elrincondeldetective/erd-devtools/commit/f98b40fb8ad2e6c825f1aed68feaba5f1b80d5c2))
* **git-promote:** mejorar flujo de trabajo con cambios automáticos de rama y validaciones ([8817579](https://github.com/elrincondeldetective/erd-devtools/commit/88175794a00671b1535b78d70c0a360fd65fb217))
* **git-tools:** añadir `git-sweep` para limpiar ramas/tags y exponer alias `git-sw`/`git-lim` ([976e6d8](https://github.com/elrincondeldetective/erd-devtools/commit/976e6d85a22b8601c739cb0e49d93a999a5a3053))
* **promote:** habilitar sync aplastante con `--force-with-lease` en `bin/git-promote.sh` ([40c449c](https://github.com/elrincondeldetective/erd-devtools/commit/40c449cf677ec21d5da49d0910c3399947afc991))
* **scripts:** automatizar migración de trabajo desde ramas protegidas a feature/* ([ed3cad2](https://github.com/elrincondeldetective/erd-devtools/commit/ed3cad26fb1755b2f072922c9b6af62e17322738))
* **scripts:** implementar política estricta de ramas feature y PR automáticos ([e82cf77](https://github.com/elrincondeldetective/erd-devtools/commit/e82cf77c707d51e1cfa5118c07dcd86d127b02e4))
* **setup:** automatizar configuración de identidad, SSH y entorno en el wizard ([ce7acdd](https://github.com/elrincondeldetective/erd-devtools/commit/ce7acdd00d40d7eafec79236c9f45375806b5932)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** separa firma GPG y conexión SSH en `setup-wizard` ([17f64cb](https://github.com/elrincondeldetective/erd-devtools/commit/17f64cbc95a48b53e1f3334fad70d693f26774e1))
* **wizard:** refuerza `setup-wizard` para submódulos y mejora flujo SSH/GitHub ([ef1bed8](https://github.com/elrincondeldetective/erd-devtools/commit/ef1bed8328668a3a746c79876ebd176e17f6ad8a))


### Bug Fixes

* **acp:** cargar `ui/styles.sh` antes de `git-flow.sh` en `bin/git-acp.sh` ([edb2db3](https://github.com/elrincondeldetective/erd-devtools/commit/edb2db37bfc976041b0e32a77236345acf8d4775))
* **ci:** endurecer flujo post-push con fallbacks de UI y gate obligatorio ([6f8cd35](https://github.com/elrincondeldetective/erd-devtools/commit/6f8cd358649a7a1128b8b43d949866a94bd647d4))
* **ci:** evitar comandos de CI cacheados y desactivar fallback a `act` ([6516e72](https://github.com/elrincondeldetective/erd-devtools/commit/6516e724171535948f6fe5a3d7ac6ad8f78efc56))
* **ci:** evitar fallos por variables no definidas y robustecer detección en `lib/ci-workflow.sh` ([975bbbf](https://github.com/elrincondeldetective/erd-devtools/commit/975bbbf2cbcd5303b3a8996a9fcd3d6495de1083))
* **ci:** hacer `task_exists` más confiable al parsear `task --list` ([f9837e6](https://github.com/elrincondeldetective/erd-devtools/commit/f9837e6d7b9da8890d76c33cb8c1103ee666090f))
* **ci:** robustecer detección de comandos y evitar fallos con `set -u` en `lib/ci-workflow.sh` ([269085c](https://github.com/elrincondeldetective/erd-devtools/commit/269085cfadec847749d5a4ff903344cf88fea12c))
* **devbox:** actualiza alias y comandos para usar .devtools/bin ([168ebd4](https://github.com/elrincondeldetective/erd-devtools/commit/168ebd48f3c3fe79b6a4b174610aa959bb595998))
* **devbox:** corregir rutas de scripts y simplificar configuración del entorno ([2fde055](https://github.com/elrincondeldetective/erd-devtools/commit/2fde055349c08a805758e221382c0414509ab65d))
* **devbox:** hace más robusto el auto-discovery de scripts en .devtools ([a96e203](https://github.com/elrincondeldetective/erd-devtools/commit/a96e203ca2f3a22ae82e9cb3d34e92d7912107b1))
* **devbox:** revertir variables de starship y mejorar detección de ruta raíz para configuración ([581e6b4](https://github.com/elrincondeldetective/erd-devtools/commit/581e6b4cfebb48b715da0308d3a65cd68b15ba08))
* **git-acp:** corregir detección de formato de firma y manejo de llaves SSH ([46d8e0f](https://github.com/elrincondeldetective/erd-devtools/commit/46d8e0ffc79d535995db6624a4063ab582435e95))
* **promote:** evitar `unbound variable` y permitir tags manuales leyendo `VERSION` ([6529bfb](https://github.com/elrincondeldetective/erd-devtools/commit/6529bfbeff5997e064a150a3f1d4fb16f4ec5b99))
* **promote:** valida SHA consistente en promociones y registra `golden` ([66456aa](https://github.com/elrincondeldetective/erd-devtools/commit/66456aa24361b2f97131d2405e4ad9b19fbd6268))
* **scripts:** corregir el valor de la variable MODE en git-feature.sh ([6d4633f](https://github.com/elrincondeldetective/erd-devtools/commit/6d4633f9cb33f7754a0e40666b47f107a196e8ed)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** hace idempotente `setup-wizard` y añade modo `--verify-only` ([5caf7ab](https://github.com/elrincondeldetective/erd-devtools/commit/5caf7ab61f5623b1ac6449e2b235bfbda4bc7be5))
* **wizard:** corrige detección TTY y endurece manejo de `set -e` y `ssh-add` ([6f11d1c](https://github.com/elrincondeldetective/erd-devtools/commit/6f11d1ccb2059eb105d77bc00e7159fc1beffbd4))
* **wizard:** endurece `setup-wizard` con bypass y verificaciones seguras ([459c0dc](https://github.com/elrincondeldetective/erd-devtools/commit/459c0dc48d52595b73d08c487a9dfa0ba10cdb4e))
* **wizard:** endurece `setup-wizard` para submódulos, CI y firma SSH ([1477db8](https://github.com/elrincondeldetective/erd-devtools/commit/1477db8e714763a8c14414fcef219b6210a146a5))
* **wizard:** endurece helpers y asegura escrituras atómicas de perfiles ([4e635f6](https://github.com/elrincondeldetective/erd-devtools/commit/4e635f605808c96ca5265d5a85529b11f944a2f3))
* **wizard:** evita fallo en `--verify-only` cuando falta `git_get` ([36e33ed](https://github.com/elrincondeldetective/erd-devtools/commit/36e33edf80130408dd0facef8c218fafd571a1b9))
* **wizard:** mejora registro de perfiles y protege cambio de remote a SSH ([cacccee](https://github.com/elrincondeldetective/erd-devtools/commit/cacccee7441b47072af68e2125bdc1bac92bebd4))


### Miscellaneous Chores

* **devtools:** elimina scripts de automatización de Git ([848c6b7](https://github.com/elrincondeldetective/erd-devtools/commit/848c6b71c84a5c77684d3aee2082303389619150))


### Code Refactoring

* **devtools:** reorganiza librerías en `lib/core` y modulariza `setup-wizard` ([4ff3483](https://github.com/elrincondeldetective/erd-devtools/commit/4ff3483a046bb4334baf02146c4735c1bd56cabe))
* **setup:** divide `setup-wizard` en pasos y añade modo de verificación ([059d3c5](https://github.com/elrincondeldetective/erd-devtools/commit/059d3c5f97ab2358973a7212a9394f14739e4fb3))

## [2.1.0](https://github.com/elrincondeldetective/erd-devtools/compare/erd-devtools-v2.0.0...erd-devtools-v2.1.0) (2026-01-26)


### Features

* **promote:** habilitar sync aplastante con `--force-with-lease` en `bin/git-promote.sh` ([40c449c](https://github.com/elrincondeldetective/erd-devtools/commit/40c449cf677ec21d5da49d0910c3399947afc991))


### Bug Fixes

* **promote:** evitar `unbound variable` y permitir tags manuales leyendo `VERSION` ([6529bfb](https://github.com/elrincondeldetective/erd-devtools/commit/6529bfbeff5997e064a150a3f1d4fb16f4ec5b99))

## [2.0.0](https://github.com/elrincondeldetective/erd-devtools/compare/erd-devtools-v1.1.0...erd-devtools-v2.0.0) (2026-01-24)


### ⚠ BREAKING CHANGES

* **setup:** se eliminó el script monolítico `_old_setup-wizard` y cambió la estructura del wizard a módulos en `lib/wizard/`; cualquier automatización que dependía de funciones inline debe actualizarse.
* **devtools:** los imports y rutas de librerías cambiaron de `lib/*.sh` a `lib/core/*.sh`; cualquier script externo que `source`e `lib/config.sh`, `lib/utils.sh` o `lib/git-core.sh` debe actualizarse.
* **setup:** `setup-wizard` deja de generar llaves SSH y de registrar perfiles en `.devtools/.git-acprc`; ahora asume llaves GPG/SSH existentes y solo configura firma y transporte.
* **devbox:** los comandos ahora dependen de `find` para localizar scripts; si hay múltiples coincidencias o `find` no está disponible en el entorno, los alias/comandos pueden apuntar a un script inesperado o fallar.
* **devtools:** se retiraron los comandos/atajos provistos por esos scripts (p. ej., `git acp`, `git feature`, `git gp`, `git pr`, `git promote`, `git rp` y `setup-wizard`); actualiza tus alias, documentación y pipelines.

### Features

* **ci:** añadir menú por niveles para ejecutar CI local y exponer `git-ci` ([aeb3afc](https://github.com/elrincondeldetective/erd-devtools/commit/aeb3afc93c4d1e9459de9525aa721aae5b955af3))
* **ci:** detectar `task ci`/`task ci:act`/`task pipeline:local` de forma estricta y añadir `git-pipeline` ([8453a9d](https://github.com/elrincondeldetective/erd-devtools/commit/8453a9d1b2db0c5491491bf749a60b1dc5818607))
* **ci:** detectar contrato `task ci`/`task ci:act` y añadir `git-pipeline` para ejecutar `task pipeline:local` ([863f07b](https://github.com/elrincondeldetective/erd-devtools/commit/863f07b569d2f3e625af22af80c258852b723a57))
* **ci:** enriquecer menú post-push con acciones rápidas y ayuda ([e2d0eca](https://github.com/elrincondeldetective/erd-devtools/commit/e2d0ecaeed66badcf2e2e8996d72e927c3667659))
* **ci:** mejora detección de CI y flujo post-push ([773afa3](https://github.com/elrincondeldetective/erd-devtools/commit/773afa3c0405d6b32e70d24aa20e3bc4cfe25bf8))
* **ci:** mostrar panel de entorno y añadir fallback seguro para `act` ([1bc9156](https://github.com/elrincondeldetective/erd-devtools/commit/1bc91568def4b2190772b36cf49f76bbc6570acf))
* **devbox:** autodetecta scripts de .devtools y actualiza alias automáticamente ([9973764](https://github.com/elrincondeldetective/erd-devtools/commit/9973764c51a3a1db0701ebac40c25153bbd818d7))
* **devtools:** agrega `git-profile` y refuerza modelo de identidades V1 ([4196fb6](https://github.com/elrincondeldetective/erd-devtools/commit/4196fb697208e78827254b06efcead0af7b8cc4b))
* **devtools:** agrega `github-core` para gestionar PRs con `gh` ([0c686c5](https://github.com/elrincondeldetective/erd-devtools/commit/0c686c5692805ff02bb686d0b27c51014f6f497a))
* **devtools:** agrega herramientas git y automatiza versionado con release-please ([f406e39](https://github.com/elrincondeldetective/erd-devtools/commit/f406e39bd39c1f4576a3d8c2348bedcf3361ff21))
* **devtools:** agrega modo `sync` y refactoriza `git-promote` con `release-flow` ([280b6cf](https://github.com/elrincondeldetective/erd-devtools/commit/280b6cf7ede98cb8036754a7561ee230e78716dc))
* **devtools:** refuerza `git promote sync` con identidad y absorción automática ([748d8da](https://github.com/elrincondeldetective/erd-devtools/commit/748d8da393c24e6d71f708048f9163bd1e27ecdc))
* **devtools:** versiona el esquema de perfiles y endurece el parseo en `ssh-ident` ([b3e4882](https://github.com/elrincondeldetective/erd-devtools/commit/b3e488295dc0377a3b7e53c57aa5e4b33b22cb77))
* **devx:** sugerir comandos de logs cuando Compose está activo ([9780523](https://github.com/elrincondeldetective/erd-devtools/commit/9780523fbac6b22e56f3e18effcdc6834e7d3041))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([353f90e](https://github.com/elrincondeldetective/erd-devtools/commit/353f90e31467f1cb2a7819e8744c3a1e1c5627d6))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([f98b40f](https://github.com/elrincondeldetective/erd-devtools/commit/f98b40fb8ad2e6c825f1aed68feaba5f1b80d5c2))
* **git-promote:** mejorar flujo de trabajo con cambios automáticos de rama y validaciones ([8817579](https://github.com/elrincondeldetective/erd-devtools/commit/88175794a00671b1535b78d70c0a360fd65fb217))
* **git-tools:** añadir `git-sweep` para limpiar ramas/tags y exponer alias `git-sw`/`git-lim` ([976e6d8](https://github.com/elrincondeldetective/erd-devtools/commit/976e6d85a22b8601c739cb0e49d93a999a5a3053))
* **scripts:** automatizar migración de trabajo desde ramas protegidas a feature/* ([ed3cad2](https://github.com/elrincondeldetective/erd-devtools/commit/ed3cad26fb1755b2f072922c9b6af62e17322738))
* **scripts:** implementar política estricta de ramas feature y PR automáticos ([e82cf77](https://github.com/elrincondeldetective/erd-devtools/commit/e82cf77c707d51e1cfa5118c07dcd86d127b02e4))
* **setup:** automatizar configuración de identidad, SSH y entorno en el wizard ([ce7acdd](https://github.com/elrincondeldetective/erd-devtools/commit/ce7acdd00d40d7eafec79236c9f45375806b5932)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** separa firma GPG y conexión SSH en `setup-wizard` ([17f64cb](https://github.com/elrincondeldetective/erd-devtools/commit/17f64cbc95a48b53e1f3334fad70d693f26774e1))
* **wizard:** refuerza `setup-wizard` para submódulos y mejora flujo SSH/GitHub ([ef1bed8](https://github.com/elrincondeldetective/erd-devtools/commit/ef1bed8328668a3a746c79876ebd176e17f6ad8a))


### Bug Fixes

* **acp:** cargar `ui/styles.sh` antes de `git-flow.sh` en `bin/git-acp.sh` ([edb2db3](https://github.com/elrincondeldetective/erd-devtools/commit/edb2db37bfc976041b0e32a77236345acf8d4775))
* **ci:** endurecer flujo post-push con fallbacks de UI y gate obligatorio ([6f8cd35](https://github.com/elrincondeldetective/erd-devtools/commit/6f8cd358649a7a1128b8b43d949866a94bd647d4))
* **ci:** evitar comandos de CI cacheados y desactivar fallback a `act` ([6516e72](https://github.com/elrincondeldetective/erd-devtools/commit/6516e724171535948f6fe5a3d7ac6ad8f78efc56))
* **ci:** evitar fallos por variables no definidas y robustecer detección en `lib/ci-workflow.sh` ([975bbbf](https://github.com/elrincondeldetective/erd-devtools/commit/975bbbf2cbcd5303b3a8996a9fcd3d6495de1083))
* **ci:** hacer `task_exists` más confiable al parsear `task --list` ([f9837e6](https://github.com/elrincondeldetective/erd-devtools/commit/f9837e6d7b9da8890d76c33cb8c1103ee666090f))
* **ci:** robustecer detección de comandos y evitar fallos con `set -u` en `lib/ci-workflow.sh` ([269085c](https://github.com/elrincondeldetective/erd-devtools/commit/269085cfadec847749d5a4ff903344cf88fea12c))
* **devbox:** actualiza alias y comandos para usar .devtools/bin ([168ebd4](https://github.com/elrincondeldetective/erd-devtools/commit/168ebd48f3c3fe79b6a4b174610aa959bb595998))
* **devbox:** corregir rutas de scripts y simplificar configuración del entorno ([2fde055](https://github.com/elrincondeldetective/erd-devtools/commit/2fde055349c08a805758e221382c0414509ab65d))
* **devbox:** hace más robusto el auto-discovery de scripts en .devtools ([a96e203](https://github.com/elrincondeldetective/erd-devtools/commit/a96e203ca2f3a22ae82e9cb3d34e92d7912107b1))
* **devbox:** revertir variables de starship y mejorar detección de ruta raíz para configuración ([581e6b4](https://github.com/elrincondeldetective/erd-devtools/commit/581e6b4cfebb48b715da0308d3a65cd68b15ba08))
* **git-acp:** corregir detección de formato de firma y manejo de llaves SSH ([46d8e0f](https://github.com/elrincondeldetective/erd-devtools/commit/46d8e0ffc79d535995db6624a4063ab582435e95))
* **scripts:** corregir el valor de la variable MODE en git-feature.sh ([6d4633f](https://github.com/elrincondeldetective/erd-devtools/commit/6d4633f9cb33f7754a0e40666b47f107a196e8ed)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** hace idempotente `setup-wizard` y añade modo `--verify-only` ([5caf7ab](https://github.com/elrincondeldetective/erd-devtools/commit/5caf7ab61f5623b1ac6449e2b235bfbda4bc7be5))
* **wizard:** corrige detección TTY y endurece manejo de `set -e` y `ssh-add` ([6f11d1c](https://github.com/elrincondeldetective/erd-devtools/commit/6f11d1ccb2059eb105d77bc00e7159fc1beffbd4))
* **wizard:** endurece `setup-wizard` con bypass y verificaciones seguras ([459c0dc](https://github.com/elrincondeldetective/erd-devtools/commit/459c0dc48d52595b73d08c487a9dfa0ba10cdb4e))
* **wizard:** endurece `setup-wizard` para submódulos, CI y firma SSH ([1477db8](https://github.com/elrincondeldetective/erd-devtools/commit/1477db8e714763a8c14414fcef219b6210a146a5))
* **wizard:** endurece helpers y asegura escrituras atómicas de perfiles ([4e635f6](https://github.com/elrincondeldetective/erd-devtools/commit/4e635f605808c96ca5265d5a85529b11f944a2f3))
* **wizard:** evita fallo en `--verify-only` cuando falta `git_get` ([36e33ed](https://github.com/elrincondeldetective/erd-devtools/commit/36e33edf80130408dd0facef8c218fafd571a1b9))
* **wizard:** mejora registro de perfiles y protege cambio de remote a SSH ([cacccee](https://github.com/elrincondeldetective/erd-devtools/commit/cacccee7441b47072af68e2125bdc1bac92bebd4))


### Miscellaneous Chores

* **devtools:** elimina scripts de automatización de Git ([848c6b7](https://github.com/elrincondeldetective/erd-devtools/commit/848c6b71c84a5c77684d3aee2082303389619150))


### Code Refactoring

* **devtools:** reorganiza librerías en `lib/core` y modulariza `setup-wizard` ([4ff3483](https://github.com/elrincondeldetective/erd-devtools/commit/4ff3483a046bb4334baf02146c4735c1bd56cabe))
* **setup:** divide `setup-wizard` en pasos y añade modo de verificación ([059d3c5](https://github.com/elrincondeldetective/erd-devtools/commit/059d3c5f97ab2358973a7212a9394f14739e4fb3))

## [1.1.0](https://github.com/elrincondeldetective/erd-devtools/compare/erd-devtools-v1.0.0...erd-devtools-v1.1.0) (2026-01-24)


### Features

* **ci:** mejora detección de CI y flujo post-push ([773afa3](https://github.com/elrincondeldetective/erd-devtools/commit/773afa3c0405d6b32e70d24aa20e3bc4cfe25bf8))


### Bug Fixes

* **acp:** cargar `ui/styles.sh` antes de `git-flow.sh` en `bin/git-acp.sh` ([edb2db3](https://github.com/elrincondeldetective/erd-devtools/commit/edb2db37bfc976041b0e32a77236345acf8d4775))
* **ci:** evitar fallos por variables no definidas y robustecer detección en `lib/ci-workflow.sh` ([975bbbf](https://github.com/elrincondeldetective/erd-devtools/commit/975bbbf2cbcd5303b3a8996a9fcd3d6495de1083))

## [1.0.0](https://github.com/elrincondeldetective/erd-devtools/compare/erd-devtools-v0.1.0...erd-devtools-v1.0.0) (2026-01-24)


### ⚠ BREAKING CHANGES

* **setup:** se eliminó el script monolítico `_old_setup-wizard` y cambió la estructura del wizard a módulos en `lib/wizard/`; cualquier automatización que dependía de funciones inline debe actualizarse.
* **devtools:** los imports y rutas de librerías cambiaron de `lib/*.sh` a `lib/core/*.sh`; cualquier script externo que `source`e `lib/config.sh`, `lib/utils.sh` o `lib/git-core.sh` debe actualizarse.
* **setup:** `setup-wizard` deja de generar llaves SSH y de registrar perfiles en `.devtools/.git-acprc`; ahora asume llaves GPG/SSH existentes y solo configura firma y transporte.
* **devbox:** los comandos ahora dependen de `find` para localizar scripts; si hay múltiples coincidencias o `find` no está disponible en el entorno, los alias/comandos pueden apuntar a un script inesperado o fallar.
* **devtools:** se retiraron los comandos/atajos provistos por esos scripts (p. ej., `git acp`, `git feature`, `git gp`, `git pr`, `git promote`, `git rp` y `setup-wizard`); actualiza tus alias, documentación y pipelines.

### Features

* **ci:** añadir menú por niveles para ejecutar CI local y exponer `git-ci` ([aeb3afc](https://github.com/elrincondeldetective/erd-devtools/commit/aeb3afc93c4d1e9459de9525aa721aae5b955af3))
* **ci:** detectar `task ci`/`task ci:act`/`task pipeline:local` de forma estricta y añadir `git-pipeline` ([8453a9d](https://github.com/elrincondeldetective/erd-devtools/commit/8453a9d1b2db0c5491491bf749a60b1dc5818607))
* **ci:** detectar contrato `task ci`/`task ci:act` y añadir `git-pipeline` para ejecutar `task pipeline:local` ([863f07b](https://github.com/elrincondeldetective/erd-devtools/commit/863f07b569d2f3e625af22af80c258852b723a57))
* **devbox:** autodetecta scripts de .devtools y actualiza alias automáticamente ([9973764](https://github.com/elrincondeldetective/erd-devtools/commit/9973764c51a3a1db0701ebac40c25153bbd818d7))
* **devtools:** agrega `git-profile` y refuerza modelo de identidades V1 ([4196fb6](https://github.com/elrincondeldetective/erd-devtools/commit/4196fb697208e78827254b06efcead0af7b8cc4b))
* **devtools:** agrega `github-core` para gestionar PRs con `gh` ([0c686c5](https://github.com/elrincondeldetective/erd-devtools/commit/0c686c5692805ff02bb686d0b27c51014f6f497a))
* **devtools:** agrega herramientas git y automatiza versionado con release-please ([f406e39](https://github.com/elrincondeldetective/erd-devtools/commit/f406e39bd39c1f4576a3d8c2348bedcf3361ff21))
* **devtools:** agrega modo `sync` y refactoriza `git-promote` con `release-flow` ([280b6cf](https://github.com/elrincondeldetective/erd-devtools/commit/280b6cf7ede98cb8036754a7561ee230e78716dc))
* **devtools:** refuerza `git promote sync` con identidad y absorción automática ([748d8da](https://github.com/elrincondeldetective/erd-devtools/commit/748d8da393c24e6d71f708048f9163bd1e27ecdc))
* **devtools:** versiona el esquema de perfiles y endurece el parseo en `ssh-ident` ([b3e4882](https://github.com/elrincondeldetective/erd-devtools/commit/b3e488295dc0377a3b7e53c57aa5e4b33b22cb77))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([353f90e](https://github.com/elrincondeldetective/erd-devtools/commit/353f90e31467f1cb2a7819e8744c3a1e1c5627d6))
* **git-acp:** rediseñar flujo post-push e integrar CI local interactivo ([f98b40f](https://github.com/elrincondeldetective/erd-devtools/commit/f98b40fb8ad2e6c825f1aed68feaba5f1b80d5c2))
* **git-promote:** mejorar flujo de trabajo con cambios automáticos de rama y validaciones ([8817579](https://github.com/elrincondeldetective/erd-devtools/commit/88175794a00671b1535b78d70c0a360fd65fb217))
* **git-tools:** añadir `git-sweep` para limpiar ramas/tags y exponer alias `git-sw`/`git-lim` ([976e6d8](https://github.com/elrincondeldetective/erd-devtools/commit/976e6d85a22b8601c739cb0e49d93a999a5a3053))
* **scripts:** automatizar migración de trabajo desde ramas protegidas a feature/* ([ed3cad2](https://github.com/elrincondeldetective/erd-devtools/commit/ed3cad26fb1755b2f072922c9b6af62e17322738))
* **scripts:** implementar política estricta de ramas feature y PR automáticos ([e82cf77](https://github.com/elrincondeldetective/erd-devtools/commit/e82cf77c707d51e1cfa5118c07dcd86d127b02e4))
* **setup:** automatizar configuración de identidad, SSH y entorno en el wizard ([ce7acdd](https://github.com/elrincondeldetective/erd-devtools/commit/ce7acdd00d40d7eafec79236c9f45375806b5932)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** separa firma GPG y conexión SSH en `setup-wizard` ([17f64cb](https://github.com/elrincondeldetective/erd-devtools/commit/17f64cbc95a48b53e1f3334fad70d693f26774e1))
* **wizard:** refuerza `setup-wizard` para submódulos y mejora flujo SSH/GitHub ([ef1bed8](https://github.com/elrincondeldetective/erd-devtools/commit/ef1bed8328668a3a746c79876ebd176e17f6ad8a))


### Bug Fixes

* **devbox:** actualiza alias y comandos para usar .devtools/bin ([168ebd4](https://github.com/elrincondeldetective/erd-devtools/commit/168ebd48f3c3fe79b6a4b174610aa959bb595998))
* **devbox:** corregir rutas de scripts y simplificar configuración del entorno ([2fde055](https://github.com/elrincondeldetective/erd-devtools/commit/2fde055349c08a805758e221382c0414509ab65d))
* **devbox:** hace más robusto el auto-discovery de scripts en .devtools ([a96e203](https://github.com/elrincondeldetective/erd-devtools/commit/a96e203ca2f3a22ae82e9cb3d34e92d7912107b1))
* **devbox:** revertir variables de starship y mejorar detección de ruta raíz para configuración ([581e6b4](https://github.com/elrincondeldetective/erd-devtools/commit/581e6b4cfebb48b715da0308d3a65cd68b15ba08))
* **git-acp:** corregir detección de formato de firma y manejo de llaves SSH ([46d8e0f](https://github.com/elrincondeldetective/erd-devtools/commit/46d8e0ffc79d535995db6624a4063ab582435e95))
* **scripts:** corregir el valor de la variable MODE en git-feature.sh ([6d4633f](https://github.com/elrincondeldetective/erd-devtools/commit/6d4633f9cb33f7754a0e40666b47f107a196e8ed)), closes [#2](https://github.com/elrincondeldetective/erd-devtools/issues/2)
* **setup:** hace idempotente `setup-wizard` y añade modo `--verify-only` ([5caf7ab](https://github.com/elrincondeldetective/erd-devtools/commit/5caf7ab61f5623b1ac6449e2b235bfbda4bc7be5))
* **wizard:** corrige detección TTY y endurece manejo de `set -e` y `ssh-add` ([6f11d1c](https://github.com/elrincondeldetective/erd-devtools/commit/6f11d1ccb2059eb105d77bc00e7159fc1beffbd4))
* **wizard:** endurece `setup-wizard` con bypass y verificaciones seguras ([459c0dc](https://github.com/elrincondeldetective/erd-devtools/commit/459c0dc48d52595b73d08c487a9dfa0ba10cdb4e))
* **wizard:** endurece `setup-wizard` para submódulos, CI y firma SSH ([1477db8](https://github.com/elrincondeldetective/erd-devtools/commit/1477db8e714763a8c14414fcef219b6210a146a5))
* **wizard:** endurece helpers y asegura escrituras atómicas de perfiles ([4e635f6](https://github.com/elrincondeldetective/erd-devtools/commit/4e635f605808c96ca5265d5a85529b11f944a2f3))
* **wizard:** evita fallo en `--verify-only` cuando falta `git_get` ([36e33ed](https://github.com/elrincondeldetective/erd-devtools/commit/36e33edf80130408dd0facef8c218fafd571a1b9))
* **wizard:** mejora registro de perfiles y protege cambio de remote a SSH ([cacccee](https://github.com/elrincondeldetective/erd-devtools/commit/cacccee7441b47072af68e2125bdc1bac92bebd4))


### Miscellaneous Chores

* **devtools:** elimina scripts de automatización de Git ([848c6b7](https://github.com/elrincondeldetective/erd-devtools/commit/848c6b71c84a5c77684d3aee2082303389619150))


### Code Refactoring

* **devtools:** reorganiza librerías en `lib/core` y modulariza `setup-wizard` ([4ff3483](https://github.com/elrincondeldetective/erd-devtools/commit/4ff3483a046bb4334baf02146c4735c1bd56cabe))
* **setup:** divide `setup-wizard` en pasos y añade modo de verificación ([059d3c5](https://github.com/elrincondeldetective/erd-devtools/commit/059d3c5f97ab2358973a7212a9394f14739e4fb3))
