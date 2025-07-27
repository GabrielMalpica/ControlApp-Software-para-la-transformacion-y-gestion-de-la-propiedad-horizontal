import { EstadoMaquinaria, PrismaClient, TipoMaquinaria } from '../generated/prisma';

export class EmpresaService {
  constructor(private prisma: PrismaClient, private empresaId: string) {}

  async crearEmpresa(nombre: string, nit: string) {
    const existe = await this.prisma.empresa.findUnique({ where: { nit } });
    if (existe) throw new Error("Ya existe una empresa con este NIT.");

    return await this.prisma.empresa.create({
      data: { nombre, nit },
    });
  }

  async agregarMaquinaria(maquinariaData: {
    nombre: string;
    marca: string;
    tipo: TipoMaquinaria;
  }) {
    try {
      return await this.prisma.maquinaria.create({
        data: {
          nombre: maquinariaData.nombre,
          marca: maquinariaData.marca,
          tipo: maquinariaData.tipo,
          estado: EstadoMaquinaria.OPERATIVA,
          disponible: true,
          empresaId: this.empresaId
        }
      });
    } catch (error) {
      console.error("Error al agregar maquinaria:", error);
      throw new Error("No se pudo agregar la maquinaria. Verifica el tipo.");
    }
  }

  async listarMaquinariaDisponible() {
    return await this.prisma.maquinaria.findMany({
      where: {
        empresaId: this.empresaId,
        disponible: true
      }
    });
  }

  async obtenerMaquinariaPrestada() {
    const maquinaria = await this.prisma.maquinaria.findMany({
      where: {
        empresaId: this.empresaId,
        disponible: false,
        conjuntoId: { not: null }
      },
      include: {
        asignadaA: true,
        responsable: {
          include: {
            usuario: true
          }
        }
      }
    });

    return maquinaria.map(m => ({
      maquina: m,
      conjunto: m.asignadaA?.nombre ?? "Desconocido",
      responsable: m.responsable?.usuario?.nombre ?? "Sin asignar",
      fechaPrestamo: m.fechaPrestamo!,
      fechaDevolucionEstimada: m.fechaDevolucionEstimada
    }));
  }

  async agregarJefeOperaciones(usuarioId: number) {
    const existente = await this.prisma.jefeOperaciones.findFirst({
      where: {
        id: usuarioId,
        empresaId: this.empresaId
      }
    });

    if (existente) throw new Error("Este jefe ya está registrado en la empresa");

    return await this.prisma.jefeOperaciones.update({
      where: { id: usuarioId },
      data: {
        empresaId: this.empresaId
      }
    });
  }

  async recibirSolicitudTarea(solicitudId: number) {
    return await this.prisma.solicitudTarea.update({
      where: { id: solicitudId },
      data: {
        empresaId: this.empresaId
      }
    });
  }

  async eliminarSolicitudTarea(id: number) {
    return await this.prisma.solicitudTarea.delete({
      where: { id }
    });
  }

  async solicitudesTareaPendientes() {
    return await this.prisma.solicitudTarea.findMany({
      where: {
        empresaId: this.empresaId,
        estado: "PENDIENTE"
      },
      include: {
        conjunto: true,
        ubicacion: true,
        elemento: true
      }
    });
  }

  async agregarInsumoAlCatalogo(insumoData: { nombre: string; unidad: string }) {
    const existe = await this.prisma.insumo.findFirst({
      where: {
        empresaId: this.empresaId,
        nombre: insumoData.nombre,
        unidad: insumoData.unidad
      }
    });

    if (existe) {
      throw new Error("🚫 Ya existe un insumo con ese nombre y unidad en el catálogo");
    }

    return await this.prisma.insumo.create({
      data: {
        ...insumoData,
        empresaId: this.empresaId
      }
    });
  }

  async listarCatalogo() {
    const insumos = await this.prisma.insumo.findMany({
      where: { empresaId: this.empresaId }
    });

    return insumos.map(i => `${i.nombre} (${i.unidad})`);
  }

  async buscarInsumoPorId(id: number) {
    return await this.prisma.insumo.findFirst({
      where: {
        id,
        empresaId: this.empresaId
      }
    });
  }
}
