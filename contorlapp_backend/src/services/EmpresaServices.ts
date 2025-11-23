// src/services/EmpresaService.ts
import {
  PrismaClient,
  EstadoMaquinaria,
  TipoMaquinaria,
  EstadoSolicitud,
} from "../generated/prisma";
import { z } from "zod";

import {
  CrearMaquinariaDTO,
  maquinariaPublicSelect,
  toMaquinariaPublica,
} from "../model/Maquinaria";

import { CrearInsumoDTO, insumoPublicSelect } from "../model/Insumo";

import {
  CrearEmpresaDTO,
  EditarEmpresaDTO,
  empresaPublicSelect,
  toEmpresaPublica,
} from "../model/Empresa";

/** Zod local para setear el límite semanal directamente */
const SetLimiteHorasDTO = z.object({
  limiteHorasSemana: z.number().int().min(1).max(84),
});

const AgregarJefeOperacionesDTO = z.object({
  usuarioId: z.number().int().positive(),
});

const IdNumericoDTO = z.object({ id: z.number().int().positive() });

export class EmpresaService {
  constructor(private prisma: PrismaClient, private empresaId: string) {} // empresaId = NIT

  /* ===================== EMPRESA ===================== */

  async crearEmpresa(payload: unknown) {
    const dto = CrearEmpresaDTO.parse(payload);

    const existe = await this.prisma.empresa.findUnique({
      where: { nit: dto.nit },
    });
    if (existe) throw new Error("Ya existe una empresa con este NIT.");

    const creada = await this.prisma.empresa.create({
      data: {
        nombre: dto.nombre,
        nit: dto.nit,
        // si no viene, aplica default de Prisma (46)
        limiteHorasSemana: dto.limiteHorasSemana ?? undefined,
      },
      select: empresaPublicSelect,
    });

    // Si creas y además quieres operar con esa empresa, actualiza el NIT interno
    this.empresaId = creada.nit;

    return toEmpresaPublica(creada);
  }

  async editarEmpresa(payload: unknown) {
    const dto = EditarEmpresaDTO.parse(payload);

    // Actualización parcial por NIT (clave operativa del service)
    const actualizada = await this.prisma.empresa.update({
      where: { nit: this.empresaId },
      data: {
        nombre: dto.nombre ?? undefined,
        nit: dto.nit ?? undefined,
        limiteHorasSemana: dto.limiteHorasSemana ?? undefined,
      },
      select: empresaPublicSelect,
    });

    // Si cambiaste el NIT, mantén el service sincronizado
    if (dto.nit && dto.nit !== this.empresaId) {
      this.empresaId = dto.nit;
    }

    return toEmpresaPublica(actualizada);
  }

  async getEmpresa() {
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit: this.empresaId },
      select: empresaPublicSelect,
    });
    if (!empresa) throw new Error("Empresa no encontrada.");
    return toEmpresaPublica(empresa);
  }

  async getLimiteHorasSemana(): Promise<number> {
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit: this.empresaId },
      select: { limiteHorasSemana: true },
    });
    if (!empresa) throw new Error("Empresa no encontrada.");
    return empresa.limiteHorasSemana;
  }

  async setLimiteHorasSemana(payload: unknown) {
    const { limiteHorasSemana } = SetLimiteHorasDTO.parse(payload);
    await this.prisma.empresa.update({
      where: { nit: this.empresaId },
      data: { limiteHorasSemana },
    });
  }

  /* ===================== MAQUINARIA ===================== */

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
          operarioId: base.operarioId!.toString() ?? null,
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

  /* ===================== ROLES ===================== */

  async agregarJefeOperaciones(payload: unknown) {
    const { usuarioId } = AgregarJefeOperacionesDTO.parse(payload);

    const existente = await this.prisma.jefeOperaciones.findFirst({
      where: { id: usuarioId.toString(), empresaId: this.empresaId },
    });
    if (existente)
      throw new Error("Este jefe ya está registrado en la empresa.");

    // Debe existir el registro JefeOperaciones por el id (relación 1:1 con Usuario)
    const jefe = await this.prisma.jefeOperaciones.findUnique({
      where: { id: usuarioId.toString() },
    });
    if (!jefe)
      throw new Error(
        "El usuario no es Jefe de Operaciones (no existe el rol)."
      );

    return this.prisma.jefeOperaciones.update({
      where: { id: usuarioId.toString() },
      data: { empresaId: this.empresaId },
    });
  }

  /* ===================== SOLICITUDES DE TAREA ===================== */

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
      where: { empresaId: this.empresaId, estado: EstadoSolicitud.PENDIENTE },
      include: { conjunto: true, ubicacion: true, elemento: true },
    });
  }

  /* ===================== CATÁLOGO DE INSUMOS ===================== */

  async agregarInsumoAlCatalogo(payload: unknown) {
    const dto = CrearInsumoDTO.parse(payload);

    const existe = await this.prisma.insumo.findFirst({
      where: {
        empresaId: this.empresaId,
        nombre: dto.nombre,
        unidad: dto.unidad,
      },
      select: { id: true },
    });
    if (existe) {
      throw new Error(
        "🚫 Ya existe un insumo con ese nombre y unidad en el catálogo."
      );
    }

    const creado = await this.prisma.insumo.create({
      data: {
        nombre: dto.nombre,
        unidad: dto.unidad,
        categoria: dto.categoria,
        umbralBajo: dto.umbralBajo ?? null,
        empresaId: this.empresaId,
      },
      select: insumoPublicSelect,
    });

    return creado;
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
