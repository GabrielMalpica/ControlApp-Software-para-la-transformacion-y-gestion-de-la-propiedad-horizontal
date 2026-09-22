// src/services/InventarioService.ts
import { TipoMovimientoInsumo, CategoriaInsumo } from "@prisma/client";
import { Prisma, PrismaClient } from "@prisma/client";
import { z } from "zod";
import { decToNumber, toDec } from "../utils/decimal";
import {
  CrearInsumoPersonalizadoDTO,
  EditarInsumoPersonalizadoDTO,
} from "../model/Insumo";
import type { ActorAuditoria } from "../model/Auditoria";

const AgregarInsumoDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

const InsumoIdDTO = z.object({
  insumoId: z.number().int().positive(),
});

const ListarBajosDTO = z.object({
  umbral: z.coerce.number().int().min(0).default(5),
  nombre: z.string().optional(),
  categoria: z.string().optional(),
});

const ListarFiltroDTO = z.object({
  nombre: z.string().optional(),
  categoria: z.string().optional(),
});

export const ListarBajosQueryDTO = z.object({
  umbral: z.coerce.number().int().min(0).optional(),
  nombre: z.string().optional(),
  categoria: z.string().optional(),
});

const AgregarStockDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.coerce.number().positive(),

  operarioId: z.string().optional(),
  observacion: z.string().optional(),
});

const ConsumirDTO = z.object({
  // Solo lo necesita consumirInsumoPorId (busca el inventario por conjunto).
  // consumirStock no lo usa: ya opera sobre this.inventarioId.
  conjuntoId: z.string().min(1).optional(),
  insumoId: z.number().int().positive(),
  cantidad: z.coerce.number().positive(), // 👈 decimal ok
  operarioId: z.string().min(1).optional(),
  tareaId: z.number().int().positive().optional(),
  observacion: z.string().max(500).optional(),
});

export const SetUmbralDTO = z.object({
  insumoId: z.number().int().positive(),
  umbralMinimo: z.coerce.number().int().min(0),
});

/**
 * cantidad (num. de "unidad" contadas, ej. tarros) * contenidoPorUnidad
 * (ej. 1.8 L por tarro) = total real disponible en unidadContenido.
 * Null cuando no se conoce el contenido por unidad (ej. items que se
 * cuentan por unidad simple, como escobas).
 */
function calcularTotalDisponible(
  cantidad: number,
  contenidoPorUnidad: Prisma.Decimal | number | null | undefined,
): number | null {
  if (contenidoPorUnidad === null || contenidoPorUnidad === undefined) {
    return null;
  }
  return cantidad * decToNumber(contenidoPorUnidad);
}

export class InventarioService {
  constructor(
    private prisma: PrismaClient,
    private inventarioId: number,
    private actor?: ActorAuditoria,
  ) {}

  private async nombresUsuarios(ids: (string | null | undefined)[]) {
    const unicos = Array.from(
      new Set(ids.filter((id): id is string => typeof id === "string" && id.length > 0)),
    );
    if (!unicos.length) return new Map<string, string>();
    const usuarios = await this.prisma.usuario.findMany({
      where: { id: { in: unicos } },
      select: { id: true, nombre: true },
    });
    return new Map(usuarios.map((u) => [u.id, u.nombre]));
  }

  /* ========= Stock básico ========= */

