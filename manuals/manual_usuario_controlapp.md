# Manual de Usuario Completo — ControlApp

**Producto:** Control Limpieza S.A.S. (ControlApp)  
**Versión del manual:** 2.0 (revisión integral)  
**Fecha:** 12 de abril de 2026  
**Audiencia:** Gerente, Supervisor, Jefe de Operaciones, Administrador y Operario

---

## Índice general

1. Propósito del manual
2. ¿Qué es ControlApp y qué resuelve?
3. Roles del sistema y alcance real
4. Flujo recomendado de implementación (orden correcto)
5. Acceso, inicio de sesión y seguridad
6. Configuración inicial (solo Gerente)
7. Gestión de usuarios (crear, editar, eliminar, reasignar)
8. Gestión de conjuntos (crear y administrar)
9. Gestión de ubicaciones y elementos
10. Gestión de inventario de insumos
11. Gestión de herramientas y stock por estado
12. Gestión de maquinaria
13. Solicitudes (insumos/maquinaria/tareas)
14. Tareas correctivas (ciclo completo)
15. Tareas preventivas (definición y automatización)
16. Cronograma (mensual y semanal)
17. Agenda de maquinaria
18. Agenda de herramientas
19. Compromisos / PQRS
20. Reportes, tableros y exportables PDF
21. Notificaciones y cumpleaños
22. Flujos detallados por rol (paso a paso)
23. Reglas operativas críticas
24. Errores frecuentes y cómo resolverlos
25. Checklist diario, semanal y mensual
26. Glosario rápido

---

## 1) Propósito del manual

Este documento explica **cómo usar la aplicación en su totalidad**, no solo qué módulos existen.  
Aquí encontrará instrucciones completas para ejecutar los procesos principales:

- Crear usuarios.
- Crear conjuntos.
- Configurar inventarios y recursos.
- Crear tareas correctivas y preventivas.
- Programar, ejecutar, cerrar y aprobar tareas.
- Gestionar solicitudes.
- Controlar agendas de maquinaria y herramientas.
- Generar reportes de gestión.

> Objetivo: que cualquier equipo pueda operar ControlApp correctamente siguiendo un orden claro y sin improvisación.

---

## 2) ¿Qué es ControlApp y qué resuelve?

ControlApp es una plataforma de gestión operativa para servicios de aseo, mantenimiento, jardinería, piscina y tareas locativas en conjuntos.

Centraliza:

- Planeación (preventivas y cronogramas).
- Ejecución (tareas de campo por operarios).
- Control (aprobaciones y veredictos).
- Recursos (insumos, herramientas y maquinaria).
- Seguimiento (compromisos, PQRS, notificaciones).
- Medición (KPIs y reportes).

---

## 3) Roles del sistema y alcance real

### 3.1 Gerente

Rol con mayor alcance. Puede:

- Crear empresa, conjuntos y usuarios.
- Asignar usuarios por rol y por conjunto.
- Gestionar catálogos de insumos, herramientas y maquinaria.
- Crear tareas correctivas.
- Definir preventivas y generar cronogramas.
- Revisar reportes globales y por conjunto.
- Gestionar compromisos globales y por conjunto.

### 3.2 Supervisor

Rol de control táctico diario. Puede:

- Ver tareas del conjunto.
- Emitir veredictos de tareas (aprobación/rechazo).
- Gestionar solicitudes.
- Revisar cronograma, inventario y agendas.

### 3.3 Jefe de Operaciones

Rol de coordinación transversal. Puede:

- Atender pendientes operativos.
- Emitir veredictos de tareas.
- Gestionar solicitudes y compromisos.
- Revisar inventario, cronograma y agendas globales.

### 3.4 Administrador

Rol administrativo del conjunto asignado. Puede:

- Gestionar PQRS/compromisos de su conjunto.
- Consultar inventario, cronograma y reportes del conjunto.

### 3.5 Operario

Rol ejecutor en campo. Puede:

- Consultar tareas asignadas.
- Iniciar/ejecutar/cerrar tareas.
- Registrar observaciones e insumos usados.
- Consultar solicitudes asociadas a su operación.

---

## 4) Flujo recomendado de implementación (orden correcto)

Para usar el sistema sin bloqueos, siga este orden:

1. **Crear empresa** (si aplica en despliegue inicial).
2. **Crear usuarios clave** (gerente/supervisor/jefe/administrador/operarios).
3. **Crear conjuntos**.
4. **Configurar ubicaciones y elementos** por conjunto.
5. **Cargar catálogos** de insumos/herramientas/maquinaria.
6. **Cargar inventario inicial** del conjunto.
7. **Definir preventivas** por ubicación y elemento.
8. **Generar borrador de cronograma** y validar disponibilidad.
9. **Crear correctivas** cuando existan novedades.
10. **Ejecutar ciclo diario:** asignación → ejecución → cierre → veredicto.
11. **Revisar reportes** semanal y mensualmente.

