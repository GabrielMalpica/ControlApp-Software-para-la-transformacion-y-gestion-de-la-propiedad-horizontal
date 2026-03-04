"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.InventarioService = exports.SetUmbralDTO = exports.ListarBajosQueryDTO = void 0;
// src/services/InventarioService.ts
const client_1 = require("@prisma/client");
const client_2 = require("@prisma/client");
const zod_1 = require("zod");
const decimal_1 = require("../utils/decimal");
const AgregarInsumoDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.number().int().positive(),
});
const InsumoIdDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
});
const ListarBajosDTO = zod_1.z.object({
    umbral: zod_1.z.coerce.number().int().min(0).default(5),
    nombre: zod_1.z.string().optional(),
    categoria: zod_1.z.string().optional(),
});
const ListarFiltroDTO = zod_1.z.object({
    nombre: zod_1.z.string().optional(),
    categoria: zod_1.z.string().optional(),
});
exports.ListarBajosQueryDTO = zod_1.z.object({
    umbral: zod_1.z.coerce.number().int().min(0).optional(),
    nombre: zod_1.z.string().optional(),
    categoria: zod_1.z.string().optional(),
});
const AgregarStockDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.coerce.number().positive(),
    operarioId: zod_1.z.string().optional(),
    observacion: zod_1.z.string().optional(),
});
const ConsumirDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(1),
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.coerce.number().positive(), // 👈 decimal ok
    operarioId: zod_1.z.string().min(1).optional(),
    tareaId: zod_1.z.number().int().positive().optional(),
    observacion: zod_1.z.string().max(500).optional(),
});
exports.SetUmbralDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    umbralMinimo: zod_1.z.coerce.number().int().min(0),
});
class InventarioService {
    constructor(prisma, inventarioId) {
        this.prisma = prisma;
        this.inventarioId = inventarioId;
    }
    /* ========= Stock básico ========= */
    async agregarInsumo(payload) {
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
    async listarInsumosDetallado(payload) {
        const { nombre, categoria } = ListarFiltroDTO.parse(payload ?? {});
        const rows = await this.prisma.inventarioInsumo.findMany({
            where: { inventarioId: this.inventarioId },
            include: { insumo: true },
            orderBy: [{ insumo: { nombre: "asc" } }],
        });
        // filtros suaves (no rompen si categoria no existe en Insumo)
        return rows
            .filter((r) => {
            const nombreOk = !nombre ||
                r.insumo.nombre.toLowerCase().includes(nombre.toLowerCase());
            const cat = r.insumo.categoria;
            const categoriaOk = !categoria || cat === categoria;
            return nombreOk && categoriaOk;
        })
            .map((r) => ({
            inventarioInsumoId: r.id,
            insumoId: r.insumoId,
            nombre: r.insumo.nombre,
            unidad: r.insumo.unidad,
            categoria: r.insumo.categoria ?? null,
            umbralBajo: r.insumo.umbralBajo ?? null,
            umbralMinimo: r.umbralMinimo ?? null,
            cantidad: (0, decimal_1.decToNumber)(r.cantidad),
        }));
    }
    async agregarStock(payload) {
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
                cantidad: { increment: (0, decimal_1.toDec)(dto.cantidad) },
            },
            create: {
                inventarioId: this.inventarioId,
                insumoId: dto.insumoId,
                cantidad: (0, decimal_1.toDec)(dto.cantidad),
            },
        });
        // 2) registrar movimiento ENTRADA
        await this.prisma.consumoInsumo.create({
            data: {
                inventarioId: this.inventarioId,
                insumoId: dto.insumoId,
                tipo: client_1.TipoMovimientoInsumo.ENTRADA,
                cantidad: (0, decimal_1.toDec)(dto.cantidad),
                fecha: new Date(),
                operarioId: dto.operarioId ?? null,
                observacion: dto.observacion ?? null,
            },
        });
        return {
            inventarioInsumoId: updated.id,
            insumoId: updated.insumoId,
            cantidad: (0, decimal_1.decToNumber)(updated.cantidad),
        };
    }
    async eliminarInsumo(payload) {
        const { insumoId } = InsumoIdDTO.parse(payload);
        await this.prisma.inventarioInsumo.delete({
            where: {
                inventarioId_insumoId: { inventarioId: this.inventarioId, insumoId },
            },
        });
    }
    async buscarInsumoPorId(payload) {
        const { insumoId } = InsumoIdDTO.parse(payload);
        const row = await this.prisma.inventarioInsumo.findUnique({
            where: {
                inventarioId_insumoId: { inventarioId: this.inventarioId, insumoId },
            },
            include: { insumo: true },
        });
        if (!row)
            return null;
        return {
            inventarioInsumoId: row.id,
            insumoId: row.insumoId,
            nombre: row.insumo.nombre,
            unidad: row.insumo.unidad,
            categoria: row.insumo.categoria ?? null,
            umbralBajo: row.insumo.umbralBajo ?? null,
            umbralMinimo: row.umbralMinimo ?? null,
            cantidad: (0, decimal_1.decToNumber)(row.cantidad),
        };
    }
    async consumirInsumoPorId(payload) {
        const dto = ConsumirDTO.parse(payload);
        const cant = new client_2.Prisma.Decimal(dto.cantidad);
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
                throw new Error("Este insumo no está registrado en el inventario del conjunto.");
            }
            // 3) Validar stock suficiente
            const disponible = new client_2.Prisma.Decimal(invItem.cantidad);
            if (disponible.lt(cant)) {
                throw new Error(`Stock insuficiente. Disponible: ${disponible.toString()} - Requerido: ${cant.toString()}`);
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
                    tipo: client_1.TipoMovimientoInsumo.SALIDA,
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
    async consumirStock(payload) {
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
                throw new Error(`El insumo con ID "${dto.insumoId}" no existe en el inventario.`);
            }
            const disponible = (0, decimal_1.decToNumber)(existente.cantidad);
            if (disponible < dto.cantidad) {
                throw new Error(`Cantidad insuficiente de "${existente.insumo.nombre}". Disponible: ${disponible}`);
            }
            const updated = await tx.inventarioInsumo.update({
                where: { id: existente.id },
                data: { cantidad: { decrement: (0, decimal_1.toDec)(dto.cantidad) } },
            });
            await tx.consumoInsumo.create({
                data: {
                    inventarioId: this.inventarioId,
                    insumoId: dto.insumoId,
                    tipo: client_1.TipoMovimientoInsumo.SALIDA,
                    cantidad: (0, decimal_1.toDec)(dto.cantidad),
                    fecha: new Date(),
                    operarioId: dto.operarioId ?? null,
                    tareaId: dto.tareaId ?? null,
                    observacion: dto.observacion ?? null,
                },
            });
            return {
                inventarioInsumoId: updated.id,
                insumoId: updated.insumoId,
                cantidad: (0, decimal_1.decToNumber)(updated.cantidad),
            };
        });
    }
    async listarInsumos() {
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
    async listarInsumosBajos(payload) {
        const { umbral, nombre, categoria } = ListarBajosDTO.parse(payload ?? {});
        const rows = await this.prisma.inventarioInsumo.findMany({
            where: { inventarioId: this.inventarioId },
            include: { insumo: true },
            orderBy: [{ insumo: { nombre: "asc" } }],
        });
        const salida = [];
        for (const r of rows) {
            const nombreOk = !nombre || r.insumo.nombre.toLowerCase().includes(nombre.toLowerCase());
            const cat = r.insumo.categoria;
            const categoriaOk = !categoria || cat === categoria;
            if (!nombreOk || !categoriaOk)
                continue;
            // Umbral efectivo:
            // inventarioInsumo.umbralMinimo ?? insumo.umbralBajo ?? umbralParam
            const umbralGlobal = r.insumo.umbralBajo;
            const umbralLocal = r.umbralMinimo ?? undefined;
            const umbralEfectivo = (typeof umbralLocal === "number" ? umbralLocal : undefined) ??
                (typeof umbralGlobal === "number" ? umbralGlobal : undefined) ??
                umbral;
            const cant = (0, decimal_1.decToNumber)(r.cantidad);
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
    async setUmbralMinimo(payload) {
        const dto = exports.SetUmbralDTO.parse(payload);
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
                cantidad: (0, decimal_1.toDec)(0),
                umbralMinimo: dto.umbralMinimo,
            },
        });
    }
    async unsetUmbralMinimo(payload) {
        const { insumoId } = InsumoIdDTO.parse(payload);
        // si no existe, no pasa nada
        await this.prisma.inventarioInsumo.updateMany({
            where: { inventarioId: this.inventarioId, insumoId },
            data: { umbralMinimo: null },
        });
    }
}
exports.InventarioService = InventarioService;
