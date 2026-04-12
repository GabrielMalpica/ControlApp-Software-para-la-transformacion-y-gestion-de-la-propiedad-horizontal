# Manual de Usuario Ultra Detallado - ControlApp

Version manual: 2.0
Fecha: 2026-04-12
Formato principal: Guia operativa completa
Formato de descarga: PDF (en carpeta manuals)
Idioma: Espanol sin tildes

---

## 0. Como usar este manual

Este manual esta pensado para:

- induccion de personal nuevo,
- operacion diaria,
- auditoria interna,
- estandarizacion de procesos.

Se recomienda leer en este orden:

1. secciones 1 a 6 para entender arquitectura funcional,
2. secciones 7 a 20 para ejecucion por modulo,
3. secciones 21 a 26 para operacion por rol,
4. secciones 27 a 32 para control, calidad y cierre.

### Espacios de captura globales

[ESPACIO CAPTURA 00-1: Pantalla de login completa]  
[ESPACIO CAPTURA 00-2: Dashboard principal por rol]  
[ESPACIO CAPTURA 00-3: Menu de navegacion y acciones rapidas]

---

## 1. Objetivo general de ControlApp

ControlApp centraliza la gestion operativa de servicios en conjuntos:

- planeacion de tareas,
- ejecucion de campo,
- validacion de cumplimiento,
- control de recursos,
- reporteria de resultados.

Resultados esperados al usar bien la plataforma:

- menos reprocesos,
- mas trazabilidad,
- mejor uso de insumos y equipos,
- mayor capacidad de decision por datos.

---

## 2. Alcance funcional total del sistema

El sistema cubre de punta a punta:

1. autenticacion y seguridad,
2. usuarios y roles,
3. conjuntos,
4. ubicaciones y elementos,
5. inventario de insumos,
6. herramientas y stock por estado,
7. maquinaria,
8. solicitudes,
9. tareas correctivas,
10. tareas preventivas,
11. cronograma mensual y semanal,
12. agenda de maquinaria,
13. agenda de herramientas,
14. compromisos y pqrs,
15. reportes y exportables,
16. notificaciones y cumpleanos.

---

## 3. Roles y permisos operativos reales

## 3.1 Gerente

Puede ejecutar practicamente toda la operacion:

- crear usuarios,
- editar usuarios,
- eliminar usuarios,
- crear conjuntos,
- editar conjuntos,
- crear catalogos,
- crear tareas,
- definir preventivas,
- aprobar decisiones clave,
- revisar tableros e informes globales.

## 3.2 Supervisor

Gestion tactica del dia a dia:

- seguimiento de tareas,
- veredicto de cierre,
- gestion de solicitudes,
- control del cronograma,
- monitoreo de recursos.

## 3.3 Jefe de operaciones

Orquestacion transversal:

- pendientes criticos,
- veredictos,
- solicitudes,
- compromisos,
- revision de agendas globales.

## 3.4 Administrador

Operacion administrativa por conjunto:

- pqrs,
- compromisos,
- consulta de inventario,
- consulta de cronograma,
- consulta de reportes.

## 3.5 Operario

Ejecucion en campo:

- visualizar tareas,
- ejecutar tareas,
- cerrar tareas,
- registrar observaciones y consumos,
- consultar solicitudes.

[ESPACIO CAPTURA 03-1: Comparativo visual de dashboards por rol]

---

## 4. Orden recomendado de puesta en marcha

Nunca inicie por tareas sin antes crear estructura base.

Orden obligatorio recomendado:

1. crear empresa y parametros,
2. crear usuarios base,
3. crear conjuntos,
4. definir ubicaciones y elementos,
5. cargar catalogo de insumos,
6. cargar catalogo de herramientas,
7. cargar catalogo de maquinaria,
8. configurar inventario inicial,
9. crear preventivas,
10. generar borrador de cronograma,
11. crear correctivas urgentes,
12. operar ciclo diario,
13. medir con reportes.

