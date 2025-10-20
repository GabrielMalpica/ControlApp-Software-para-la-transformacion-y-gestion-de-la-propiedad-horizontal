// src/services/InventarioService.ts
import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

const AgregarInsumoDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

const InsumoIdDTO = z.object({
  insumoId: z.number().int().positive(),
});

const UmbralQueryDTO = z.object({
  umbral: z.number().int().min(0).default(5),
  nombre: z.string().optional(),
  // Si aún NO tienes CategoriaInsumo en Prisma, este filtro simplemente se ignora.
  categoria: z.string().optional(),
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

  async agregarStock(payload: unknown) {
    return this.agregarInsumo(payload);
  }

  async eliminarInsumo(payload: unknown) {
    const { insumoId } = InsumoIdDTO.parse(payload);
    await this.prisma.inventarioInsumo.deleteMany({
      where: { inventarioId: this.inventarioId, insumoId },
    });
  }

  async buscarInsumoPorId(payload: unknown) {
    const { insumoId } = InsumoIdDTO.parse(payload);
    return this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      include: { insumo: true },
    });
  }

  async consumirInsumoPorId(payload: unknown) {
    const { insumoId, cantidad } = AgregarInsumoDTO.parse(payload); // mismas reglas

    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      include: { insumo: true },
    });

    if (!existente) throw new Error(`El insumo con ID "${insumoId}" no existe en el inventario.`);
    if (existente.cantidad < cantidad) {
      throw new Error(`Cantidad insuficiente de "${existente.insumo.nombre}". Disponible: ${existente.cantidad}`);
    }

    await this.prisma.inventarioInsumo.update({
      where: { id: existente.id },
      data: { cantidad: { decrement: cantidad } },
    });

    await this.prisma.consumoInsumo.create({
      data: {
        inventarioId: this.inventarioId,
        insumoId,
        cantidad,
        fecha: new Date(),
      },
    });
  }

  async consumirStock(payload: unknown) {
    return this.consumirInsumoPorId(payload);
  }

  async listarInsumos(): Promise<string[]> {
    const insumos = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId },
      include: { insumo: true },
    });
    return insumos.map((i) => `${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad}`);
  }

  /* ========= Insumos bajos con umbral efectivo + filtros =========
     - umbralEfectivo = inventarioInsumo.umbralMinimo ?? insumo.umbralGlobalMinimo ?? umbralParam
     - Si aún no tienes esos campos en Prisma, el cálculo usa solo umbralParam (no rompe).
  */
  async listarInsumosBajos(payload?: unknown): Promise<
    Array<{
      id: number;
      insumoId: number;
      nombre: string;
      unidad: string;
      cantidad: number;
      umbralUsado: number;
      categoria?: string | null; // si existe en tu schema
    }>
  > {
    const { umbral, nombre, categoria } = UmbralQueryDTO.parse(payload ?? {});

    // Traemos el insumo completo para poder (opcionalmente) filtrar por nombre/categoría y leer umbralGlobalMinimo
    const filas = await this.prisma.inventarioInsumo.findMany({
      where: {
        inventarioId: this.inventarioId,
        // Filtros por nombre/categoría se aplican en memoria para no romper si aún no existen campos en Prisma
      },
      include: {
        insumo: true,
      },
      orderBy: { id: "asc" },
    });

    const salida: Array<{
      id: number;
      insumoId: number;
      nombre: string;
      unidad: string;
      cantidad: number;
      umbralUsado: number;
      categoria?: string | null;
    }> = [];

    for (const row of filas) {
      const nombreOk = !nombre || row.insumo.nombre.toLowerCase().includes(nombre.toLowerCase());
      // Si tu Prisma todavía NO tiene insumo.categoria, esto será undefined y el filtro no excluirá nada
      const categoriaActual = (row.insumo as any).categoria as string | undefined;
      const categoriaOk = !categoria || categoriaActual === categoria;

      if (!nombreOk || !categoriaOk) continue;

      // Si no tienes estos campos aún, se vuelven undefined y usamos el param
      const umbralGlobal = (row.insumo as any).umbralGlobalMinimo as number | undefined;
      const umbralLocal = (row as any).umbralMinimo as number | undefined;

      const umbralEfectivo =
        (typeof umbralLocal === "number" ? umbralLocal : undefined) ??
        (typeof umbralGlobal === "number" ? umbralGlobal : undefined) ??
        umbral;

      if (row.cantidad <= umbralEfectivo) {
        salida.push({
          id: row.id,
          insumoId: row.insumoId,
          nombre: row.insumo.nombre,
          unidad: row.insumo.unidad,
          cantidad: row.cantidad,
          umbralUsado: umbralEfectivo,
          categoria: categoriaActual ?? null,
        });
      }
    }

    // Si quieres la salida como strings (como tenías), puedes mapear aquí:
    // return salida.map(i => `⚠️ ${i.nombre}: ${i.cantidad} ${i.unidad} (umbral ${i.umbralUsado})`);
    return salida;
  }

  /* ========= (Opcional futuro) Umbral por inventario-insumo =========
     Activa cuando agregues el campo `umbralMinimo Int?` en `InventarioInsumo`.
     De momento quedan como referencia (comentados para no romper tu build).
  */

  // async setUmbralMinimo(payload: unknown) {
  //   const dto = z.object({
  //     insumoId: z.number().int().positive(),
  //     umbralMinimo: z.number().int().min(0),
  //   }).parse(payload);
  //
  //   const existente = await this.prisma.inventarioInsumo.findFirst({
  //     where: { inventarioId: this.inventarioId, insumoId: dto.insumoId },
  //     select: { id: true },
  //   });
  //   if (!existente) {
  //     // crea registro con umbral
  //     await this.prisma.inventarioInsumo.create({
  //       data: {
  //         inventarioId: this.inventarioId,
  //         insumoId: dto.insumoId,
  //         cantidad: 0,
  //         // @ts-expect-error — aparece cuando ya migres Prisma
  //         umbralMinimo: dto.umbralMinimo,
  //       },
  //     });
  //     return;
  //   }
  //   await this.prisma.inventarioInsumo.update({
  //     where: { id: existente.id },
  //     data: {
  //       // @ts-expect-error — aparece cuando ya migres Prisma
  //       umbralMinimo: dto.umbralMinimo,
  //     },
  //   });
  // }
  //
  // async unsetUmbralMinimo(payload: unknown) {
  //   const { insumoId } = InsumoIdDTO.parse(payload);
  //   const existente = await this.prisma.inventarioInsumo.findFirst({
  //     where: { inventarioId: this.inventarioId, insumoId },
  //     select: { id: true },
  //   });
  //   if (!existente) return;
  //   await this.prisma.inventarioInsumo.update({
  //     where: { id: existente.id },
  //     data: {
  //       // @ts-expect-error — aparece cuando ya migres Prisma
  //       umbralMinimo: null,
  //     },
  //   });
  // }
}