---

## 5) Acceso, inicio de sesión y seguridad

## 5.1 Iniciar sesión

1. Abra la pantalla de login.
2. Ingrese **Correo** y **Contraseña**.
3. Pulse **Ingresar**.
4. El sistema redirige al panel correspondiente al rol.

## 5.2 Recuperar contraseña

1. En login, pulse **Recuperar acceso**.
2. Ingrese correo e identificación solicitada.
3. Defina nueva contraseña segura.
4. Vuelva a iniciar sesión.

## 5.3 Cambiar contraseña autenticado

1. En cualquier panel, pulse ícono de candado (**Cambiar contraseña**).
2. Ingrese contraseña actual.
3. Ingrese nueva contraseña.
4. Confirme y guarde.

## 5.4 Reglas de seguridad

- Si el token expira, el sistema solicitará autenticación nuevamente.
- Si un rol no tiene permiso, mostrará “No autorizado”.
- No comparta credenciales entre usuarios.

---

## 6) Configuración inicial (solo Gerente)

Este bloque se ejecuta una sola vez por cliente o en aperturas de nuevos conjuntos.

## 6.1 Crear empresa (cuando aplique)

1. Ingrese al panel de Gerente.
2. Abra la opción de configuración de empresa.
3. Registre datos principales (NIT, nombre, parámetros).
4. Guarde y valide respuesta exitosa.

## 6.2 Ajustar límites de operación

1. Defina límites de tiempo semanales (si el cliente lo requiere).
2. Ajuste horarios operativos y descansos por conjunto.
3. Verifique que los parámetros queden consistentes con el cronograma.

---

## 7) Gestión de usuarios (crear, editar, eliminar, reasignar)

## 7.1 Crear un usuario

1. En panel Gerente, ingrese a **Usuarios**.
2. Pulse **Crear usuario**.
3. Diligencie campos mínimos:
   - Nombre completo.
   - Correo (único).
   - Documento/identificación.
   - Rol.
   - Datos de contacto.
4. Guarde.
5. Si aplica, asigne conjunto(s) al usuario.

### Recomendación

Cree primero **supervisores y operarios** antes de crear tareas.

## 7.2 Editar usuario

1. Busque usuario por nombre/correo.
2. Pulse **Editar**.
3. Ajuste datos necesarios (rol, contacto, estado, etc.).
4. Guarde y confirme.

## 7.3 Eliminar usuario

1. Desde listado, pulse **Eliminar**.
2. Confirme la acción.
3. Revise impactos:
   - tareas futuras,
   - asignaciones vigentes,
   - historial.

## 7.4 Cambiar contraseña de otro usuario (Gerente)

1. Ubique al usuario objetivo.
2. Seleccione acción **Cambiar contraseña**.
3. Defina nueva clave robusta.
4. Informe al usuario para primer acceso.

## 7.5 Reasignar en bloque (cuando haya rotación)

1. Identifique conjuntos afectados.
2. Use flujos de reemplazo para administrador/supervisor/operario.
3. Valide que no queden conjuntos sin responsable.

---

## 8) Gestión de conjuntos (crear y administrar)

## 8.1 Crear un conjunto

1. En panel Gerente, vaya a **Conjuntos**.
2. Pulse **Crear conjunto**.
3. Registre:
   - NIT del conjunto.
   - Nombre.
   - Dirección.
   - Correo/medios de contacto.
   - Tipo de servicio.
4. Guarde.

## 8.2 Editar conjunto

1. Abra el detalle del conjunto.
2. Pulse **Editar**.
3. Actualice datos (servicios, consignas, valor agregado).
4. Guarde.

## 8.3 Asignar operarios al conjunto

1. En detalle del conjunto, abra **Operarios**.
2. Seleccione usuarios disponibles.
3. Confirme asignación.
4. Valide que aparezcan en filtros de creación de tareas.

## 8.4 Eliminar conjunto

Solo cuando ya no se opere allí.

1. Verifique que no existan tareas activas pendientes.
2. Exporte respaldos/reportes necesarios.
3. Ejecute eliminación con confirmación.

---

## 9) Gestión de ubicaciones y elementos

> Sin ubicaciones/elementos bien definidos, las tareas pierden trazabilidad.

## 9.1 Crear ubicación