[ESPACIO CAPTURA 04-1: Diagrama de flujo de implementacion inicial]

---

## 5. Acceso y autenticacion

## 5.1 Iniciar sesion

Paso a paso:

1. abrir app,
2. ingresar correo,
3. ingresar contrasena,
4. pulsar ingresar,
5. verificar redireccion por rol.

## 5.2 Recuperar acceso

1. pulsar recuperar acceso,
2. ingresar datos de validacion,
3. definir nueva contrasena,
4. reintentar login.

## 5.3 Cambio de contrasena autenticado

1. icono de candado,
2. contrasena actual,
3. contrasena nueva,
4. guardar.

## 5.4 Cierre de sesion

1. icono salir,
2. confirmar,
3. validar retorno al login.

[ESPACIO CAPTURA 05-1: Login]  
[ESPACIO CAPTURA 05-2: Dialogo recuperar acceso]  
[ESPACIO CAPTURA 05-3: Dialogo cambiar contrasena]

---

## 6. Configuracion inicial de empresa

## 6.1 Crear empresa

Campos recomendados:

- nit,
- nombre,
- correo,
- reglas generales de operacion.

## 6.2 Parametros de tiempo

- limite de minutos por semana,
- horario apertura/cierre,
- descanso.

## 6.3 Festivos

- definir rango,
- cargar festivos,
- validar impacto en cronograma.

[ESPACIO CAPTURA 06-1: Pantalla festivos]  
[ESPACIO CAPTURA 06-2: Parametros operativos empresa]

---

## 7. Gestion completa de usuarios

## 7.1 Crear usuario (flujo completo)

1. entrar a crear usuario,
2. completar datos personales,
3. elegir rol,
4. completar contacto,
5. guardar,
6. validar que aparezca en lista.

Checklist al crear usuario:

- correo unico,
- rol correcto,
- identificacion correcta,
- datos minimos completos.

## 7.2 Editar usuario

1. abrir detalle usuario,
2. editar campos,
3. guardar,
4. validar reflejo en lista.

## 7.3 Eliminar usuario

1. validar que no deje proceso huercano,
2. eliminar,
3. confirmar.

## 7.4 Reasignar usuario entre conjuntos

1. identificar conjunto origen,
2. retirar asignacion,
3. asignar en destino,
4. validar permisos visibles.

## 7.5 Cambiar contrasena de usuario por gerente

1. seleccionar usuario,
2. ingresar nueva contrasena,
3. guardar,
4. notificar al usuario.

[ESPACIO CAPTURA 07-1: Formulario crear usuario]  
[ESPACIO CAPTURA 07-2: Lista usuarios con acciones]  
[ESPACIO CAPTURA 07-3: Edicion usuario]

---

## 8. Gestion completa de conjuntos

## 8.1 Crear conjunto

1. abrir crear conjunto,
2. ingresar nit,
3. ingresar nombre,
4. ingresar direccion,
5. ingresar contacto,
6. definir tipo de servicio,
7. guardar.

## 8.2 Editar conjunto

1. abrir detalle conjunto,
2. editar datos,
3. guardar.

## 8.3 Eliminar conjunto

Solo si no hay operacion activa:

- sin tareas pendientes criticas,
- sin solicitudes pendientes criticas,
- con respaldo de reportes.

## 8.4 Usuarios por conjunto

1. abrir usuarios del conjunto,
2. asignar administrador,
3. asignar supervisor,
4. asignar operarios,
5. guardar.

[ESPACIO CAPTURA 08-1: Crear conjunto]  
[ESPACIO CAPTURA 08-2: Detalle conjunto]  
[ESPACIO CAPTURA 08-3: Usuarios por conjunto]

---

## 9. Ubicaciones y elementos

## 9.1 Crear ubicacion

1. entrar a ubicaciones,
2. agregar ubicacion,
3. nombre descriptivo,
4. guardar.

