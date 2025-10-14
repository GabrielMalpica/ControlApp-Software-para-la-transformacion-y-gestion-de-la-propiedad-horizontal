import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

// DTOs ya definidos en /models (los reutilizamos donde aplica)
import { CrearUbicacionDTO, FiltroUbicacionDTO } from "../model/Ubicacion";

// DTOs locales (inputs simples de este servicio)
const AsignarOperarioDTO = z.object({
  operarioId: z.number().int().positive(),
});

const AsignarAdministradorDTO = z.object({
  administradorId: z.number().int().positive(),
});

const AgregarMaquinariaDTO = z.object({
  maquinariaId: z.number().int().positive(),
});

const TareaIdDTO = z.object({
  tareaId: z.number().int().positive(),
});

const FechaDTO = z.object({
  fecha: z.coerce.date(),
});

const TareasPorOperarioDTO = z.object({
  operarioId: z.number().int().positive(),
});

const TareasPorUbicacionDTO = z.object({
  nombreUbicacion: z.string().min(1),
});

export class ConjuntoService {
  constructor(
    private prisma: PrismaClient,
    private conjuntoId: string // nit
  ) {}

  async setActivo(activo: boolean) {
    await this.prisma.conjunto.update({
      where: { nit: this.conjuntoId },
      data: { activo },
    });
  }

  async asignarOperario(payload: unknown) {
    const { operarioId } = AsignarOperarioDTO.parse(payload);
    try {
      // opcional: verificar que el operario exista
      const existeOperario = await this.prisma.operario.findUnique({ where: { id: operarioId }, select: { id: true } });
      if (!existeOperario) throw new Error("Operario no encontrado.");

      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: {
          operarios: { connect: { id: operarioId } },
        },
      });
    } catch (error) {
      console.error("Error al asignar operario:", error);
      throw new Error("No se pudo asignar el operario.");
    }
  }

  async asignarAdministrador(payload: unknown) {
    const { administradorId } = AsignarAdministradorDTO.parse(payload);
    try {
      const existeAdmin = await this.prisma.administrador.findUnique({ where: { id: administradorId }, select: { id: true } });
      if (!existeAdmin) throw new Error("Administrador no encontrado.");

      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: {
          administrador: { connect: { id: administradorId } },
        },
      });
    } catch (error) {
      console.error("Error al asignar administrador:", error);
      throw new Error("No se pudo asignar el administrador.");
    }
  }

  async eliminarAdministrador() {
    try {
      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: { administradorId: null },
      });
    } catch (error) {
      console.error("Error al eliminar administrador:", error);
      throw new Error("No se pudo eliminar el administrador.");
    }
  }

  async agregarMaquinaria(payload: unknown) {
    const { maquinariaId } = AgregarMaquinariaDTO.parse(payload);
    try {
      const maq = await this.prisma.maquinaria.findUnique({
        where: { id: maquinariaId },
        select: { id: true, disponible: true, conjuntoId: true },
      });
      if (!maq) throw new Error("Maquinaria no encontrada.");
      if (maq.conjuntoId && maq.conjuntoId !== this.conjuntoId) {
        throw new Error("La maquinaria ya está asignada a otro conjunto.");
      }

      await this.prisma.maquinaria.update({
        where: { id: maquinariaId },
        data: {
          conjuntoId: this.conjuntoId,
          disponible: false,
          fechaPrestamo: new Date(),
        },
      });
    } catch (error) {
      console.error("Error al agregar maquinaria al conjunto:", error);
      throw new Error("No se pudo asignar la maquinaria al conjunto.");
    }
  }

  async entregarMaquinaria(payload: unknown) {
    const { maquinariaId } = AgregarMaquinariaDTO.parse(payload);
    try {
      await this.prisma.maquinaria.update({
        where: { id: maquinariaId },
        data: {
          conjuntoId: null,
          disponible: true,
          fechaDevolucionEstimada: null,
          fechaPrestamo: null,
        },
      });
    } catch (error) {
      console.error("Error al devolver maquinaria:", error);
      throw new Error("No se pudo devolver la maquinaria.");
    }
  }

  async agregarUbicacion(payload: unknown) {
    // Reutilizamos CrearUbicacionDTO (nombre, conjuntoId)
    const dto = CrearUbicacionDTO.parse({ ...(payload as any), conjuntoId: this.conjuntoId });
    try {
      const yaExiste = await this.prisma.ubicacion.findFirst({
        where: { nombre: dto.nombre, conjuntoId: this.conjuntoId },
        select: { id: true },
      });

      if (!yaExiste) {
        await this.prisma.ubicacion.create({
          data: {
            nombre: dto.nombre,
            conjunto: { connect: { nit: this.conjuntoId } },
          },
        });
      }
    } catch (error) {
      console.error("Error al agregar ubicación:", error);
      throw new Error("No se pudo agregar la ubicación.");
    }
  }

  async buscarUbicacion(payload: unknown) {
    const dto = FiltroUbicacionDTO.parse({ ...(payload as any), conjuntoId: this.conjuntoId });
    return this.prisma.ubicacion.findFirst({
      where: {
        conjuntoId: this.conjuntoId,
        nombre: dto.nombre,
      },
      select: { id: true, nombre: true },
    });
  }

  async agregarTareaACronograma(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    try {
      // opcional: validar que la tarea existe
      const tarea = await this.prisma.tarea.findUnique({ where: { id: tareaId }, select: { id: true } });
      if (!tarea) throw new Error("Tarea no encontrada.");

      await this.prisma.tarea.update({
        where: { id: tareaId },
        data: {
          conjunto: { connect: { nit: this.conjuntoId } },
        },
      });
    } catch (error) {
      console.error("Error al agregar tarea al cronograma:", error);
      throw new Error("No se pudo agregar la tarea al cronograma.");
    }
  }

  async tareasPorFecha(payload: unknown) {
    const { fecha } = FechaDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
    });
  }

  async tareasPorOperario(payload: unknown) {
    const { operarioId } = TareasPorOperarioDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: { conjuntoId: this.conjuntoId, operarioId },
    });
  }

  async tareasPorUbicacion(payload: unknown) {
    const { nombreUbicacion } = TareasPorUbicacionDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        ubicacion: { nombre: { equals: nombreUbicacion, mode: "insensitive" } },
      },
    });
  }
}