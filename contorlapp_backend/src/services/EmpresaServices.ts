import { PrismaClient, EstadoMaquinaria, TipoMaquinaria } from "../generated/prisma";
import { z } from "zod";
import {
  CrearMaquinariaDTO,
  maquinariaPublicSelect,
  toMaquinariaPublica,
} from "../model/Maquinaria";
import {
  CrearInsumoDTO,
  insumoPublicSelect,
} from "../model/Insumo";

/** DTOs locales */
const CrearEmpresaDTO = z.object({
  nombre: z.string().min(3),
  nit: z.string().min(3),
});

const AgregarJefeOperacionesDTO = z.object({
  usuarioId: z.number().int().positive(),
});

const IdNumericoDTO = z.object({ id: z.number().int().positive() });

export class EmpresaService {
  constructor(private prisma: PrismaClient, private empresaId: string) {} // empresaId = nit

  async crearEmpresa(payload: unknown) {
    const dto = CrearEmpresaDTO.parse(payload);

    const existe = await this.prisma.empresa.findUnique({ where: { nit: dto.nit } });
    if (existe) throw new Error("Ya existe una empresa con este NIT.");

    return this.prisma.empresa.create({
      data: { nombre: dto.nombre, nit: dto.nit },
    });
  }

  async agregarMaquinaria(payload: unknown) {
    // Reutilizamos tu DTO de maquinaria y forzamos empresaId = this.empresaId
    const base = CrearMaquinariaDTO.parse(payload);
    try {
      const creada = await this.prisma.maquinaria.create({
        data: {
          nombre: base.nombre,
          marca: base.marca,
          tipo: base.tipo as TipoMaquinaria,
          estado: base.estado ?? EstadoMaquinaria.OPERATIVA,
          disponible: base.disponible ?? true,
          empresaId: this.empresaId,
          conjuntoId: base.conjuntoId ?? null,
          operarioId: base.operarioId ?? null,
          fechaPrestamo: base.fechaPrestamo ?? null,
          fechaDevolucionEstimada: base.fechaDevolucionEstimada ?? null,
        },
        select: maquinariaPublicSelect,
      });
      return toMaquinariaPublica(creada);
    } catch (error) {
      console.error("Error al agregar maquinaria:", error);
      throw new Error("No se pudo agregar la maquinaria. Verifica los datos.");
    }
  }

  async listarMaquinariaDisponible() {
    return this.prisma.maquinaria.findMany({
      where: { empresaId: this.empresaId, disponible: true },
      select: maquinariaPublicSelect,
    });
  }

  async obtenerMaquinariaPrestada() {
    const maquinaria = await this.prisma.maquinaria.findMany({
      where: {
        empresaId: this.empresaId,
        disponible: false,
        conjuntoId: { not: null },
      },
      include: {
        asignadaA: true,
        responsable: { include: { usuario: true } },
      },
    });

    return maquinaria.map((m) => ({
      maquina: {
        id: m.id,
        nombre: m.nombre,
        marca: m.marca,
        tipo: m.tipo,
        estado: m.estado,
        disponible: m.disponible,
      },
      conjunto: m.asignadaA?.nombre ?? "Desconocido",
      responsable: m.responsable?.usuario?.nombre ?? "Sin asignar",
      fechaPrestamo: m.fechaPrestamo!,
      fechaDevolucionEstimada: m.fechaDevolucionEstimada ?? null,
    }));
  }

  async agregarJefeOperaciones(payload: unknown) {
    const { usuarioId } = AgregarJefeOperacionesDTO.parse(payload);

    const existente = await this.prisma.jefeOperaciones.findFirst({
      where: { id: usuarioId, empresaId: this.empresaId },
    });
    if (existente) throw new Error("Este jefe ya está registrado en la empresa.");

    // Debe existir el registro JefeOperaciones por el id (relación 1:1 con Usuario)
    const jefe = await this.prisma.jefeOperaciones.findUnique({ where: { id: usuarioId } });
    if (!jefe) throw new Error("El usuario no es Jefe de Operaciones (no existe el rol).");

    return this.prisma.jefeOperaciones.update({
      where: { id: usuarioId },
      data: { empresaId: this.empresaId },
    });
  }

  async recibirSolicitudTarea(payload: unknown) {
    const { id } = IdNumericoDTO.parse(payload);
    return this.prisma.solicitudTarea.update({
      where: { id },
      data: { empresaId: this.empresaId },
    });
  }

  async eliminarSolicitudTarea(payload: unknown) {
    const { id } = IdNumericoDTO.parse(payload);
    return this.prisma.solicitudTarea.delete({ where: { id } });
  }

  async solicitudesTareaPendientes() {
    return this.prisma.solicitudTarea.findMany({
      where: { empresaId: this.empresaId, estado: "PENDIENTE" },
      include: { conjunto: true, ubicacion: true, elemento: true },
    });
  }

  async agregarInsumoAlCatalogo(payload: unknown) {
    // Usa tu DTO de insumo; fuerza empresaId actual
    const dto = CrearInsumoDTO.parse({ ...(payload as any), empresaId: this.empresaId });

    const existe = await this.prisma.insumo.findFirst({
      where: { empresaId: this.empresaId, nombre: dto.nombre, unidad: dto.unidad },
      select: { id: true },
    });
    if (existe) throw new Error("🚫 Ya existe un insumo con ese nombre y unidad en el catálogo.");

    return this.prisma.insumo.create({
      data: { nombre: dto.nombre, unidad: dto.unidad, empresaId: this.empresaId },
      select: insumoPublicSelect,
    });
  }

  async listarCatalogo() {
    const insumos = await this.prisma.insumo.findMany({
      where: { empresaId: this.empresaId },
      select: insumoPublicSelect,
    });
    return insumos.map((i) => `${i.nombre} (${i.unidad})`);
  }

  async buscarInsumoPorId(payload: unknown) {
    const { id } = IdNumericoDTO.parse(payload);
    return this.prisma.insumo.findFirst({
      where: { id, empresaId: this.empresaId },
      select: insumoPublicSelect,
    });
  }
}