## 9.2 Crear elemento

1. abrir ubicacion,
2. agregar elemento,
3. nombrar elemento,
4. guardar.

## 9.3 Busqueda y orden

Mantener convencion:

- ubicacion: zona general,
- elemento: punto puntual.

Ejemplo:

- ubicacion: Torre B - Piscina,
- elemento: Borde piscina norte.

[ESPACIO CAPTURA 09-1: Lista ubicaciones]  
[ESPACIO CAPTURA 09-2: Elementos por ubicacion]

---

## 10. Inventario de insumos (todo el flujo)

## 10.1 Cargar catalogo de insumos

1. entrar a crear insumo,
2. definir nombre,
3. categoria,
4. unidad,
5. umbral,
6. guardar.

## 10.2 Ver inventario por conjunto

1. abrir inventario,
2. pestana insumos,
3. aplicar busqueda/filtros.

## 10.3 Agregar stock

1. seleccionar insumo,
2. agregar cantidad,
3. registrar movimiento.

## 10.4 Consumir stock

1. seleccionar insumo,
2. cantidad consumida,
3. confirmar.

## 10.5 Identificar stock bajo

1. filtrar bajos,
2. priorizar por criticidad,
3. disparar solicitud.

[ESPACIO CAPTURA 10-1: Inventario insumos tabla]  
[ESPACIO CAPTURA 10-2: Dialogo agregar stock]  
[ESPACIO CAPTURA 10-3: Vista de insumos bajos]

---

## 11. Herramientas (catalogo y stock por estado)

## 11.1 Crear herramienta

1. abrir crear herramienta,
2. nombre,
3. categoria,
4. unidad,
5. modo de control,
6. guardar.

## 11.2 Ver stock herramientas

Columnas clave:

- herramienta,
- cantidad,
- estado,
- modo control,
- origen.

## 11.3 Ajustar cantidad

1. seleccionar herramienta,
2. ajustar stock,
3. guardar.

## 11.4 Cambiar estado

1. seleccionar herramienta,
2. mover cantidad a estado nuevo,
3. guardar.

## 11.5 Devolver prestamo

1. seleccionar item prestado,
2. definir cantidad a devolver,
3. confirmar.

[ESPACIO CAPTURA 11-1: Lista herramientas]  
[ESPACIO CAPTURA 11-2: Cambio de estado herramienta]  
[ESPACIO CAPTURA 11-3: Devolucion de prestamo]

---

## 12. Maquinaria (catalogo, disponibilidad y agenda)

## 12.1 Crear maquinaria

Campos:

- nombre,
- tipo,
- estado,
- propietario,
- tenencia,
- observaciones.

## 12.2 Editar maquinaria

1. abrir listado,
2. editar,
3. guardar.

## 12.3 Revisar disponibilidad

1. elegir rango de fechas,
2. consultar disponibilidad,
3. validar conflictos.

## 12.4 Gestion de conflictos

Si equipo ocupado:

- cambiar equipo,
- mover horario,
- dividir actividad.

[ESPACIO CAPTURA 12-1: Crear maquinaria]  
[ESPACIO CAPTURA 12-2: Lista maquinaria]  
[ESPACIO CAPTURA 12-3: Agenda maquinaria por mes]

---

## 13. Solicitudes (insumos, maquinaria, tarea)

## 13.1 Solicitud de insumos

1. abrir solicitud insumos,
2. revisar recomendados,
3. agregar carrito,
4. enviar.

## 13.2 Revision de solicitudes

1. abrir lista solicitudes,
2. filtrar por estado,
3. abrir detalle,
4. aprobar o rechazar.

## 13.3 Solicitud de maquinaria

1. registrar necesidad,
2. definir rango esperado,
3. enviar,
4. hacer seguimiento.

## 13.4 Solicitud de tarea

