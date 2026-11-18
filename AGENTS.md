# AGENTS.md

## Scope

- Workspace root: `C:\Users\Acer\Desktop\Proyecto de grado`.
- `controlapp_frontend/`: Flutter client.
- `contorlapp_backend/`: Node.js + TypeScript + Express + Prisma API.
- Root `package.json` only proxies backend install/build/start tasks.
- Keep the folder name `contorlapp_backend` as-is; the typo is part of the repo.

## Instruction Sources

- Existing root agent guide: this file.
- Cursor rules checked in `.cursor/rules/`: none found.
- `.cursorrules`: none found.
- Copilot instructions checked in `.github/copilot-instructions.md`: none found.
- When repo-specific guidance is missing, follow nearby code and config files.

## Build, Lint, And Test Commands

### Root

- Install backend deps: `npm run install:backend`
- Build backend via root proxy: `npm run build`
- Start backend via root proxy: `npm start`
- There is no root lint command.
- There is no root unified test command.

### Frontend (`controlapp_frontend/`)

- Install deps: `flutter pub get`
- Run app: `flutter run`
- Run app against local backend: `flutter run --dart-define=API_BASE_URL=http://localhost:4000` (el backend local escucha en el 4000; sin `API_BASE_URL` la app ya usa ese puerto)
- Probar desde el celular en la red local (solo desarrollo): `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5300 --dart-define=API_BASE_URL=http://<IP-del-PC>:3000` y en `contorlapp_backend/.env` (no se sube a git) `CORS_ALLOWED_ORIGINS=http://<IP-del-PC>:5300`. Nunca poner IPs locales en la configuración de producción.
- Analyze/lint: `flutter analyze`
- Format: `dart format lib test`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/path/to/file_test.dart`
- Run a single test by name: `flutter test --plain-name "case name" test/path/to/file_test.dart`
- Build web: `flutter build web`
- Build web with explicit API URL: `flutter build web --dart-define=API_BASE_URL=https://...`

### Backend (`contorlapp_backend/`)

- Install deps: `npm install`
- Dev server: `npm run dev`
- Compile TypeScript: `npm run build`
- Start production script: `npm start`
- Run all backend tests: `npm test`
- Run a single backend test file: `npx jest tests/path/to/file.test.ts --runInBand`
- Run a single backend test by name: `npx jest --runInBand -t "case name"`
- Prisma client generation: runs automatically via `postinstall`
- Prisma smoke script: `npm run test-prisma`
- Helper cleanup script: `npm run clear-maquinaria`
- There is no dedicated backend lint script.

## Single-Test Reality

