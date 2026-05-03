import { DiaSemana, Prisma, PrismaClient } from "@prisma/client";
import { z } from "zod";
import {
  construirRutaElemento,
  elementoParentChainInclude,
} from "../utils/elementoHierarchy";

const AsignarAConjuntoDTO = z.object({
  conjuntoId: z.string().min(3),
  responsableId: z.string().optional(), // ✅ Operario.id es String en tu schema
  diasPrestamo: z.number().int().positive().default(7),
});
type YMD = { y: number; m: number; d: number };

const DELIVERY_PICKUP_DOW = new Set<number>([1, 3, 6]); // Lun, Mie, Sab

export type ConflictoMaquinaria = {
  maquinariaId: number;
  usoId: number;
  tareaId: number;
  inicio: Date;
  fin: Date | null;
};

export class MaquinariaService {
  constructor(
    private prisma: PrismaClient,
    private maquinariaId: number,
  ) {}

  async asignarAConjunto(payload: unknown) {
    const { conjuntoId, responsableId, diasPrestamo } =
      AsignarAConjuntoDTO.parse(payload);

    const fechaInicio = new Date();
    const fechaDevolucionEstimada = new Date(
      fechaInicio.getTime() + diasPrestamo * 24 * 60 * 60 * 1000,
    );

    // 1) Validar existencia maquinaria y conjunto
    const [maq, conj] = await Promise.all([
      this.prisma.maquinaria.findUnique({
        where: { id: this.maquinariaId },
        select: { id: true },
      }),
      this.prisma.conjunto.findUnique({
        where: { nit: conjuntoId },
        select: { nit: true },
      }),
    ]);
    if (!maq) throw new Error("Maquinaria no encontrada");
    if (!conj) throw new Error("Conjunto no encontrado");

    // 2) Validar que NO esté ACTIVA en otro conjunto
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
      select: { id: true, conjuntoId: true },
    });
    if (activa) {
      throw new Error(
        `La maquinaria ya está asignada (ACTIVA) al conjunto ${activa.conjuntoId}.`,
      );
    }

    // 3) Crear asignación (inventario del conjunto)
    return this.prisma.maquinariaConjunto.create({
      data: {
        conjunto: { connect: { nit: conjuntoId } },
        maquinaria: { connect: { id: this.maquinariaId } },
        tipoTenencia: "PRESTADA",
        estado: "ACTIVA",
        fechaInicio,
        fechaDevolucionEstimada,
        ...(responsableId
          ? { responsable: { connect: { id: responsableId } } }
          : {}),
      },
      include: {
        conjunto: { select: { nit: true, nombre: true } },
        maquinaria: {
          select: { id: true, nombre: true, marca: true, estado: true },
        },
        responsable: { include: { usuario: { select: { nombre: true } } } },
      },
    });
  }

  async devolver(conjuntoId: string) {
    // 1) Buscar asignación ACTIVA en ese conjunto
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: {
        maquinariaId: this.maquinariaId,
        conjuntoId,
        estado: "ACTIVA",
      },
      select: { id: true },
    });

    if (!activa) {
      throw new Error(
        "No existe una asignación ACTIVA de esta maquinaria en ese conjunto.",
      );
    }

    // 2) Cerrar asignación
    return this.prisma.maquinariaConjunto.update({
      where: { id: activa.id },
      data: {
        estado: "DEVUELTA",
        fechaFin: new Date(),
      },
    });
  }

  async estaDisponible(): Promise<boolean> {
    // Disponible si NO tiene asignación ACTIVA
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
      select: { id: true },
    });
    return !activa;
  }

  async obtenerResponsableEnConjunto(conjuntoId: string): Promise<string> {
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: {
        maquinariaId: this.maquinariaId,
        conjuntoId,
        estado: "ACTIVA",
      },
      include: { responsable: { include: { usuario: true } } },
    });

    return activa?.responsable?.usuario?.nombre ?? "Sin asignar";
  }

  async agendaMaquinariaPorMaquina(params: {
    conjuntoId: string;
    maquinariaId: number;
    desde: Date;
    hasta: Date;
  }) {
    const { conjuntoId, maquinariaId, desde, hasta } = params;

    // maquinaria propia del conjunto (para marcar "propia")
    const propias = await this.prisma.maquinariaConjunto.findMany({
      where: { conjuntoId, estado: "ACTIVA", maquinariaId },
      select: { maquinariaId: true },
    });
    const esPropiaConjunto = propias.length > 0;

    const usos = await this.prisma.usoMaquinaria.findMany({
      where: {
        maquinariaId: this.maquinariaId,
        fechaInicio: { lt: hasta },
        fechaFin: { gt: desde },
      },
      include: {
        maquinaria: { select: { id: true, nombre: true } },
        tarea: {
          select: {
            id: true,
            descripcion: true,
            fechaInicio: true,
            fechaFin: true,
            estado: true,
            tipo: true,
            prioridad: true,
            borrador: true,
            conjuntoId: true,
            conjunto: { select: { nombre: true } },
            ubicacion: { select: { nombre: true } },
            elemento: { include: elementoParentChainInclude },
          },
        },
      },
      orderBy: [{ fechaInicio: "asc" }],
    });

    const getMaqIds = (json: any): number[] => {
      if (!Array.isArray(json)) return [];
      return json
        .map((x) => Number(x?.maquinariaId))
        .filter((n) => Number.isFinite(n) && n > 0);
    };

    const borradores = await this.prisma.tarea.findMany({
      where: {
        borrador: true,
        tipo: "PREVENTIVA",
        fechaInicio: { lt: hasta },
        fechaFin: { gt: desde },
      },
      select: {
        id: true,
        descripcion: true,
        fechaInicio: true,
        fechaFin: true,
        conjuntoId: true,
        conjunto: { select: { nombre: true } },
        maquinariaPlanJson: true,
      },
      orderBy: [{ fechaInicio: "asc" }],
    });

    const definiciones = await this.prisma.definicionTareaPreventiva.findMany({
      where: { activo: true },
      select: {
        id: true,
        descripcion: true,
        frecuencia: true,
        diaSemanaProgramado: true,
        diaMesProgramado: true,
        diasParaCompletar: true,
        conjuntoId: true,
        conjunto: { select: { nombre: true } },
        maquinariaPlanJson: true,
      },
      orderBy: [{ descripcion: "asc" }],
    });

    const diaSemanaToJs: Record<DiaSemana, number> = {
      LUNES: 1,
      MARTES: 2,
      MIERCOLES: 3,
      JUEVES: 4,
      VIERNES: 5,
      SABADO: 6,
      DOMINGO: 0,
    };

    const definicionReservas = definiciones.flatMap((def) => {
      const maqIds = new Set(getMaqIds(def.maquinariaPlanJson));
      if (!maqIds.has(maquinariaId)) return [];

      const items: Array<{
        id: number;
        fechaInicio: Date;
        fechaFin: Date;
        tareaId: number | null;
        tarea: any;
        observacion: string | null;
        fuente: "DEFINICION";
      }> = [];

      const duracionDias = Math.max(1, def.diasParaCompletar ?? 1);
      const pushReserva = (fechaBase: Date) => {
        const ini = startOfDayLocal(fechaBase);
        const fin = addDaysLocal(ini, duracionDias - 1);
        if (ini >= hasta || fin < desde) return;
        items.push({
          id: -def.id,
          fechaInicio: ini,
          fechaFin: new Date(fin.getFullYear(), fin.getMonth(), fin.getDate(), 23, 59, 59),
          tareaId: null,
          tarea: {
            id: def.id,
            descripcion: def.descripcion,
            estado: "DEFINICION",
            tipo: "PREVENTIVA",
            prioridad: 0,
            ubicacion: null,
            elemento: null,
            fechaInicio: ini,
            fechaFin: fin,
            conjuntoId: def.conjuntoId,
            conjuntoNombre: def.conjunto?.nombre ?? null,
          },
          observacion: "Preventiva en definicion",
          fuente: "DEFINICION",
        });
      };

      const cursor = new Date(desde.getFullYear(), desde.getMonth(), 1);
      const finMes = new Date(hasta.getFullYear(), hasta.getMonth(), 0);

      if (def.diaMesProgramado != null) {
        const day = Math.max(1, Math.min(31, def.diaMesProgramado));
        const fecha = new Date(cursor.getFullYear(), cursor.getMonth(), day);
        pushReserva(fecha);
      } else if (def.diaSemanaProgramado != null) {
        const target = diaSemanaToJs[def.diaSemanaProgramado];
        for (let d = new Date(cursor); d <= finMes; d = addDaysLocal(d, 1)) {
          if (d.getDay() == target) pushReserva(d);
        }
      }
      return items;
    });

    return {
      maquinariaId,
      nombre: usos[0]?.maquinaria?.nombre ?? "",
      esPropiaConjunto,
      reservas: [
        ...usos.map((u) => ({
          id: u.id,
          fechaInicio: u.fechaInicio,
          fechaFin: u.fechaFin,
          tareaId: u.tareaId,
          tarea: u.tarea
            ? {
                id: u.tarea.id,
                descripcion: u.tarea.descripcion,
                estado: u.tarea.estado,
                tipo: u.tarea.tipo,
                prioridad: u.tarea.prioridad,
                ubicacion: u.tarea.ubicacion?.nombre ?? null,
                elemento: construirRutaElemento(u.tarea.elemento as any) ?? null,
                fechaInicio: u.tarea.fechaInicio,
                fechaFin: u.tarea.fechaFin,
                conjuntoId: u.tarea.conjuntoId,
                conjuntoNombre: u.tarea.conjunto?.nombre ?? null,
              }
            : null,
          observacion: u.observacion ?? null,
          fuente: u.tarea?.borrador == true ? "BORRADOR" : "PUBLICADA",
        })),
        ...borradores
          .filter((t) => getMaqIds(t.maquinariaPlanJson).includes(maquinariaId))
          .map((t) => ({
            id: -t.id,
            fechaInicio: t.fechaInicio,
            fechaFin: t.fechaFin,
            tareaId: t.id,
            tarea: {
              id: t.id,
              descripcion: t.descripcion,
              estado: "BORRADOR",
              tipo: "PREVENTIVA",
              prioridad: 0,
              ubicacion: null,
              elemento: null,
              fechaInicio: t.fechaInicio,
              fechaFin: t.fechaFin,
              conjuntoId: t.conjuntoId,
              conjuntoNombre: t.conjunto?.nombre ?? null,
            },
            observacion: "Preventiva en borrador",
            fuente: "BORRADOR",
          })),
        ...definicionReservas,
      ].sort((a, b) => a.fechaInicio.getTime() - b.fechaInicio.getTime()),
    };
  }

  async resumenEstado(): Promise<string> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      select: { nombre: true, marca: true, estado: true },
    });
    if (!maquinaria) throw new Error("🛠️ Maquinaria no encontrada");

    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
      include: { conjunto: { select: { nombre: true } } },
    });

    const estadoAsignacion = activa
      ? `Prestada a ${activa.conjunto?.nombre ?? activa.conjuntoId}`
      : "Disponible";

    return `🛠️ ${maquinaria.nombre} (${maquinaria.marca}) - ${maquinaria.estado} - ${estadoAsignacion}`;
  }
}