1. registrar requerimiento,
2. adjuntar descripcion clara,
3. enviar a aprobacion.

[ESPACIO CAPTURA 13-1: Formulario solicitud insumos]  
[ESPACIO CAPTURA 13-2: Lista solicitudes y filtros]  
[ESPACIO CAPTURA 13-3: Detalle solicitud con aprobar/rechazar]

---

## 14. Tareas correctivas (creacion, ejecucion, cierre, veredicto)

## 14.1 Crear tarea correctiva

Paso a paso completo:

1. abrir crear tarea,
2. seleccionar conjunto,
3. seleccionar ubicacion,
4. seleccionar elemento,
5. escribir descripcion accionable,
6. definir prioridad,
7. definir fecha inicio,
8. definir fecha fin,
9. definir hora inicio,
10. definir duracion minutos,
11. asignar operarios,
12. asignar supervisor,
13. asignar maquinaria (si aplica),
14. asignar herramientas (si aplica),
15. guardar.

## 14.2 Reglas durante creacion

El sistema puede:

- bloquear por conflicto de recurso,
- aplicar reemplazos de baja prioridad,
- marcar preventivas impactadas.

## 14.3 Ejecucion por operario

1. abrir tareas,
2. filtrar hoy/pendientes,
3. abrir detalle,
4. iniciar,
5. ejecutar.

## 14.4 Cierre por operario

1. pulsar cerrar,
2. registrar observaciones,
3. registrar insumos usados,
4. enviar a validacion.

## 14.5 Veredicto supervisor o jefe

1. abrir pendientes de aprobacion,
2. revisar cierre,
3. aprobar o rechazar,
4. dejar motivo si rechaza.

## 14.6 Reproceso de rechazo

1. operario revisa causa,
2. corrige,
3. vuelve a cerrar.

[ESPACIO CAPTURA 14-1: Formulario crear tarea]  
[ESPACIO CAPTURA 14-2: Cerrar tarea con insumos]  
[ESPACIO CAPTURA 14-3: Veredicto aprobacion/rechazo]

---

## 15. Tareas preventivas (definicion, reglas, regeneracion)

## 15.1 Crear preventiva

1. abrir modulo preventivas,
2. crear preventiva,
3. descripcion,
4. frecuencia,
5. ubicacion,
6. elemento,
7. operarios,
8. supervisor,
9. prioridad,
10. definir modelo de duracion,
11. asociar recursos,
12. guardar.

## 15.2 Modelos de duracion

- fija en minutos,
- por rendimiento y unidad.

## 15.3 Division en dias

Si tarea larga:

- activar dividir en dias,
- definir numero de dias,
- guardar.

## 15.4 Editar preventiva

1. abrir item,
2. editar,
3. guardar.

## 15.5 Eliminar preventiva

1. eliminar,
2. confirmar,
3. regenerar borrador.

## 15.6 Generar cronograma mensual

1. seleccionar mes y anio,
2. ejecutar generacion,
3. revisar tareas creadas,
4. validar colisiones.

[ESPACIO CAPTURA 15-1: Lista preventivas]  
[ESPACIO CAPTURA 15-2: Crear preventiva]  
[ESPACIO CAPTURA 15-3: Regenerar borrador]

---

## 16. Cronograma (vista mensual y semanal)

## 16.1 Vista mensual

Permite:

- lectura macro de carga,
- revison de dias criticos,
- revision por estado.

## 16.2 Vista semanal

Permite:

- seguimiento fino,
- control tactico diario,
- ajustes rapidos.

## 16.3 Filtros

- tipo,
- estado,
- operario,
- ubicacion.

## 16.4 Horario y descanso

El cronograma considera:

- apertura,
- cierre,
- descanso,
- festivos.

[ESPACIO CAPTURA 16-1: Cronograma mensual]  
[ESPACIO CAPTURA 16-2: Cronograma semanal]  
[ESPACIO CAPTURA 16-3: Panel de filtros]

