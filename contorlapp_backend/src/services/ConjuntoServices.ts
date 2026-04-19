// src/services/ConjuntoService.ts
import type { PrismaClient } from "@prisma/client";
import { z } from "zod";
import { CrearUbicacionDTO, FiltroUbicacionDTO } from "../model/Ubicacion";
import { InventarioService } from "./InventarioServices";
import { elementoTreeInclude } from "../utils/elementoHierarchy";

// DTOs locales
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

  private async getOrCreateInventarioId(): Promise<number> {
    const inv = await this.prisma.inventario.upsert({
      where: { conjuntoId: this.conjuntoId },
      update: {},
      create: { conjuntoId: this.conjuntoId },
      select: { id: true },
    });
    return inv.id;
  }

  async listarInventario(filtro?: { nombre?: string; categoria?: string }) {
    const inventarioId = await this.getOrCreateInventarioId();
    const invService = new InventarioService(this.prisma, inventarioId);
    return invService.listarInsumosDetallado(filtro);
  }

  async listarInsumosBajos(filtro?: { umbral?: number; nombre?: string; categoria?: string }) {
    const inventarioId = await this.getOrCreateInventarioId();
    const invService = new InventarioService(this.prisma, inventarioId);
    return invService.listarInsumosBajos(filtro);
  }

  async agregarStock(payload: unknown) {
    const inventarioId = await this.getOrCreateInventarioId();
    const invService = new InventarioService(this.prisma, inventarioId);
    return invService.agregarStock(payload);
  }

  async consumirStock(payload: unknown) {
    const inventarioId = await this.getOrCreateInventarioId();
    const invService = new InventarioService(this.prisma, inventarioId);
    return invService.consumirStock(payload);
  }

  async buscarInsumoPorId(payload: unknown) {
    const inventarioId = await this.getOrCreateInventarioId();
    const invService = new InventarioService(this.prisma, inventarioId);
    return invService.buscarInsumoPorId(payload);
  }

  async setUmbralMinimo(payload: unknown) {
    const inventarioId = await this.getOrCreateInventarioId();
    const invService = new InventarioService(this.prisma, inventarioId);
    return invService.setUmbralMinimo(payload);
  }

  async unsetUmbralMinimo(payload: unknown) {
    const inventarioId = await this.getOrCreateInventarioId();
    const invService = new InventarioService(this.prisma, inventarioId);
    return invService.unsetUmbralMinimo(payload);
  }

  /** Activa/Inactiva el conjunto y retorna el valor actualizado */
  async setActivo(activo: boolean): Promise<boolean> {
    const existe = await this.prisma.conjunto.findUnique({
      where: { nit: this.conjuntoId },
      select: { nit: true },
    });
    if (!existe) throw new Error("Conjunto no encontrado.");

    const updated = await this.prisma.conjunto.update({
      where: { nit: this.conjuntoId },
      data: { activo },
      select: { activo: true },
    });
    return updated.activo;
  }

  async listarMaquinariaDelConjunto() {
    const [propia, prestada] = await Promise.all([
      this.prisma.maquinaria.findMany({
        where: {
          propietarioTipo: "CONJUNTO",
          conjuntoPropietarioId: this.conjuntoId,
        },
        select: {
          id: true,
          nombre: true,
          marca: true,
          tipo: true,
          estado: true,
          propietarioTipo: true,
          conjuntoPropietarioId: true,
        },
      }),

      // 2️⃣ Maquinaria prestada (asignación ACTIVA)
      this.prisma.maquinariaConjunto.findMany({
        where: {
          conjuntoId: this.conjuntoId,
          estado: "ACTIVA",
        },
        select: {
          tipoTenencia: true,
          fechaDevolucionEstimada: true,
          maquinaria: {
            select: {
              id: true,
              nombre: true,
              marca: true,
              tipo: true,
              estado: true,
              propietarioTipo: true,
              empresaId: true,
            },
          },
        },
      }),
    ]);

    // 🔄 Normalizamos a un solo formato
    return [
      ...propia.map((m) => ({
        ...m,
        origen: "PROPIA",
      })),
      ...prestada.map((p) => ({
        ...p.maquinaria,
        origen: "PRESTADA",
        tipoTenencia: p.tipoTenencia,
        fechaDevolucionEstimada: p.fechaDevolucionEstimada,
      })),
    ];
  }

  async asignarOperario(payload: unknown) {
    const { operarioId } = AsignarOperarioDTO.parse(payload);
    try {
      const existeOperario = await this.prisma.operario.findUnique({
        where: { id: operarioId.toString() },
        select: { id: true },
      });
      if (!existeOperario) throw new Error("Operario no encontrado.");

      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: { operarios: { connect: { id: operarioId.toString() } } },
      });
    } catch (error) {
      console.error("Error al asignar operario:", error);
      throw new Error("No se pudo asignar el operario.");
    }
  }

  async asignarAdministrador(payload: unknown) {
    const { administradorId } = AsignarAdministradorDTO.parse(payload);
    try {
      const existeAdmin = await this.prisma.administrador.findUnique({
        where: { id: administradorId.toString() },
        select: { id: true },
      });
      if (!existeAdmin) throw new Error("Administrador no encontrado.");

      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: {
          administrador: { connect: { id: administradorId.toString() } },
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
      // 1) validar que la maquinaria exista
      const maq = await this.prisma.maquinaria.findUnique({
        where: { id: maquinariaId },
        select: { id: true },
      });
      if (!maq) throw new Error("Maquinaria no encontrada.");

      // 2) validar que no esté ACTIVA en otro conjunto
      const asignacionActiva = await this.prisma.maquinariaConjunto.findFirst({
        where: { maquinariaId, estado: "ACTIVA" },
        select: { id: true, conjuntoId: true },
      });

      if (asignacionActiva) {
        if (asignacionActiva.conjuntoId === this.conjuntoId) {
          throw new Error("La maquinaria ya está asignada a este conjunto.");
        }
        throw new Error("La maquinaria ya está asignada a otro conjunto.");
      }

      // 3) crear asignación (inventario de maquinaria del conjunto)
      await this.prisma.maquinariaConjunto.create({
        data: {
          conjunto: { connect: { nit: this.conjuntoId } },
          maquinaria: { connect: { id: maquinariaId } },
          tipoTenencia: "PRESTADA",
          estado: "ACTIVA",
          fechaInicio: new Date(),
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
      const asignacion = await this.prisma.maquinariaConjunto.findFirst({
        where: {
          maquinariaId,
          conjuntoId: this.conjuntoId,
          estado: "ACTIVA",
        },
        select: { id: true },
      });

      if (!asignacion) {
        throw new Error(
          "No hay una asignación ACTIVA de esa maquinaria en este conjunto."
        );
      }

      await this.prisma.maquinariaConjunto.update({
        where: { id: asignacion.id },
        data: {
          estado: "DEVUELTA",
          fechaFin: new Date(),
        },
      });
    } catch (error) {
      console.error("Error al devolver maquinaria:", error);
      throw new Error("No se pudo devolver la maquinaria.");
    }
  }

  async agregarUbicacion(payload: unknown) {
    const dto = CrearUbicacionDTO.parse({
      ...(payload as any),
      conjuntoId: this.conjuntoId,
    });
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
    const dto = FiltroUbicacionDTO.parse({
      ...(payload as any),
      conjuntoId: this.conjuntoId,
    });
    return this.prisma.ubicacion.findFirst({
      where: { conjuntoId: this.conjuntoId, nombre: dto.nombre },
      select: { id: true, nombre: true },
    });
  }

  async agregarTareaACronograma(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    try {
      const tarea = await this.prisma.tarea.findUnique({
        where: { id: tareaId },
        select: { id: true },
      });
      if (!tarea) throw new Error("Tarea no encontrada.");

      await this.prisma.tarea.update({
        where: { id: tareaId },
        data: { conjunto: { connect: { nit: this.conjuntoId } } },
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
        borrador: false,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
    });
  }

  async tareasPorOperario(payload: unknown) {
    const { operarioId } = TareasPorOperarioDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        operarios: { some: { id: operarioId.toString() } },
      },
    });
  }

  async obtenerDetalleMapa() {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: this.conjuntoId },
      select: {
        nit: true,
        nombre: true,
        direccion: true,
        correo: true,
        activo: true,
        tipoServicio: true,
        valorMensual: true,
        fechaInicioContrato: true,
        fechaFinContrato: true,
        consignasEspeciales: true,
        valorAgregado: true,
        administrador: {
          include: { usuario: true },
        },
        operarios: {
          include: { usuario: true },
        },
        horarios: true,
        ubicaciones: {
          include: {
            elementos: {
              where: { padreId: null },
              include: elementoTreeInclude,
              orderBy: { nombre: "asc" },
            },
          },
        },
        mapaConjuntoNombreArchivo: true,
        mapaConjuntoMimeType: true,
        mapaConjuntoActualizadoEn: true,
      },
    });

    if (!conjunto) throw new Error("Conjunto no encontrado.");
    return conjunto;
  }

  async obtenerMapaArchivo() {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: this.conjuntoId },
      select: {
        nit: true,
        mapaConjuntoBytes: true,
        mapaConjuntoMimeType: true,
        mapaConjuntoNombreArchivo: true,
      },
    });

    if (!conjunto) throw new Error("Conjunto no encontrado.");
    if (!conjunto.mapaConjuntoBytes || !conjunto.mapaConjuntoMimeType) {
      const error: Error & { status?: number } = new Error(
        "Este conjunto todavia no tiene un mapa cargado.",
      );
      error.status = 404;
      throw error;
    }

    return {
      bytes: conjunto.mapaConjuntoBytes,
      mimeType: conjunto.mapaConjuntoMimeType,
      nombreArchivo: conjunto.mapaConjuntoNombreArchivo ?? "mapa_conjunto",
    };
  }

  async actualizarMapaArchivo(file: Express.Multer.File) {
    if (!file?.buffer?.length) {
      throw new Error("Debes adjuntar una imagen del mapa del conjunto.");
    }

    const mimeType = String(file.mimetype ?? "").toLowerCase();
    if (!mimeType.startsWith("image/")) {
      throw new Error("Solo se permiten archivos de imagen para el mapa.");
    }

    await this.prisma.conjunto.update({
      where: { nit: this.conjuntoId },
      data: {
        mapaConjuntoNombreArchivo: file.originalname?.trim() || "mapa_conjunto",
        mapaConjuntoMimeType: mimeType,
        mapaConjuntoBytes: file.buffer,
        mapaConjuntoActualizadoEn: new Date(),
      },
      select: { nit: true },
    });

    return this.obtenerDetalleMapa();
  }

  async tareasPorUbicacion(payload: unknown) {
    const { nombreUbicacion } = TareasPorUbicacionDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        ubicacion: { nombre: { equals: nombreUbicacion, mode: "insensitive" } },
      },
    });
  }
}
