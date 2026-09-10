import { randomUUID } from "crypto";
import type { Prisma, PrismaClient } from "@prisma/client";

import { AuditoriaService } from "./AuditoriaService";

function makeHttpError(status: number, message: string) {
  const err = new Error(message) as Error & { status: number };
  err.status = status;
  return err;
}

const CONCEPTOS_DEFAULT: Array<{
  codigo: string;
  nombre: string;
  cuentaComoTrabajado: boolean;
  colorHex: string;
  orden: number;
}> = [
  { codigo: "A", nombre: "Asistencia", cuentaComoTrabajado: true, colorHex: "#43A047", orden: 1 },
  {
    codigo: "DFC",
    nombre: "Asistencia domingo o festivo con compensatorio",
    cuentaComoTrabajado: true,
    colorHex: "#26A69A",
    orden: 2,
  },
  {
    codigo: "DFP",
    nombre: "Asistencia domingo o festivo sin compensatorio (pleno)",
    cuentaComoTrabajado: true,
    colorHex: "#00897B",
    orden: 3,
  },
  { codigo: "PR", nombre: "Permiso remunerado", cuentaComoTrabajado: true, colorHex: "#42A5F5", orden: 4 },
  { codigo: "PNR", nombre: "Permiso no remunerado", cuentaComoTrabajado: false, colorHex: "#78909C", orden: 5 },
  { codigo: "F", nombre: "Faltas", cuentaComoTrabajado: false, colorHex: "#E53935", orden: 6 },
  { codigo: "DF", nombre: "Descuento por falta", cuentaComoTrabajado: false, colorHex: "#FB8C00", orden: 7 },
  { codigo: "D", nombre: "Descanso", cuentaComoTrabajado: true, colorHex: "#9E9E9E", orden: 8 },
  {
    codigo: "EG",
    nombre: "Incapacidad por enfermedad general",
    cuentaComoTrabajado: false,
    colorHex: "#8E24AA",
    orden: 9,
  },
  {
    codigo: "AT",
    nombre: "Incapacidad por accidente de trabajo",
    cuentaComoTrabajado: false,
    colorHex: "#6A1B9A",
    orden: 10,
  },
  { codigo: "V", nombre: "Vacaciones", cuentaComoTrabajado: true, colorHex: "#FDD835", orden: 11 },
  { codigo: "LC", nombre: "Licencias", cuentaComoTrabajado: false, colorHex: "#C0CA33", orden: 12 },
  { codigo: "C", nombre: "Compensatorios", cuentaComoTrabajado: true, colorHex: "#00ACC1", orden: 13 },
];

const QR_PREFIX = "CTRLAPP-ASISTENCIA";

function toYmd(d: Date): string {
  return `${d.getFullYear().toString().padStart(4, "0")}-${(d.getMonth() + 1)
    .toString()
    .padStart(2, "0")}-${d.getDate().toString().padStart(2, "0")}`;
}

function parseYmdAsUtcDate(ymd: string): Date {
  const [y, m, d] = ymd.split("-").map((part) => Number(part));
  return new Date(Date.UTC(y, (m ?? 1) - 1, d ?? 1));
}

function daysInMonth(anio: number, mes: number): number {
  return new Date(anio, mes, 0).getDate();
}

function nombreCompletoOperario(operario: { usuario?: { nombre: string } | null }): string {
  return operario.usuario?.nombre ?? "";
}

type RegistroConConcepto = {
  id: number;
  conceptoId: number;
  origen: string;
  horaEntrada: Date | null;
  horaSalida: Date | null;
  observacion: string | null;
  concepto: { codigo: string; nombre: string; colorHex: string };
};

function serializeRegistro(registro: RegistroConConcepto) {
  return {
    id: registro.id,
    conceptoId: registro.conceptoId,
    conceptoCodigo: registro.concepto.codigo,
    conceptoNombre: registro.concepto.nombre,
    colorHex: registro.concepto.colorHex,
    origen: registro.origen,
    horaEntrada: registro.horaEntrada,
    horaSalida: registro.horaSalida,
    observacion: registro.observacion,
  };
}

export class AsistenciaService {
  private auditoria: AuditoriaService;