---

## 17. Agenda de maquinaria

## 17.1 Consulta por mes

1. abrir agenda maquinaria,
2. cambiar mes anterior/siguiente,
3. elegir maquina,
4. revisar planilla semanal.

## 17.2 Interpretacion codigos

Use la leyenda de la pantalla para interpretar:

- entrada,
- actividad,
- reserva,
- retorno.

## 17.3 Decision operativa

No crear tarea con equipo si no existe hueco real.

[ESPACIO CAPTURA 17-1: Agenda maquinaria panel izquierdo]  
[ESPACIO CAPTURA 17-2: Agenda maquinaria planilla]

---

## 18. Agenda de herramientas

## 18.1 Consulta por mes y herramienta

1. abrir agenda herramientas,
2. seleccionar mes,
3. buscar herramienta,
4. abrir detalle semanal.

## 18.2 Uso para planificacion

- confirmar disponibilidad,
- evitar doble reserva,
- replanificar cuando haya colision.

[ESPACIO CAPTURA 18-1: Agenda herramientas listado]  
[ESPACIO CAPTURA 18-2: Agenda herramientas detalle]

---

## 19. Compromisos y pqrs

## 19.1 Crear compromiso

1. abrir compromisos,
2. escribir descripcion,
3. guardar.

## 19.2 Crear pqrs (administrador)

1. abrir pqrs,
2. registrar novedad/requerimiento,
3. guardar,
4. hacer seguimiento.

## 19.3 Actualizar y cerrar

1. editar estado,
2. actualizar observacion,
3. cerrar cuando termina.

[ESPACIO CAPTURA 19-1: Formulario compromiso/pqrs]  
[ESPACIO CAPTURA 19-2: Lista con estados]

---

## 20. Reportes y exportables

## 20.1 Tipos de reporte

- kpis,
- serie diaria por estado,
- resumen por conjunto,
- resumen por operario,
- uso insumos,
- top maquinaria,
- top herramientas,
- detalle mensual tareas.

## 20.2 Flujo para generar informe

1. elegir rango fechas,
2. elegir conjunto o general,
3. cargar tablero,
4. analizar,
5. exportar pdf.

## 20.3 Uso recomendado de reportes

- comite semanal,
- cierre mensual,
- plan de mejora.

[ESPACIO CAPTURA 20-1: Dashboard reportes]  
[ESPACIO CAPTURA 20-2: Exportacion informe]

---

## 21. Notificaciones y cumpleanos

## 21.1 Notificaciones

1. abrir campana,
2. revisar no leidas,
3. marcar leida individual,
4. marcar todas.

## 21.2 Cumpleanos

1. abrir modulo cumpleanos,
2. revisar hoy,
3. revisar mes,
4. revisar anio.

[ESPACIO CAPTURA 21-1: Panel notificaciones]  
[ESPACIO CAPTURA 21-2: Pantalla cumpleanos]

---

## 22. Catalogo de pantallas y que hacer en cada una

Esta seccion sirve como mapa total de la app.

Pantallas principales identificadas:

- login,
- splash decision,
- dashboard gerente,
- dashboard supervisor,
- dashboard administrador,
- dashboard operario,
- dashboard jefe operaciones,
- crear usuario,
- lista usuarios,
- editar usuario,
- crear conjunto,
- lista conjuntos,
- detalle conjunto,
- mapa conjunto,
- zonificacion,
- crear insumo,
- lista insumos,
- crear maquinaria,
- lista maquinaria,
- crear herramienta,
- lista herramientas,
- stock herramientas empresa,
- inventario,
- solicitud insumo,
- solicitud maquinaria,
- solicitudes,
- crear tarea,
- tareas,
- editar tarea,
- preventivas,
- crear preventiva,
- cronograma,
- crear cronograma,
- borrador preventivas,
- agenda maquinaria,
- agenda herramientas,
- compromisos,
- compromisos por conjunto,
- reportes,
- reportes general,
- notificaciones,
- festivos,
- cumpleanos,
- pendientes jefe operaciones.

