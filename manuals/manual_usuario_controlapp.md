# Manual de Usuario Integral — ControlApp

**Versión del manual:** 1.0  
**Fecha:** 12 de abril de 2026  
**Producto:** Control Limpieza S.A.S. (ControlApp)  

---

## Tabla de contenido

1. Introducción y objetivo del manual  
2. Alcance funcional del sistema  
3. Requisitos de acceso y sesión  
4. Roles del sistema y permisos operativos  
5. Flujo general recomendado de implementación  
6. Módulo de autenticación y seguridad  
7. Módulo de usuarios y estructura organizacional  
8. Módulo de conjuntos (sedes/proyectos)  
9. Módulo de inventario (insumos y herramientas)  
10. Módulo de solicitudes  
11. Módulo de tareas correctivas  
12. Módulo de tareas preventivas  
13. Módulo de cronograma mensual/semanal  
14. Módulo de agendas de maquinaria y herramientas  
15. Módulo de compromisos / PQRS  
16. Módulo de reportes y exportación PDF  
17. Módulo de notificaciones y cumpleaños  
18. Flujos por rol (paso a paso)  
19. Reglas operativas y buenas prácticas  
20. Errores frecuentes y recuperación  
21. Checklist de operación diaria y cierre mensual  

---

## 1) Introducción y objetivo del manual

Este manual está diseñado para uso operativo real y cubre el ciclo completo de trabajo de la aplicación: configuración inicial, creación de usuarios, planificación, ejecución, aprobación, control de recursos y explotación de reportes.

Su propósito es que cada rol sepa:

- Qué puede hacer.
- En qué orden debe hacerlo.
- Qué validaciones aplica el sistema.
- Cómo actuar ante incidencias.

---

## 2) Alcance funcional del sistema

ControlApp gestiona operación de mantenimiento/aseo por conjuntos y centraliza:

- Gestión de usuarios por rol.
- Gestión de conjuntos, ubicaciones y elementos.
- Inventario de insumos y herramientas.
- Gestión de maquinaria y agenda de uso.
- Solicitudes de recursos.
- Tareas correctivas y preventivas.
- Cronograma operativo mensual/semanal.
- Veredictos de aprobación/rechazo.
- Reportería operativa, productividad y consumo.
- Notificaciones y alertas.

---

## 3) Requisitos de acceso y sesión

### 3.1 Inicio de sesión

1. Ingrese a la pantalla de login.
2. Diligencie **Correo** y **Contraseña**.
3. Haga clic en **Ingresar**.
4. El sistema redirige automáticamente según su rol.

### 3.2 Recuperación de acceso

Use **Recuperar acceso** en login cuando no recuerde credenciales.

### 3.3 Seguridad

- Toda llamada protegida usa token Bearer.
- El token se valida en backend.
- Si expira o es inválido, debe iniciar sesión de nuevo.
- Existe cambio de contraseña para usuario autenticado y cambio administrado por gerente.

---

## 4) Roles del sistema y permisos operativos

### 4.1 Gerente

Control total corporativo:

- Crear/editar/eliminar usuarios.
- Crear y administrar conjuntos.
- Gestionar catálogo (insumos, maquinaria, herramientas).
- Crear tareas correctivas.
- Definir preventivas y generar cronogramas.
- Ver reportes por conjunto y globales.
- Gestionar compromisos globales y por conjunto.

### 4.2 Supervisor

Control táctico de campo:

- Revisar y filtrar tareas.
- Aprobar/rechazar tareas pendientes.
- Gestionar solicitudes.
- Consultar cronograma y recursos operativos.

### 4.3 Jefe de Operaciones

Control operativo transversal:

- Revisar pendientes.
- Emitir veredictos de tareas.
- Supervisar solicitudes, agendas, inventario y compromisos.

### 4.4 Administrador

Operación administrativa del conjunto:

- Consultar conjuntos asignados.
- Gestionar PQRS/compromisos del conjunto.
- Consultar inventario, cronograma y reportes del conjunto.

### 4.5 Operario

Ejecución en campo:

- Ver tareas asignadas.
- Iniciar/gestionar avance.
- Cerrar tareas (con observaciones e insumos usados).
- Consultar solicitudes.

---

## 5) Flujo general recomendado de implementación

Orden sugerido para despliegue en un cliente nuevo:

1. Crear empresa y parámetros base.
2. Crear usuarios clave (gerente, supervisores, jefes, administradores, operarios).
3. Crear conjuntos.
4. Definir ubicaciones/elementos por conjunto.
5. Cargar catálogo de insumos, herramientas y maquinaria.
6. Configurar inventario inicial por conjunto.
7. Definir preventivas por ubicación/elemento.
8. Generar borrador de cronograma y revisar solapes.
9. Publicar ejecución de tareas.
10. Operar ciclo diario (ejecución → cierre → veredicto).
11. Revisar reportes semanales/mensuales.

---

## 6) Módulo de autenticación y seguridad

### Funcionalidades