- Frontend supports narrow test execution through `flutter test` file paths and `--plain-name`.
- Frontend has focused commerce tests in `test/commerce_service_models_test.dart`.
- Backend uses Jest with `ts-jest` from `contorlapp_backend/tests/`.
- Backend supports narrow execution through `npx jest tests/path/to/file.test.ts --runInBand` and `npx jest --runInBand -t "case name"`.
- `npm run test-prisma` remains a Prisma smoke script, not a replacement for the Jest suite.
- Backend DB-backed test (omitido sin variable): `TEST_DATABASE_URL=<url de una base cuyo nombre contenga "test"> npx jest tests/integration/catalogo-operativo.db.test.ts --runInBand`. Nunca apuntarlo a la base de desarrollo.
- Frontend tiene `test/catalogo_operativo_models_test.dart` (categorías, perfiles, preventivas y tareas con categoría).
- Categorías/perfiles/asignación por capacidades: ver `docs/categorias-perfiles-operativos.md`.
- Agenda de recursos (necesidad vs reserva, restricciones de exclusión, triggers): ver `docs/agenda-recursos.md`.
- Backend DB-backed de agenda (omitido sin variable): `TEST_DATABASE_URL=<url de una base cuyo nombre contenga "test"> npx jest tests/integration/agenda-recursos.db.test.ts --runInBand`.
- Lógica pura de la agenda: `npx jest tests/unit/reserva-recurso.unit.test.ts --runInBand`.
- Frontend agenda de recursos: `flutter test test/recurso_agenda_model_test.dart` y `flutter test test/recursos_widgets_test.dart`.
- Cronograma accesible (vistas Hoy/Semana/Mes, Mis actividades del operario, cierre guiado): ver `docs/cronograma-claro.md`. Solo administrador y operario usan `CronogramaClaroPage`; gerente, jefe de operaciones y supervisor siguen con `CronogramaPage` (su vista Semanal ya usa las mismas tarjetas: estado + ícono de categoría).
- Cambio de titular de una plaza (Reemplazar/Liberar/Asignar): las actividades pendientes del cronograma publicado y del borrador pasan al nuevo titular; ver `docs/categorias-perfiles-operativos.md`. Backend: `npx jest tests/unit/plaza-titular-sync.unit.test.ts tests/unit/conjunto-necesidad.unit.test.ts --runInBand`.
- Cambiar operarios de una tarea o excluida (borrador y excluidas del publicado) admite varios a la vez (`nuevosOperariosIds`). Frontend: `flutter test test/seleccionar_operarios_sheet_test.dart`; backend: `npx jest tests/unit/cronograma-excluidas.unit.test.ts --runInBand`.
- Frontend cronograma, lógica pura (estados, colores con contraste, simultáneas, progreso): `flutter test test/cronograma_visual_test.dart`.
- Vistas Mensual/Semanal/Diaria del cronograma del equipo (definitivo `CronogramaPage` y borrador): matriz por ubicación u operario con iniciales de color, semana por operario con barra de carga, día por operario con panel de detalle; ver `docs/cronograma-vistas.md`. Frontend: `flutter test test/vistas_cronograma_test.dart`.
- Frontend cronograma, widgets y accesibilidad (`meetsGuideline`, letra al 200 %, cierre guiado): `flutter test test/cronograma_widgets_test.dart`.
- Impresión del cronograma (`CronogramaImpresionPage`, PDF en `lib/pdf/cronograma_pdf.dart`): portada del equipo + una hoja por operario y semana con la cuadrícula por horas; `lib/utils/cronograma/hoja_impresion.dart` calcula la hoja y el PDF y la vista previa (`widgets/cronograma/hoja_impresion_vista.dart`) la dibujan igual. Ver "Impresión" en `docs/cronograma-claro.md`. Frontend: `flutter test test/cronograma_impresion_test.dart` (con `--dart-define=PDF_SALIDA=<ruta.pdf>` guarda el PDF de muestra).
- Actividades especiales (correctivas) arrastradas al cronograma: se reemplazan las tareas de todos sus operarios, previsualización `POST /gerente/tareas/reemplazo/impacto` (huecos, bloqueos, recurso ocupado, horario sugerido) y diálogo `ImpactoEspecialDialog`; el formulario solo ofrece operarios con plaza y las máquinas propias del conjunto. Ver `docs/actividades-especiales-reemplazo.md`. Backend: `npx jest tests/unit/correctiva-impacto.unit.test.ts --runInBand`. Frontend: `flutter test test/impacto_especial_test.dart`.
- Backend actividades del operario e ícono de categoría: `npx jest tests/unit/operario-actividades.unit.test.ts --runInBand`.
- Migración de datos a la agenda (simulación por defecto): `npm --prefix contorlapp_backend run migrar-agenda-recursos [-- --apply]`.
- Marca de agua de auditoría en evidencias (hora de la foto, conjunto, calle/barrio/ciudad por GPS, distancia al conjunto): ver `docs/marca-agua-evidencias.md`. Backend: `npx jest tests/unit/marca-agua-evidencia.unit.test.ts tests/unit/direccion-gps.unit.test.ts tests/unit/drive-carpetas-cache.unit.test.ts --runInBand`. Frontend: `flutter test test/evidencia_captura_test.dart test/exif_captura_test.dart` (hora/GPS del EXIF en fotos de galería); optimizador de fotos en navegador real: `flutter test --platform chrome test/optimizar_imagen_web_test.dart`. La fuente va dentro del código (`src/utils/fuente_roboto_bold.ts`, base64 de `assets/fonts/Roboto-Bold.ttf`; regenerar con `node scripts/generar-fuente-marca-agua.js`), no depende de qué copie el despliegue; no volver a leerla de un archivo.
- Ubicación del dispositivo: usar `UbicacionDispositivo` (`lib/service/ubicacion_service.dart`), no geolocator directo (en web geolocator_web 4.1.x pasa el tiempo límite en microsegundos). La asistencia por QR exige ubicación siempre: la app no abre el escáner sin ella y el backend rechaza el registro. Frontend: `flutter test test/ubicacion_asistencia_test.dart`; backend: `npx jest tests/unit/ubicacion-asistencia.unit.test.ts tests/unit/asistencia-festivos.unit.test.ts --runInBand`.
- Actualización automática de la web (sin Ctrl+F5): `web/flutter_bootstrap.js` va incrustado en `index.html` y carga `main.dart.js?v=<ETag>`; con la app abierta, `AvisoVersionNueva` ofrece actualizar. El login y el perfil muestran "Versión de la app: <fecha de publicación>" para saber qué versión tiene alguien. `web/.htaccess` (Hostinger) va en cada build: rutas a index.html + `no-cache` en los archivos de nombre fijo. Ver `docs/actualizacion-web.md`. Frontend: `flutter test test/aviso_version_nueva_test.dart test/version_web_test.dart`.
- Content-Security-Policy de la web en `web/.htaccess`: mínima obligatoria (`frame-ancestors`, `object-src`, `base-uri`) + completa en `Report-Only` hasta revisarla en producción. El arranque en línea se permite por hash: después de cada `flutter build web`, desde `controlapp_frontend`, `node scripts/csp-web.js --api <API_BASE_URL>` (actualiza el hash en `build/web/.htaccess` y `web/.htaccess`; falla si `connect-src` no permite la API). Un host o script nuevo se agrega a la directiva que toque, nunca `'unsafe-inline'`/`'unsafe-eval'`. Ver "Content-Security-Policy" en `docs/actualizacion-web.md`.
- Pagos Factus, worker y conciliación (sin `FACTUS_PAY_*` no arrancan; tras un fallo esperan 6 h; en sandbox no reportan pagos de otros entornos): `npx jest tests/unit/pagos-reconciler.unit.test.ts tests/unit/pagos-conciliacion.unit.test.ts --runInBand`.
- Plugin de la tienda `controlapp-factus-pay` 1.1 (Bre-B: QR + llave en la página de pago del pedido, se confirma solo por el aviso de Factus; Woo no cancela sola una orden con QR vigente): ver su README y `docs/pagos-factus.md` ("Flujo (tienda web)"). En el WordPress de Docker necesita `CONTROLAPP_PAGOS_SECRET` en `docker/wordpress-local/.env` (no se sube a git). Sintaxis: `docker exec wordpress-local-wordpress-1 php -l /var/www/html/wp-content/plugins/controlapp-factus-pay/includes/class-cfp-gateway.php`; backend: `npx jest tests/unit/pagos-woo-service.unit.test.ts tests/unit/pagos-woo-hmac.unit.test.ts --runInBand`.
- Seguimiento de PQRS (estados, historial inmutable, evidencias y notificación al administrador): `npx jest tests/unit/compromiso-seguimiento.unit.test.ts tests/unit/evidencia-acceso.unit.test.ts tests/integration/permissions-routing.integration.test.ts --runInBand`; frontend: `flutter test test/compromiso_model_test.dart`.
- Saldo de servicios con anticipo y mora: al terminar el servicio (reserva `completada` en el marketplace) se registra el saldo, se cobra con un recaudo nuevo (canal `SALDO_SERVICIO`, `SA-`) y, mientras esté pendiente, el servidor no deja pedir en la app ni en la web (por cuenta, correo o teléfono). Panel "Clientes en mora" con permisos `comercio.mora.ver/gestionar`. Ver `docs/saldos-servicio.md`. Backend: `npx jest tests/unit/saldo-servicio.unit.test.ts tests/unit/pagos-service.unit.test.ts tests/unit/commerce-service-order.unit.test.ts --runInBand`. Frontend: `flutter test test/saldo_servicio_model_test.dart`.
- Webhook de Factus Pay (`POST /commerce/webhooks/factus-pay?key=`, llave en `FACTUS_PAY_WEBHOOK_KEY`): el aviso no confirma nada por sí solo, se guarda en `PagoWebhookFactus` y dispara la verificación por API; toda escritura de estado del cobro es condicional (worker, "Ya pagué" y webhook pueden consultar a la vez). Ver `docs/pagos-factus.md` ("Webhook"). Backend: `npx jest tests/unit/factus-webhook.unit.test.ts tests/unit/factus-webhook-http.unit.test.ts tests/unit/pagos-concurrencia.unit.test.ts tests/unit/pagos-service.unit.test.ts --runInBand`.
- Modo de confirmación de pagos (`PAGOS_MODO_CONFIRMACION=polling|webhook`, degradado automático a sondeo si un pago llega sin aviso del webhook), QR alineado a la vigencia de Factus (24 h, sin `FACTUS_PAY_EXPIRA_MIN`), "Verificar con Factus" y salud en el panel, conciliación con doble verificación y cierre de vencidos: ver `docs/pagos-factus.md`. Backend: `npx jest tests/unit/pagos-salud.unit.test.ts tests/unit/pagos-vigencia.unit.test.ts tests/unit/pagos-conciliacion-v2.unit.test.ts tests/unit/pagos-admin.unit.test.ts --runInBand`. Frontend: `flutter test test/pago_admin_models_test.dart test/pago_cobro_info_test.dart`.
- Marketplace de operarios (WordPress): el cliente ya no elige operario; el equipo lo asigna desde el pedido o `POST /clmk/v1/reservas/{id}/operario`. Ver `docs/marketplace-operarios.md`. Sintaxis: `docker exec wordpress-local-wordpress-1 php -l /var/www/html/wp-content/plugins/control-marketplace/<archivo>`.
- Landing de inicio (Elementor, página 2327 del WordPress): fuente y checklist de producción/AIOSEO en `docs/landing-seo/`.
- Documentos de los formularios web (registro de conjuntos, postulación de trabajadores) a Google Drive vía el plugin puente `controlapp-archivos-drive` + pantalla de solo lectura "Solicitudes de la web" (gerente / jefe de operaciones, permiso `web.solicitudes.ver`): ver `docs/solicitudes-web-drive.md`. Backend: `npx jest tests/unit/web-archivos-hmac.unit.test.ts tests/unit/drive-archivos-web.unit.test.ts tests/unit/solicitudes-web.unit.test.ts tests/unit/pagos-woo-hmac.unit.test.ts --runInBand`. Frontend: `flutter test test/solicitudes_web_model_test.dart`.
- Postulaciones desde la app: marcar revisada o borrar (permiso `web.solicitudes.gestionar`; WordPress se niega si la persona tiene reservas). Formularios de "Trabaja con nosotros" y "Registro Conjunto" en HTML para Elementor, que piden nonce y opciones por admin-ajax: ver `docs/formularios-web/README.md`. Mismas pruebas que la línea anterior.
- Informe detallado personalizable en PDF (plantillas, filtros, secciones de auditoría, fotos, retomar el informe en curso; el administrador no recibe datos internos): ver `docs/informe-detallado.md`. Backend: `npx jest tests/unit/informe-mensual.unit.test.ts tests/unit/informe-mensual-opciones.unit.test.ts tests/integration/informe-mensual-pdf.integration.test.ts --runInBand`. Frontend: `flutter test test/informe_detallado_opciones_test.dart` y `flutter test test/informe_detallado_opciones_sheet_test.dart`.
- Sesiones seguras (auditoría de seguridad, Fase 0 del plan MCP): JWT con emisor/audiencia fijos (`src/utils/jwtSesion.ts`), estado de sesión contrastado con la BD en cada petición (activo, rol, `Usuario.versionSesion`, contraseña temporal pendiente; `src/services/SesionService.ts`), web con token corto en memoria + cookie HttpOnly `ca_sesion` rotativa (`POST /auth/refresh`, detección de reuso), recuperación con correo + cédula desactivada (410; la restablece un gerente/jefe y queda temporal), log de acceso JSON (`src/middlewares/access-log.middleware.ts`). Ver `docs/convenciones-seguridad.md`. Backend: `npx jest tests/unit/sesion-segura.unit.test.ts tests/unit/registro-acceso.unit.test.ts tests/integration/gerente-carga-conjunto.integration.test.ts --runInBand`. Frontend: `flutter test test/sesion_web_token_test.dart`.
- Alcance del administrador (cliente) en reportes, informe PDF y asistencia: solo sus conjuntos; uno ajeno → 404 (`src/aplicacion/alcanceConjuntos.ts`, reutilizable fuera de Express). Backend: `npx jest tests/unit/alcance-administrador.unit.test.ts tests/integration/informe-mensual-pdf.integration.test.ts --runInBand`.
- Vista de tabla de usuarios (planilla de personal) en "Gestión de usuarios" y "Usuarios del conjunto": todas las columnas del usuario, "Días para vacaciones" (aniversario de ingreso + vacaciones de Asistencia), esconder/reordenar columnas (arrastrando el título), agrupar por conjunto o rol, copiar para Excel; se recuerda por dispositivo. `GET /gerente/usuarios/planilla` (`src/services/PlanillaPersonalService.ts`, sin contraseña, mismo alcance que la lista; no se expone por MCP). Ver `docs/planilla-personal.md`. Backend: `npx jest tests/unit/planilla-personal.unit.test.ts --runInBand`. Frontend: `flutter test test/planilla_usuarios_test.dart test/planilla_usuarios_widgets_test.dart`.
- Hoja de vida del usuario: ARL y caja de compensación (enums `ARL` y `CajaCompensacion`, se escogen de lista) y contacto de emergencia (nombre, parentesco, teléfono), opcionales, en crear/editar/detalle de usuario, edición rápida del administrador, carga masiva (hoja Operarios; regenerar `docs/plantillas/plantilla_conjunto.xlsx` con `npx tsx scripts/generar-plantilla-conjunto.ts` desde `contorlapp_backend`) y columnas de la planilla. `Usuario.nombre` sigue siendo el nombre completo (sin apellido aparte). No se exponen por MCP. Ver "ARL, caja de compensación y contacto de emergencia" en `docs/planilla-personal.md`. Backend: `npx jest tests/unit/usuario-hoja-vida.unit.test.ts tests/unit/conjunto-excel.unit.test.ts tests/unit/planilla-personal.unit.test.ts --runInBand`. Frontend: `flutter test test/hoja_vida_usuario_test.dart test/planilla_usuarios_test.dart`.
- Jerarquía al gestionar usuarios (`src/utils/jerarquiaRoles.ts`): solo un gerente toca gerentes o asigna `rol: "gerente"`; los demás, solo roles inferiores; nadie cambia su propio rol o `activo`. También la usa el restablecimiento de contraseñas. Cambios de usuarios, roles, matriz de permisos y traslados quedan en `AuditoriaEvento` (PERSONAL/SEGURIDAD). Backend: `npx jest tests/unit/jerarquia-roles.unit.test.ts tests/unit/gerente-operario-necesidades.unit.test.ts --runInBand`.
- Ediciones rápidas (`PATCH /gerente/administradores|operarios|supervisores/:id`): rechazan `rol`, `activo`, `contrasena` y `empresaId` (`camposFueraDeEdicionRapida` en `src/model/Usuario.ts`); eso solo cambia por `PATCH /gerente/usuarios/:id`. `POST /gerente/administradores/reemplazos` exige conjuntos de la empresa y un administrador nuevo existente, activo y sin conjuntos de otra empresa; aplica todo o nada y audita cada cambio (PERSONAL, `REEMPLAZAR`). Backend: `npx jest tests/unit/gerente-ediciones-rapidas.unit.test.ts --runInBand`.
- `GET /evidencias/:fileId` solo sirve archivos de una tarea, diagnóstico o comprobante que el usuario ya puede ver (si no, 404; los documentos web no salen por aquí): `src/services/EvidenciaAccesoService.ts`. Backend: `npx jest tests/unit/evidencia-acceso.unit.test.ts --runInBand`.
- `GET /tarea` y `GET /tarea/:id` por rol (gerente/jefe: empresa; administrador: sus conjuntos; supervisor: las que supervisa; operario: las suyas publicadas) y tope de 500 resultados. Backend: `npx jest tests/unit/tareas-alcance.unit.test.ts --runInBand`.
- Editar, eliminar y corregir cierre (`/tarea/:id`, `/gerente/tareas/:tareaId`, `/tarea-correctiva/tareas/:id`) usan el mismo alcance de lectura (`alcanceMutacionTareasPorRol`; fuera → 404; operario → 403); al crear sin supervisor, el supervisor que crea queda a cargo. Los filtros de `GET /tarea` llegan como texto y se convierten. Crear y editar por `/gerente/tareas` y `/tarea-correctiva` exigen ubicación/elemento del conjunto y supervisor/operarios de la empresa (operarios también del conjunto; en ediciones solo se revisa lo que cambia), y el administrador solo crea en sus conjuntos (fuera → 404). `GET /tarea-correctiva/conjuntos/:nit/tareas` tiene el mismo tope de 500. Ver "Alcance por rol de las tareas" en `docs/convenciones-seguridad.md`. Backend: `npx jest tests/unit/tareas-mutacion-alcance.unit.test.ts tests/unit/tareas-relaciones-alcance.unit.test.ts --runInBand`.
- MCP para gerentes (Claude/ChatGPT): servicio aparte `npm --prefix contorlapp_backend run start:mcp` (`src/mcp/`), OAuth 2.1 propio (PKCE S256, CIMD con lista blanca, refresh rotativo, RFC 8707/9207/9728/8414), herramientas que solo llaman casos de uso de `src/aplicacion/` (mismos services que la app), previsualizar + `confirmar_operacion`, aprobación en la app para alto riesgo, bitácora `McpInvocacion` y `AuditoriaEvento` con origen MCP, panel `/integraciones-ia` y página Flutter "Integraciones IA". Solo gerentes con `Gerente.mcpHabilitado` (`npm run mcp:gerente`); interruptores con `npm run mcp:config`. Ver `docs/mcp/arquitectura.md`, `docs/mcp/despliegue.md`, `docs/mcp/runbook-kill-switch.md`. **Todo módulo nuevo decide su exposición MCP** según `docs/mcp/MCP_INTEGRATION_GUIDELINES.md` (lo exige `tests/unit/mcp-catalogo.unit.test.ts`). Backend: `npx jest tests/integration/mcp-oauth.integration.test.ts tests/unit/mcp-seguridad.unit.test.ts tests/unit/mcp-catalogo.unit.test.ts tests/unit/integraciones-ia.unit.test.ts --runInBand`. Frontend: `flutter test test/integracion_ia_model_test.dart`.
- App Android sin conexión (operarios): sesión larga de la app (`sesionApp: true` + `POST /auth/refresh-app`, `SesionRefresh.canal`), cierres y asistencia QR hechos sin señal y enviados después con su hora original (`src/utils/horaSinConexion.ts`: hora estimada por reloj monotónico y desfase del reloj), rechazos con `code` (`TAREA_YA_CERRADA`, `TAREA_REASIGNADA`, …), deduplicación por `clienteCierreId`/`clienteRegistroId`, marca de agua "Enviada … (sin señal)", versión mínima `APP_ANDROID_VERSION_MINIMA` (426 `APP_DESACTUALIZADA`) y `/healthz` + `/readyz`. No se expone por MCP. Ver `docs/app-android-sin-conexion.md`. Backend: `npx jest tests/unit/sesion-app-refresh.unit.test.ts tests/unit/cierre-sin-conexion.unit.test.ts tests/unit/asistencia-sin-senal.unit.test.ts tests/unit/app-version-minima.unit.test.ts tests/unit/cierre-tarea-idempotencia.unit.test.ts --runInBand`.
- App Android sin conexión, lado Flutter: `applicationId` `co.com.controlsas.controlapp`, firma desde `android/key.properties` (sin él, debug), cliente HTTP global `lib/service/http/cliente_http_app.dart` (instalado en `main.dart` con `http.runWithClient`: `X-App-Version`, renovar ante 401 con `/auth/refresh-app`, 426, hora del servidor), arranque con el perfil guardado si no hay red (`lib/service/arranque_sesion.dart`), cola de asistencias y cierres en `TareaSyncEngine` (asistencias primero, consulta `GET .../cierres/:clienteCierreId` antes de reenviar, rechazos nunca se descartan solos) con WorkManager (`lib/service/offline/sincronizacion_fondo_io.dart`), hora estimada `lib/service/reloj_confiable.dart` (canal `controlapp/reloj` en `MainActivity.kt`), galería por `image_picker` y auto-actualización `lib/service/actualizacion_app_service.dart` (`APP_DESCARGAS_URL`). La APK no se compila en este PC (sin Android SDK). Ver "App (Flutter)" en `docs/app-android-sin-conexion.md`. Frontend: `flutter test test/sync_engine_sin_senal_test.dart test/reloj_confiable_test.dart test/actualizacion_app_test.dart test/arranque_sin_red_test.dart test/cliente_http_app_test.dart test/error_classifier_test.dart`. Publicar web + APK es un clic (Actions → "App Android y web"): el `versionCode` sale solo (publicado + 1), exige los secretos `HOSTINGER_FTP_*`, sube `descargas/android.json` de último y comprueba la descarga; `/descargas/` sin archivo da 404 y el aviso "Descarga la app" del login no sale si la APK no está publicada. Pruebas: `node controlapp_frontend/scripts/empaquetar-android.test.js` y `flutter test test/aviso_descarga_app_test.dart`.