  /**
   * Crea un insumo "personalizado" (no pasa por el catálogo de empresa, no es
   * comprable via Woo) y lo agrega de una vez al inventario de este conjunto
   * con su stock inicial. Pensado para presentaciones propias del conjunto
   * (ej. "Clorox galón" en vez del "Clorox 1L x6" del catálogo) o para
   * insumos que la empresa no vende pero el cliente quiere controlar.
   */
  async crearInsumoPersonalizado(
    payload: unknown,
    ctx: { empresaId: string; conjuntoId: string },
  ) {
    const dto = CrearInsumoPersonalizadoDTO.parse(payload);
    const cantidadInicial = dto.cantidadInicial ?? 0;

    return this.prisma.$transaction(async (tx) => {
      // Puede existir un Insumo huérfano con el mismo nombre/unidad si antes
      // se eliminó del inventario (eliminarInsumo solo borra el vínculo
      // InventarioInsumo, no el catálogo). En ese caso lo reutilizamos en vez
      // de fallar por duplicado.
      const existente = await tx.insumo.findFirst({
        where: {
          empresaId: ctx.empresaId,
          conjuntoId: ctx.conjuntoId,
          nombre: dto.nombre,
          unidad: dto.unidad,
        },
        select: { id: true },
      });

      if (existente) {
        const vinculado = await tx.inventarioInsumo.findUnique({
          where: {
            inventarioId_insumoId: {
              inventarioId: this.inventarioId,
              insumoId: existente.id,
            },
          },
          select: { id: true },
        });
        if (vinculado) {
          throw new Error(
            "Ya existe un insumo personalizado con ese nombre y unidad en este conjunto.",
          );
        }
      }

      const contenidoPorUnidad = dto.contenidoPorUnidad
        ? toDec(dto.contenidoPorUnidad)
        : null;
      const unidadContenido = dto.unidadContenido ?? null;

      const insumo = existente
        ? await tx.insumo.update({
            where: { id: existente.id },
            data: {
              categoria: dto.categoria,
              umbralBajo: dto.umbralBajo ?? null,
              contenidoPorUnidad,
              unidadContenido,
            },
          })
        : await tx.insumo.create({
            data: {
              nombre: dto.nombre,
              unidad: dto.unidad,
              categoria: dto.categoria,
              umbralBajo: dto.umbralBajo ?? null,
              empresaId: ctx.empresaId,
              conjuntoId: ctx.conjuntoId,
              contenidoPorUnidad,
              unidadContenido,
              creadoPorId: this.actor?.id ?? null,
            },
          });

      const inventarioInsumo = await tx.inventarioInsumo.create({
        data: {
          inventarioId: this.inventarioId,
          insumoId: insumo.id,
          cantidad: toDec(cantidadInicial),
        },
      });

      if (cantidadInicial > 0) {
        await tx.consumoInsumo.create({
          data: {
            inventarioId: this.inventarioId,
            insumoId: insumo.id,
            tipo: TipoMovimientoInsumo.ENTRADA,
            cantidad: toDec(cantidadInicial),
            fecha: new Date(),
            observacion: "Stock inicial - insumo personalizado",
          },
        });
      }

      return {
        inventarioInsumoId: inventarioInsumo.id,
        insumoId: insumo.id,
        nombre: insumo.nombre,
        unidad: insumo.unidad,
        categoria: insumo.categoria as CategoriaInsumo,
        umbralBajo: insumo.umbralBajo,
        umbralMinimo: inventarioInsumo.umbralMinimo ?? null,
        cantidad: cantidadInicial,
        personalizado: true,
        contenidoPorUnidad: insumo.contenidoPorUnidad
          ? decToNumber(insumo.contenidoPorUnidad)
          : null,
        unidadContenido: insumo.unidadContenido,
        totalDisponible: calcularTotalDisponible(
          cantidadInicial,
          insumo.contenidoPorUnidad,
        ),
        creadoPorId: insumo.creadoPorId,
        creadoPorNombre: this.actor?.nombre ?? null,
        creadoEn: insumo.creadoEn,
      };
    });
  }

