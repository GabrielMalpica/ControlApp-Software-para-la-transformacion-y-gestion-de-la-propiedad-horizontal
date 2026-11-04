// src/services/OperarioService.ts
import {
  PrismaClient,
  EstadoTarea,
  EstadoUsoHerramienta,
  TipoMovimientoInsumo,
  Prisma,
} from "@prisma/client";
import { z } from "zod";
import { TareaService } from "./TareaServices";
import { InventarioService } from "./InventarioServices";
import {
  buildEvidenciaFileName,
  eliminarEvidenciaDeDrive,
  extraerDriveId,
  uploadEvidenciaToDrive,
} from "../utils/drive_evidencias";
import { subirEvidenciasConMarca } from "../utils/marca_agua_evidencia";
import {
  desfaseRelojMs,
  esVerdadero,
  parsearFecha,
  resolverHora,
} from "../utils/horaSinConexion";
import fs from "fs";
import { NotificacionService } from "./NotificacionService";
import { elementoParentChainInclude } from "../utils/elementoHierarchy";
import { adjuntarCategoriaCronograma } from "../utils/categoriaCronograma";

function httpError(status: number, message: string, code?: string) {
  const err = new Error(message) as Error & { status: number; code?: string };
  err.status = status;
  if (code) err.code = code;
  return err;
}

/** Un cierre guardado sin señal puede llegar días después, pero no meses. */
const ANTIGUEDAD_MAXIMA_CIERRE_MS = 45 * 86_400_000;

const ESTADOS_YA_CERRADA = new Set<EstadoTarea>([
  EstadoTarea.APROBADA,
  EstadoTarea.NO_COMPLETADA,
  EstadoTarea.PENDIENTE_APROBACION,
  EstadoTarea.RECHAZADA,
]);

function formatearFechaHora(fecha: Date): string {
  return new Intl.DateTimeFormat("es-CO", {
    timeZone: "America/Bogota",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
  }).format(fecha);
}

function borrarTemporales(files: Express.Multer.File[] | undefined) {
  for (const f of files ?? []) {
    try {
      if (f?.path && fs.existsSync(f.path)) fs.unlinkSync(f.path);
    } catch {}
  }
}

function esDuplicadoDeIdempotencia(err: unknown): boolean {
  if (!(err instanceof Prisma.PrismaClientKnownRequestError) || err.code !== "P2002") {
    return false;
  }
  const target = (err.meta as { target?: unknown; modelName?: unknown } | undefined) ?? {};
  const texto = `${String(target.modelName ?? "")} ${
    Array.isArray(target.target) ? target.target.join(",") : String(target.target ?? "")
  }`;
  return /CierreTareaIdempotencia|clienteCierreId/i.test(texto);
}

export type ResultadoCierreOperario = { duplicado: boolean };

const TareaIdDTO = z.object({ tareaId: z.number().int().positive() });

const MarcarCompletadaDTO = z.object({
  tareaId: z.number().int().positive(),
  evidencias: z.array(z.string()).default([]),
  insumosUsados: z
    .array(
      z.object({
        insumoId: z.number().int().positive(),
        cantidad: z.coerce.number().positive(),
      })
    )
    .default([]),
});

const FechaDTO = z.object({ fecha: z.coerce.date() });

const CerrarMultipartDTO = z.object({
  accion: z.enum(["COMPLETADA", "NO_COMPLETADA"]).optional(),
  observaciones: z.string().optional(),
  fechaFinalizarTarea: z.string().optional(),
  insumosUsados: z.string().optional(),
  clienteCierreId: z.string().uuid().optional(),
  evidenciasCaptura: z.string().optional(), // JSON: [{tomadaEn, tomadaEnEstimada?, latitud, longitud} | null]
  // App Android: el cierre viene de la cola sin señal (ver horaSinConexion.ts).
  sinConexion: z.union([z.string(), z.boolean()]).optional(),
  horaDispositivoEnvio: z.string().optional(),
  horaEstimada: z.string().optional(),
});

