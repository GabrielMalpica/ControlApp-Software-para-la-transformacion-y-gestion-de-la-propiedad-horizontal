// src/services/CatalogoOperativoService.ts
import type { Prisma, PrismaClient, TipoFuncion } from "@prisma/client";

import {
  mismosRoles,
  nombrePerfilDesdeRoles,
  normalizarTexto,
  rolesNormalizados,
} from "../utils/perfilOperativo";
import { sugerirCategoriaPorTexto } from "../utils/sugerenciaCategoria";

type Cliente = PrismaClient | Prisma.TransactionClient;

function httpError(status: number, message: string) {
  const err = new Error(message) as Error & { status: number };
  err.status = status;
  return err;
}

/** Categorías que se siembran para una empresa sin catálogo (orden = prioridad de programación). */
export const CATEGORIAS_POR_DEFECTO: ReadonlyArray<{
  nombre: string;
  colorHex: string;
  palabrasClave: string[];
}> = [
  {
    nombre: "Mantenimiento de piscinas",
    colorHex: "#0288D1",
    palabrasClave: ["piscin", "shock", "choque", "choke", "aspir", "clorar", "cloro", "vidrios de encerramiento", "parametros", "cepillar paredes y fondo"],
  },
  { nombre: "Poda", colorHex: "#558B2F", palabrasClave: ["poda", "podar", "deshierb", "deshoj", "cesped", "corte de"] },
  {
    nombre: "Jardinería",
    colorHex: "#2E7D32",
    palabrasClave: ["jardin", "riego", "fertiliz", "herbicida", "plaga", "matera", "zona verde", "zonas verdes", "maleza"],
  },
  {
    nombre: "Aseo",
    colorHex: "#8E24AA",
    palabrasClave: ["aseo", "barr", "trape", "limpi", "lav", "desinfec", "despapel", "shut", "vaciar", "retirar residuos", "recoger residuos", "cepill", "desempolv"],
  },
  {
    nombre: "Mantenimientos básicos",
    colorHex: "#EF6C00",
    palabrasClave: ["mantenimiento general", "inspecc", "revis", "verific", "extintor", "repar"],
  },
  { nombre: "Salvamento acuático", colorHex: "#D32F2F", palabrasClave: ["salvavidas", "salvamento"] },
  { nombre: "Actividades de supervisión", colorHex: "#455A64", palabrasClave: ["supervis"] },
];

const HEX = /^#[0-9A-Fa-f]{6}$/;

function limpiarNombre(valor: unknown, campo: string): string {
  const nombre = String(valor ?? "").trim().replace(/\s+/g, " ");
  if (!nombre) throw httpError(400, `${campo} es obligatorio.`);
  if (nombre.length > 80) throw httpError(400, `${campo} no puede superar 80 caracteres.`);
  return nombre;
}

function limpiarPalabrasClave(valor: readonly string[] | undefined): string[] {
  const vistas = new Set<string>();
  const out: string[] = [];
  for (const p of valor ?? []) {
    const limpia = String(p ?? "").trim();
    const clave = normalizarTexto(limpia);
    if (!clave || vistas.has(clave)) continue;
    vistas.add(clave);
    out.push(limpia);
  }
  return out;
}

function limpiarColor(valor: string | null | undefined): string | null {
  if (valor == null || valor === "") return null;
  if (!HEX.test(valor)) throw httpError(400, "El color debe tener formato #RRGGBB.");
  return valor.toUpperCase();
}

export class CatalogoOperativoService {
  constructor(private prisma: PrismaClient) {}

  /* ============================ CATEGORÍAS ============================ */

  /** Siembra las categorías por defecto solo si la empresa no tiene ninguna (idempotente). */
  async asegurarCategoriasPorDefecto(empresaId: string): Promise<void> {
    const existentes = await this.prisma.categoriaTarea.count({ where: { empresaId } });
    if (existentes > 0) return;
    await this.prisma.categoriaTarea.createMany({
      data: CATEGORIAS_POR_DEFECTO.map((c, i) => ({
        empresaId,
        nombre: c.nombre,
        ordenProgramacion: i + 1,
        colorHex: c.colorHex,
        palabrasClave: c.palabrasClave,
      })),
      skipDuplicates: true,
    });
  }

