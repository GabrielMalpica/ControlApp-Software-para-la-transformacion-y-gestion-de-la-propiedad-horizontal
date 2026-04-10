import { PrismaClient } from "@prisma/client";
import { CrearSolicitudTareaDTO } from "../model/SolicitudTarea";
import {
  CrearSolicitudInsumoDTO,
  SolicitudInsumoItemDTO,
} from "../model/SolicitudInsumo";
import { CrearSolicitudMaquinariaDTO } from "../model/SolicitudMaquinaria";
import { CompromisoConjuntoService } from "./CompromisoConjuntoService";
import { NotificacionService } from "./NotificacionService";

export class AdministradorService {
  constructor(private prisma: PrismaClient, private administradorId: number) {}

  private get adminIdAsString() {
    return this.administradorId.toString();
  }

  private async validarConjuntoAsignado(conjuntoId: string) {
    const conjunto = await this.prisma.conjunto.findFirst({
      where: {
        nit: conjuntoId,
        administradorId: this.adminIdAsString,
      },
      select: { nit: true, nombre: true },
    });

    if (!conjunto) {
      throw new Error("No tienes acceso a ese conjunto.");
    }

    return conjunto;
  }

  private async validarCompromisoAsignado(id: number) {
    const compromiso = await this.prisma.compromisoConjunto.findFirst({
      where: {
        id,
        conjunto: { administradorId: this.adminIdAsString },
      },
      select: { id: true, conjuntoId: true },
    });

    if (!compromiso) {
      throw new Error("No tienes acceso a esa PQRS.");
    }

    return compromiso;
  }

  async verConjuntos() {
    try {
      const conjuntos = await this.prisma.conjunto.findMany({
        where: { administradorId: this.administradorId.toString() },
        select: { nombre: true, nit: true },
      });
      return conjuntos;
    } catch (error) {
      console.error("Error al obtener conjuntos:", error);
      throw new Error("No se pudieron obtener los conjuntos.");
    }
  }

  async listarCompromisosConjunto(conjuntoId: string) {
    await this.validarConjuntoAsignado(conjuntoId);
    const service = new CompromisoConjuntoService(this.prisma);
    return service.listarPorConjunto(conjuntoId);
  }

  async crearCompromisoConjunto(input: {
    conjuntoId: string;
    titulo: string;
    creadoPorId?: string | null;
  }) {
    await this.validarConjuntoAsignado(input.conjuntoId);

    const service = new CompromisoConjuntoService(this.prisma);
    const creado = await service.crear(input);

    try {
      const notificaciones = new NotificacionService(this.prisma);
      await notificaciones.notificarPqrsCreadaPorAdministrador({
        compromisoId: creado.id,
        conjuntoId: input.conjuntoId,
        titulo: creado.titulo,
        actorId: input.creadoPorId ?? this.adminIdAsString,
      });
    } catch (error) {
      console.error("No se pudo notificar la PQRS creada por administrador:", error);
    }

    return creado;
  }

  async actualizarCompromiso(id: number, data: { titulo?: string; completado?: boolean }) {
    await this.validarCompromisoAsignado(id);
    const service = new CompromisoConjuntoService(this.prisma);
    return service.actualizar(id, data);
  }

  async eliminarCompromiso(id: number) {
    await this.validarCompromisoAsignado(id);
    const service = new CompromisoConjuntoService(this.prisma);
    return service.eliminar(id);
  }

  /**
   * Solicitar una tarea (SolicitudTarea) para un conjunto/ubicación/elemento.
   * Valida payload con Zod y además verifica coherencia:
   * - Ubicación pertenece al Conjunto
   * - Elemento pertenece a la Ubicación
   */
  async solicitarTarea(payload: unknown) {
    try {
      const dto = CrearSolicitudTareaDTO.parse(payload);

      // Validaciones de coherencia relacional
      const ubicacion = await this.prisma.ubicacion.findUnique({
        where: { id: dto.ubicacionId },
        select: { id: true, conjuntoId: true },
      });
      if (!ubicacion || ubicacion.conjuntoId !== dto.conjuntoId) {
        throw new Error("La ubicación no pertenece al conjunto indicado.");
      }

      const elemento = await this.prisma.elemento.findUnique({
        where: { id: dto.elementoId },
        select: { id: true, ubicacionId: true },
      });
      if (!elemento || elemento.ubicacionId !== dto.ubicacionId) {
        throw new Error("El elemento no pertenece a la ubicación indicada.");
      }

      return await this.prisma.solicitudTarea.create({
        data: {
          descripcion: dto.descripcion,
          duracionHoras: dto.duracionHoras,
          estado: "PENDIENTE",
          observaciones: dto.observaciones ?? null,
          conjunto: { connect: { nit: dto.conjuntoId } },
          ubicacion: { connect: { id: dto.ubicacionId } },
          elemento: { connect: { id: dto.elementoId } },
          empresa: dto.empresaId
            ? { connect: { nit: dto.empresaId } }
            : undefined,
        },
      });
    } catch (error) {
      console.error("Error al crear solicitud de tarea:", error);
      throw new Error("No se pudo registrar la solicitud de tarea.");
    }
  }

