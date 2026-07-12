import type { PrismaClient } from "@prisma/client";

function makeHttpError(status: number, message: string) {
  const err = new Error(message) as Error & { status: number };
  err.status = status;
  return err;
}

type CompromisoRow = {
  id: number;
  conjuntoId: string;
  titulo: string;
  completado: boolean;
  creadaEn: Date;
  cerradaEn: Date | null;
  actualizadaEn: Date;
  creadoPorId: string | null;
  creadoPor?: {
    nombre: string;
    rol: string;
  } | null;
  conjunto?: {
    nit: string;
    nombre: string;
  } | null;
};

export class CompromisoConjuntoService {
  constructor(private readonly prisma: PrismaClient) {}

  private buildAns(compromiso: Pick<CompromisoRow, "completado" | "creadaEn">) {
    if (compromiso.completado) {
      return {
        ansEstado: "cerrado",
        ansColor: "neutral",
        ansLabel: "Cerrado",
      };
    }

    const msAbierto = Date.now() - compromiso.creadaEn.getTime();
    const diasAbierto = Math.max(0, Math.floor(msAbierto / (1000 * 60 * 60 * 24)));

    if (diasAbierto <= 7) {
      return {
        ansEstado: "verde",
        ansColor: "green",
        ansLabel: "ANS en tiempo",
      };
    }

    if (diasAbierto <= 21) {
      return {
        ansEstado: "naranja",
        ansColor: "orange",
        ansLabel: "ANS en seguimiento",
      };
    }

    return {
      ansEstado: "rojo",
      ansColor: "red",
      ansLabel: "ANS critico",
    };
  }

  private formatRol(rol?: string | null) {
    const normalized = String(rol ?? "").trim().toLowerCase();
    if (normalized == "jefe_operaciones") return "Jefe de operaciones";
    if (normalized == "administrador") return "Administrador";
    if (normalized == "supervisor") return "Supervisor";
    if (normalized == "operario") return "Operario";
    if (normalized == "gerente") return "Gerente";
    return normalized ? normalized[0].toUpperCase() + normalized.slice(1) : null;
  }

  private serializeCompromiso(item: CompromisoRow) {
    const ans = this.buildAns(item);
    return {
      id: item.id,
      conjuntoId: item.conjuntoId,
      titulo: item.titulo,
      completado: item.completado,
      creadaEn: item.creadaEn,
      cerradaEn: item.cerradaEn,
      actualizadaEn: item.actualizadaEn,
      creadoPorId: item.creadoPorId,
      creadoPorNombre: item.creadoPor?.nombre ?? null,
      creadoPorRol: this.formatRol(item.creadoPor?.rol),
      diasAbierto: Math.max(
        0,
        Math.floor((Date.now() - item.creadaEn.getTime()) / (1000 * 60 * 60 * 24)),
      ),
      ansEstado: ans.ansEstado,
      ansColor: ans.ansColor,
      ansLabel: ans.ansLabel,
      conjuntoNombre: item.conjunto?.nombre ?? item.conjuntoId,
      conjuntoNit: item.conjunto?.nit ?? item.conjuntoId,
    };
  }

  async listarPorConjunto(conjuntoId: string) {
    const items = await this.prisma.compromisoConjunto.findMany({
      where: { conjuntoId },
      orderBy: [{ completado: "asc" }, { creadaEn: "desc" }],
      select: {
        id: true,
        conjuntoId: true,
        titulo: true,
        completado: true,
        creadaEn: true,
        cerradaEn: true,
        actualizadaEn: true,
        creadoPorId: true,
        creadoPor: {
          select: {
            nombre: true,
            rol: true,
          },
        },
      },
    });

    return items.map((item) => this.serializeCompromiso(item));
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
        cerradaEn: true,
        actualizadaEn: true,
        creadoPorId: true,
        creadoPor: {
          select: {
            nombre: true,
            rol: true,
          },
        },
        conjunto: { select: { nit: true, nombre: true } },
      },
    });

    return items.map((item) => this.serializeCompromiso(item));
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

    const created = await this.prisma.compromisoConjunto.create({
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
        cerradaEn: true,
        actualizadaEn: true,
        creadoPorId: true,
        creadoPor: {
          select: {
            nombre: true,
            rol: true,
          },
        },
      },
    });

    return this.serializeCompromiso(created);
  }

  async actualizar(id: number, data: { titulo?: string; completado?: boolean }) {
    const current = await this.prisma.compromisoConjunto.findUnique({ where: { id } });
    if (!current) {
      throw makeHttpError(404, "Compromiso no encontrado");
    }

    const payload: { titulo?: string; completado?: boolean; cerradaEn?: Date | null } = {};
    if (typeof data.titulo === "string") {
      const titulo = data.titulo.trim();
      if (!titulo) {
        throw makeHttpError(400, "El compromiso no puede estar vacio");
      }
      payload.titulo = titulo;
    }
    if (typeof data.completado === "boolean") {
      payload.completado = data.completado;
      if (data.completado && !current.completado) {
        payload.cerradaEn = new Date();
      }
      if (!data.completado && current.completado) {
        payload.cerradaEn = null;
      }
    }

    const updated = await this.prisma.compromisoConjunto.update({
      where: { id },
      data: payload,
      select: {
        id: true,
        conjuntoId: true,
        titulo: true,
        completado: true,
        creadaEn: true,
        cerradaEn: true,
        actualizadaEn: true,
        creadoPorId: true,
        creadoPor: {
          select: {
            nombre: true,
            rol: true,
          },
        },
      },
    });

    return this.serializeCompromiso(updated);
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