  constructor(private readonly prisma: PrismaClient) {
    this.auditoria = new AuditoriaService(prisma);
  }

  /* ------------------------------ conceptos ------------------------------ */

  async ensureConceptosSeed(empresaId: string) {
    const existentes = await this.prisma.conceptoAsistencia.count({ where: { empresaId } });
    if (existentes > 0) return;

    await this.prisma.conceptoAsistencia.createMany({
      data: CONCEPTOS_DEFAULT.map((c) => ({ ...c, empresaId })),
      skipDuplicates: true,
    });
  }

  async listarConceptos(empresaId: string) {
    await this.ensureConceptosSeed(empresaId);
    return this.prisma.conceptoAsistencia.findMany({
      where: { empresaId },
      orderBy: [{ orden: "asc" }, { codigo: "asc" }],
    });
  }

  async actualizarConcepto(
    empresaId: string,
    id: number,
    data: { nombre?: string; colorHex?: string; cuentaComoTrabajado?: boolean; activo?: boolean },
  ) {
    const actual = await this.prisma.conceptoAsistencia.findFirst({ where: { id, empresaId } });
    if (!actual) throw makeHttpError(404, "Concepto no encontrado");

    return this.prisma.conceptoAsistencia.update({
      where: { id },
      data: {
        nombre: data.nombre?.trim() || undefined,
        colorHex: data.colorHex?.trim() || undefined,
        cuentaComoTrabajado: typeof data.cuentaComoTrabajado === "boolean" ? data.cuentaComoTrabajado : undefined,
        activo: typeof data.activo === "boolean" ? data.activo : undefined,
      },
    });
  }

  /* --------------------------------- QR ----------------------------------- */

