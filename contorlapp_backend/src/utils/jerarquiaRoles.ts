// src/utils/jerarquiaRoles.ts
import { Rol } from "@prisma/client";

/**
 * Jerarquia para gestionar usuarios: gerente > jefe_operaciones > supervisor >
 * administrador / operario / residente. El permiso `usuarios.gestionar` se puede
 * delegar desde la matriz de permisos, asi que tenerlo no basta: quien lo tenga
 * solo gestiona roles estrictamente inferiores al suyo.
 */
const NIVEL_POR_ROL: Record<Rol, number> = {
  [Rol.gerente]: 4,
  [Rol.jefe_operaciones]: 3,
  [Rol.supervisor]: 2,
  [Rol.administrador]: 1,
  [Rol.operario]: 1,
  [Rol.residente]: 1,
};

const ETIQUETA_POR_ROL: Record<Rol, string> = {
  [Rol.gerente]: "gerente",
  [Rol.jefe_operaciones]: "jefe de operaciones",
  [Rol.supervisor]: "supervisor",
  [Rol.administrador]: "administrador",
  [Rol.operario]: "operario",
  [Rol.residente]: "residente",
};

export function normalizarRol(value: string | null | undefined): Rol | null {
  const rol = String(value ?? "").trim().toLowerCase();
  return rol in NIVEL_POR_ROL ? (rol as Rol) : null;
}

export function etiquetaRol(value: string | null | undefined): string {
  const rol = normalizarRol(value);
  return rol ? ETIQUETA_POR_ROL[rol] : String(value ?? "sin rol");
}

export type SolicitudGestionUsuario = {
  actor: { id: string; rol: string | null | undefined };
  /** Usuario afectado; null o ausente cuando se esta creando. */
  objetivoId?: string | null;
  /** Rol actual del usuario afectado (ausente al crear). */
  rolActual?: string | null;
  /** Rol que quedara asignado (ausente si no se toca el rol). */
  rolNuevo?: string | null;
  /** true solo si `activo` cambia de valor. */
  cambiaActivo?: boolean;
  elimina?: boolean;
};

/**
 * Devuelve el motivo por el que el actor no puede hacer el cambio, o null si
 * puede. Funcion pura: el servicio resuelve los roles desde la base.
 */
export function motivoRechazoGestionUsuario(solicitud: SolicitudGestionUsuario): string | null {
  const { actor, objetivoId, cambiaActivo, elimina } = solicitud;
  const rolActor = normalizarRol(actor.rol);
  const rolActual = solicitud.rolActual != null ? normalizarRol(solicitud.rolActual) : null;
  const rolNuevo = solicitud.rolNuevo != null ? normalizarRol(solicitud.rolNuevo) : null;
  const esPropio = objetivoId != null && String(objetivoId) === String(actor.id);

  if (esPropio) {
    if (elimina) return "No puedes eliminar tu propia cuenta.";
    if (rolNuevo && rolNuevo !== rolActual) {
      return "No puedes cambiar tu propio rol; debe hacerlo otro gerente.";
    }
    if (cambiaActivo) return "No puedes activar ni desactivar tu propia cuenta.";
  }

  if (!rolActor) return "Tu rol no permite gestionar usuarios.";
  if (rolActor === Rol.gerente) return null;

  if (rolActual === Rol.gerente || rolNuevo === Rol.gerente) {
    return "Solo un gerente puede crear, editar, asignar o eliminar usuarios con rol gerente.";
  }

  const nivelActor = NIVEL_POR_ROL[rolActor];
  const etiquetaActor = ETIQUETA_POR_ROL[rolActor];
  // Un rol que no se reconoce no se presume inferior: solo el gerente lo toca.
  const nivelObjetivo = (rol: Rol | null) => (rol ? NIVEL_POR_ROL[rol] : Number.POSITIVE_INFINITY);

  if (solicitud.rolActual != null && nivelObjetivo(rolActual) >= nivelActor) {
    return `Como ${etiquetaActor} solo puedes gestionar usuarios de roles inferiores al tuyo.`;
  }

  if (solicitud.rolNuevo != null && nivelObjetivo(rolNuevo) >= nivelActor) {
    return `Como ${etiquetaActor} no puedes asignar el rol ${etiquetaRol(solicitud.rolNuevo)}: solo roles inferiores al tuyo.`;
  }

  return null;
}
