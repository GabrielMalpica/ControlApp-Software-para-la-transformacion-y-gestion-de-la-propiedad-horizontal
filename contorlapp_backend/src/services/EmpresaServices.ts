// src/services/EmpresaService.ts
import {
  PrismaClient,
  EstadoMaquinaria,
  EstadoSolicitud,
} from "../generated/prisma";
import { z } from "zod";

import {
  CrearMaquinariaDTO,
  EditarMaquinariaDTO,
  FiltroMaquinariaDTO,
  maquinariaPublicSelect,
  toMaquinariaPublica,
} from "../model/Maquinaria";

import {
  CrearInsumoDTO,
  EditarInsumoDTO,
  FiltroInsumoDTO,
  InsumoPublico,
  insumoPublicSelect,
  toInsumoPublico,
} from "../model/Insumo";

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

const RangoDTO = z.object({
  pais: z.string().min(2).default("CO"),
  desde: z.string().min(10),
  hasta: z.string().min(10),
});

const FestivosRangoDTO = RangoDTO.extend({
  fechas: z.array(
    z.object({
      fecha: z.string().min(10),
      nombre: z.string().optional().nullable(),
    })
  ),
});

export class EmpresaService {
  private empresaNit: string;

  constructor(private prisma: PrismaClient, empresaNit: string) {
    this.empresaNit = empresaNit; // empresaNit = NIT (clave)
  }

  /* ===================== HELPERS ===================== */