  async obtenerQr(conjuntoId: string) {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { nit: true, nombre: true, qrAsistenciaToken: true, qrAsistenciaActualizado: true },
    });
    if (!conjunto) throw makeHttpError(404, "Conjunto no encontrado");

    let token = conjunto.qrAsistenciaToken;
    let actualizado = conjunto.qrAsistenciaActualizado;
    if (!token) {
      token = randomUUID();
      const updated = await this.prisma.conjunto.update({
        where: { nit: conjuntoId },
        data: { qrAsistenciaToken: token, qrAsistenciaActualizado: new Date() },
        select: { qrAsistenciaActualizado: true },
      });
      actualizado = updated.qrAsistenciaActualizado;
    }

    return {
      conjuntoId: conjunto.nit,
      conjuntoNombre: conjunto.nombre,
      token,
      payload: `${QR_PREFIX}|${conjunto.nit}|${token}`,
      actualizadoEn: actualizado,
    };
  }

  async regenerarQr(conjuntoId: string, actor: { id?: string | null; rol?: string | null }) {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { nit: true, nombre: true },
    });
    if (!conjunto) throw makeHttpError(404, "Conjunto no encontrado");

    const token = randomUUID();
    const updated = await this.prisma.conjunto.update({
      where: { nit: conjuntoId },
      data: { qrAsistenciaToken: token, qrAsistenciaActualizado: new Date() },
      select: { qrAsistenciaActualizado: true },
    });

    await this.auditoria.registrar({
      modulo: "asistencia",
      entidad: "ConjuntoQr",
      entidadId: conjunto.nit,
      accion: "REGENERAR_QR",
      conjuntoId: conjunto.nit,
      actor: { id: actor.id ?? null, rol: actor.rol ?? null, nombre: null },
      descripcion: `QR de asistencia regenerado para ${conjunto.nombre}`,
    });

    return {
      conjuntoId: conjunto.nit,
      conjuntoNombre: conjunto.nombre,
      token,
      payload: `${QR_PREFIX}|${conjunto.nit}|${token}`,
      actualizadoEn: updated.qrAsistenciaActualizado,
    };
  }

  /* ------------------------------- check-in -------------------------------- */

  async checkin(input: { operarioId: string; conjuntoId: string; qrPayload: string }) {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: input.conjuntoId },
      select: { nit: true, nombre: true, qrAsistenciaToken: true },
    });
    if (!conjunto || !conjunto.qrAsistenciaToken) {
      throw makeHttpError(404, "El conjunto no tiene un QR de asistencia configurado");
    }

    const payloadEsperado = `${QR_PREFIX}|${conjunto.nit}|${conjunto.qrAsistenciaToken}`;
    if (input.qrPayload.trim() !== payloadEsperado) {
      throw makeHttpError(400, "El codigo QR no es valido o ya fue reemplazado. Pide uno nuevo en el sitio.");
    }

    const operario = await this.prisma.operario.findUnique({
      where: { id: input.operarioId },
      select: { id: true, empresaId: true },
    });
    if (!operario) throw makeHttpError(404, "Operario no encontrado");

    await this.ensureConceptosSeed(operario.empresaId);
    const conceptoAsistencia = await this.prisma.conceptoAsistencia.findUnique({
      where: { empresaId_codigo: { empresaId: operario.empresaId, codigo: "A" } },
    });
    if (!conceptoAsistencia) {
      throw makeHttpError(500, "No se pudo resolver el concepto de asistencia por defecto");
    }

    const ahora = new Date();
    const hoyYmd = toYmd(ahora);
    const fecha = parseYmdAsUtcDate(hoyYmd);
    const esDomingo = ahora.getDay() === 0;
    const festivo = await this.prisma.festivo.findUnique({ where: { fecha } });

    const existente = await this.prisma.registroAsistencia.findUnique({
      where: { operarioId_fecha: { operarioId: operario.id, fecha } },
    });

    if (!existente) {
      const observacion =
        esDomingo || festivo
          ? "Trabajo en domingo/festivo: pendiente clasificar como DFC o DFP."
          : null;

      const creado = await this.prisma.registroAsistencia.create({
        data: {
          operarioId: operario.id,
          conjuntoId: conjunto.nit,
          fecha,
          conceptoId: conceptoAsistencia.id,
          horaEntrada: ahora,
          origen: "QR",
          observacion,
        },
        include: { concepto: true },
      });

      return {
        tipo: "ENTRADA" as const,
        registro: serializeRegistro(creado),
        conjuntoNombre: conjunto.nombre,
      };
    }

    if (existente.horaEntrada && !existente.horaSalida) {
      const actualizado = await this.prisma.registroAsistencia.update({
        where: { id: existente.id },
        data: { horaSalida: ahora },
        include: { concepto: true },
      });

      return {
        tipo: "SALIDA" as const,
        registro: serializeRegistro(actualizado),
        conjuntoNombre: conjunto.nombre,
      };
    }

    throw makeHttpError(409, "Ya registraste entrada y salida hoy.");
  }

  /* ---------------------------- registro manual ---------------------------- */

  async upsertRegistro(input: {
    empresaId: string;
    operarioId: string;
    fecha: string;
    conceptoId: number;
    conjuntoId?: string | null;
    observacion?: string | null;
    actorId?: string | null;
  }) {
    const operario = await this.prisma.operario.findFirst({
      where: { id: input.operarioId, empresaId: input.empresaId },
      select: { id: true },
    });
    if (!operario) throw makeHttpError(404, "Operario no encontrado");

    const concepto = await this.prisma.conceptoAsistencia.findFirst({
      where: { id: input.conceptoId, empresaId: input.empresaId },
    });
    if (!concepto) throw makeHttpError(404, "Concepto de asistencia no encontrado");

    const fecha = parseYmdAsUtcDate(input.fecha);

    const registro = await this.prisma.registroAsistencia.upsert({
      where: { operarioId_fecha: { operarioId: input.operarioId, fecha } },
      create: {
        operarioId: input.operarioId,
        conjuntoId: input.conjuntoId ?? null,
        fecha,
        conceptoId: concepto.id,
        origen: "MANUAL",
        observacion: input.observacion ?? null,
        registradoPorId: input.actorId ?? null,
      },
      update: {
        conceptoId: concepto.id,
        conjuntoId: input.conjuntoId ?? undefined,
        observacion: input.observacion ?? undefined,
        actualizadoPorId: input.actorId ?? null,
      },
      include: { concepto: true },
    });

    return serializeRegistro(registro);
  }

  async bulkUpsertRegistro(input: {
    empresaId: string;
    operarioIds: string[];
    fechaInicio: string;
    fechaFin: string;
    conceptoId: number;
    conjuntoId?: string | null;
    observacion?: string | null;
    actorId?: string | null;
  }) {
    if (!input.operarioIds.length) {
      throw makeHttpError(400, "Selecciona al menos un operario");
    }

    const operarios = await this.prisma.operario.findMany({
      where: { id: { in: input.operarioIds }, empresaId: input.empresaId },
      select: { id: true },
    });
    if (operarios.length !== input.operarioIds.length) {
      throw makeHttpError(404, "Alguno de los operarios seleccionados no existe");
    }

    const concepto = await this.prisma.conceptoAsistencia.findFirst({
      where: { id: input.conceptoId, empresaId: input.empresaId },
    });
    if (!concepto) throw makeHttpError(404, "Concepto de asistencia no encontrado");

    const inicio = parseYmdAsUtcDate(input.fechaInicio);
    const fin = parseYmdAsUtcDate(input.fechaFin);
    if (fin.getTime() < inicio.getTime()) {
      throw makeHttpError(400, "La fecha final debe ser posterior o igual a la fecha inicial");
    }

    const fechas: Date[] = [];
    for (let t = inicio.getTime(); t <= fin.getTime(); t += 86_400_000) {
      fechas.push(new Date(t));
    }
    if (fechas.length > 62) {
      throw makeHttpError(400, "El rango de fechas es demasiado amplio (maximo 62 dias)");
    }

    let total = 0;
    await this.prisma.$transaction(async (tx) => {
      for (const operarioId of input.operarioIds) {
        for (const fecha of fechas) {
          await tx.registroAsistencia.upsert({
            where: { operarioId_fecha: { operarioId, fecha } },
            create: {
              operarioId,
              conjuntoId: input.conjuntoId ?? null,
              fecha,
              conceptoId: concepto.id,
              origen: "MANUAL",
              observacion: input.observacion ?? null,
              registradoPorId: input.actorId ?? null,
            },
            update: {
              conceptoId: concepto.id,
              conjuntoId: input.conjuntoId ?? undefined,
              observacion: input.observacion ?? undefined,
              actualizadoPorId: input.actorId ?? null,
            },
          });
          total += 1;
        }
      }
    });

    return { ok: true, registrosActualizados: total };
  }

  /* ---------------------------------- grid ---------------------------------- */

  async getGrid(input: { empresaId: string; conjuntoId?: string | null; anio: number; mes: number }) {
    await this.ensureConceptosSeed(input.empresaId);

    const totalDias = daysInMonth(input.anio, input.mes);
    const primerDia = new Date(Date.UTC(input.anio, input.mes - 1, 1));
    const ultimoDia = new Date(Date.UTC(input.anio, input.mes - 1, totalDias));

    const operarioWhere: Prisma.OperarioWhereInput = {
      empresaId: input.empresaId,
      AND: [
        { fechaIngreso: { lte: ultimoDia } },
        { OR: [{ fechaSalida: null }, { fechaSalida: { gte: primerDia } }] },
        ...(input.conjuntoId
          ? [
              {
                OR: [
                  { conjuntos: { some: { nit: input.conjuntoId } } },
                  {
                    registrosAsistencia: {
                      some: { conjuntoId: input.conjuntoId, fecha: { gte: primerDia, lte: ultimoDia } },
                    },
                  },
                ],
              },
            ]
          : []),
      ],
    };

    const operarios = await this.prisma.operario.findMany({
      where: operarioWhere,
      select: {
        id: true,
        funciones: true,
        usuario: { select: { nombre: true, rol: true } },
        conjuntos: { select: { nit: true, nombre: true } },
      },
      orderBy: { usuario: { nombre: "asc" } },
    });

    const registros = await this.prisma.registroAsistencia.findMany({
      where: {
        operarioId: { in: operarios.map((o) => o.id) },
        fecha: { gte: primerDia, lte: ultimoDia },
      },
      include: { concepto: true },
    });

    const registrosPorOperario = new Map<string, Map<string, (typeof registros)[number]>>();
    for (const registro of registros) {
      const key = toYmd(registro.fecha);
      if (!registrosPorOperario.has(registro.operarioId)) {
        registrosPorOperario.set(registro.operarioId, new Map());
      }
      registrosPorOperario.get(registro.operarioId)!.set(key, registro);
    }

    const hoy = toYmd(new Date());

    const filas = operarios.map((operario) => {
      const registrosOp = registrosPorOperario.get(operario.id) ?? new Map();
      const dias = Array.from({ length: totalDias }, (_, idx) => {
        const dia = idx + 1;
        const fechaObj = new Date(Date.UTC(input.anio, input.mes - 1, dia));
        const ymd = toYmd(fechaObj);
        const registro = registrosOp.get(ymd);
        const esFuturo = ymd > hoy;

        return {
          dia,
          fecha: ymd,
          diaSemana: fechaObj.getUTCDay(),
          pendiente: !registro && !esFuturo,
          registro: registro
            ? {
                id: registro.id,
                conceptoId: registro.conceptoId,
                conceptoCodigo: registro.concepto.codigo,
                conceptoNombre: registro.concepto.nombre,
                colorHex: registro.concepto.colorHex,
                origen: registro.origen,
                horaEntrada: registro.horaEntrada,
                horaSalida: registro.horaSalida,
                observacion: registro.observacion,
              }
            : null,
        };
      });

      return {
        operarioId: operario.id,
        nombre: nombreCompletoOperario(operario),
        cedula: operario.id,
        cargo: operario.funciones.join(", "),
        conjuntos: operario.conjuntos,
        dias,
      };
    });

    return {
      anio: input.anio,
      mes: input.mes,
      totalDias,
      operarios: filas,
    };
  }

  /* -------------------------------- resumen --------------------------------- */

  async getResumen(input: { empresaId: string; conjuntoId?: string | null; anio: number; mes: number }) {
    const grid = await this.getGrid(input);

    const resumen = grid.operarios.map((fila) => {
      const conteoPorConcepto = new Map<string, number>();
      let pendientes = 0;

      for (const dia of fila.dias) {
        if (dia.pendiente) {
          pendientes += 1;
          continue;
        }
        if (!dia.registro) continue;
        const codigo = dia.registro.conceptoCodigo;
        conteoPorConcepto.set(codigo, (conteoPorConcepto.get(codigo) ?? 0) + 1);
      }

      return {
        operarioId: fila.operarioId,
        nombre: fila.nombre,
        cedula: fila.cedula,
        cargo: fila.cargo,
        pendientes,
        conteoPorConcepto: Object.fromEntries(conteoPorConcepto),
      };
    });

    const primerDia = new Date(Date.UTC(input.anio, input.mes - 1, 1));
    const ultimoDia = new Date(Date.UTC(input.anio, input.mes - 1, grid.totalDias));

    const turnosExtra = await this.prisma.turnoExtra.findMany({
      where: {
        empresaId: input.empresaId,
        fecha: { gte: primerDia, lte: ultimoDia },
        ...(input.conjuntoId ? { conjuntoId: input.conjuntoId } : {}),
      },
      include: {
        operario: { select: { id: true, usuario: { select: { nombre: true } } } },
        operarioReemplazado: { select: { id: true, usuario: { select: { nombre: true } } } },
      },
      orderBy: [{ fecha: "asc" }],
    });

    return {
      anio: input.anio,
      mes: input.mes,
      operarios: resumen,
      turnosExtra: turnosExtra.map((t) => ({
        id: t.id,
        fecha: toYmd(t.fecha),
        operarioId: t.operarioId,
        operarioNombre: t.operario.usuario?.nombre ?? "",
        conjuntoId: t.conjuntoId,
        tipo: t.tipo,
        esReemplazo: t.esReemplazo,
        reemplazadoNombre: t.operarioReemplazado?.usuario?.nombre ?? t.reemplazadoNombreLibre ?? null,
        motivo: t.motivo,
        valorNegociado: t.valorNegociado,
        turnosOrdinarios: t.turnosOrdinarios,
        turnosDominicales: t.turnosDominicales,
        estado: t.estado,
      })),
    };
  }

  /* ------------------------------ turnos extra ------------------------------ */

  async listarTurnosExtra(input: {
    empresaId: string;
    conjuntoId?: string | null;
    operarioId?: string | null;
    anio?: number;
    mes?: number;
  }) {
    const where: Prisma.TurnoExtraWhereInput = {
      empresaId: input.empresaId,
      ...(input.conjuntoId ? { conjuntoId: input.conjuntoId } : {}),
      ...(input.operarioId ? { operarioId: input.operarioId } : {}),
    };

    if (input.anio && input.mes) {
      const total = daysInMonth(input.anio, input.mes);
      where.fecha = {
        gte: new Date(Date.UTC(input.anio, input.mes - 1, 1)),
        lte: new Date(Date.UTC(input.anio, input.mes - 1, total)),
      };
    }

    return this.prisma.turnoExtra.findMany({
      where,
      include: {
        operario: { select: { id: true, usuario: { select: { nombre: true } } } },
        operarioReemplazado: { select: { id: true, usuario: { select: { nombre: true } } } },
        conjunto: { select: { nit: true, nombre: true } },
      },
      orderBy: [{ fecha: "desc" }],
    });
  }

  async crearTurnoExtra(input: {
    empresaId: string;
    operarioId: string;
    conjuntoId?: string | null;
    fecha: string;
    tipo: "TURNO" | "NOVENA" | "OTRO";
    esReemplazo: boolean;
    operarioReemplazadoId?: string | null;
    reemplazadoNombreLibre?: string | null;
    motivo?: string | null;
    valorNegociado?: number | null;
    turnosOrdinarios?: number;
    turnosDominicales?: number;
    registradoPorId?: string | null;
  }) {
    const operario = await this.prisma.operario.findFirst({
      where: { id: input.operarioId, empresaId: input.empresaId },
      select: { id: true },
    });
    if (!operario) throw makeHttpError(404, "Operario no encontrado");

    if (input.operarioReemplazadoId) {
      const reemplazado = await this.prisma.operario.findFirst({
        where: { id: input.operarioReemplazadoId, empresaId: input.empresaId },
        select: { id: true },
      });
      if (!reemplazado) throw makeHttpError(404, "El operario reemplazado no existe");
    }

    return this.prisma.turnoExtra.create({
      data: {
        empresaId: input.empresaId,
        operarioId: input.operarioId,
        conjuntoId: input.conjuntoId ?? null,
        fecha: parseYmdAsUtcDate(input.fecha),
        tipo: input.tipo,
        esReemplazo: input.esReemplazo,
        operarioReemplazadoId: input.operarioReemplazadoId ?? null,
        reemplazadoNombreLibre: input.operarioReemplazadoId ? null : input.reemplazadoNombreLibre ?? null,
        motivo: input.motivo ?? null,
        valorNegociado: input.valorNegociado ?? null,
        turnosOrdinarios: input.turnosOrdinarios ?? 0,
        turnosDominicales: input.turnosDominicales ?? 0,
        registradoPorId: input.registradoPorId ?? null,
      },
      include: {
        operario: { select: { id: true, usuario: { select: { nombre: true } } } },
        operarioReemplazado: { select: { id: true, usuario: { select: { nombre: true } } } },
      },
    });
  }

  async actualizarTurnoExtra(
    empresaId: string,
    id: number,
    data: Partial<{
      motivo: string | null;
      valorNegociado: number | null;
      turnosOrdinarios: number;
      turnosDominicales: number;
      estado: "PENDIENTE" | "PAGADO" | "CANCELADO";
    }>,
  ) {
    const actual = await this.prisma.turnoExtra.findFirst({ where: { id, empresaId } });
    if (!actual) throw makeHttpError(404, "Turno extra no encontrado");

    return this.prisma.turnoExtra.update({
      where: { id },
      data: {
        motivo: data.motivo,
        valorNegociado: data.valorNegociado,
        turnosOrdinarios: data.turnosOrdinarios,
        turnosDominicales: data.turnosDominicales,
        estado: data.estado,
      },
    });
  }

  async eliminarTurnoExtra(empresaId: string, id: number) {
    const actual = await this.prisma.turnoExtra.findFirst({ where: { id, empresaId } });
    if (!actual) throw makeHttpError(404, "Turno extra no encontrado");
    await this.prisma.turnoExtra.delete({ where: { id } });
    return { ok: true };
  }
}