Para cada pantalla:

1. abrir,
2. identificar accion principal,
3. ejecutar,
4. validar resultado,
5. registrar novedad si falla.

[ESPACIO CAPTURA 22-1: Collage de pantallas criticas]

---

## 23. Flujos operativos diarios por rol

## 23.1 Flujo gerente

1. revisar notificaciones,
2. revisar solicitudes,
3. revisar cronograma,
4. ajustar recursos,
5. revisar reportes,
6. cerrar compromisos.

## 23.2 Flujo supervisor

1. revisar tareas del dia,
2. monitorear en proceso,
3. aprobar/rechazar cierres,
4. atender solicitudes,
5. confirmar agenda siguiente dia.

## 23.3 Flujo jefe operaciones

1. tablero pendientes,
2. resolver cuellos de botella,
3. veredictos,
4. seguimiento compromisos.

## 23.4 Flujo administrador

1. pqrs,
2. inventario,
3. cronograma,
4. reporte.

## 23.5 Flujo operario

1. tomar tarea,
2. ejecutar,
3. cerrar con evidencia,
4. atender rechazo si aplica.

---

## 24. Flujos semanales y mensuales

## 24.1 Semanal

- corte de cumplimiento,
- revision rechazos,
- revision stock,
- revision compromisos.

## 24.2 Mensual

- cierre kpis,
- analisis eficiencia,
- comparativo periodos,
- plan mejora siguiente mes.

---

## 25. Reglas de calidad de datos

Reglas:

1. no usar descripciones genericas,
2. no duplicar usuarios,
3. no dejar tareas sin responsable,
4. no cerrar tareas sin observacion,
5. no consumir insumos sin registro,
6. no aprobar sin revisar evidencia.

---

## 26. Matriz de errores y acciones correctivas

Error: token requerido  
Accion: reingresar

Error: no autorizado  
Accion: usar rol correcto

Error: recurso ocupado  
Accion: reprogramar o cambiar recurso

Error: validacion de formulario  
Accion: completar datos obligatorios

Error: tarea rechazada  
Accion: corregir y reenviar cierre

---

## 27. Checklist diario operativo

- revisar no leidas,
- revisar pendientes hoy,
- revisar cierres pendientes,
- revisar stock bajo,
- revisar agenda manana.

## 28. Checklist semanal operativo

- revisar cumplimiento por operario,
- revisar tareas rechazadas,
- revisar preventivas criticas,
- revisar compromisos vencidos.

## 29. Checklist mensual operativo

- consolidar kpis,
- validar consumo vs ejecucion,
- generar informe,
- socializar plan mejora.

---

## 30. Plantilla para evidencias de captura

Use esta plantilla en cada proceso:

- captura antes,
- captura durante,
- captura resultado.

Formato sugerido:

[ESPACIO CAPTURA XX-A: Antes]  
[ESPACIO CAPTURA XX-B: Durante]  
[ESPACIO CAPTURA XX-C: Resultado]

---

## 31. Glosario completo

conjunto: unidad operativa  
ubicacion: zona de trabajo  
elemento: punto de intervencion  
correctiva: tarea por novedad  
preventiva: tarea periodica  
veredicto: aprobacion o rechazo  
pqrs: requerimiento administrativo  
cronograma: plan de ejecucion en tiempo  
agenda: plan de uso de recurso

---

## 32. Cierre del manual

Este manual esta disenado para cubrir TODO lo que se puede hacer en la app a nivel funcional y operativo.

Recomendacion final:

- usarlo como base oficial de entrenamiento,
- actualizarlo cada vez que se agregue una pantalla,
- mantener biblioteca de capturas en cada seccion.

[ESPACIO CAPTURA 32-1: Portada final del manual con version y fecha]
