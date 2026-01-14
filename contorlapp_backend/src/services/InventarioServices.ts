// src/services/InventarioService.ts
import { PrismaClient, TipoMovimientoInsumo } from "../generated/prisma";
import { z } from "zod";
import { decToNumber, toDec } from "../utils/decimal";

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

const ConsumirStockDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.coerce.number().positive(),
  // opcional: para trazabilidad
  tareaId: z.number().int().positive().optional(),
  operarioId: z.string().optional(),
  observacion: z.string().optional(),
});

export const SetUmbralDTO = z.object({
  insumoId: z.number().int().positive(),
  umbralMinimo: z.coerce.number().int().min(0),
});

export class InventarioService {
  constructor(private prisma: PrismaClient, private inventarioId: number) {}

  /* ========= Stock básico ========= */

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
      .map((r) => ({
        inventarioInsumoId: r.id,
        insumoId: r.insumoId,
        nombre: r.insumo.nombre,
        unidad: r.insumo.unidad,
        categoria: ((r.insumo as any).categoria as string | undefined) ?? null,
        umbralBajo:
          ((r.insumo as any).umbralBajo as number | undefined) ?? null,
        umbralMinimo: r.umbralMinimo ?? null,
        cantidad: decToNumber(r.cantidad),
      }));
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
        observacion: dto.observacion ?? null,
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

    return {
      inventarioInsumoId: row.id,
      insumoId: row.insumoId,
      nombre: row.insumo.nombre,
      unidad: row.insumo.unidad,
      categoria: ((row.insumo as any).categoria as string | undefined) ?? null,
      umbralBajo:
        ((row.insumo as any).umbralBajo as number | undefined) ?? null,
      umbralMinimo: row.umbralMinimo ?? null,
      cantidad: decToNumber(row.cantidad),
    };
  }

  async consumirInsumoPorId(payload: unknown) {
    const { insumoId, cantidad, tareaId, operarioId, observacion } =
      ConsumirStockDTO.parse(payload);

    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      include: { insumo: true },
    });

    if (!existente) {
      throw new Error(
        `El insumo con ID "${insumoId}" no existe en el inventario.`
      );
    }

    const disponibleNum = decToNumber(existente.cantidad);
    if (disponibleNum < cantidad) {
      throw new Error(
        `Cantidad insuficiente de "${existente.insumo.nombre}". Disponible: ${disponibleNum}`
      );
    }

    await this.prisma.inventarioInsumo.update({
      where: { id: existente.id },
      data: { cantidad: { decrement: toDec(cantidad) } },
    });

    await this.prisma.consumoInsumo.create({
      data: {
        inventarioId: this.inventarioId,
        insumoId,
        cantidad: toDec(cantidad),
        fecha: new Date(),
        // si existe en tu schema:
        // tipo: "SALIDA",
        // tareaId: tareaId ?? null,
        // operarioId: operarioId ?? null,
        // observacion: observacion ?? null,
      } as any,
    });
  }

  async consumirStock(payload: unknown) {
    const dto = ConsumirStockDTO.parse(payload);

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
          `El insumo con ID "${dto.insumoId}" no existe en el inventario.`
        );
      }

      const disponible = decToNumber(existente.cantidad);
      if (disponible < dto.cantidad) {
        throw new Error(
          `Cantidad insuficiente de "${existente.insumo.nombre}". Disponible: ${disponible}`
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
          observacion: dto.observacion ?? null,
        },
      });

      return {
        inventarioInsumoId: updated.id,
        insumoId: updated.insumoId,
        cantidad: decToNumber(updated.cantidad),
      };
    });
  }

  async listarInsumos(): Promise<string[]> {
    const insumos = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId },
      include: { insumo: true },
    });
    return insumos.map(
      (i) => `${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad}`
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