## Minimum Validation Expectations

- Backend-only edits: run `npm --prefix contorlapp_backend run build`.
- Backend logic changes with tests available: run `npm --prefix contorlapp_backend test`.
- Frontend-only edits: run `flutter analyze` in `controlapp_frontend/`.
- Frontend behavior changes: run the narrowest relevant `flutter test` command when tests exist.
- Cross-stack API contract changes: run frontend analyze plus backend build.
- Do not invent lint/test commands that are not present in the repo.

## Frontend Style Guidelines

- Follow `dart format`; do not hand-align spacing.
- The analyzer extends `package:flutter_lints/flutter.yaml` via `controlapp_frontend/analysis_options.yaml`.
- Prefer single quotes, matching current Dart files.
- Group imports as Dart SDK, Flutter/packages, then app-local imports.
- Prefer `package:flutter_application_1/...` imports for cross-folder app code.
- Use relative imports only for very local neighbors if the file already follows that pattern.
- Use `PascalCase` for classes, enums, typedefs, and widget types.
- Use `camelCase` for methods, variables, parameters, and named arguments.
- Use leading `_` for private fields, helpers, and private widgets within a library.
- File names are snake_case; pages usually end with `_page.dart`, APIs with `_api.dart`, services with `_service.dart`.
- Prefer `final` for references and `const` wherever widgets or values are compile-time constant.
- Convert JSON to typed models or typed `Map<String, dynamic>` shapes early.
- Keep network code in `lib/api/`, `lib/service/`, or repositories, not directly in widgets.
- Reuse shared helpers such as `ApiClient`, `AppError`, `AppFeedback`, and `SessionService`.
- In async UI flows, clear stale error state before retrying and restore loading flags in `finally`.
- Use mounted-safe `setState` patterns around awaited work.
- Dispose controllers, focus nodes, animation controllers, and other owned resources.
- Avoid hardcoded localhost URLs in feature code; use existing constants or client helpers.

