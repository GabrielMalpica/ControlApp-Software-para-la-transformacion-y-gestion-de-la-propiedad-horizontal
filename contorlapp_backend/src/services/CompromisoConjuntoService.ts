import type { PrismaClient } from "@prisma/client";

function makeHttpError(status: number, message: string) {
  const err = new Error(message) as Error & { status: number };
  err.status = status;
  return err;
}

export class CompromisoConjuntoService {
  constructor(private readonly prisma: PrismaClient) {}

  async listarPorConjunto(conjuntoId: string) {
    return this.prisma.compromisoConjunto.findMany({
      where: { conjuntoId },
      orderBy: [{ completado: "asc" }, { creadaEn: "desc" }],
      select: {
        id: true,
        conjuntoId: true,
        titulo: true,
        completado: true,
        creadaEn: true,
        actualizadaEn: true,
        creadoPorId: true,
      },
    });
  }

  async listarGlobal() {
    const items = await this.prisma.compromisoConjunto.findMany({
      orderBy: [
        { completado: "asc" },
        { conjunto: { nombre: "asc" } },
        { creadaEn: "desc" },
      ],
      select: {
        id: true,
        conjuntoId: true,
        titulo: true,
        completado: true,
        creadaEn: true,
        actualizadaEn: true,
        conjunto: { select: { nit: true, nombre: true } },
      },
    });

    return items.map((item) => ({
      id: item.id,
      conjuntoId: item.conjuntoId,
      titulo: item.titulo,
      completado: item.completado,
      creadaEn: item.creadaEn,
      actualizadaEn: item.actualizadaEn,
      conjuntoNombre: item.conjunto?.nombre ?? item.conjuntoId,
      conjuntoNit: item.conjunto?.nit ?? item.conjuntoId,
    }));
  }

  async crear(input: {
    conjuntoId: string;
    titulo: string;
    creadoPorId?: string | null;
  }) {
    const titulo = input.titulo.trim();
    if (!titulo) {
      throw makeHttpError(400, "El compromiso no puede estar vacio");
    }

    return this.prisma.compromisoConjunto.create({
      data: {
        conjuntoId: input.conjuntoId,
        titulo,
        creadoPorId: input.creadoPorId ?? null,
      },
      select: {
        id: true,
        conjuntoId: true,
        titulo: true,
        completado: true,
        creadaEn: true,
        actualizadaEn: true,
        creadoPorId: true,
      },
    });
  }

  async actualizar(id: number, data: { titulo?: string; completado?: boolean }) {
    const current = await this.prisma.compromisoConjunto.findUnique({ where: { id } });
    if (!current) {
      throw makeHttpError(404, "Compromiso no encontrado");
    }

    const payload: { titulo?: string; completado?: boolean } = {};
    if (typeof data.titulo === "string") {
      const titulo = data.titulo.trim();
      if (!titulo) {
        throw makeHttpError(400, "El compromiso no puede estar vacio");
      }
      payload.titulo = titulo;
    }
    if (typeof data.completado === "boolean") {
      payload.completado = data.completado;
    }

    return this.prisma.compromisoConjunto.update({
      where: { id },
      data: payload,
      select: {
        id: true,
        conjuntoId: true,
        titulo: true,
        completado: true,
        creadaEn: true,
        actualizadaEn: true,
        creadoPorId: true,
      },
    });
  }

  async eliminar(id: number) {
    const current = await this.prisma.compromisoConjunto.findUnique({ where: { id } });
    if (!current) {
      throw makeHttpError(404, "Compromiso no encontrado");
    }
    await this.prisma.compromisoConjunto.delete({ where: { id } });
    return { ok: true };
  }
}