  async listarCategorias(empresaId: string) {
    await this.asegurarCategoriasPorDefecto(empresaId);
    const [categorias, usos] = await Promise.all([
      this.prisma.categoriaTarea.findMany({
        where: { empresaId },
        orderBy: [{ ordenProgramacion: "asc" }, { id: "asc" }],
      }),
      this.prisma.definicionTareaPreventiva.groupBy({
        by: ["categoriaId"],
        where: { categoriaId: { not: null }, conjunto: { empresaId } },
        _count: { _all: true },
      }),
    ]);
    const usoPorId = new Map(usos.map((u) => [u.categoriaId as number, u._count._all]));
    return categorias.map((c) => ({ ...c, preventivas: usoPorId.get(c.id) ?? 0 }));
  }

  async crearCategoria(
    empresaId: string,
    dto: { nombre: string; colorHex?: string | null; palabrasClave?: string[] },
  ) {
    await this.asegurarCategoriasPorDefecto(empresaId);
    const nombre = limpiarNombre(dto.nombre, "El nombre");
    await this.validarNombreCategoriaLibre(empresaId, nombre);
    const ultimo = await this.prisma.categoriaTarea.aggregate({
      where: { empresaId },
      _max: { ordenProgramacion: true },
    });
    return this.prisma.categoriaTarea.create({
      data: {
        empresaId,
        nombre,
        ordenProgramacion: (ultimo._max.ordenProgramacion ?? 0) + 1,
        colorHex: limpiarColor(dto.colorHex),
        palabrasClave: limpiarPalabrasClave(dto.palabrasClave),
      },
    });
  }

  async editarCategoria(
    empresaId: string,
    id: number,
    dto: {
      nombre?: string;
      colorHex?: string | null;
      palabrasClave?: string[];
      activa?: boolean;
    },
  ) {
    const actual = await this.prisma.categoriaTarea.findFirst({ where: { id, empresaId } });
    if (!actual) throw httpError(404, "Categoría no encontrada.");

    const data: Prisma.CategoriaTareaUpdateInput = {};
    if (dto.nombre !== undefined) {
      const nombre = limpiarNombre(dto.nombre, "El nombre");
      if (nombre !== actual.nombre) await this.validarNombreCategoriaLibre(empresaId, nombre, id);
      data.nombre = nombre;
    }
    if (dto.colorHex !== undefined) data.colorHex = limpiarColor(dto.colorHex);
    if (dto.palabrasClave !== undefined) data.palabrasClave = limpiarPalabrasClave(dto.palabrasClave);
    if (dto.activa !== undefined) data.activa = dto.activa;
    return this.prisma.categoriaTarea.update({ where: { id }, data });
  }

  /** `ids` debe contener TODAS las categorías de la empresa; se reescribe 1..n en una transacción. */
  async reordenarCategorias(empresaId: string, ids: number[]) {
    const unicos = Array.from(new Set(ids));
    if (unicos.length !== ids.length) throw httpError(400, "El orden contiene categorías repetidas.");
    const existentes = await this.prisma.categoriaTarea.findMany({
      where: { empresaId },
      select: { id: true },
    });
    const setExistentes = new Set(existentes.map((c) => c.id));
    if (
      unicos.length !== setExistentes.size ||
      unicos.some((id) => !setExistentes.has(id))
    ) {
      throw httpError(400, "El orden debe incluir exactamente las categorías de la empresa.");
    }
    await this.prisma.$transaction(
      unicos.map((id, i) =>
        this.prisma.categoriaTarea.update({ where: { id }, data: { ordenProgramacion: i + 1 } }),
      ),
    );
    return this.listarCategorias(empresaId);
  }

  async eliminarCategoria(empresaId: string, id: number) {
    const actual = await this.prisma.categoriaTarea.findFirst({ where: { id, empresaId } });
    if (!actual) throw httpError(404, "Categoría no encontrada.");
    const enUso = await this.prisma.definicionTareaPreventiva.count({ where: { categoriaId: id } });
    if (enUso > 0) {
      throw httpError(
        409,
        `La categoría '${actual.nombre}' la usan ${enUso} preventiva(s). Desactívala o cámbiales la categoría antes de eliminarla.`,
      );
    }
    await this.prisma.categoriaTarea.delete({ where: { id } });
    return { ok: true };
  }

  private async validarNombreCategoriaLibre(empresaId: string, nombre: string, excluirId?: number) {
    const todas = await this.prisma.categoriaTarea.findMany({
      where: { empresaId },
      select: { id: true, nombre: true },
    });
    const clave = normalizarTexto(nombre);
    if (todas.some((c) => c.id !== excluirId && normalizarTexto(c.nombre) === clave)) {
      throw httpError(409, `Ya existe una categoría llamada '${nombre}'.`);
    }
  }