  /**
   * Solicitar insumos (SolicitudInsumo + items).
   * Valida con Zod y asegura que el array de items no esté vacío.
   */
  async solicitarInsumos(payload: unknown) {
    try {
      // Validación principal
      const dto = CrearSolicitudInsumoDTO.parse(payload);
      // (Opcional) Validación por item si llega desde múltiples sitios
      dto.items.forEach((i) => SolicitudInsumoItemDTO.parse(i));

      // Validar que el conjunto exista (y empresa opcional)
      const conjunto = await this.prisma.conjunto.findUnique({
        where: { nit: dto.conjuntoId },
        select: { nit: true },
      });
      if (!conjunto) throw new Error("Conjunto no encontrado.");

      if (dto.empresaId) {
        const empresa = await this.prisma.empresa.findUnique({
          where: { nit: dto.empresaId },
          select: { nit: true },
        });
        if (!empresa) throw new Error("Empresa no encontrada.");
      }

      return await this.prisma.solicitudInsumo.create({
        data: {
          conjunto: { connect: { nit: dto.conjuntoId } },
          empresa: dto.empresaId
            ? { connect: { nit: dto.empresaId } }
            : undefined,
          fechaSolicitud: new Date(),
          aprobado: false,
          insumosSolicitados: {
            create: dto.items.map(({ insumoId, cantidad }) => ({
              insumo: { connect: { id: insumoId } },
              cantidad,
            })),
          },
        },
        include: {
          insumosSolicitados: true,
        },
      });
    } catch (error) {
      console.error("Error al crear solicitud de insumos:", error);
      throw new Error("No se pudo registrar la solicitud de insumos.");
    }
  }

  /**
   * Solicitar maquinaria (SolicitudMaquinaria).
   * Valida con Zod y comprueba existencia de relaciones clave.
   */
  async solicitarMaquinaria(payload: unknown) {
    const dto = CrearSolicitudMaquinariaDTO.parse(payload);

    const [conjunto, maquinaria, operario] = await Promise.all([
      this.prisma.conjunto.findUnique({
        where: { nit: dto.conjuntoId },
        select: { nit: true },
      }),
      this.prisma.maquinaria.findUnique({
        where: { id: dto.maquinariaId },
        select: { id: true },
      }),
      this.prisma.operario.findUnique({
        where: { id: dto.operarioId.toString() },
        select: { id: true },
      }),
    ]);

    if (!conjunto) throw new Error("Conjunto no encontrado.");
    if (!maquinaria) throw new Error("Maquinaria no encontrada.");
    if (!operario) throw new Error("Operario responsable no encontrado.");

    // (opcional) evitar pedir una maquinaria ya ACTIVA en algún conjunto
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: dto.maquinariaId, estado: "ACTIVA" },
      select: { id: true },
    });
    if (activa)
      throw new Error(
        "❌ Esa maquinaria ya está asignada (ACTIVA) a un conjunto."
      );

    return this.prisma.solicitudMaquinaria.create({
      data: {
        conjunto: { connect: { nit: dto.conjuntoId } },
        maquinaria: { connect: { id: dto.maquinariaId } },
        responsable: { connect: { id: dto.operarioId.toString() } },
        empresa: dto.empresaId
          ? { connect: { nit: dto.empresaId } }
          : undefined,
        fechaUso: dto.fechaUso,
        fechaDevolucionEstimada: dto.fechaDevolucionEstimada,
        estado: "PENDIENTE",
      },
    });
  }
}