export function startOfDayLocal(date: Date): Date {
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    0,
    0,
    0,
    0,
  );
}

export function addDaysLocal(date: Date, days: number): Date {
  const d = new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    0,
    0,
    0,
    0,
  );
  d.setDate(d.getDate() + days);
  return d;
}

export function isDeliveryPickupDay(date: Date): boolean {
  return DELIVERY_PICKUP_DOW.has(date.getDay() === 0 ? 7 : date.getDay());
}

/**
 * Devuelve el día logístico "anterior o igual" (para entrega).
 * Ej: Martes -> Lunes, Jueves -> Miércoles, Domingo -> Sábado.
 */
export function prevDeliveryDayInclusive(fechaUso: Date): Date {
  let d = startOfDayLocal(fechaUso);
  for (let guard = 0; guard < 8; guard++) {
    if (isDeliveryPickupDay(d)) return d;
    d = addDaysLocal(d, -1);
  }
  return startOfDayLocal(fechaUso);
}

/**
 * Devuelve el día logístico "posterior o igual" (para recogida).
 * Ej: Martes -> Miércoles, Miércoles -> Miércoles, Jueves -> Sábado.
 */
export function nextPickupDayInclusive(fechaUso: Date): Date {
  let d = startOfDayLocal(fechaUso);
  for (let guard = 0; guard < 8; guard++) {
    if (isDeliveryPickupDay(d)) return d;
    d = addDaysLocal(d, 1);
  }
  return startOfDayLocal(fechaUso);
}