  /* ============================== PERFILES ============================== */

  async listarPerfiles(empresaId: string) {
    const perfiles = await this.prisma.perfilOperativo.findMany({
      where: { empresaId },
      orderBy: [{ nombre: "asc" }, { id: "asc" }],
      include: {
        categorias: { select: { categoriaId: true } },
        _count: { select: { plazas: true } },
      },
    });
    return perfiles.map(({ categorias, _count, ...p }) => ({
      ...p,
      categoriasIds: categorias.map((c) => c.categoriaId).sort((a, b) => a - b),
      plazas: _count.plazas,
    }));
  }

  async crearPerfil(
    empresaId: string,
    dto: {
      nombre: string;
      roles: TipoFuncion[];
      descripcion?: string | null;
      categoriasIds?: number[];
    },
  ) {
    const nombre = limpiarNombre(dto.nombre, "El nombre");
    const roles = rolesNormalizados(dto.roles);
    if (!roles.length) throw httpError(400, "El perfil debe tener al menos un rol.");
    await this.validarNombrePerfilLibre(empresaId, nombre);
    const categoriasIds = await this.validarCategoriasDeEmpresa(empresaId, dto.categoriasIds ?? []);

    const creado = await this.prisma.perfilOperativo.create({
      data: {
        empresaId,
        nombre,
        roles,
        descripcion: dto.descripcion?.trim() || null,
        categorias: { create: categoriasIds.map((categoriaId) => ({ categoriaId })) },
      },
    });
    return (await this.listarPerfiles(empresaId)).find((p) => p.id === creado.id)!;
  }

  async editarPerfil(
    empresaId: string,
    id: number,
    dto: {
      nombre?: string;
      roles?: TipoFuncion[];
      descripcion?: string | null;
      activo?: boolean;
      categoriasIds?: number[];
    },
  ) {
    const actual = await this.prisma.perfilOperativo.findFirst({
      where: { id, empresaId },
      include: {
        plazas: {
          select: { id: true, operarioId: true, etiqueta: true },
        },
      },
    });
    if (!actual) throw httpError(404, "Perfil no encontrado.");

    const data: Prisma.PerfilOperativoUpdateInput = {};
    if (dto.nombre !== undefined) {
      const nombre = limpiarNombre(dto.nombre, "El nombre");
      if (nombre !== actual.nombre) await this.validarNombrePerfilLibre(empresaId, nombre, id);
      data.nombre = nombre;
    }
    if (dto.descripcion !== undefined) data.descripcion = dto.descripcion?.trim() || null;
    if (dto.activo !== undefined) data.activo = dto.activo;

    let rolesNuevos: TipoFuncion[] | null = null;
    if (dto.roles !== undefined) {
      const roles = rolesNormalizados(dto.roles);
      if (!roles.length) throw httpError(400, "El perfil debe tener al menos un rol.");
      if (!mismosRoles(roles, actual.roles)) {
        // Cada ocupante actual debe seguir cumpliendo TODOS los roles nuevos.
        const ocupantesIds = actual.plazas
          .map((p) => p.operarioId)
          .filter((o): o is string => !!o);
        if (ocupantesIds.length) {
          const operarios = await this.prisma.operario.findMany({
            where: { id: { in: ocupantesIds } },
            select: { id: true, funciones: true, usuario: { select: { nombre: true } } },
          });
          const incompatibles = operarios.filter(
            (o) => !roles.every((r) => o.funciones.includes(r)),
          );
          if (incompatibles.length) {
            throw httpError(
              409,
              `No se pueden cambiar los roles: ${incompatibles
                .map((o) => o.usuario?.nombre ?? o.id)
                .join(", ")} ocupa(n) una plaza con este perfil y no tiene(n) todos los roles nuevos. Libera esas plazas primero.`,
            );
          }
        }
        rolesNuevos = roles;
        data.roles = roles;
      }
    }

    const categoriasIds =
      dto.categoriasIds !== undefined
        ? await this.validarCategoriasDeEmpresa(empresaId, dto.categoriasIds)
        : null;

    await this.prisma.$transaction(async (tx) => {
      await tx.perfilOperativo.update({ where: { id }, data });
      if (rolesNuevos) {
        // `roles` de la plaza se mantiene sincronizado con el perfil.
        await tx.conjuntoNecesidadOperario.updateMany({
          where: { perfilId: id },
          data: { roles: rolesNuevos },
        });
      }
      if (categoriasIds) {
        await tx.perfilOperativoCategoria.deleteMany({ where: { perfilId: id } });
        if (categoriasIds.length) {
          await tx.perfilOperativoCategoria.createMany({
            data: categoriasIds.map((categoriaId) => ({ perfilId: id, categoriaId })),
          });
        }
      }
    });
    return (await this.listarPerfiles(empresaId)).find((p) => p.id === id)!;
  }