- Login por correo + contraseña.
- Autodetección de sesión al abrir la app.
- Validación de sesión con endpoint **/auth/me**.
- Cambio de contraseña propio.
- Recuperación de contraseña.
- Cambio de contraseña de terceros por gerente.

### Consideraciones

- Si aparece “Token requerido” o “Token inválido o expirado”, el usuario debe reingresar.
- Los permisos de cada endpoint dependen del rol en token.

---

## 7) Módulo de usuarios y estructura organizacional

### Operaciones principales

- Crear usuario por rol.
- Listar usuarios.
- Editar usuario.
- Eliminar usuario.
- Asignar usuario a conjunto.

### Buenas prácticas

- Definir primero supervisores y operarios antes de crear tareas.
- Validar correo único por usuario.
- Mantener datos de contacto actualizados para notificaciones y soporte.

---

## 8) Módulo de conjuntos (sedes/proyectos)

### Operaciones principales

- Crear conjunto con NIT.
- Editar información del conjunto.
- Asignar operarios al conjunto.
- Consultar detalle del conjunto.

### Datos críticos

- NIT: identificador funcional usado en múltiples pantallas.
- Ubicaciones y elementos: base para crear preventivas y correctivas precisas.

---

## 9) Módulo de inventario (insumos y herramientas)

## 9.1 Insumos

Permite:

- Consultar stock del conjunto.
- Ver insumos bajos.
- Agregar y consumir stock.
- Solicitar reposición.

## 9.2 Herramientas

Permite:

- Ver stock por estado.
- Ajustar estado (disponible, reservado, en uso, etc.).
- Devolver préstamo de herramientas.

### Recomendaciones

- Registrar consumos al cierre de tareas para mantener trazabilidad real.
- Revisar insumos bajos a diario.

---

## 10) Módulo de solicitudes

El sistema maneja solicitudes de recursos, especialmente insumos, con estados.

### Flujo estándar

1. Usuario operativo crea solicitud.
2. Supervisor/Jefe/Gerente revisa detalle.
3. Se aprueba o rechaza.
4. Si se aprueba, impacta la operación logística.

### Campos típicos

- Conjunto.
- Empresa.
- Ítems solicitados.
- Cantidades.
- Fecha y estado.

---

## 11) Módulo de tareas correctivas

### Creación de tarea

Al crear una tarea correctiva se recomienda definir:

- Conjunto.
- Ubicación y elemento.
- Descripción clara y accionable.
- Prioridad.
- Rango de fechas y hora de inicio.
- Duración en minutos.
- Operarios asignados.
- Supervisor responsable.
- Recursos: maquinaria y herramientas (si aplica).

### Ejecución y cierre

- El operario puede iniciar/avanzar/cerrar según permisos.
- En cierre se registran observaciones e insumos usados.
- La tarea pasa a estados de validación según flujo.

### Estados relevantes

- ASIGNADA
- EN_PROCESO
- PENDIENTE_APROBACION
- APROBADA
- RECHAZADA
- NO_COMPLETADA

---

## 12) Módulo de tareas preventivas

### ¿Qué resuelve?

Automatiza rutinas recurrentes (diarias, semanales, mensuales), evitando omisiones.

### Configuración de una preventiva

- Ubicación + elemento objetivo.
- Frecuencia (diaria/semanal/mensual).
- Responsable(s): operarios/supervisor.
- Regla de duración:
  - Fija en minutos, o
  - Por rendimiento (unidad y tasa).
- Insumos, maquinaria y herramientas planificadas.
- Opción de dividir ejecución en varios días.

### Generación de cronograma

Tras crear/editar/eliminar preventivas, el sistema puede regenerar el borrador mensual para reflejar reglas actuales.

---

## 13) Módulo de cronograma mensual/semanal

### Vistas

- Mensual: panorama de carga por día.
- Semanal: detalle operativo y secuencia de trabajo.

### Funcionalidades

- Filtros por tipo, estado, operario y ubicación.
- Consideración de horarios del conjunto.
- Gestión de festivos.
- Cierre de tareas desde cronograma (según rol/permisos).

### Objetivo operativo

Detectar sobrecarga, huecos de asignación y conflictos de agenda antes de afectar la ejecución.

---

## 14) Módulo de agendas de maquinaria y herramientas

### Agenda de maquinaria

- Vista mensual por equipo.
- Identificación por estados en calendario (entrega, actividad, reserva/devolución según codificación de la pantalla).
- Diferencia visual entre equipos del conjunto y equipos con agenda compartida.

### Agenda de herramientas

- Vista por herramienta y semana/grupo.
- Conteo de reservas mensuales.
- Filtro por conjunto para ver disponibilidad real local.

### Buenas prácticas

- Revisar agenda antes de crear tareas de alta demanda.
- Evitar asignar equipos en conflicto temporal.

---

## 15) Módulo de compromisos / PQRS

Permite registrar compromisos y/o PQRS por conjunto y globalmente.

### Usos típicos

- Registrar requerimientos del cliente.
- Hacer seguimiento a acuerdos.
- Medir cumplimiento del equipo.

