// src/services/EmpresaService.ts
import {
  EstadoSolicitud,
} from "@prisma/client";
import { z } from "zod";
import { prisma } from "../db/prisma";
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
import {
  CrearMaquinariaDTO,
  DevolverMaquinariaDeConjuntoDTO,
  EditarMaquinariaCatalogoDTO,
  FiltroMaquinariaDTO,
  maquinariaCatalogoSelect,
  maquinariaConjuntoSelect,
  PrestarMaquinariaAConjuntoDTO,
} from "../model/Maquinaria";

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

  constructor(empresaNit: string) {
    this.empresaNit = empresaNit; // empresaNit = NIT (clave)
  }

  /* ===================== HELPERS ===================== */

  /** Devuelve el límite legal/operativo semanal en HORAS para esta empresa */
  async getLimiteHorasSemana(): Promise<number> {
    const empresa = await prisma.empresa.findUnique({
      where: { nit: this.empresaNit },
      select: { limiteHorasSemana: true },
    });
    if (!empresa) throw new Error("Empresa no encontrada.");
    return empresa.limiteHorasSemana;
  }

  /** Setter del límite semanal (HORAS) para esta empresa */
  async setLimiteHorasSemana(payload: unknown) {
    const { limiteHorasSemana } = SetLimiteHorasDTO.parse(payload);
    await prisma.empresa.update({
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
    const conjunto = await prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { empresaId: true, limiteHorasSemanaOverride: true },
    });

    const override = conjunto?.limiteHorasSemanaOverride;
    if (override != null) return override * 60;

    // si el conjunto cuelga de otra empresa, respetamos esa
    const empresaNit = conjunto?.empresaId ?? this.empresaNit;

    const empresa = await prisma.empresa.findUnique({
      where: { nit: empresaNit },
      select: { limiteHorasSemana: true },
    });

    return (empresa?.limiteHorasSemana ?? 42) * 60;
  }

  /* ===================== EMPRESA ===================== */

  async crearEmpresa(payload: unknown) {
    const dto = CrearEmpresaDTO.parse(payload);

    const existe = await prisma.empresa.findUnique({
      where: { nit: dto.nit },
      select: { nit: true },
    });
    if (existe) throw new Error("Ya existe una empresa con este NIT.");

    const creada = await prisma.empresa.create({
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

    const actualizada = await prisma.empresa.update({
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
    const empresa = await prisma.empresa.findUnique({
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

    return prisma.festivo.findMany({
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
    await prisma.festivo.deleteMany({
      where: { pais: dto.pais, fecha: { gte: d1, lt: d2Next } },
    });

    // 2) crear set nuevo (normalizado)
    if (dto.fechas.length) {
      await prisma.festivo.createMany({
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
    const dto = CrearMaquinariaDTO.parse(payload);

    // Si es de conjunto, valida que ese conjunto exista y sea de esta empresa (si aplica)
    if (dto.propietarioTipo === "CONJUNTO") {
      const conj = await prisma.conjunto.findUnique({
        where: { nit: dto.conjuntoPropietarioId! },
        select: { nit: true, empresaId: true },
      });
      if (!conj) throw new Error("Conjunto propietario no existe.");
      // opcional: si manejas multi-empresa
      if (conj.empresaId && conj.empresaId !== this.empresaNit) {
        throw new Error("Ese conjunto no pertenece a esta empresa.");
      }
    }

    const creada = await prisma.maquinaria.create({
      data: {
        nombre: dto.nombre,
        marca: dto.marca,
        tipo: dto.tipo,
        estado: dto.estado,

        propietarioTipo: dto.propietarioTipo,
        empresaId: this.empresaNit,
        conjuntoPropietarioId:
          dto.propietarioTipo === "CONJUNTO" ? dto.conjuntoPropietarioId : null,
      },
      select: {
        id: true,
        nombre: true,
        marca: true,
        tipo: true,
        estado: true,
        propietarioTipo: true,
        empresaId: true,
        conjuntoPropietarioId: true,
      },
    });

    return creada;
  }

  async editarMaquinaria(id: number, payload: unknown) {
    const dto = EditarMaquinariaCatalogoDTO.parse(payload);

    const data: any = {
      nombre: dto.nombre ?? undefined,
      marca: dto.marca ?? undefined,
      tipo: dto.tipo ?? undefined,
      estado: dto.estado ?? undefined,
    };

    if (dto.operarioId !== undefined) {
      data.operario =
        dto.operarioId === null
          ? { disconnect: true }
          : { connect: { id: dto.operarioId } };
    }

    return prisma.maquinaria.update({
      where: { id },
      data,
      select: maquinariaCatalogoSelect,
    });
  }

  async eliminarMaquinaria(id: number) {
    const existente = await prisma.maquinaria.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: { id: true },
    });
    if (!existente)
      throw new Error("Maquinaria no encontrada para esta empresa.");

    await prisma.maquinaria.delete({ where: { id } });
  }

  async prestarMaquinariaAConjunto(payload: unknown) {
    const dto = PrestarMaquinariaAConjuntoDTO.parse(payload);

    // 1) validar que exista maquinaria
    const maq = await prisma.maquinaria.findUnique({
      where: { id: dto.maquinariaId },
      select: { id: true },
    });
    if (!maq) throw new Error("Maquinaria no encontrada.");

    // 2) validar que no esté ACTIVA en ningún conjunto
    const activa = await prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: dto.maquinariaId, estado: "ACTIVA" },
      select: { id: true, conjuntoId: true },
    });
    if (activa)
      throw new Error(`❌ Ya está ACTIVA en el conjunto ${activa.conjuntoId}.`);

    // 3) crear asignación inventario
    return prisma.maquinariaConjunto.create({
      data: {
        conjunto: { connect: { nit: dto.conjuntoId } },
        maquinaria: { connect: { id: dto.maquinariaId } },
        tipoTenencia: "PRESTADA",
        estado: "ACTIVA",
        fechaInicio: new Date(),

        ...(dto.fechaDevolucionEstimada
          ? { fechaDevolucionEstimada: dto.fechaDevolucionEstimada }
          : {}),
        ...(dto.operarioId
          ? { responsable: { connect: { id: dto.operarioId } } }
          : {}),
      },
      select: maquinariaConjuntoSelect,
    });
  }

  async devolverMaquinariaDeConjunto(payload: unknown) {
    const dto = DevolverMaquinariaDeConjuntoDTO.parse(payload);

    const asignacion = await prisma.maquinariaConjunto.findFirst({
      where: {
        maquinariaId: dto.maquinariaId,
        conjuntoId: dto.conjuntoId,
        estado: "ACTIVA",
      },
      select: { id: true },
    });

    if (!asignacion) {
      throw new Error(
        "No hay una asignación ACTIVA de esa maquinaria en este conjunto."
      );
    }

    return prisma.maquinariaConjunto.update({
      where: { id: asignacion.id },
      data: {
        estado: "DEVUELTA",
        fechaFin: new Date(),
      },
      select: maquinariaConjuntoSelect,
    });
  }

  async listarMaquinariaCatalogo(payloadFiltro?: unknown) {
    const filtro = payloadFiltro
      ? FiltroMaquinariaDTO.parse(payloadFiltro)
      : {};
    const empresaId = filtro.empresaId ?? this.empresaNit;

    const where: any = {
      empresaId,
      estado: filtro.estado ?? undefined,
      tipo: filtro.tipo ?? undefined,
      propietarioTipo: filtro.propietarioTipo ?? undefined,
    };

    // ✅ filtro por “disponible” (derivado de asignación ACTIVA)
    if (filtro.disponible === true) {
      where.asignaciones = { none: { estado: "ACTIVA" } };
    } else if (filtro.disponible === false) {
      where.asignaciones = { some: { estado: "ACTIVA" } };
    }

    // ✅ filtro por “prestada a este conjunto”
    if (filtro.conjuntoId) {
      // solo las que tienen asignación ACTIVA en ese conjunto
      where.asignaciones = {
        ...(where.asignaciones ?? {}),
        some: { estado: "ACTIVA", conjuntoId: filtro.conjuntoId },
      };
    }

    const items = await prisma.maquinaria.findMany({
      where,
      select: {
        id: true,
        nombre: true,
        marca: true,
        tipo: true,
        estado: true,

        propietarioTipo: true,
        empresaId: true,
        conjuntoPropietarioId: true,

        // responsable global (si lo usas en Maquinaria)
        operarioId: true,
        operario: { select: { usuario: { select: { nombre: true } } } },

        // ✅ asignación ACTIVA (si existe) para mostrar “prestada a…”
        asignaciones: {
          where: { estado: "ACTIVA" },
          select: {
            id: true,
            conjuntoId: true,
            tipoTenencia: true,
            fechaInicio: true,
            fechaDevolucionEstimada: true,
            conjunto: { select: { nombre: true } },
            responsable: { select: { usuario: { select: { nombre: true } } } },
          },
          take: 1,
        },

        // ✅ si es dueño CONJUNTO, traemos el nombre del conjunto propietario
        conjuntoPropietario: { select: { nit: true, nombre: true } },
      },
      orderBy: { nombre: "asc" },
    });

    return items.map((m) => {
      const activa = m.asignaciones[0] ?? null;

      // origen/dueño para el front
      const origen = m.propietarioTipo; // "EMPRESA" | "CONJUNTO"

      // disponible derivado
      const disponible = !activa;

      // si está asignada ACTIVA, a qué conjunto
      const prestadaA = activa
        ? {
            conjuntoId: activa.conjuntoId,
            conjuntoNombre: activa.conjunto?.nombre ?? null,
            tipoTenencia: activa.tipoTenencia, // PRESTADA/PROPIA (en esa asignación)
            fechaInicio: activa.fechaInicio,
            fechaDevolucionEstimada: activa.fechaDevolucionEstimada ?? null,
            responsableNombre: activa.responsable?.usuario?.nombre ?? null,
            asignacionId: activa.id,
          }
        : null;

      // si el dueño es CONJUNTO, cuál es el conjunto propietario
      const propietarioConjunto =
        m.propietarioTipo === "CONJUNTO"
          ? {
              conjuntoId:
                m.conjuntoPropietario?.nit ?? m.conjuntoPropietarioId ?? null,
              conjuntoNombre: m.conjuntoPropietario?.nombre ?? null,
            }
          : null;

      return {
        id: m.id,
        nombre: m.nombre,
        marca: m.marca,
        tipo: m.tipo,
        estado: m.estado,

        // ✅ clave para UI
        origen, // EMPRESA o CONJUNTO
        disponible, // derivado

        // ✅ si es de conjunto
        propietarioConjunto,

        // ✅ si está prestada/asignada
        prestadaA,

        // opcional: responsable global de la máquina (si lo manejas)
        operarioId: m.operarioId ?? null,
        operarioNombre: m.operario?.usuario?.nombre ?? null,

        empresaId: m.empresaId ?? null,
      };
    });
  }

  async listarMaquinariaDisponible() {
    return prisma.maquinaria.findMany({
      where: {
        propietarioTipo: "EMPRESA",
        empresaId: this.empresaNit,
        asignaciones: { none: { estado: "ACTIVA" } },
      },
      select: maquinariaCatalogoSelect,
      orderBy: { nombre: "asc" },
    });
  }

  async obtenerMaquinariaPrestada() {
    return prisma.maquinariaConjunto.findMany({
      where: {
        estado: "ACTIVA",
        tipoTenencia: "PRESTADA",
        maquinaria: { empresaId: this.empresaNit },
      },
      include: {
        conjunto: { select: { nit: true, nombre: true } },
        maquinaria: {
          select: {
            id: true,
            nombre: true,
            marca: true,
            tipo: true,
            estado: true,
          },
        },
        responsable: { include: { usuario: { select: { nombre: true } } } },
      },
    });
  }

  /* ===================== ROLES ===================== */

  async agregarJefeOperaciones(payload: unknown) {
    const { usuarioId } = AgregarJefeOperacionesDTO.parse(payload);

    const existente = await prisma.jefeOperaciones.findFirst({
      where: { id: usuarioId.toString(), empresaId: this.empresaNit },
    });
    if (existente)
      throw new Error("Este jefe ya está registrado en la empresa.");

    const jefe = await prisma.jefeOperaciones.findUnique({
      where: { id: usuarioId.toString() },
      select: { id: true },
    });
    if (!jefe)
      throw new Error(
        "El usuario no es Jefe de Operaciones (no existe el rol)."
      );

    return prisma.jefeOperaciones.update({
      where: { id: usuarioId.toString() },
      data: { empresaId: this.empresaNit },
    });
  }

  /* ===================== SOLICITUDES DE TAREA ===================== */

  async recibirSolicitudTarea(payload: unknown) {
    const { id } = IdNumericoDTO.parse(payload);
    return prisma.solicitudTarea.update({
      where: { id },
      data: { empresaId: this.empresaNit },
    });
  }

  async eliminarSolicitudTarea(payload: unknown) {
    const { id } = IdNumericoDTO.parse(payload);
    return prisma.solicitudTarea.delete({ where: { id } });
  }

  async solicitudesTareaPendientes() {
    return prisma.solicitudTarea.findMany({
      where: { empresaId: this.empresaNit, estado: EstadoSolicitud.PENDIENTE },
      include: { conjunto: true, ubicacion: true, elemento: true },
    });
  }

  /* ===================== CATÁLOGO DE INSUMOS ===================== */

  async agregarInsumoAlCatalogo(payload: unknown) {
    const dto = CrearInsumoDTO.parse(payload);

    const empresa = await prisma.empresa.findUnique({
      where: { nit: this.empresaNit },
      select: { nit: true },
    });

    if (!empresa) {
      throw new Error(
        `La empresa con NIT ${this.empresaNit} no existe. Debes crearla antes de agregar insumos al catálogo.`
      );
    }

    const existe = await prisma.insumo.findFirst({
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

    const creado = await prisma.insumo.create({
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

    const insumos = await prisma.insumo.findMany({
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

    const insumo = await prisma.insumo.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: insumoPublicSelect,
    });

    return insumo ? toInsumoPublico(insumo) : null;
  }

  async editarInsumoCatalogo(id: number, payload: unknown) {
    const dto = EditarInsumoDTO.parse(payload);

    const existente = await prisma.insumo.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: { id: true },
    });
    if (!existente) throw new Error("Insumo no encontrado para esta empresa.");

    const actualizado = await prisma.insumo.update({
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
    const existente = await prisma.insumo.findFirst({
      where: { id, empresaId: this.empresaNit },
      select: { id: true },
    });
    if (!existente) throw new Error("Insumo no encontrado para esta empresa.");

    await prisma.insumo.delete({ where: { id } });
  }
}