/**
 * Ventana de préstamo logístico:
 * - inicio = 00:00 del día de entrega (prevDeliveryDayInclusive)
 * - finExclusivo = 00:00 del día siguiente a la recogida (nextPickupDayInclusive + 1)
 *
 * Así el intervalo es [inicio, finExclusivo) y es fácil de comparar en BD.
 */
export function calcularVentanaPrestamoLogistico(
  fechaInicioUso: Date,
  fechaFinUso: Date,
): {
  inicioPrestamo: Date;
  finPrestamoExclusivo: Date;
  diaEntrega: Date;
  diaRecogida: Date;
} {
  const diaEntrega = prevDeliveryDayInclusive(fechaInicioUso);
  const diaRecogida = nextPickupDayInclusive(fechaFinUso);

  const inicioPrestamo = startOfDayLocal(diaEntrega);
  const finPrestamoExclusivo = addDaysLocal(diaRecogida, 1); // 00:00 día siguiente

  return { inicioPrestamo, finPrestamoExclusivo, diaEntrega, diaRecogida };
}

export async function validarMaquinariaDisponibleEnVentana(params: {
  prisma: PrismaClient;
  maquinariaIds: number[];
  ventanaInicio: Date; // inclusive
  ventanaFinExclusivo: Date; // exclusivo
  ignorarTareaIds?: number[]; // útil en reprogramaciones
}): Promise<{ ok: true } | { ok: false; conflictos: ConflictoMaquinaria[] }> {
  const {
    prisma,
    maquinariaIds,
    ventanaInicio,
    ventanaFinExclusivo,
    ignorarTareaIds = [],
  } = params;

  if (!maquinariaIds.length) return { ok: true };

  const usos = await prisma.usoMaquinaria.findMany({
    where: {
      maquinariaId: { in: maquinariaIds },
      // overlap: (usoInicio < ventanaFin) AND (usoFin > ventanaInicio)
      fechaInicio: { lt: ventanaFinExclusivo },
      OR: [
        { fechaFin: null }, // abierto => ocupa
        { fechaFin: { gt: ventanaInicio } },
      ],
      ...(ignorarTareaIds.length
        ? { NOT: { tareaId: { in: ignorarTareaIds } } }
        : {}),
    },
    select: {
      id: true,
      maquinariaId: true,
      tareaId: true,
      fechaInicio: true,
      fechaFin: true,
    },
  });

  if (!usos.length) return { ok: true };

  return {
    ok: false,
    conflictos: usos.map((u) => ({
      maquinariaId: u.maquinariaId,
      usoId: u.id,
      tareaId: u.tareaId,
      inicio: u.fechaInicio,
      fin: u.fechaFin,
    })),
  };
}

export async function crearReservasMaquinariaParaTarea(params: {
  tx: PrismaClient | Prisma.TransactionClient;
  tareaId: number;
  maquinariaIds: number[];
  fechaInicioUso: Date;
  fechaFinUso: Date;
  observacion?: string;
}): Promise<void> {
  const { tx, tareaId, maquinariaIds, fechaInicioUso, fechaFinUso } = params;
  if (!maquinariaIds.length) return;

  const { inicioPrestamo, finPrestamoExclusivo, diaEntrega, diaRecogida } =
    calcularVentanaPrestamoLogistico(fechaInicioUso, fechaFinUso);

  const obs =
    params.observacion ??
    `Reserva logística: entrega ${diaEntrega.toISOString().slice(0, 10)} / recogida ${diaRecogida.toISOString().slice(0, 10)}`;

  // 1 registro por máquina
  for (const maqId of maquinariaIds) {
    await (tx as any).usoMaquinaria.create({
      data: {
        tareaId,
        maquinariaId: maqId,
        fechaInicio: inicioPrestamo,
        fechaFin: finPrestamoExclusivo, // ✅ fin exclusivo (00:00 día siguiente a recogida)
        observacion: obs,
      },
    });
  }
}