  async eliminarPerfil(empresaId: string, id: number) {
    const actual = await this.prisma.perfilOperativo.findFirst({
      where: { id, empresaId },
      include: { _count: { select: { plazas: true } } },
    });
    if (!actual) throw httpError(404, "Perfil no encontrado.");
    if (actual._count.plazas > 0) {
      throw httpError(
        409,
        `El perfil '${actual.nombre}' lo usan ${actual._count.plazas} plaza(s). Desactívalo o cambia el perfil de esas plazas antes de eliminarlo.`,
      );
    }
    await this.prisma.perfilOperativo.delete({ where: { id } });
    return { ok: true };
  }

  /**
   * Busca el perfil de la empresa con exactamente esa combinación de roles o
   * lo crea (sin categorías). Garantiza que ninguna plaza quede aislada cuando
   * se crea por la vía antigua (solo `roles`).
   */
  async resolverPerfilParaRoles(
    empresaId: string,
    roles: readonly TipoFuncion[],
    client: Cliente = this.prisma,
  ) {
    const normalizados = rolesNormalizados(roles);
    if (!normalizados.length) throw httpError(400, "Se requiere al menos un rol.");
    const perfiles = await client.perfilOperativo.findMany({ where: { empresaId } });
    const existente =
      perfiles.find((p) => p.activo && mismosRoles(p.roles, normalizados)) ??
      perfiles.find((p) => mismosRoles(p.roles, normalizados));
    if (existente) return existente;

    const base = nombrePerfilDesdeRoles(normalizados);
    const nombres = new Set(perfiles.map((p) => normalizarTexto(p.nombre)));
    let nombre = base;
    for (let n = 2; nombres.has(normalizarTexto(nombre)); n++) nombre = `${base} (${n})`;
    return client.perfilOperativo.create({
      data: { empresaId, nombre, roles: normalizados },
    });
  }

  /** Perfil existente de la empresa (para plazas que traen `perfilId`). */
  async obtenerPerfilDeEmpresa(empresaId: string, perfilId: number, client: Cliente = this.prisma) {
    const perfil = await client.perfilOperativo.findFirst({ where: { id: perfilId, empresaId } });
    if (!perfil) throw httpError(404, "Perfil no encontrado.");
    if (!perfil.activo) throw httpError(409, `El perfil '${perfil.nombre}' está desactivado.`);
    return perfil;
  }

  private async validarNombrePerfilLibre(empresaId: string, nombre: string, excluirId?: number) {
    const todos = await this.prisma.perfilOperativo.findMany({
      where: { empresaId },
      select: { id: true, nombre: true },
    });
    const clave = normalizarTexto(nombre);
    if (todos.some((p) => p.id !== excluirId && normalizarTexto(p.nombre) === clave)) {
      throw httpError(409, `Ya existe un perfil llamado '${nombre}'.`);
    }
  }

  private async validarCategoriasDeEmpresa(empresaId: string, ids: number[]): Promise<number[]> {
    const unicos = Array.from(new Set(ids));
    if (!unicos.length) return [];
    const encontradas = await this.prisma.categoriaTarea.count({
      where: { id: { in: unicos }, empresaId },
    });
    if (encontradas !== unicos.length) {
      throw httpError(400, "Alguna de las categorías indicadas no existe en la empresa.");
    }
    return unicos;
  }

  /* ============ PREVENTIVAS: categoría, orden y sugerencias ============ */