### Flujo

1. Crear compromiso/PQRS.
2. Actualizar estado/observación.
3. Cerrar o eliminar cuando corresponda.

---

## 16) Módulo de reportes y exportación PDF

### Capacidades

- KPIs del periodo.
- Serie diaria por estado.
- Resumen por conjunto.
- Resumen por operario.
- Uso de insumos.
- Top de maquinaria y herramientas.
- Detalle mensual de tareas.

### Exportables

- Informes en PDF desde dashboard de reportes.
- Reportes de apoyo a comité operativo y cierre mensual.

### Recomendación

Definir un corte fijo (semanal/mensual) para comparar periodos homogéneos.

---

## 17) Módulo de notificaciones y cumpleaños

### Notificaciones

- Conteo de no leídas.
- Marcado individual o masivo como leídas.
- Historial consultable por panel lateral/modal.

### Cumpleaños

- Sección dedicada para mes actual, anual y día.
- Útil para clima laboral y recordatorios internos.

---

## 18) Flujos por rol (paso a paso)

## 18.1 Gerente — flujo recomendado

1. Ingresar al panel de gerente.
2. Seleccionar conjunto activo.
3. Crear o actualizar usuarios faltantes.
4. Verificar catálogo de recursos (insumos/herramientas/maquinaria).
5. Configurar preventivas.
6. Crear correctivas urgentes si existen novedades.
7. Revisar solicitudes pendientes.
8. Revisar cronograma del mes y semana.
9. Analizar reportes y descargar PDF.
10. Actualizar compromisos/PQRS de seguimiento.

## 18.2 Supervisor — flujo recomendado

1. Entrar a panel supervisor.
2. Revisar tareas del día y pendientes.
3. Aprobar/rechazar cierres o veredictos pendientes.
4. Gestionar solicitudes entrantes.
5. Confirmar disponibilidad de inventario y recursos.
6. Ajustar planeación con cronograma si hay cambios.

## 18.3 Jefe de Operaciones — flujo recomendado

1. Revisar pendientes críticos.
2. Emitir veredictos.
3. Priorizar atención de solicitudes.
4. Monitorear uso de maquinaria/herramientas.
5. Revisar compromisos por conjunto.

## 18.4 Administrador — flujo recomendado

1. Ingresar al conjunto asignado.
2. Registrar y dar seguimiento a PQRS.
3. Monitorear inventario.
4. Revisar cronograma del conjunto.
5. Consultar reportes para comité con gerente/supervisor.

## 18.5 Operario — flujo recomendado

1. Revisar tareas asignadas (hoy/pendientes).
2. Iniciar y ejecutar actividad.
3. Registrar novedades.
4. Cerrar tarea incluyendo insumos usados y observaciones.
5. Revisar tareas rechazadas/no completadas para reproceso.

---

## 19) Reglas operativas y buenas prácticas

- Nunca crear tareas sin operario responsable.
- Evitar descripciones ambiguas (“hacer mantenimiento”); usar acción + objeto + ubicación.
- Registrar consumo real de insumos para evitar desbalances de inventario.
- Validar agenda de maquinaria/herramientas antes de asignar tareas críticas.
- Revisar estados RECHAZADA/NO_COMPLETADA al cierre de jornada.
- Mantener higiene de datos en usuarios, ubicaciones y elementos.

---

## 20) Errores frecuentes y recuperación

### 20.1 No autenticado / token inválido

- Causa: sesión expirada o token ausente.
- Acción: cerrar sesión e ingresar nuevamente.

### 20.2 No autorizado

- Causa: el rol no tiene permiso para ese recurso.
- Acción: solicitar ejecución al rol correspondiente o reasignación.

### 20.3 Conflictos operativos de recursos

- Causa: maquinaria/herramienta ocupada en el rango.
- Acción: cambiar recurso, ajustar horario o reprogramar.

### 20.4 Datos obligatorios faltantes

- Causa: validaciones de backend (campos requeridos).
- Acción: completar formulario y reenviar.

---

## 21) Checklist de operación diaria y cierre mensual

## 21.1 Cierre diario

- [ ] Revisar tareas pendientes del día.
- [ ] Validar cierres pendientes de aprobación.
- [ ] Actualizar compromisos/PQRS críticos.
- [ ] Revisar inventario bajo.
- [ ] Confirmar agenda de recursos para mañana.

## 21.2 Cierre mensual

- [ ] Verificar cumplimiento preventivas vs ejecutadas.
- [ ] Revisar tareas rechazadas/no completadas.
- [ ] Consolidar consumo de insumos.
- [ ] Revisar top uso maquinaria/herramientas.
- [ ] Descargar reporte PDF y socializar con dirección.

---

## Conclusión

ControlApp es un sistema integral de operación con enfoque en trazabilidad, disciplina de ejecución y control de recursos. Cuando se sigue el orden recomendado (configuración → planificación → ejecución → validación → análisis), el sistema entrega visibilidad completa para la toma de decisiones por rol y por conjunto.