export class OperarioService {
  constructor(private prisma: PrismaClient, private operarioId: number) {}

  /** Obtiene el límite semanal (horas) desde la Empresa del operario */
  private async getLimiteHorasSemana(): Promise<number> {
    const op = await this.prisma.operario.findUnique({
      where: { id: this.operarioId.toString() },
      select: { empresa: { select: { limiteHorasSemana: true } } },
    });
    return op?.empresa?.limiteHorasSemana ?? 46;
  }

  /** Asigna una tarea al operario respetando el límite semanal empresarial */
  async asignarTarea(payload: unknown): Promise<void> {
    const { tareaId } = TareaIdDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        fechaInicio: true,
        duracionMinutos: true,
        id: true,
        borrador: true,
      },
    });
    if (!tarea) throw new Error("Tarea no encontrada");
    if (tarea.borrador) {
      throw new Error("No se puede asignar una tarea en borrador.");
    }

    const limite = await this.getLimiteHorasSemana();
    const horasSemana = await this.horasAsignadasEnSemana(tarea.fechaInicio);
    if (horasSemana + tarea.duracionMinutos > limite) {
      const operario = await this.prisma.operario.findUnique({
        where: { id: this.operarioId.toString() },
        select: { usuario: { select: { nombre: true } } },
      });
      const nombre = operario?.usuario?.nombre ?? "Operario";
      throw new Error(
        `❌ Supera el límite de ${limite} horas semanales para ${nombre}`
      );
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { operarios: { connect: { id: this.operarioId.toString() } } },
    });
  }

  /**
   * Inicia una tarea (cambia estado a EN_PROCESO). Solo la puede iniciar un
   * operario asignado a ella, igual que el cierre.
   */
  async iniciarTarea(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, borrador: true, estado: true, operarios: { select: { id: true } } },
    });
    if (!tarea || tarea.borrador) {
      throw httpError(404, "La tarea no existe o está en borrador.");
    }
    const asignado = tarea.operarios.some((o) => o.id === this.operarioId.toString());
    if (!asignado) {
      throw httpError(403, "Esta tarea no está asignada al operario autenticado.");
    }
    if (tarea.estado !== "ASIGNADA") {
      throw httpError(409, "Esta actividad ya fue iniciada o cerrada.");
    }
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.iniciarTarea();
  }

  /**
   * Marca tarea como completada y consume insumos.
   * - Usa InventarioService para registrar el consumo (con operarioId/tareaId si tu versión lo soporta).
   * - Cambia estado a APROBADA (lo hace TareaService, cierre directo sin aprobación).
   * - Actualiza evidencias.
   */
  async marcarComoCompletada(
    payload: unknown,
    inventarioService: InventarioService
  ) {
    const { tareaId, evidencias, insumosUsados } =
      MarcarCompletadaDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, conjuntoId: true, borrador: true },
    });
    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.borrador) {
      throw new Error("No se puede completar una tarea en borrador.");
    }
    if (tarea.conjuntoId === null) {
      throw new Error("❌ La tarea no tiene un conjunto asignado.");
    }

    // Si tu InventarioService.consumirInsumoPorId acepta metadata (operarioId/tareaId),
    // puedes pasarla así para evitar duplicados y tener mejor trazabilidad.
    // Ej: await inventarioService.consumirInsumoPorId({ insumoId, cantidad, operarioId: this.operarioId, tareaId })
    await new TareaService(this.prisma, tareaId).marcarComoCompletadaConInsumos(
      { insumosUsados },
      {
        // Adapter que cumple con (payload: unknown) => Promise<void>
        consumirInsumoPorId: async (payload: unknown) => {
          // valida/extrae campos con Zod (opcional pero recomendado)
          const p = z
            .object({
              insumoId: z.number().int().positive(),
              cantidad: z.number().int().positive(),
            })
            .parse(payload);

          // llama a tu InventarioService con el shape que ya acepta
          // si en tu InventarioService agregaste metadata (operarioId/tareaId),
          // complétala aquí.
          await (inventarioService as any).consumirInsumoPorId({
            insumoId: p.insumoId,
            cantidad: p.cantidad,
            // operarioId: this.operarioId,
            // tareaId,
          });
        },
      }
    );

    // Guardar/mergear evidencias (no lo hace TareaService)
    const actuales =
      (
        await this.prisma.tarea.findUnique({
          where: { id: tareaId },
          select: { evidencias: true },
        })
      )?.evidencias ?? [];

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { evidencias: [...actuales, ...evidencias] },
    });
  }

  /** Marca una tarea como NO_COMPLETADA */
  async marcarComoNoCompletada(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, borrador: true },
    });
    if (!tarea || tarea.borrador) {
      throw new Error("La tarea no existe o está en borrador.");
    }
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.marcarNoCompletada();
  }

  /** Tareas del día para este operario */
  async tareasDelDia(payload: unknown) {
    const { fecha } = FechaDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        borrador: false,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
    });
  }

  /**
   * Actividades del operario. Con `desde`/`hasta` limita por fecha de inicio
   * (sin rango devuelve todo, como antes). Incluye a los compañeros de las
   * actividades compartidas, la categoría con la que se pintan y quién las
   * cerró, para que la app del operario muestre lo mismo que el cronograma.
   */
  async listarTareas(rango: { desde?: Date; hasta?: Date } = {}) {
    const fechaInicio =
      rango.desde || rango.hasta
        ? {
            ...(rango.desde ? { gte: rango.desde } : {}),
            ...(rango.hasta ? { lte: rango.hasta } : {}),
          }
        : undefined;
    const tareas = await this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        borrador: false,
        ...(fechaInicio ? { fechaInicio } : {}),
      },
      orderBy: { fechaInicio: "asc" },
      include: {
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
        // Nunca `conjunto: true`: trae mapaConjuntoBytes (la imagen del mapa)
        // por cada tarea y la respuesta de Prisma revienta por tamaño.
        conjunto: { select: { nit: true, nombre: true, direccion: true, activo: true } },
        operarios: {
          select: { id: true, funciones: true, usuario: { select: { nombre: true } } },
        },
      },
    });

    const conCategoria = await adjuntarCategoriaCronograma(this.prisma, tareas);

    const cerradoresIds = Array.from(
      new Set(
        conCategoria
          .map((t) => t.finalizadaPorId)
          .filter((id): id is string => typeof id === "string" && id.length > 0),
      ),
    );
    const cerradores = cerradoresIds.length
      ? await this.prisma.usuario.findMany({
          where: { id: { in: cerradoresIds } },
          select: { id: true, nombre: true },
        })
      : [];
    const nombrePorId = new Map(cerradores.map((u) => [u.id, u.nombre]));

    return conCategoria.map((t) => ({
      ...t,
      finalizadaPorNombre: t.finalizadaPorId ? (nombrePorId.get(t.finalizadaPorId) ?? null) : null,
    }));
  }

  async cerrarTareaConEvidencias(
    tareaId: number,
    payload: unknown,
    files: Express.Multer.File[],
  ): Promise<ResultadoCierreOperario> {
    const recibidoEn = new Date();
    let dto: z.infer<typeof CerrarMultipartDTO>;
    try {
      dto = CerrarMultipartDTO.parse(payload ?? {});
    } catch (err) {
      borrarTemporales(files);
      throw err;
    }
    const accion = dto.accion ?? "COMPLETADA";
    const sinConexion = esVerdadero(dto.sinConexion);

    // La cola offline del operario puede reenviar el mismo cierre si nunca
    // llegó la confirmación (timeout, app cerrada, etc.). Si ya se procesó
    // este clienteCierreId, es un replay: no se vuelve a subir evidencias
    // ni se reprocesa inventario, solo se limpian los archivos temporales
    // que multer ya escribió a disco para esta petición.
    if (dto.clienteCierreId) {
      const yaProcesado = await this.prisma.cierreTareaIdempotencia.findUnique({
        where: { clienteCierreId: dto.clienteCierreId },
      });
      if (yaProcesado) {
        borrarTemporales(files);
        if (yaProcesado.tareaId !== tareaId) {
          throw httpError(
            409,
            "Este cierre ya se usó para otra tarea. Descártalo y ciérrala de nuevo.",
            "CIERRE_ID_REUTILIZADO",
          );
        }
        return { duplicado: true };
      }
    }

    // Hora oficial del cierre: la del celular cuando cerró (puede ser horas
    // antes si estaba sin señal), corregida si su reloj estaba mal.
    const fechaCliente = parsearFecha(dto.fechaFinalizarTarea);
    if (dto.fechaFinalizarTarea && !fechaCliente) {
      borrarTemporales(files);
      throw httpError(400, "La fecha de cierre no es válida.", "FECHA_CIERRE_INVALIDA");
    }
    const desfaseMs = desfaseRelojMs(dto.horaDispositivoEnvio, recibidoEn);
    const horaCierre = resolverHora({
      hora: fechaCliente,
      horaEstimada: parsearFecha(dto.horaEstimada),
      desfaseMs,
      recibidoEn,
    });
    const fechaCierre = horaCierre.hora ?? recibidoEn;
    if (recibidoEn.getTime() - fechaCierre.getTime() > ANTIGUEDAD_MAXIMA_CIERRE_MS) {
      borrarTemporales(files);
      throw httpError(
        400,
        "Este cierre es de hace más de 45 días y ya no se puede registrar. Avísale a tu supervisor.",
        "FECHA_CIERRE_INVALIDA",
      );
    }

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        id: true,
        descripcion: true,
        estado: true,
        borrador: true,
        evidencias: true,
        conjuntoId: true,
        supervisorId: true,
        fechaFinalizarTarea: true,
        finalizadaPorId: true,
        operarios: { select: { id: true } },
        conjunto: {
          select: { nit: true, nombre: true, direccion: true, latitud: true, longitud: true },
        },
      },
    });

    // Rechazos: el operario ve el motivo en la app y sus fotos se quedan en
    // el celular. Los temporales de multer se borran en cada salida.
    const rechazar = (err: Error) => {
      borrarTemporales(files);
      return err;
    };
    if (!tarea) {
      throw rechazar(
        httpError(
          404,
          "Esta tarea ya no existe: la eliminaron mientras estabas sin señal.",
          "TAREA_ELIMINADA",
        ),
      );
    }
    if (tarea.borrador) {
      throw rechazar(
        httpError(409, "No se puede cerrar una tarea en borrador.", "TAREA_EN_BORRADOR"),
      );
    }

    const operarioAsignado = tarea.operarios.some(
      (o) => o.id === this.operarioId.toString(),
    );
    if (!operarioAsignado) {
      throw rechazar(
        httpError(
          409,
          "Esta tarea ya no está asignada a ti: se la pasaron a otro operario.",
          "TAREA_REASIGNADA",
        ),
      );
    }

    const permitidos = new Set<EstadoTarea>([
      EstadoTarea.ASIGNADA,
      EstadoTarea.EN_PROCESO,
      EstadoTarea.COMPLETADA,
    ]);

    if (!permitidos.has(tarea.estado)) {
      throw rechazar(await this.errorTareaNoCerrable(tarea));
    }

    if (accion === "COMPLETADA" && !tarea.conjuntoId) {
      borrarTemporales(files);
      throw new Error(
        "La tarea no tiene conjunto asignado, no puedo descontar inventario.",
      );
    }
    if (accion === "NO_COMPLETADA" && (!dto.observaciones || dto.observaciones.trim().length < 3)) {
      borrarTemporales(files);
      throw new Error("Debes indicar el motivo u observación de por qué no se realizó la tarea.");
    }

    let insumosUsados: Array<{ insumoId: number; cantidad: number }> = [];
    if (accion === "COMPLETADA" && dto.insumosUsados && dto.insumosUsados.trim().length) {
      try {
        insumosUsados = z
          .array(
            z.object({
              insumoId: z.number().int().positive(),
              cantidad: z.number().positive(),
            }),
          )
          .parse(JSON.parse(dto.insumosUsados));
      } catch {
        borrarTemporales(files);
        throw new Error(
          "insumosUsados debe ser un JSON válido: [{insumoId, cantidad}]",
        );
      }
    }

    const actor = await this.prisma.usuario.findUnique({
      where: { id: this.operarioId.toString() },
      select: { nombre: true },
    });
    const subidoPor = actor?.nombre ?? this.operarioId.toString();

    let urls: string[] = [];
    try {
      // Marca de agua de auditoría (hora, conjunto, dirección) antes de
      // subir; se estampa una foto mientras la anterior sube.
      urls = await subirEvidenciasConMarca(
        {
          files: files ?? [],
          capturas: dto.evidenciasCaptura,
          conjunto: tarea.conjunto,
          subidaEn: recibidoEn,
          sinConexion,
          desfaseRelojMs: desfaseMs,
        },
        (f, indice) =>
          uploadEvidenciaToDrive({
            filePath: f.path,
            fileName: buildEvidenciaFileName({
              subidoPor,
              rol: "OPERARIO",
              fecha: fechaCierre,
              originalName: f.originalname,
              indice,
            }),
            mimeType: f.mimetype,
            conjuntoNit: tarea.conjunto?.nit ?? tarea.conjuntoId ?? "SIN_CONJUNTO",
            conjuntoNombre: tarea.conjunto?.nombre ?? undefined,
            fecha: fechaCierre,
          }),
      );
    } finally {
      borrarTemporales(files);
    }

    const evidenciasMerge = [...(tarea.evidencias ?? []), ...urls];

    try {
      await this.prisma.$transaction(async (tx) => {
        const inventario = accion === "COMPLETADA"
          ? await tx.inventario.findUnique({
              where: { conjuntoId: tarea.conjuntoId! },
              select: { id: true },
            })
          : null;

        if (accion === "COMPLETADA" && !inventario) {
          throw new Error("No existe inventario para este conjunto.");
        }

        for (const item of insumosUsados) {
          const invItem = await tx.inventarioInsumo.findUnique({
            where: {
              inventarioId_insumoId: {
                  inventarioId: inventario!.id,
                insumoId: item.insumoId,
              },
            },
            select: { id: true, cantidad: true },
          });

          if (!invItem) {
            throw httpError(
              409,
              `El insumo ${item.insumoId} no existe en inventario del conjunto.`,
              "INSUMO_NO_EN_INVENTARIO",
            );
          }

          const actual = invItem.cantidad;
          const usar = new Prisma.Decimal(item.cantidad);

          if (usar.lte(0)) continue;
          if (actual.lt(usar)) {
            throw httpError(
              409,
              `Stock insuficiente para insumo ${item.insumoId}. Stock=${actual.toString()} / Usar=${usar.toString()}`,
              "STOCK_INSUFICIENTE",
            );
          }

          await tx.inventarioInsumo.update({
            where: { id: invItem.id },
            data: { cantidad: actual.minus(usar) },
          });

          await tx.consumoInsumo.create({
            data: {
              inventario: { connect: { id: inventario!.id } },
              insumo: { connect: { id: item.insumoId } },
              tipo: TipoMovimientoInsumo.SALIDA,
              tarea: { connect: { id: tareaId } },
              operario: { connect: { id: this.operarioId.toString() } },
              cantidad: usar,
              fecha: fechaCierre,
              observacion: `Consumo en cierre de tarea #${tareaId} por operario ${this.operarioId}`,
            },
          });
        }

        await tx.usoMaquinaria.updateMany({
          where: { tareaId, fechaFin: null },
          data: {
            fechaFin: fechaCierre,
            operarioId: this.operarioId.toString(),
            observacion: "Devuelta al cerrar tarea por operario",
          },
        });

        await tx.usoHerramienta.updateMany({
          where: { tareaId, fechaFin: null },
          data: {
            fechaFin: fechaCierre,
            operarioId: this.operarioId.toString(),
            estado: EstadoUsoHerramienta.DEVUELTA,
            observacion: "Devuelta al cerrar tarea por operario",
          },
        });

        await tx.maquinariaConjunto.updateMany({
          where: { tareaId },
          data: { tareaId: null, operarioId: null, fechaDevolucionEstimada: null },
        });

        const estadoResultante =
          accion === "NO_COMPLETADA"
            ? EstadoTarea.NO_COMPLETADA
            : EstadoTarea.APROBADA;

        await tx.tarea.update({
          where: { id: tareaId },
          data: {
            evidencias: evidenciasMerge,
            observaciones: dto.observaciones ?? undefined,
            insumosUsados: accion === "COMPLETADA" ? (insumosUsados as any) : undefined,
            estado: estadoResultante,
            fechaFinalizarTarea: fechaCierre,
            fechaVerificacion:
              accion === "NO_COMPLETADA" ? undefined : fechaCierre,
            finalizadaPorId: this.operarioId.toString(),
            finalizadaPorRol: "OPERARIO",
          },
        });

        if (dto.clienteCierreId) {
          await tx.cierreTareaIdempotencia.create({
            data: {
              clienteCierreId: dto.clienteCierreId,
              tareaId,
              estadoResultante,
              operarioId: this.operarioId.toString(),
              sinConexion,
              recibidoEn,
              desfaseRelojSeg: desfaseMs == null ? null : Math.round(desfaseMs / 1000),
              horaAjustada: horaCierre.ajustada,
            },
          });
        }
      }, { maxWait: 5_000, timeout: 20_000 });
    } catch (err) {
      // Dos copias del mismo cierre llegaron a la vez (la app reintentó porque
      // la primera tardó): ganó la otra. No es un error para el operario; las
      // fotos que subió esta copia sobran y se borran de Drive.
      if (dto.clienteCierreId && esDuplicadoDeIdempotencia(err)) {
        await this.borrarEvidenciasHuerfanas(urls);
        return { duplicado: true };
      }
      throw err;
    }

    if (sinConexion || horaCierre.ajustada) {
      console.log(
        `[cierre-sin-senal] tarea #${tareaId} operario ${this.operarioId}: cerrada ${fechaCierre.toISOString()}, recibida ${recibidoEn.toISOString()}${
          horaCierre.ajustada ? ` (hora corregida: ${horaCierre.motivo})` : ""
        }`,
      );
    }

    try {
      const notificaciones = new NotificacionService(this.prisma);
      if (tarea.conjuntoId) {
        await notificaciones.notificarCierreTarea({
          tareaId,
          descripcionTarea: tarea.descripcion,
          conjuntoId: tarea.conjuntoId,
          actorId: this.operarioId.toString(),
          actorRol: "OPERARIO",
          supervisorId: tarea.supervisorId,
        });
      }
    } catch (e) {
      console.error("No se pudo notificar cierre de tarea (operario):", e);
    }

    return { duplicado: false };
  }

  /**
   * La app pregunta esto antes de reenviar un cierre de su cola: si ya entró
   * (la respuesta se perdió), lo marca como enviado sin volver a subir fotos.
   */
  async estadoCierreCliente(clienteCierreId: string) {
    const fila = await this.prisma.cierreTareaIdempotencia.findUnique({
      where: { clienteCierreId },
      select: { tareaId: true, estadoResultante: true, creadoEn: true, operarioId: true },
    });
    if (!fila || fila.operarioId !== this.operarioId.toString()) {
      return { procesado: false as const };
    }
    return {
      procesado: true as const,
      tareaId: fila.tareaId,
      estadoResultante: fila.estadoResultante,
      registradoEn: fila.creadoEn,
    };
  }

  /** La tarea ya no admite cierre: dice por qué, con quién y cuándo si se sabe. */
  private async errorTareaNoCerrable(tarea: {
    estado: EstadoTarea;
    fechaFinalizarTarea: Date | null;
    finalizadaPorId: string | null;
  }) {
    if (tarea.estado === EstadoTarea.PENDIENTE_REPROGRAMACION) {
      return httpError(
        409,
        "Esta tarea quedó pendiente de reprogramación mientras estabas sin señal; ya no se puede cerrar.",
        "TAREA_REPROGRAMADA",
      );
    }
    if (ESTADOS_YA_CERRADA.has(tarea.estado)) {
      let quien = "";
      if (tarea.finalizadaPorId && tarea.finalizadaPorId !== this.operarioId.toString()) {
        const usuario = await this.prisma.usuario
          .findUnique({ where: { id: tarea.finalizadaPorId }, select: { nombre: true } })
          .catch(() => null);
        if (usuario?.nombre) quien = ` por ${usuario.nombre}`;
      } else if (tarea.finalizadaPorId === this.operarioId.toString()) {
        quien = " por ti";
      }
      const cuando = tarea.fechaFinalizarTarea
        ? ` el ${formatearFechaHora(tarea.fechaFinalizarTarea)}`
        : "";
      return httpError(
        409,
        `Esta tarea ya fue cerrada${quien}${cuando}.`,
        "TAREA_YA_CERRADA",
      );
    }
    return httpError(409, `No puedes cerrar una tarea en estado ${tarea.estado}.`, "TAREA_NO_CERRABLE");
  }

  private async borrarEvidenciasHuerfanas(urls: string[]) {
    for (const url of urls) {
      const id = typeof url === "string" ? extraerDriveId(url) : null;
      if (!id) continue;
      try {
        await eliminarEvidenciaDeDrive(id);
      } catch (e) {
        console.warn("[cierre] No se pudo borrar una evidencia duplicada de Drive:", id);
      }
    }
  }

  /** Suma de horas en la semana (lunes a domingo) de la fecha dada */
  async horasAsignadasEnSemana(fecha: Date): Promise<number> {
    const inicio = this.inicioSemana(fecha);
    const fin = new Date(inicio);
    fin.setDate(inicio.getDate() + 6);
    fin.setHours(23, 59, 59, 999);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        borrador: false,
        fechaFin: { gte: inicio },
        fechaInicio: { lte: fin },
      },
      select: { duracionMinutos: true },
    });

    return tareas.reduce((sum, t) => sum + t.duracionMinutos, 0);
  }

  async horasRestantesEnSemana(payload: unknown): Promise<number> {
    const { fecha } = FechaDTO.parse(payload);
    const limite = await this.getLimiteHorasSemana();
    const horas = await this.horasAsignadasEnSemana(fecha);
    return Math.max(0, limite - horas);
  }

  async resumenDeHoras(payload: unknown): Promise<string> {
    const { fecha } = FechaDTO.parse(payload);
    const limite = await this.getLimiteHorasSemana();
    const horas = await this.horasAsignadasEnSemana(fecha);
    const operario = await this.prisma.operario.findUnique({
      where: { id: this.operarioId.toString() },
      select: { usuario: { select: { nombre: true } } },
    });
    const nombre = operario?.usuario?.nombre ?? "Operario";
    return `🔔 A ${nombre} le quedan ${Math.max(
      0,
      limite - horas
    )}h disponibles esta semana (límite ${limite}h).`;
    // si quieres, puedes retornar también { horasAsignadas: horas, limite, restantes: limite - horas }
  }

  /** Lunes de la semana ISO de la fecha dada */
  private inicioSemana(fecha: Date): Date {
    const d = new Date(fecha);
    const day = d.getDay(); // 0=Dom ... 6=Sab
    const diff = d.getDate() - day + (day === 0 ? -6 : 1); // Lunes
    return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
  }
}
