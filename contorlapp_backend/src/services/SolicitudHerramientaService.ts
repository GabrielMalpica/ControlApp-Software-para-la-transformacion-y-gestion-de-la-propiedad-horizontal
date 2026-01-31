import { PrismaClient } from "../generated/prisma";
import {
  CrearSolicitudHerramientaDTO,
  AprobarSolicitudHerramientaDTO,
  FiltroSolicitudHerramientaDTO,
} from "../model/SolicitudHerramienta";

type EstadoSolicitud = "PENDIENTE" | "APROBADA" | "RECHAZADA";
type EstadoStock = "OPERATIVA" | "DANADA" | "PERDIDA" | "BAJA";

export class SolicitudHerramientaService {
  constructor(private prisma: PrismaClient) {}

  async crear(payload: unknown) {
    const dto = CrearSolicitudHerramientaDTO.parse(payload);

    // ✅ Validar conjunto
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: dto.conjuntoId },
      select: { nit: true },
    });
    if (!conjunto) throw new Error("Conjunto no existe");

    // ✅ Validar herramientas
    const ids = dto.items.map((i) => i.herramientaId);
    const herramientas = await this.prisma.herramienta.findMany({
      where: { id: { in: ids } },
      select: { id: true },
    });
    if (herramientas.length !== ids.length)
      throw new Error("Una o más herramientas no existen");

    // Consolidar duplicados (por herramientaId + estado)
    const keyMap = new Map<string, number>();
    for (const it of dto.items) {
      const estado = (it.estado ?? "OPERATIVA") as EstadoStock;
      const key = `${it.herramientaId}__${estado}`;
      keyMap.set(key, (keyMap.get(key) ?? 0) + Number(it.cantidad));
    }

    const itemsCreate = Array.from(keyMap.entries()).map(([key, cantidad]) => {
      const [herramientaIdStr, estado] = key.split("__");
      return {
        herramientaId: Number(herramientaIdStr),
        estado: estado as any, // si tu item tiene estado en el modelo; si NO, quítalo del create
        cantidad: cantidad as any,
      };
    });

    // ⚠️ Importante: tu modelo SolicitudHerramientaItem que te di antes NO tenía "estado".
    // Si tu schema NO tiene estado en SolicitudHerramientaItem, entonces en itemsCreate quitas "estado".
    // Y el estado se decide al aprobar (estadoIngreso).
    // --> Abajo te pongo la versión sin estado en item para que sea compatible con el schema que te pasé.

    return this.prisma.solicitudHerramienta.create({
      data: {
        conjuntoId: dto.conjuntoId,
        empresaId: dto.empresaId ?? null,
        estado: "PENDIENTE" as any,
        items: {
          create: dto.items.map((it) => ({
            herramientaId: it.herramientaId,
            cantidad: it.cantidad as any,
          })),
        },
      },
      include: {
        items: {
          include: {
            herramienta: {
              select: { nombre: true, unidad: true, modoControl: true },
            },
          },
        },
        conjunto: { select: { nit: true, nombre: true } },
      },
    });
  }

  async aprobar(id: number, payload: unknown) {
    const dto = AprobarSolicitudHerramientaDTO.parse(payload);

    return this.prisma.$transaction(async (tx) => {
      const sol = await tx.solicitudHerramienta.findUnique({
        where: { id },
        include: { items: true },
      });

      if (!sol) throw new Error("Solicitud no encontrada");
      if (sol.estado === "APROBADA") return sol;

      const estadoIngreso = (dto.estadoIngreso ?? "OPERATIVA") as EstadoStock;

      // ✅ sumar stock al conjunto
      for (const it of sol.items) {
        await tx.conjuntoHerramientaStock.upsert({
          where: {
            conjuntoId_herramientaId_estado: {
              conjuntoId: sol.conjuntoId,
              herramientaId: it.herramientaId,
              estado: estadoIngreso,
            },
          },
          create: {
            conjuntoId: sol.conjuntoId,
            herramientaId: it.herramientaId,
            estado: estadoIngreso as any,
            cantidad: it.cantidad as any,
          },
          update: {
            cantidad: { increment: it.cantidad as any },
          },
        });
      }

      // ✅ actualizar solicitud
      return tx.solicitudHerramienta.update({
        where: { id },
        data: {
          estado: "APROBADA" as any,
          fechaAprobacion: dto.fechaAprobacion ?? new Date(),
          empresaId: dto.empresaId ?? undefined,
        },
        include: {
          items: {
            include: {
              herramienta: {
                select: { nombre: true, unidad: true, modoControl: true },
              },
            },
          },
          conjunto: { select: { nit: true, nombre: true } },
        },
      });
    });
  }

  async rechazar(id: number, payload: unknown) {
    // si quieres método espejo
    const { observacionRespuesta } = (payload ?? {}) as any;

    return this.prisma.solicitudHerramienta.update({
      where: { id },
      data: {
        estado: "RECHAZADA" as any,
        observacionRespuesta: observacionRespuesta ?? null,
      },
      include: {
        items: {
          include: {
            herramienta: {
              select: { nombre: true, unidad: true, modoControl: true },
            },
          },
        },
        conjunto: { select: { nit: true, nombre: true } },
      },
    });
  }

  async listar(payload: unknown) {
    const f = FiltroSolicitudHerramientaDTO.parse(payload);

    const rango: { gte?: Date; lte?: Date } = {};
    if (f.fechaDesde) rango.gte = f.fechaDesde;
    if (f.fechaHasta) rango.lte = f.fechaHasta;

    return this.prisma.solicitudHerramienta.findMany({
      where: {
        conjuntoId: f.conjuntoId ?? undefined,
        empresaId: f.empresaId ?? undefined,
        estado: f.estado ?? undefined,
        fechaSolicitud: Object.keys(rango).length ? rango : undefined,
      },
      include: {
        items: {
          include: {
            herramienta: {
              select: { nombre: true, unidad: true, modoControl: true },
            },
          },
        },
        conjunto: { select: { nit: true, nombre: true } },
      },
      orderBy: { id: "desc" },
    });
  }

  async obtener(id: number) {
    return this.prisma.solicitudHerramienta.findUnique({
      where: { id },
      include: {
        items: {
          include: {
            herramienta: {
              select: { nombre: true, unidad: true, modoControl: true },
            },
          },
        },
        conjunto: { select: { nit: true, nombre: true } },
      },
    });
  }

  async eliminar(id: number) {
    await this.prisma.solicitudHerramienta.delete({ where: { id } });
  }
}