1. Ingrese al módulo del conjunto.
2. Abra **Ubicaciones**.
3. Pulse **Agregar ubicación**.
4. Ingrese nombre descriptivo (ej. “Torre A - Lobby”).
5. Guarde.

## 9.2 Crear elemento dentro de ubicación

1. Entre a la ubicación.
2. Pulse **Agregar elemento**.
3. Ingrese nombre del elemento (ej. “Vidrio puerta principal”).
4. Guarde.

## 9.3 Estructura recomendada

- Ubicación: zona física macro.
- Elemento: punto puntual de intervención.

---

## 10) Gestión de inventario de insumos

## 10.1 Ver inventario del conjunto

1. Abra **Inventario**.
2. Seleccione pestaña **Insumos**.
3. Revise existencias, categoría y unidad.

## 10.2 Registrar entrada de insumos

1. Pulse **Agregar stock**.
2. Seleccione insumo del catálogo.
3. Ingrese cantidad.
4. Confirme movimiento.

## 10.3 Registrar consumo de insumos

1. Pulse **Consumir stock**.
2. Seleccione insumo y cantidad.
3. Registre motivo (si lo pide el formulario).
4. Guarde.

## 10.4 Revisar insumos bajos

1. Use filtro **Bajo stock / agotados**.
2. Identifique prioridad de reposición.
3. Genere solicitud de insumos desde el mismo flujo.

---

## 11) Gestión de herramientas y stock por estado

## 11.1 Ver stock de herramientas

1. En Inventario, cambie a pestaña **Herramientas**.
2. Revise columnas:
   - nombre,
   - cantidad,
   - estado,
   - modo de control,
   - tenencia/origen.

## 11.2 Cambiar estado de herramienta

1. Seleccione herramienta.
2. Pulse **Cambiar estado**.
3. Indique cantidad y nuevo estado.
4. Confirme movimiento.

## 11.3 Devolver préstamo al origen

1. Seleccione herramienta prestada.
2. Pulse **Devolver**.
3. Ingrese cantidad a devolver.
4. Confirme y verifique actualización de stock.

---

## 12) Gestión de maquinaria

## 12.1 Registrar maquinaria en catálogo

1. Abra opción **Crear maquinaria**.
2. Diligencie:
   - nombre,
   - tipo,
   - estado,
   - propietario (empresa/conjunto),
   - tenencia.
3. Guarde.

## 12.2 Editar maquinaria

1. Vaya a listado de maquinaria.
2. Pulse **Editar**.
3. Actualice estado, observación o metadatos.
4. Guarde.

## 12.3 Disponibilidad

Antes de asignar una tarea:

1. Consulte disponibilidad en rango de fechas.
2. Revise agenda de ese equipo.
3. Si hay conflicto, cambie equipo o reprogramación.

---

## 13) Solicitudes (insumos/maquinaria/tareas)

## 13.1 Solicitud de insumos (flujo completo)

1. Ingrese a **Solicitud de insumos**.
2. Revise recomendados por bajo stock.
3. Agregue ítems al carrito (cantidad por insumo).
4. Envíe solicitud.
5. Supervisor/Jefe/Gerente revisa detalle y aprueba/rechaza.

## 13.2 Gestión de solicitudes pendientes

1. Abra módulo **Solicitudes**.
2. Filtre por estado (**Pendiente**, **Aprobada**).
3. Abra detalle de cada solicitud.
4. Aplique acción:
   - **Aprobar** (habilita reposición),
   - **Rechazar** (dejar observación operativa).

## 13.3 Solicitudes de maquinaria y tareas

Aplican cuando el rol administrativo requiere escalamiento operativo.

- Registrar necesidad.
- Adjuntar contexto.
- Dar seguimiento al estado.

---

## 14) Tareas correctivas (ciclo completo)

## 14.1 Crear tarea correctiva

1. Entre a **Crear tarea**.
2. Seleccione conjunto.
3. Seleccione ubicación y elemento.
4. Ingrese descripción precisa (acción + objeto + ubicación).
5. Defina prioridad.
6. Defina fecha inicio, fecha fin y hora de inicio.
7. Defina duración en minutos.
8. Seleccione operario(s).
9. Seleccione supervisor responsable.
10. Seleccione maquinaria/herramientas requeridas.
11. Guarde.

## 14.2 Reemplazos automáticos y validaciones

Algunas reglas pueden:

- Reemplazar preventivas de baja prioridad.
- Marcar tareas afectadas como no completadas.
- Bloquear por conflicto de disponibilidad.

## 14.3 Estados de una tarea