## Backend Style Guidelines

- Write TypeScript compatible with `strict: true` in `contorlapp_backend/tsconfig.json`.
- Note that `noImplicitAny` is disabled, but new code should still avoid unnecessary `any`.
- Prefer double quotes, matching current backend files.
- Import external packages first, then internal modules.
- Use `import type` for type-only imports when appropriate.
- Use `PascalCase` for classes and service/controller types.
- Use `camelCase` for variables, functions, methods, and local helpers.
- Preserve existing file naming patterns even when they are inconsistent (`AuthController.ts`, `authService.ts`, `GerenteServices.ts`).
- Keep route files thin: register endpoints, middleware, and controller methods only.
- Keep controllers focused on request parsing, auth extraction, Zod validation, and response shaping.
- Put business logic, Prisma access, and multi-step workflows in services.
- Reuse the shared Prisma client from `contorlapp_backend/src/db/prisma.ts`.
- Do not create ad hoc Prisma clients in controllers or services.
- Validate external input near the boundary with `zod` schemas.
- Prefer `async`/`await` over chained promises.
- Keep nullability explicit in Prisma selects/includes and returned objects.
- Use transactions for multi-step writes that must stay consistent.
- Let shared middleware or central error handling perform final HTTP serialization.
- Do not bypass existing auth, role, or request-user patterns.