  /** Devuelve el límite legal/operativo semanal en HORAS para esta empresa */
  async getLimiteHorasSemana(): Promise<number> {
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit: this.empresaNit },
      select: { limiteHorasSemana: true },
    });
    if (!empresa) throw new Error("Empresa no encontrada.");
    return empresa.limiteHorasSemana;
  }

  /** Setter del límite semanal (HORAS) para esta empresa */
  async setLimiteHorasSemana(payload: unknown) {
    const { limiteHorasSemana } = SetLimiteHorasDTO.parse(payload);
    await this.prisma.empresa.update({
      where: { nit: this.empresaNit },
      data: { limiteHorasSemana },
    });
  }

  /**
   * ✅ Límite semanal en MINUTOS aplicable a un conjunto:
   * 1) Si el conjunto tiene override -> usarlo
   * 2) Si no -> usa el de la empresa operadora
   */
  async getLimiteMinSemanaPorConjunto(conjuntoId: string): Promise<number> {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { empresaId: true, limiteHorasSemanaOverride: true },
    });

    const override = conjunto?.limiteHorasSemanaOverride;
    if (override != null) return override * 60;

    // si el conjunto cuelga de otra empresa, respetamos esa
    const empresaNit = conjunto?.empresaId ?? this.empresaNit;

    const empresa = await this.prisma.empresa.findUnique({
      where: { nit: empresaNit },
      select: { limiteHorasSemana: true },
    });

    return (empresa?.limiteHorasSemana ?? 42) * 60;
  }

  /* ===================== EMPRESA ===================== */

  async crearEmpresa(payload: unknown) {
    const dto = CrearEmpresaDTO.parse(payload);

    const existe = await this.prisma.empresa.findUnique({
      where: { nit: dto.nit },
      select: { nit: true },
    });
    if (existe) throw new Error("Ya existe una empresa con este NIT.");

    const creada = await this.prisma.empresa.create({
      data: {
        nombre: dto.nombre,
        nit: dto.nit,
        limiteHorasSemana: dto.limiteHorasSemana ?? undefined, // si no viene, Prisma aplica default
      },
      select: empresaPublicSelect,
    });

    // Si quieres operar con la empresa recién creada, sincroniza el service
    this.empresaNit = creada.nit;

    return toEmpresaPublica(creada);
  }

  async editarEmpresa(payload: unknown) {
    const dto = EditarEmpresaDTO.parse(payload);

    const actualizada = await this.prisma.empresa.update({
      where: { nit: this.empresaNit },
      data: {
        nombre: dto.nombre ?? undefined,
        nit: dto.nit ?? undefined, // si permites cambiarlo
        limiteHorasSemana: dto.limiteHorasSemana ?? undefined,
      },
      select: empresaPublicSelect,
    });

    if (dto.nit && dto.nit !== this.empresaNit) {
      this.empresaNit = dto.nit;
    }

    return toEmpresaPublica(actualizada);
  }

  async getEmpresa() {
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit: this.empresaNit },
      select: empresaPublicSelect,
    });
    if (!empresa) throw new Error("Empresa no encontrada.");
    return toEmpresaPublica(empresa);
  }

  startOfDayLocal(dateStr: string) {
    const [y, m, d] = dateStr.split("-").map(Number);
    return new Date(y, m - 1, d, 0, 0, 0, 0);
  }

  async listarFestivos(desde: string, hasta: string, pais = "CO") {
    const d1 = this.startOfDayLocal(desde);
    const d2 = this.startOfDayLocal(hasta);
    // hasta inclusive -> sumas 1 día para usar lt
    const d2Next = new Date(d2.getTime() + 24 * 60 * 60 * 1000);

    return this.prisma.festivo.findMany({
      where: { pais, fecha: { gte: d1, lt: d2Next } },
      orderBy: { fecha: "asc" },
    });
  }

  async reemplazarFestivosEnRango(payload: unknown) {
    const dto = FestivosRangoDTO.parse(payload);

    const d1 = this.startOfDayLocal(dto.desde);
    const d2 = this.startOfDayLocal(dto.hasta);
    const d2Next = new Date(d2.getTime() + 24 * 60 * 60 * 1000);

    // 1) borrar rango
    await this.prisma.festivo.deleteMany({
      where: { pais: dto.pais, fecha: { gte: d1, lt: d2Next } },
    });

    // 2) crear set nuevo (normalizado)
    if (dto.fechas.length) {
      await this.prisma.festivo.createMany({
        data: dto.fechas.map((f) => ({
          pais: dto.pais,
          fecha: this.startOfDayLocal(f.fecha),
          nombre: f.nombre ?? null,
        })),
        skipDuplicates: true, // por si acaso
      });
    }

    return { ok: true, total: dto.fechas.length };
  }

  /* ===================== MAQUINARIA ===================== */

  async agregarMaquinaria(payload: unknown) {
    const base = CrearMaquinariaDTO.parse(payload);

    try {
      const creada = await this.prisma.maquinaria.create({
        data: {
          nombre: base.nombre,
          marca: base.marca,
          tipo: base.tipo,
          estado: base.estado ?? EstadoMaquinaria.OPERATIVA,
          disponible: base.disponible ?? true,
          empresaId: this.empresaNit,
          conjuntoId: base.conjuntoId ?? null,
          operarioId:
            base.operarioId != null ? base.operarioId.toString() : null,
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

  async editarMaquinaria(id: number, payload: unknown) {
    const dto = EditarMaquinariaDTO.parse(payload);

    const existente = await this.prisma.maquinaria.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: { id: true },
    });
    if (!existente)
      throw new Error("Maquinaria no encontrada para esta empresa.");

    const actualizada = await this.prisma.maquinaria.update({
      where: { id },
      data: {
        nombre: dto.nombre ?? undefined,
        marca: dto.marca ?? undefined,
        tipo: dto.tipo ?? undefined,
        estado: dto.estado ?? undefined,
        disponible: dto.disponible ?? undefined,
        conjuntoId: dto.conjuntoId ?? undefined,
        operarioId:
          dto.operarioId === null
            ? null
            : dto.operarioId != null
            ? dto.operarioId.toString()
            : undefined,
        empresaId: dto.empresaId ?? undefined,
        fechaPrestamo:
          dto.fechaPrestamo === null ? null : dto.fechaPrestamo ?? undefined,
        fechaDevolucionEstimada:
          dto.fechaDevolucionEstimada === null
            ? null
            : dto.fechaDevolucionEstimada ?? undefined,
      },
      select: maquinariaPublicSelect,
    });

    return toMaquinariaPublica(actualizada);
  }

  async eliminarMaquinaria(id: number) {
    const existente = await this.prisma.maquinaria.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: { id: true },
    });
    if (!existente)
      throw new Error("Maquinaria no encontrada para esta empresa.");

    await this.prisma.maquinaria.delete({ where: { id } });
  }

  async listarMaquinariaCatalogo(payloadFiltro?: unknown) {
    const filtro = payloadFiltro
      ? FiltroMaquinariaDTO.parse(payloadFiltro)
      : {};

    const items = await this.prisma.maquinaria.findMany({
      where: {
        empresaId: filtro.empresaId ?? this.empresaNit,
        conjuntoId: filtro.conjuntoId ?? undefined,
        estado: filtro.estado ?? undefined,
        disponible: filtro.disponible ?? undefined,
        tipo: filtro.tipo ?? undefined,
      },
      select: {
        id: true,
        nombre: true,
        marca: true,
        tipo: true,
        estado: true,
        disponible: true,
        conjuntoId: true,
        operarioId: true,
        empresaId: true,
        fechaPrestamo: true,
        fechaDevolucionEstimada: true,
        asignadaA: { select: { nombre: true } },
        responsable: { select: { usuario: { select: { nombre: true } } } },
      },
      orderBy: { nombre: "asc" },
    });

    return items.map((m) => ({
      id: m.id,
      nombre: m.nombre,
      marca: m.marca,
      tipo: m.tipo,
      estado: m.estado,
      disponible: m.disponible,
      conjuntoId: m.conjuntoId,
      operarioId: m.operarioId as any,
      empresaId: m.empresaId,
      fechaPrestamo: m.fechaPrestamo,
      fechaDevolucionEstimada: m.fechaDevolucionEstimada,
      conjuntoNombre: m.asignadaA?.nombre ?? null,
      operarioNombre: m.responsable?.usuario?.nombre ?? null,
    }));
  }

  async listarMaquinariaDisponible() {
    const items = await this.prisma.maquinaria.findMany({
      where: { empresaId: this.empresaNit, disponible: true },
      select: maquinariaPublicSelect,
      orderBy: { nombre: "asc" },
    });

    return items.map(toMaquinariaPublica);
  }

  async obtenerMaquinariaPrestada() {
    const maquinaria = await this.prisma.maquinaria.findMany({
      where: {
        empresaId: this.empresaNit,
        disponible: false,
        conjuntoId: { not: null },
      },
      include: { asignadaA: true, responsable: { include: { usuario: true } } },
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
      where: { id: usuarioId.toString(), empresaId: this.empresaNit },
    });
    if (existente)
      throw new Error("Este jefe ya está registrado en la empresa.");

    const jefe = await this.prisma.jefeOperaciones.findUnique({
      where: { id: usuarioId.toString() },
      select: { id: true },
    });
    if (!jefe)
      throw new Error(
        "El usuario no es Jefe de Operaciones (no existe el rol)."
      );

    return this.prisma.jefeOperaciones.update({
      where: { id: usuarioId.toString() },
      data: { empresaId: this.empresaNit },
    });
  }

  /* ===================== SOLICITUDES DE TAREA ===================== */

  async recibirSolicitudTarea(payload: unknown) {
    const { id } = IdNumericoDTO.parse(payload);
    return this.prisma.solicitudTarea.update({
      where: { id },
      data: { empresaId: this.empresaNit },
    });
  }

  async eliminarSolicitudTarea(payload: unknown) {
    const { id } = IdNumericoDTO.parse(payload);
    return this.prisma.solicitudTarea.delete({ where: { id } });
  }

  async solicitudesTareaPendientes() {
    return this.prisma.solicitudTarea.findMany({
      where: { empresaId: this.empresaNit, estado: EstadoSolicitud.PENDIENTE },
      include: { conjunto: true, ubicacion: true, elemento: true },
    });
  }

  /* ===================== CATÁLOGO DE INSUMOS ===================== */

  async agregarInsumoAlCatalogo(payload: unknown) {
    const dto = CrearInsumoDTO.parse(payload);

    const empresa = await this.prisma.empresa.findUnique({
      where: { nit: this.empresaNit },
      select: { nit: true },
    });

    if (!empresa) {
      throw new Error(
        `La empresa con NIT ${this.empresaNit} no existe. Debes crearla antes de agregar insumos al catálogo.`
      );
    }

    const existe = await this.prisma.insumo.findFirst({
      where: {
        empresaId: this.empresaNit,
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
        empresaId: this.empresaNit,
      },
      select: insumoPublicSelect,
    });

    return creado;
  }

  async listarCatalogo(filtroRaw?: unknown): Promise<InsumoPublico[]> {
    const filtro = filtroRaw ? FiltroInsumoDTO.parse(filtroRaw) : {};

    const insumos = await this.prisma.insumo.findMany({
      where: {
        empresaId: filtro.empresaId ?? this.empresaNit,
        categoria: filtro.categoria ?? undefined,
        nombre: filtro.nombre
          ? { contains: filtro.nombre, mode: "insensitive" }
          : undefined,
      },
      select: insumoPublicSelect,
      orderBy: { nombre: "asc" },
    });

    return insumos.map(toInsumoPublico);
  }

  async buscarInsumoPorId(payload: unknown): Promise<InsumoPublico | null> {
    const { id } = IdNumericoDTO.parse(payload);

    const insumo = await this.prisma.insumo.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: insumoPublicSelect,
    });

    return insumo ? toInsumoPublico(insumo) : null;
  }

  async editarInsumoCatalogo(id: number, payload: unknown) {
    const dto = EditarInsumoDTO.parse(payload);

    const existente = await this.prisma.insumo.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: { id: true },
    });
    if (!existente) throw new Error("Insumo no encontrado para esta empresa.");

    const actualizado = await this.prisma.insumo.update({
      where: { id },
      data: {
        nombre: dto.nombre ?? undefined,
        unidad: dto.unidad ?? undefined,
        categoria: dto.categoria ?? undefined,
        umbralBajo: dto.umbralBajo ?? undefined,
        empresaId: dto.empresaId ?? undefined,
      },
      select: insumoPublicSelect,
    });

    return toInsumoPublico(actualizado);
  }

  async eliminarInsumoCatalogo(id: number) {
    const existente = await this.prisma.insumo.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: { id: true },
    });
    if (!existente) throw new Error("Insumo no encontrado para esta empresa.");

    await this.prisma.insumo.delete({ where: { id } });
  }
}