  /**
   * Edita un insumo personalizado de este conjunto (nombre, unidad,
   * categoria, umbral, contenido medible). No permite tocar el catálogo de
   * empresa (conjuntoId "") ni insumos personalizados de otro conjunto.
   */
  async editarInsumoPersonalizado(
    insumoId: number,
    payload: unknown,
    ctx: { empresaId: string; conjuntoId: string },
  ) {
    const dto = EditarInsumoPersonalizadoDTO.parse(payload);

    return this.prisma.$transaction(async (tx) => {
      const actual = await tx.insumo.findUnique({ where: { id: insumoId } });
      if (
        !actual ||
        actual.empresaId !== ctx.empresaId ||
        actual.conjuntoId !== ctx.conjuntoId
      ) {
        throw new Error(
          "Este insumo no es un insumo personalizado de este conjunto.",
        );
      }

      const nombre = dto.nombre ?? actual.nombre;
      const unidad = dto.unidad ?? actual.unidad;

      if (nombre !== actual.nombre || unidad !== actual.unidad) {
        const duplicado = await tx.insumo.findFirst({
          where: {
            empresaId: ctx.empresaId,
            conjuntoId: ctx.conjuntoId,
            nombre,
            unidad,
            NOT: { id: insumoId },
          },
          select: { id: true },
        });
        if (duplicado) {
          throw new Error(
            "Ya existe otro insumo personalizado con ese nombre y unidad en este conjunto.",
          );
        }
      }

      const insumo = await tx.insumo.update({
        where: { id: insumoId },
        data: {
          nombre,
          unidad,
          categoria: dto.categoria ?? actual.categoria,
          umbralBajo:
            dto.umbralBajo === undefined ? actual.umbralBajo : dto.umbralBajo,
          contenidoPorUnidad:
            dto.contenidoPorUnidad === undefined
              ? actual.contenidoPorUnidad
              : dto.contenidoPorUnidad
                ? toDec(dto.contenidoPorUnidad)
                : null,
          unidadContenido:
            dto.unidadContenido === undefined
              ? actual.unidadContenido
              : dto.unidadContenido,
        },
      });

      const inventarioInsumo = await tx.inventarioInsumo.findUnique({
        where: {
          inventarioId_insumoId: {
            inventarioId: this.inventarioId,
            insumoId,
          },
        },
      });
      const cantidad = decToNumber(inventarioInsumo?.cantidad ?? 0);

      return {
        inventarioInsumoId: inventarioInsumo?.id ?? null,
        insumoId: insumo.id,
        nombre: insumo.nombre,
        unidad: insumo.unidad,
        categoria: insumo.categoria as CategoriaInsumo,
        umbralBajo: insumo.umbralBajo,
        umbralMinimo: inventarioInsumo?.umbralMinimo ?? null,
        cantidad,
        personalizado: true,
        contenidoPorUnidad: insumo.contenidoPorUnidad
          ? decToNumber(insumo.contenidoPorUnidad)
          : null,
        unidadContenido: insumo.unidadContenido,
        totalDisponible: calcularTotalDisponible(
          cantidad,
          insumo.contenidoPorUnidad,
        ),
      };
    });
  }

  /**
   * Elimina un insumo personalizado del inventario de este conjunto. Si no
   * tiene historial de movimientos, borra tambien el registro del insumo;
   * si tiene historial (ConsumoInsumo, etc.) solo se desvincula del
   * inventario para no perder ese historial, igual que eliminarInsumo.
   */
  async eliminarInsumoPersonalizado(
    insumoId: number,
    ctx: { conjuntoId: string },
  ) {
    const insumo = await this.prisma.insumo.findUnique({
      where: { id: insumoId },
      select: { id: true, conjuntoId: true },
    });
    if (!insumo || insumo.conjuntoId !== ctx.conjuntoId) {
      throw new Error(
        "Este insumo no es un insumo personalizado de este conjunto.",
      );
    }

    await this.prisma.inventarioInsumo.delete({
      where: {
        inventarioId_insumoId: { inventarioId: this.inventarioId, insumoId },
      },
    });

    // Solo se borra el registro del insumo si no tiene historial (evita
    // depender de como cada driver reporta la violacion de FK). Si tiene
    // movimientos u otras referencias, se deja huerfano: crearInsumoPersonalizado
    // lo reutiliza si se vuelve a crear con el mismo nombre/unidad.
    const [consumos, otrosInventarios] = await Promise.all([
      this.prisma.consumoInsumo.count({ where: { insumoId } }),
      this.prisma.inventarioInsumo.count({ where: { insumoId } }),
    ]);
    if (consumos === 0 && otrosInventarios === 0) {
      await this.prisma.insumo
        .delete({ where: { id: insumoId } })
        .catch(() => undefined);
    }
  }