## Naming And Domain Conventions

- Keep business nouns in Spanish when they already exist in schema, routes, or UI.
- Mirror API field names exactly in DTOs and JSON payloads.
- Preserve established identifiers such as `conjuntoId`, `operarioId`, `supervisorId`, `tareaId`, `nit`, `correo`, and `contrasena`.
- Avoid translating Prisma enum values or route segments unless the contract is intentionally changing.
- Match local naming near the edited file before normalizing anything broadly.

## Error Handling

- Prefer actionable, user-readable messages over raw technical failures.
- Frontend should convert thrown values with `AppError.messageOf(...)` before display when possible.
- Backend services may throw status-bearing errors when HTTP status matters.
- Do not leak stack traces, SQL details, secrets, or env var names to clients.
- Silent failure is acceptable only for explicit best-effort cleanup paths.

## Dependency And Import Rules

- Prefer existing workspace tools and libraries before adding dependencies.
- For backend validation and schema checks, prefer existing `zod` and Prisma patterns.
- For frontend utilities, prefer Flutter/Dart SDK facilities before new packages.
- Do not modify both app manifests for a single-app change.

## Agent Workflow

- Inspect neighboring files before editing so local conventions win over generic style advice.
- Keep changes minimal and targeted unless the task explicitly asks for refactoring.
- After backend edits, default to `npm --prefix contorlapp_backend run build`.
- After frontend edits, default to `flutter analyze` and the narrowest relevant `flutter test` command.
- If you add the first real backend or frontend tests, update this file with the exact commands.
- If a validation command cannot run in the current environment, say so explicitly in your handoff.

## Known Gaps

- No Cursor or Copilot instruction files exist today.
- No root-level lint or test orchestration exists.
- No backend lint script exists.
- Backend single-test workflow is Jest-based rather than npm-script-based.
- Commerce service parsing and payment calculations are covered by `flutter test test/commerce_service_models_test.dart`.