  private async empresaDeConjunto(conjuntoId: string, client: Cliente = this.prisma): Promise<string> {
    const conjunto = await client.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { empresaId: true },
    });
    if (!conjunto) throw httpError(404, "Conjunto no encontrado.");
    if (!conjunto.empresaId) throw httpError(409, "El conjunto no pertenece a una empresa.");
    return conjunto.empresaId;
  }

  /**
   * Plazas (con las categorías de su perfil) que ejecutarían una definición:
   * las vinculadas por `necesidadesIds` o, si no hay, las que ocupan los
   * operarios directos en este conjunto. Un operario sin plaza no aporta
   * capacidades conocidas.
   */
  private async plazasDeResponsables(params: {
    conjuntoId: string;
    necesidadesIds: number[];
    operariosIds: string[];
  }) {
    const include = {
      perfil: { select: { nombre: true, categorias: { select: { categoriaId: true } } } },
    } as const;
    if (params.necesidadesIds.length) {
      return this.prisma.conjuntoNecesidadOperario.findMany({
        where: { id: { in: params.necesidadesIds }, conjuntoId: params.conjuntoId },
        include,
      });
    }
    if (params.operariosIds.length) {
      return this.prisma.conjuntoNecesidadOperario.findMany({
        where: {
          conjuntoId: params.conjuntoId,
          activo: true,
          operarioId: { in: params.operariosIds },
        },
        include,
      });
    }
    return [];
  }

  /**
   * Mensajes de incompatibilidad entre una categoría y los responsables: solo
   * aplica a perfiles con capacidades CONFIGURADAS; uno sin configurar no
   * bloquea (se configura después en el catálogo).
   */
  async incompatibilidadesCategoria(params: {
    conjuntoId: string;
    categoriaId: number;
    categoriaNombre: string;
    necesidadesIds: number[];
    operariosIds: string[];
  }): Promise<string[]> {
    const plazas = await this.plazasDeResponsables(params);
    const out: string[] = [];
    for (const plaza of plazas) {
      const permitidas = plaza.perfil?.categorias.map((c) => c.categoriaId) ?? [];
      if (permitidas.length && !permitidas.includes(params.categoriaId)) {
        out.push(
          `La plaza '${plaza.etiqueta}' (perfil '${plaza.perfil?.nombre}') no está habilitada para la categoría '${params.categoriaNombre}'.`,
        );
      }
    }
    return out;
  }

  /** Valida la categoría de una preventiva (existe en la empresa, activa) y su compatibilidad con los responsables. */
  async validarCategoriaDeDefinicion(params: {
    conjuntoId: string;
    categoriaId: number;
    necesidadesIds: number[];
    operariosIds: string[];
    /** false al conservar una categoría ya asignada que luego se desactivó. */
    exigirActiva?: boolean;
  }) {
    const empresaId = await this.empresaDeConjunto(params.conjuntoId);
    const categoria = await this.prisma.categoriaTarea.findFirst({
      where: { id: params.categoriaId, empresaId },
    });
    if (!categoria) throw httpError(400, "La categoría indicada no existe en la empresa.");
    if ((params.exigirActiva ?? true) && !categoria.activa) {
      throw httpError(400, `La categoría '${categoria.nombre}' está desactivada.`);
    }
    const incompatibles = await this.incompatibilidadesCategoria({
      ...params,
      categoriaNombre: categoria.nombre,
    });
    if (incompatibles.length) throw httpError(400, incompatibles.join(" "));
    return categoria;
  }

  /**
   * Asigna (o quita, con null) la categoría a varias preventivas del conjunto.
   * Las que tengan una plaza no habilitada para la categoría se omiten y se
   * reportan; el resto se guarda en una sola transacción.
   */
  async asignarCategoriaLote(conjuntoId: string, dto: { ids: number[]; categoriaId: number | null }) {
    const empresaId = await this.empresaDeConjunto(conjuntoId);
    const ids = Array.from(new Set(dto.ids));
    const defs = await this.prisma.definicionTareaPreventiva.findMany({
      where: { id: { in: ids }, conjuntoId },
      select: {
        id: true,
        descripcion: true,
        necesidades: { select: { id: true } },
        operarios: { select: { id: true } },
      },
    });
    if (defs.length !== ids.length) {
      throw httpError(404, "Alguna de las preventivas no pertenece a este conjunto.");
    }

    if (dto.categoriaId == null) {
      const r = await this.prisma.definicionTareaPreventiva.updateMany({
        where: { id: { in: ids }, conjuntoId },
        data: { categoriaId: null, ordenEnCategoria: null },
      });
      return { actualizadas: r.count, omitidas: [] as Array<{ id: number; descripcion: string; motivo: string }> };
    }

    const categoria = await this.prisma.categoriaTarea.findFirst({
      where: { id: dto.categoriaId, empresaId },
    });
    if (!categoria) throw httpError(400, "La categoría indicada no existe en la empresa.");
    if (!categoria.activa) throw httpError(400, `La categoría '${categoria.nombre}' está desactivada.`);

    const aplicables: number[] = [];
    const omitidas: Array<{ id: number; descripcion: string; motivo: string }> = [];
    for (const def of defs) {
      const incompatibles = await this.incompatibilidadesCategoria({
        conjuntoId,
        categoriaId: categoria.id,
        categoriaNombre: categoria.nombre,
        necesidadesIds: def.necesidades.map((n) => n.id),
        operariosIds: def.operarios.map((o) => o.id),
      });
      if (incompatibles.length) {
        omitidas.push({ id: def.id, descripcion: def.descripcion, motivo: incompatibles.join(" ") });
      } else {
        aplicables.push(def.id);
      }
    }
    if (aplicables.length) {
      // Cambiar de categoría invalida el orden interno anterior (era de otra categoría).
      await this.prisma.$transaction([
        this.prisma.definicionTareaPreventiva.updateMany({
          where: { id: { in: aplicables }, conjuntoId, NOT: { categoriaId: categoria.id } },
          data: { ordenEnCategoria: null },
        }),
        this.prisma.definicionTareaPreventiva.updateMany({
          where: { id: { in: aplicables }, conjuntoId },
          data: { categoriaId: categoria.id },
        }),
      ]);
    }
    return { actualizadas: aplicables.length, omitidas };
  }

  /**
   * Fija el orden interno (1..n) de las preventivas de una categoría en este
   * conjunto. `ids` debe ser exactamente el conjunto de preventivas de esa
   * categoría en el conjunto, para no dejar numeraciones mezcladas.
   */
  async ordenarEnCategoria(conjuntoId: string, dto: { categoriaId: number; ids: number[] }) {
    const empresaId = await this.empresaDeConjunto(conjuntoId);
    const categoria = await this.prisma.categoriaTarea.findFirst({
      where: { id: dto.categoriaId, empresaId },
    });
    if (!categoria) throw httpError(400, "La categoría indicada no existe en la empresa.");
    const ids = Array.from(new Set(dto.ids));
    if (ids.length !== dto.ids.length) throw httpError(400, "El orden contiene preventivas repetidas.");
    const existentes = await this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId, categoriaId: categoria.id },
      select: { id: true },
    });
    const set = new Set(existentes.map((d) => d.id));
    if (ids.length !== set.size || ids.some((id) => !set.has(id))) {
      throw httpError(
        400,
        "El orden debe incluir exactamente las preventivas de esa categoría en este conjunto.",
      );
    }
    await this.prisma.$transaction(
      ids.map((id, i) =>
        this.prisma.definicionTareaPreventiva.update({
          where: { id },
          data: { ordenEnCategoria: i + 1 },
        }),
      ),
    );
    return { ok: true, total: ids.length };
  }

  /** Propone categorías para las preventivas activas sin categoría. No guarda nada. */
  async sugerirCategorias(conjuntoId: string) {
    const empresaId = await this.empresaDeConjunto(conjuntoId);
    await this.asegurarCategoriasPorDefecto(empresaId);
    const [categorias, defs] = await Promise.all([
      this.prisma.categoriaTarea.findMany({
        where: { empresaId, activa: true },
        orderBy: [{ ordenProgramacion: "asc" }, { id: "asc" }],
      }),
      this.prisma.definicionTareaPreventiva.findMany({
        where: { conjuntoId, activo: true, categoriaId: null },
        select: {
          id: true,
          descripcion: true,
          elemento: { select: { nombre: true } },
          ubicacion: { select: { nombre: true } },
        },
        orderBy: { id: "asc" },
      }),
    ]);
    const sugerencias: Array<{
      defId: number;
      descripcion: string;
      categoriaId: number;
      categoriaNombre: string;
      coincidencias: string[];
    }> = [];
    const sinSugerencia: Array<{ defId: number; descripcion: string }> = [];
    for (const def of defs) {
      const r = sugerirCategoriaPorTexto(
        def.descripcion,
        categorias,
        `${def.elemento?.nombre ?? ""} ${def.ubicacion?.nombre ?? ""}`,
      );
      if (r) sugerencias.push({ defId: def.id, descripcion: def.descripcion, ...r });
      else sinSugerencia.push({ defId: def.id, descripcion: def.descripcion });
    }
    return { sugerencias, sinSugerencia };
  }
}