  async agregarInsumo(payload: unknown) {
    const { insumoId, cantidad } = AgregarInsumoDTO.parse(payload);

    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      select: { id: true },
    });

    if (existente) {
      return this.prisma.inventarioInsumo.update({
        where: { id: existente.id },
        data: { cantidad: { increment: cantidad } },
      });
    }
    return this.prisma.inventarioInsumo.create({
      data: { inventarioId: this.inventarioId, insumoId, cantidad },
    });
  }

  async listarInsumosDetallado(payload?: unknown) {
    const { nombre, categoria } = ListarFiltroDTO.parse(payload ?? {});

    const rows = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId },
      include: { insumo: true },
      orderBy: [{ insumo: { nombre: "asc" } }],
    });

    const nombresPorId = await this.nombresUsuarios(
      rows.map((r) => (r.insumo as any).creadoPorId as string | null),
    );

    // filtros suaves (no rompen si categoria no existe en Insumo)
    return rows
      .filter((r) => {
        const nombreOk =
          !nombre ||
          r.insumo.nombre.toLowerCase().includes(nombre.toLowerCase());
        const cat = (r.insumo as any).categoria as string | undefined;
        const categoriaOk = !categoria || cat === categoria;
        return nombreOk && categoriaOk;
      })
      .map((r) => {
        const cantidad = decToNumber(r.cantidad);
        const creadoPorId = (r.insumo as any).creadoPorId as string | null;
        return {
          inventarioInsumoId: r.id,
          insumoId: r.insumoId,
          nombre: r.insumo.nombre,
          unidad: r.insumo.unidad,
          categoria:
            ((r.insumo as any).categoria as string | undefined) ?? null,
          umbralBajo:
            ((r.insumo as any).umbralBajo as number | undefined) ?? null,
          umbralMinimo: r.umbralMinimo ?? null,
          cantidad,
          personalizado: Boolean((r.insumo as any).conjuntoId),
          contenidoPorUnidad: r.insumo.contenidoPorUnidad
            ? decToNumber(r.insumo.contenidoPorUnidad)
            : null,
          unidadContenido: r.insumo.unidadContenido,
          creadoPorId,
          creadoPorNombre: creadoPorId ? nombresPorId.get(creadoPorId) ?? null : null,
          creadoEn: (r.insumo as any).creadoEn as Date | null,
          totalDisponible: calcularTotalDisponible(
            cantidad,
            r.insumo.contenidoPorUnidad,
          ),
        };
      });
  }

  async agregarStock(payload: unknown) {
    const dto = AgregarStockDTO.parse(payload);

    // 1) upsert inventario
    const updated = await this.prisma.inventarioInsumo.upsert({
      where: {
        inventarioId_insumoId: {
          inventarioId: this.inventarioId,
          insumoId: dto.insumoId,
        },
      },
      update: {
        cantidad: { increment: toDec(dto.cantidad) },
      },
      create: {
        inventarioId: this.inventarioId,
        insumoId: dto.insumoId,
        cantidad: toDec(dto.cantidad),
      },
    });

    // 2) registrar movimiento ENTRADA
    await this.prisma.consumoInsumo.create({
      data: {
        inventarioId: this.inventarioId,
        insumoId: dto.insumoId,
        tipo: TipoMovimientoInsumo.ENTRADA,
        cantidad: toDec(dto.cantidad),
        fecha: new Date(),
        operarioId: dto.operarioId ?? null,
        observacion: dto.observacion ?? "Ingreso manual",
        registradoPorId: this.actor?.id ?? null,
      },
    });

    return {
      inventarioInsumoId: updated.id,
      insumoId: updated.insumoId,
      cantidad: decToNumber(updated.cantidad),
    };
  }

  async eliminarInsumo(payload: unknown) {
    const { insumoId } = InsumoIdDTO.parse(payload);

    await this.prisma.inventarioInsumo.delete({
      where: {
        inventarioId_insumoId: { inventarioId: this.inventarioId, insumoId },
      },
    });
  }

  async buscarInsumoPorId(payload: unknown) {
    const { insumoId } = InsumoIdDTO.parse(payload);

    const row = await this.prisma.inventarioInsumo.findUnique({
      where: {
        inventarioId_insumoId: { inventarioId: this.inventarioId, insumoId },
      },
      include: { insumo: true },
    });

    if (!row) return null;

    const cantidad = decToNumber(row.cantidad);
    return {
      inventarioInsumoId: row.id,
      insumoId: row.insumoId,
      nombre: row.insumo.nombre,
      unidad: row.insumo.unidad,
      categoria: ((row.insumo as any).categoria as string | undefined) ?? null,
      umbralBajo:
        ((row.insumo as any).umbralBajo as number | undefined) ?? null,
      umbralMinimo: row.umbralMinimo ?? null,
      cantidad,
      personalizado: Boolean((row.insumo as any).conjuntoId),
      contenidoPorUnidad: row.insumo.contenidoPorUnidad
        ? decToNumber(row.insumo.contenidoPorUnidad)
        : null,
      unidadContenido: row.insumo.unidadContenido,
      totalDisponible: calcularTotalDisponible(
        cantidad,
        row.insumo.contenidoPorUnidad,
      ),
    };
  }

  async consumirInsumoPorId(payload: unknown) {
    const dto = ConsumirDTO.parse(payload);
    if (!dto.conjuntoId) {
      throw new Error("conjuntoId es requerido para consumirInsumoPorId.");
    }

    const cant = new Prisma.Decimal(dto.cantidad);

    return this.prisma.$transaction(async (tx) => {
      // 1) Buscar inventario del conjunto
      // Ajusta esto si tu Inventario se encuentra diferente
      const inventario = await tx.inventario.findFirst({
        where: { conjuntoId: dto.conjuntoId },
        select: { id: true },
      });

      if (!inventario) {
        throw new Error("No existe inventario para este conjunto.");
      }

      // 2) Buscar el registro del insumo en el inventario
      const invItem = await tx.inventarioInsumo.findFirst({
        where: {
          inventarioId: inventario.id,
          insumoId: dto.insumoId,
        },
        select: {
          id: true,
          // 👇 AJUSTA este nombre si no es `cantidad`
          cantidad: true,
        },
      });

      if (!invItem) {
        throw new Error(
          "Este insumo no está registrado en el inventario del conjunto.",
        );
      }

      // 3) Validar stock suficiente
      const disponible = new Prisma.Decimal(invItem.cantidad as any);
      if (disponible.lt(cant)) {
        throw new Error(
          `Stock insuficiente. Disponible: ${disponible.toString()} - Requerido: ${cant.toString()}`,
        );
      }

      // 4) Descontar stock
      await tx.inventarioInsumo.update({
        where: { id: invItem.id },
        data: {
          // 👇 AJUSTA si tu campo no se llama `cantidad`
          cantidad: { decrement: cant },
        },
      });

      // 5) Registrar movimiento (ConsumoInsumo = SALIDA)
      await tx.consumoInsumo.create({
        data: {
          inventario: { connect: { id: inventario.id } },
          insumo: { connect: { id: dto.insumoId } },
          tipo: TipoMovimientoInsumo.SALIDA,
          cantidad: cant,
          fecha: new Date(),
          observacion: dto.observacion ?? null,

          // relaciones opcionales
          ...(dto.operarioId
            ? { operario: { connect: { id: dto.operarioId } } }
            : {}),
          ...(dto.tareaId ? { tarea: { connect: { id: dto.tareaId } } } : {}),
        },
      });

      return { ok: true };
    });
  }

  async consumirStock(payload: unknown) {
    const dto = ConsumirDTO.parse(payload);

    // transacción para consistencia
    return this.prisma.$transaction(async (tx) => {
      const existente = await tx.inventarioInsumo.findUnique({
        where: {
          inventarioId_insumoId: {
            inventarioId: this.inventarioId,
            insumoId: dto.insumoId,
          },
        },
        include: { insumo: true },
      });

      if (!existente) {
        throw new Error(
          `El insumo con ID "${dto.insumoId}" no existe en el inventario.`,
        );
      }

      const disponible = decToNumber(existente.cantidad);
      if (disponible < dto.cantidad) {
        throw new Error(
          `Cantidad insuficiente de "${existente.insumo.nombre}". Disponible: ${disponible}`,
        );
      }

      const updated = await tx.inventarioInsumo.update({
        where: { id: existente.id },
        data: { cantidad: { decrement: toDec(dto.cantidad) } },
      });

      await tx.consumoInsumo.create({
        data: {
          inventarioId: this.inventarioId,
          insumoId: dto.insumoId,
          tipo: TipoMovimientoInsumo.SALIDA,
          cantidad: toDec(dto.cantidad),
          fecha: new Date(),
          operarioId: dto.operarioId ?? null,
          tareaId: dto.tareaId ?? null,
          observacion: dto.observacion ?? "Salida manual",
          registradoPorId: this.actor?.id ?? null,
        },
      });

      return {
        inventarioInsumoId: updated.id,
        insumoId: updated.insumoId,
        cantidad: decToNumber(updated.cantidad),
      };
    });
  }

  /**
   * Kardex: historial de entradas/salidas de un insumo en este inventario,
   * con saldo corriente calculado desde el primer movimiento. Requiere que
   * todo ingreso/salida se registre como ConsumoInsumo (ya es el caso: stock
   * inicial, agregarStock, consumirStock y el consumo al cerrar tareas).
   */
  async listarMovimientos(insumoId: number) {
    const movimientos = await this.prisma.consumoInsumo.findMany({
      where: { inventarioId: this.inventarioId, insumoId },
      orderBy: { fecha: "asc" },
      include: {
        operario: { select: { usuario: { select: { nombre: true } } } },
        tarea: { select: { id: true, descripcion: true } },
      },
    });

    const nombresPorId = await this.nombresUsuarios(
      movimientos.map((m) => (m as any).registradoPorId as string | null),
    );

    let saldo = 0;
    const conSaldo = movimientos.map((m) => {
      const cantidad = decToNumber(m.cantidad);
      saldo += m.tipo === TipoMovimientoInsumo.ENTRADA ? cantidad : -cantidad;
      const registradoPorId = (m as any).registradoPorId as string | null;
      const operarioNombre = m.operario?.usuario.nombre ?? null;
      const registradoPorNombre = registradoPorId
        ? nombresPorId.get(registradoPorId) ?? null
        : null;
      // De donde vino el movimiento, para que el front elija la frase
      // correcta ("compró", "se usó en la tarea X", "registrado manualmente
      // por"): compra (pedidoAppId), cierre de tarea (tareaId) o manual.
      const origen = m.pedidoAppId
        ? "COMPRA"
        : m.tareaId
          ? "TAREA"
          : "MANUAL";
      return {
        id: m.id,
        tipo: m.tipo as TipoMovimientoInsumo,
        cantidad,
        saldo,
        fecha: m.fecha,
        observacion: m.observacion,
        operario: operarioNombre,
        registradoPorNombre,
        responsableNombre: operarioNombre ?? registradoPorNombre,
        origen,
        tareaId: m.tareaId,
        tareaDescripcion: m.tarea?.descripcion ?? null,
      };
    });

    return conSaldo.reverse(); // más reciente primero
  }

  async listarInsumos(): Promise<string[]> {
    const insumos = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId },
      include: { insumo: true },
    });
    return insumos.map(
      (i) => `${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad}`,
    );
  }

  /* ========= Insumos bajos con umbral efectivo + filtros =========
     - umbralEfectivo = inventarioInsumo.umbralMinimo ?? insumo.umbralGlobalMinimo ?? umbralParam
     - Si aún no tienes esos campos en Prisma, el cálculo usa solo umbralParam (no rompe).
  */
  async listarInsumosBajos(payload?: unknown) {
    const { umbral, nombre, categoria } = ListarBajosDTO.parse(payload ?? {});

    const rows = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId },
      include: { insumo: true },
      orderBy: [{ insumo: { nombre: "asc" } }],
    });

    const salida: Array<{
      inventarioInsumoId: number;
      insumoId: number;
      nombre: string;
      unidad: string;
      categoria: string | null;
      cantidad: number;
      umbralUsado: number;
      umbralMinimo: number | null;
      umbralBajo: number | null;
      personalizado: boolean;
      contenidoPorUnidad: number | null;
      unidadContenido: string | null;
      totalDisponible: number | null;
    }> = [];

    for (const r of rows) {
      const nombreOk =
        !nombre || r.insumo.nombre.toLowerCase().includes(nombre.toLowerCase());

      const cat = (r.insumo as any).categoria as string | undefined;
      const categoriaOk = !categoria || cat === categoria;
      if (!nombreOk || !categoriaOk) continue;

      // Umbral efectivo:
      // inventarioInsumo.umbralMinimo ?? insumo.umbralBajo ?? umbralParam
      const umbralGlobal = (r.insumo as any).umbralBajo as number | undefined;
      const umbralLocal = r.umbralMinimo ?? undefined;

      const umbralEfectivo =
        (typeof umbralLocal === "number" ? umbralLocal : undefined) ??
        (typeof umbralGlobal === "number" ? umbralGlobal : undefined) ??
        umbral;

      const cant = decToNumber(r.cantidad);

      if (cant <= umbralEfectivo) {
        salida.push({
          inventarioInsumoId: r.id,
          insumoId: r.insumoId,
          nombre: r.insumo.nombre,
          unidad: r.insumo.unidad,
          categoria: cat ?? null,
          cantidad: cant,
          umbralUsado: umbralEfectivo,
          umbralMinimo: r.umbralMinimo ?? null,
          umbralBajo: umbralGlobal ?? null,
          personalizado: Boolean((r.insumo as any).conjuntoId),
          contenidoPorUnidad: r.insumo.contenidoPorUnidad
            ? decToNumber(r.insumo.contenidoPorUnidad)
            : null,
          unidadContenido: r.insumo.unidadContenido,
          totalDisponible: calcularTotalDisponible(
            cant,
            r.insumo.contenidoPorUnidad,
          ),
        });
      }
    }

    return salida;
  }

  // ===================== UMBRAL LOCAL (opcional UI admin) =====================
  async setUmbralMinimo(payload: unknown) {
    const dto = SetUmbralDTO.parse(payload);

    // si el insumo no existe en inventario, lo creamos con cantidad 0
    await this.prisma.inventarioInsumo.upsert({
      where: {
        inventarioId_insumoId: {
          inventarioId: this.inventarioId,
          insumoId: dto.insumoId,
        },
      },
      update: { umbralMinimo: dto.umbralMinimo },
      create: {
        inventarioId: this.inventarioId,
        insumoId: dto.insumoId,
        cantidad: toDec(0),
        umbralMinimo: dto.umbralMinimo,
      },
    });
  }

  async unsetUmbralMinimo(payload: unknown) {
    const { insumoId } = InsumoIdDTO.parse(payload);

    // si no existe, no pasa nada
    await this.prisma.inventarioInsumo.updateMany({
      where: { inventarioId: this.inventarioId, insumoId },
      data: { umbralMinimo: null },
    });
  }
}
