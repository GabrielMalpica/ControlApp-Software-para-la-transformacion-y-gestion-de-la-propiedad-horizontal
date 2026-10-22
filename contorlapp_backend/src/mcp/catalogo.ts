// src/mcp/catalogo.ts
//
// Catalogo de lo que ControlApp expone por MCP y, sobre todo, de lo que NO.
// Todo modulo nuevo de la app debe aparecer en DECISIONES_POR_MODULO (lo
// exige tests/unit/mcp-catalogo.unit.test.ts). Guia:
// docs/mcp/MCP_INTEGRATION_GUIDELINES.md.
import { herramientasCambio } from "./herramientas/cambios";
import { herramientasConsulta } from "./herramientas/consultas";
import type { DefinicionHerramienta } from "./herramientas/tipos";

export const HERRAMIENTAS: DefinicionHerramienta[] = [...herramientasConsulta, ...herramientasCambio];

/**
 * Nombres que nunca deben existir como herramientas: eliminar, cambiar
 * permisos o credenciales, pagos, marcaje presencial, SQL o llamadas
 * genericas a la API.
 */
export const PATRONES_PROHIBIDOS: RegExp[] = [
  /eliminar|borrar|delete|remove/i,
  /permiso|rol(es)?_|contrasena|password|credencial|token/i,
  /pago|cobro|factus|mora|puntos/i,
  /checkin|marcar_asistencia|qr/i,
  /sql|query|api|http|fetch|ejecutar_/i,
  /residente|postulacion|evidencia_archivo|descargar/i,
];

export type DecisionModulo = { expuesto: boolean; motivo: string };

/** Modulos del catalogo de permisos de la app (PermissionService) y su decision MCP. */
export const DECISIONES_POR_MODULO: Record<string, DecisionModulo> = {
  tareas: { expuesto: true, motivo: "Solo lectura. Crear correctivas tiene reglas de reemplazo en el controller; se expondrá cuando vivan en un servicio." },
  cronograma: { expuesto: true, motivo: "Estado y publicación (alto riesgo, con aprobación en la app). Editar el borrador sigue en la app." },
  solicitudes: { expuesto: true, motivo: "Solo lectura de solicitudes de insumos; aprobar mueve inventario y queda en la app." },
  inventario: { expuesto: true, motivo: "Lectura, insumos bajos y movimientos de entrada/consumo." },
  maquinaria: { expuesto: true, motivo: "Solo lectura del estado; no hay regla de dominio de 'necesita mantenimiento'." },
  herramientas: { expuesto: false, motivo: "Pendiente: misma decisión que maquinaria cuando se pida." },
  empresa: { expuesto: false, motivo: "Configuración de la empresa: solo en la app." },
  usuarios: { expuesto: true, motivo: "Solo operarios (crear, plazas, traslados) con confirmación. Roles, gerentes, permisos y contraseñas nunca. La planilla de personal y la hoja de vida (cédula, EPS, ARL, caja de compensación, contacto de emergencia, dirección, tallas, vacaciones) quedan solo en la app." },
  conjuntos: { expuesto: true, motivo: "Lectura y creación con confirmación. Editar y eliminar quedan en la app." },
  mapa_areas: { expuesto: false, motivo: "Planos y archivos: solo en la app." },
  compromisos: { expuesto: true, motivo: "Lectura y creación." },
  reportes: { expuesto: true, motivo: "Indicadores de tareas. El PDF detallado queda en la app (costo y datos internos)." },
  cumpleanos: { expuesto: false, motivo: "Dato personal sin valor operativo para la IA." },
  residentes: { expuesto: false, motivo: "Datos personales de residentes: nunca por MCP." },
  plan_esperanza: { expuesto: false, motivo: "Diagnósticos con fotos: solo en la app." },
  asistencia: { expuesto: true, motivo: "Lectura y novedades manuales. El marcaje por QR es presencial y nunca se automatiza." },
  comercio: { expuesto: false, motivo: "Pedidos, pagos y mora: fuera del MCP." },
  web: { expuesto: false, motivo: "Postulaciones con documentos de identidad: nunca por MCP." },
};