- **ASIGNADA:** creada y programada.
- **EN_PROCESO:** ejecución en curso.
- **PENDIENTE_APROBACION:** operario cerró, falta veredicto.
- **APROBADA:** cierre validado.
- **RECHAZADA:** requiere ajuste/reproceso.
- **NO_COMPLETADA:** no se logró finalizar según criterio operativo.

## 14.4 Cerrar tarea (Operario)

1. Abra tarea asignada.
2. Pulse **Cerrar tarea**.
3. Diligencie observaciones finales.
4. Registre insumos usados.
5. Envíe cierre.

## 14.5 Veredicto (Supervisor/Jefe)

1. Abra lista de pendientes de aprobación.
2. Revise evidencia, tiempos, observaciones y consumos.
3. Emita veredicto:
   - Aprobar,
   - Rechazar (con motivo claro).

---

## 15) Tareas preventivas (definición y automatización)

## 15.1 Crear definición preventiva

1. Entre a **Preventivas**.
2. Pulse **Crear preventiva**.
3. Defina:
   - descripción,
   - ubicación,
   - elemento,
   - frecuencia (diaria/semanal/mensual),
   - operarios,
   - supervisor,
   - prioridad.
4. Defina duración:
   - fija en minutos, o
   - por rendimiento (unidad + tasa).
5. Configure recursos requeridos (insumos, maquinaria, herramientas).
6. (Opcional) active división en varios días.
7. Guarde.

## 15.2 Editar o eliminar preventiva

1. Desde listado, seleccione preventiva.
2. Edite o elimine.
3. Regenerar borrador de cronograma para que refleje cambios.

## 15.3 Generar cronograma mensual desde preventivas

1. Pulse **Generar cronograma mensual**.
2. Defina mes/año objetivo.
3. Revise cantidad de tareas creadas.
4. Valide conflictos y ajuste.

---

## 16) Cronograma (mensual y semanal)

## 16.1 Vista mensual

Uso recomendado:

- detectar sobrecarga por día,
- validar distribución por operario,
- revisar cumplimiento por estado.

## 16.2 Vista semanal

Uso recomendado:

- seguimiento táctico,
- reasignaciones,
- control fino de secuencia diaria.

## 16.3 Filtros clave

- Tipo de tarea.
- Estado.
- Operario.
- Ubicación.

## 16.4 Cierre desde cronograma

Cuando está habilitado por rol, se puede cerrar tarea directamente desde el calendario.

---

## 17) Agenda de maquinaria

## 17.1 Qué muestra

- Planilla mensual por máquina.
- Reservas por semanas/grupos.
- Actividades del conjunto y compartidas.

## 17.2 Cómo usarla correctamente

1. Seleccione mes.
2. Busque máquina por nombre.
3. Revise reservas y códigos de estado.
4. Antes de crear tarea, confirme hueco disponible.

## 17.3 Decisiones recomendadas

- Si no hay disponibilidad, reprogramar tarea o usar equipo alterno.

---

## 18) Agenda de herramientas

## 18.1 Qué muestra

- Programación por herramienta, por semana y grupo.
- Reservas totales del mes.
- Filtro por conjunto para disponibilidad real local.

## 18.2 Flujo de uso

1. Seleccione mes.
2. Busque herramienta.
3. Revise detalle semanal.
4. Ajuste asignaciones de tareas si hay conflicto.

---

## 19) Compromisos / PQRS

## 19.1 Crear compromiso o PQRS

1. Abra módulo **Compromisos** o **PQRS**.
2. Ingrese descripción del requerimiento.
3. Guarde con estado inicial.

## 19.2 Seguimiento

1. Actualice observación y estado.
2. Mantenga trazabilidad de avances.
3. Cierre cuando la gestión finalice.

---

## 20) Reportes, tableros y exportables PDF

## 20.1 Qué se puede consultar

- KPIs del rango de fechas.
- Serie diaria por estado.
- Resumen por conjunto.
- Resumen por operario.
- Uso de insumos.
- Top maquinaria/herramientas.
- Detalle mensual de tareas.

## 20.2 Cómo generar un reporte útil

1. Defina rango de fechas (desde/hasta).
2. Seleccione conjunto (o modo general).
3. Revise indicadores y gráficos.
4. Complete análisis y plan de acción.
5. Exporte PDF para comité.

## 20.3 Buenas prácticas

- Compare períodos homogéneos (mes contra mes, semana contra semana).
- Analice causas de rechazo/no completadas.
- Relacione consumo de insumos con productividad real.

---

## 21) Notificaciones y cumpleaños

## 21.1 Notificaciones

- Abra campana de notificaciones.
- Revise no leídas.
- Marque una o todas como leídas.
- Use este panel como bandeja operativa diaria.

## 21.2 Cumpleaños

- Revise cumpleaños del mes, del año y del día.
- Úselo para comunicación interna y clima laboral.

---

## 22) Flujos detallados por rol (paso a paso)

## 22.1 Flujo diario del Gerente

1. Entrar y validar conjunto activo.
2. Revisar notificaciones críticas.
3. Verificar solicitudes pendientes.
4. Revisar cronograma semanal.
5. Ajustar recursos (inventario/herramientas/maquinaria).
6. Revisar reportes de avance y riesgos.
7. Actualizar compromisos estratégicos.

## 22.2 Flujo diario del Supervisor

1. Revisar tareas del día.
2. Monitorear tareas en proceso.
3. Revisar cierres pendientes.
4. Aprobar/rechazar con criterio técnico.
5. Atender solicitudes.
6. Validar agenda de recursos para el siguiente turno.

## 22.3 Flujo diario del Jefe de Operaciones

1. Revisar tablero de pendientes críticos.
2. Resolver cuellos de botella de recursos.
3. Emitir veredictos pendientes.
4. Coordinar con gerente prioridades del día.

## 22.4 Flujo diario del Administrador

1. Revisar PQRS/compromisos del conjunto.
2. Revisar inventario y alertas de stock.
3. Consultar cronograma y cumplimiento.
4. Generar insumos para reporte interno.

## 22.5 Flujo diario del Operario

1. Revisar tareas asignadas.
2. Iniciar tarea según prioridad.
3. Reportar novedades en observaciones.
4. Cerrar tarea con consumos reales.
5. Atender tareas rechazadas para reproceso.

---

## 23) Reglas operativas críticas

1. Nunca crear tareas sin responsable asignado.
2. Nunca cerrar tarea sin observación mínima.
3. Registrar consumos reales, no estimados.
4. Revisar disponibilidad de maquinaria/herramientas antes de programar.
5. Evitar descripciones ambiguas.
6. Rechazos deben tener motivo accionable.

---

## 24) Errores frecuentes y cómo resolverlos

## 24.1 “Token requerido” / “Token inválido o expirado”

**Causa:** sesión vencida o ausente.  
**Solución:** cerrar sesión e iniciar nuevamente.

## 24.2 “No autorizado para este recurso”

**Causa:** rol sin permisos para esa acción.  
**Solución:** ejecutar con rol correcto o escalar al gerente.

## 24.3 Conflicto de disponibilidad de maquinaria/herramienta

**Causa:** recurso ya reservado en el mismo rango.  
**Solución:** cambiar recurso, cambiar horario o dividir tarea.

## 24.4 Validación de formulario rechazada

**Causa:** faltan campos obligatorios o formato inválido.  
**Solución:** completar campos y reenviar.

## 24.5 Tarea rechazada por supervisor

**Causa:** cierre incompleto, evidencia insuficiente o inconsistencias.  
**Solución:** corregir observaciones/consumos y reprocesar.

---

## 25) Checklist diario, semanal y mensual

## 25.1 Checklist diario

- [ ] Revisar notificaciones no leídas.
- [ ] Revisar tareas pendientes del día.
- [ ] Gestionar cierres pendientes de aprobación.
- [ ] Validar stock bajo de insumos.
- [ ] Validar agenda de recursos para mañana.

## 25.2 Checklist semanal

- [ ] Revisar cumplimiento por operario.
- [ ] Revisar tareas rechazadas/no completadas.
- [ ] Ajustar preventivas según hallazgos.
- [ ] Cerrar compromisos vencidos.

## 25.3 Checklist mensual

- [ ] Consolidar KPIs del mes.
- [ ] Revisar consumo de insumos vs ejecución.
- [ ] Evaluar top uso de maquinaria y herramientas.
- [ ] Exportar informe PDF.
- [ ] Definir plan de mejora del siguiente mes.

---

## 26) Glosario rápido

- **Conjunto:** sede/proyecto donde se ejecutan servicios.
- **Ubicación:** zona dentro del conjunto.
- **Elemento:** objeto puntual intervenido dentro de una ubicación.
- **Tarea correctiva:** intervención por novedad o daño.
- **Tarea preventiva:** rutina periódica planificada.
- **Veredicto:** aprobación/rechazo de cierre de tarea.
- **PQRS/Compromiso:** requerimiento y seguimiento de gestión.

---

## Cierre

Si su equipo aplica este manual en el orden indicado, tendrá control integral de operación, trazabilidad de tareas y mejor calidad en la toma de decisiones.  

**Recomendación final:** convierta este manual en procedimiento interno oficial y úselo para inducción de personal nuevo.
