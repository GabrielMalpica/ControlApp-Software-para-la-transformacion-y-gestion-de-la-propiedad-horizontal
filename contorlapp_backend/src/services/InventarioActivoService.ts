import crypto from "crypto";
import fs from "fs";
import {
  EstadoAprobacionActivo,
  EstadoHerramienta,
  EstadoMaquinaria,
  Prisma,
  PrismaClient,
  PropietarioMaquinaria,
  TipoMaquinaria,
} from "@prisma/client";

import type { ActorAuditoria } from "../model/Auditoria";
import { AuditoriaService } from "./AuditoriaService";
import {
  eliminarFotoInventario,
  obtenerFotoInventario,
  subirFotoInventario,
} from "../utils/drive_inventario";
import { normalizarNombreCatalogo } from "../utils/catalogoInventario";

export { normalizarNombreCatalogo } from "../utils/catalogoInventario";

type DbClient = PrismaClient | Prisma.TransactionClient;
type ClaseActivo = "maquinaria" | "herramienta";
type Scope = { propietarioTipo: PropietarioMaquinaria; conjuntoId: string | null };

type FotoInput = {
  path: string;
  originalname: string;
  mimetype: string;
  size: number;
};

function httpError(status: number, message: string) {
  return Object.assign(new Error(message), { status });
}

function texto(value: string | null | undefined) {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}

function esAprobador(actor: ActorAuditoria) {
  return actor.rol === "gerente" || actor.rol === "jefe_operaciones";
}

function serializarMaquinaria(item: any) {
  const asignacion = item.asignaciones?.[0] ?? null;
  return {
    ...item,
    fotoUrl: item.fotoDriveId ? `/inventario/maquinaria/${item.id}/foto` : null,
    ubicacionActual: item.propietarioTipo === "CONJUNTO"
      ? item.conjuntoPropietario
      : asignacion?.conjunto ?? null,
    prestada: Boolean(asignacion),
    disponible:
      item.estadoAprobacion === "APROBADA" &&
      item.estado === "OPERATIVA" &&
      !asignacion,
  };
}

function serializarHerramienta(item: any) {
  const asignacion = item.asignaciones?.[0] ?? null;
  return {
    ...item,
    fotoUrl: item.fotoDriveId ? `/inventario/herramientas/${item.id}/foto` : null,
    ubicacionActual: item.propietarioTipo === "CONJUNTO"
      ? item.conjuntoPropietario
      : asignacion?.conjunto ?? null,
    prestada: Boolean(asignacion),
    disponible:
      item.estadoAprobacion === "APROBADA" &&
      item.estado === "OPERATIVA" &&
      !asignacion,
  };
}

export class InventarioActivoService {
  constructor(
    private prisma: PrismaClient,
    private empresaId: string,
    private actor: ActorAuditoria,
  ) {}

  private async asegurarConjunto(conjuntoId: string, client: DbClient = this.prisma) {
    const conjunto = await client.conjunto.findFirst({
      where: {
        nit: conjuntoId,
        empresaId: this.empresaId,
        ...(this.actor.rol === "administrador" ? { administradorId: this.actor.id } : {}),
      },
      select: { nit: true, nombre: true },
    });
    if (!conjunto) throw httpError(404, "Conjunto no encontrado.");
    return conjunto;
  }

  private async asegurarAprobador() {
    if (!esAprobador(this.actor)) {
      throw httpError(403, "Solo gerente o jefe de operaciones puede aprobar o rechazar registros.");
    }
  }

  private async nombresUsuarios(items: any[]) {
    const ids = Array.from(new Set(
      items.flatMap((item) => [
        item.creadoPorId,
        item.aprobadoPorId,
        item.rechazadoPorId,
        item.actualizadoPorId,
      ]).filter((id): id is string => typeof id === "string" && id.length > 0),
    ));
    if (!ids.length) return new Map<string, string>();
    const users = await this.prisma.usuario.findMany({
      where: { id: { in: ids } },
      select: { id: true, nombre: true },
    });
    return new Map(users.map((user) => [user.id, user.nombre]));
  }

  private conResponsables(item: any, nombres: Map<string, string>) {
    return {
      ...item,
      creadoPorNombre: item.creadoPorId ? nombres.get(item.creadoPorId) ?? null : null,
      aprobadoPorNombre: item.aprobadoPorId ? nombres.get(item.aprobadoPorId) ?? null : null,
      rechazadoPorNombre: item.rechazadoPorId ? nombres.get(item.rechazadoPorId) ?? null : null,
      actualizadoPorNombre: item.actualizadoPorId ? nombres.get(item.actualizadoPorId) ?? null : null,
    };
  }

  async listarCatalogoMaquinaria(q?: string) {
    return this.prisma.tipoMaquinariaCatalogo.findMany({
      where: {
        empresaId: this.empresaId,
        activo: true,
        estadoAprobacion: EstadoAprobacionActivo.APROBADA,
        ...(q?.trim() ? { nombre: { contains: q.trim(), mode: "insensitive" } } : {}),
      },
      select: { id: true, nombre: true, tipoLegacy: true },
      orderBy: { nombre: "asc" },
      take: 500,
    });
  }

  async listarCatalogoHerramientas(q?: string) {
    return this.prisma.herramienta.findMany({
      where: {
        empresaId: this.empresaId,
        activo: true,
        canonicaId: null,
        estadoAprobacion: EstadoAprobacionActivo.APROBADA,
        ...(q?.trim() ? { nombre: { contains: q.trim(), mode: "insensitive" } } : {}),
      },
      select: {
        id: true,
        nombre: true,
        unidad: true,
        categoria: true,
        modoControl: true,
        vidaUtilDias: true,
      },
      orderBy: { nombre: "asc" },
      take: 500,
    });
  }

  private visibilityWhere(aprobacion?: string) {
    if (esAprobador(this.actor)) {
      return aprobacion ? { estadoAprobacion: aprobacion as EstadoAprobacionActivo } : {};
    }
    if (aprobacion === "PENDIENTE") {
      return { estadoAprobacion: EstadoAprobacionActivo.PENDIENTE, creadoPorId: this.actor.id };
    }
    if (aprobacion === "RECHAZADA") {
      return { estadoAprobacion: EstadoAprobacionActivo.RECHAZADA, creadoPorId: this.actor.id };
    }
    if (aprobacion === "APROBADA") {
      return { estadoAprobacion: EstadoAprobacionActivo.APROBADA };
    }
    return {
      OR: [
        { estadoAprobacion: EstadoAprobacionActivo.APROBADA },
        { estadoAprobacion: EstadoAprobacionActivo.PENDIENTE, creadoPorId: this.actor.id },
        { estadoAprobacion: EstadoAprobacionActivo.RECHAZADA, creadoPorId: this.actor.id },
      ],
    };
  }

  async listarMaquinaria(params: any, conjuntoId?: string) {
    if (conjuntoId) await this.asegurarConjunto(conjuntoId);
    const page = Number(params.page ?? 1);
    const pageSize = Number(params.pageSize ?? 25);
    const where: Prisma.MaquinariaWhereInput = {
      empresaId: this.empresaId,
      ...(params.estado ? { estado: params.estado as EstadoMaquinaria } : {}),
      ...(params.propietario ? { propietarioTipo: params.propietario } : {}),
      ...(params.catalogoId ? { tipoCatalogoId: Number(params.catalogoId) } : {}),
      AND: [
        this.visibilityWhere(params.aprobacion),
        ...(params.q
          ? [{
              OR: [
              { codigoInterno: { contains: params.q, mode: "insensitive" } },
              { nombre: { contains: params.q, mode: "insensitive" } },
              { marca: { contains: params.q, mode: "insensitive" } },
              { serial: { contains: params.q, mode: "insensitive" } },
              ],
            } satisfies Prisma.MaquinariaWhereInput]
          : []),
        ...(conjuntoId
          ? [{
            OR: [
              { propietarioTipo: PropietarioMaquinaria.CONJUNTO, conjuntoPropietarioId: conjuntoId },
              { asignaciones: { some: { conjuntoId, estado: { in: ["RESERVADA", "ACTIVA"] } } } },
            ],
          } satisfies Prisma.MaquinariaWhereInput]
          : []),
      ],
    };

    const [total, data] = await Promise.all([
      this.prisma.maquinaria.count({ where }),
      this.prisma.maquinaria.findMany({
        where,
        include: {
          tipoCatalogo: { select: { id: true, nombre: true, tipoLegacy: true } },
          conjuntoPropietario: { select: { nit: true, nombre: true } },
          asignaciones: {
            where: { estado: { in: ["RESERVADA", "ACTIVA"] } },
            include: { conjunto: { select: { nit: true, nombre: true } } },
            take: 1,
          },
        },
        orderBy: [{ creadoEn: "desc" }, { id: "desc" }],
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
    ]);
    const nombres = await this.nombresUsuarios(data);
    return {
      data: data.map((item) => serializarMaquinaria(this.conResponsables(item, nombres))),
      total,
      page,
      pageSize,
    };
  }

  async listarHerramientas(params: any, conjuntoId?: string) {
    if (conjuntoId) await this.asegurarConjunto(conjuntoId);
    const page = Number(params.page ?? 1);
    const pageSize = Number(params.pageSize ?? 25);
    const where: Prisma.HerramientaItemWhereInput = {
      empresaId: this.empresaId,
      ...(params.estado ? { estado: params.estado as EstadoHerramienta } : {}),
      ...(params.propietario ? { propietarioTipo: params.propietario } : {}),
      ...(params.catalogoId ? { herramientaId: Number(params.catalogoId) } : {}),
      AND: [
        this.visibilityWhere(params.aprobacion),
        ...(params.q
          ? [{
            OR: [
              { codigoInterno: { contains: params.q, mode: "insensitive" } },
              { alias: { contains: params.q, mode: "insensitive" } },
              { marca: { contains: params.q, mode: "insensitive" } },
              { serial: { contains: params.q, mode: "insensitive" } },
              { herramienta: { nombre: { contains: params.q, mode: "insensitive" } } },
            ],
          } satisfies Prisma.HerramientaItemWhereInput]
          : []),
        ...(conjuntoId
          ? [{
            OR: [
              { propietarioTipo: PropietarioMaquinaria.CONJUNTO, conjuntoPropietarioId: conjuntoId },
              { asignaciones: { some: { conjuntoId, estado: { in: ["RESERVADA", "ACTIVA"] } } } },
            ],
          } satisfies Prisma.HerramientaItemWhereInput]
          : []),
      ],
    };
    const [total, data] = await Promise.all([
      this.prisma.herramientaItem.count({ where }),
      this.prisma.herramientaItem.findMany({
        where,
        include: {
          herramienta: { select: { id: true, nombre: true, unidad: true, categoria: true, modoControl: true } },
          conjuntoPropietario: { select: { nit: true, nombre: true } },
          asignaciones: {
            where: { estado: { in: ["RESERVADA", "ACTIVA"] } },
            include: { conjunto: { select: { nit: true, nombre: true } } },
            take: 1,
          },
        },
        orderBy: [{ creadoEn: "desc" }, { id: "desc" }],
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
    ]);
    const nombres = await this.nombresUsuarios(data);
    return {
      data: data.map((item) => serializarHerramienta(this.conResponsables(item, nombres))),
      total,
      page,
      pageSize,
    };
  }

  async resumen(conjuntoId?: string) {
    if (conjuntoId) await this.asegurarConjunto(conjuntoId);
    const maquinariaWhere: Prisma.MaquinariaWhereInput = {
      empresaId: this.empresaId,
      estadoAprobacion: EstadoAprobacionActivo.APROBADA,
      ...(conjuntoId
        ? { OR: [
            { propietarioTipo: "CONJUNTO", conjuntoPropietarioId: conjuntoId },
            { asignaciones: { some: { conjuntoId, estado: { in: ["RESERVADA", "ACTIVA"] } } } },
          ] }
        : { propietarioTipo: "EMPRESA" }),
    };
    const herramientasWhere: Prisma.HerramientaItemWhereInput = {
      empresaId: this.empresaId,
      estadoAprobacion: EstadoAprobacionActivo.APROBADA,
      ...(conjuntoId
        ? { OR: [
            { propietarioTipo: "CONJUNTO", conjuntoPropietarioId: conjuntoId },
            { asignaciones: { some: { conjuntoId, estado: { in: ["RESERVADA", "ACTIVA"] } } } },
          ] }
        : { propietarioTipo: "EMPRESA" }),
    };
    const [maquinaria, herramientas, maquinariaPendiente, herramientasPendientes] = await Promise.all([
      this.prisma.maquinaria.count({ where: maquinariaWhere }),
      this.prisma.herramientaItem.count({ where: herramientasWhere }),
      this.prisma.maquinaria.count({ where: { empresaId: this.empresaId, estadoAprobacion: "PENDIENTE", ...(conjuntoId ? { conjuntoPropietarioId: conjuntoId } : {}), ...(this.actor.rol === "administrador" ? { creadoPorId: this.actor.id } : {}) } }),
      this.prisma.herramientaItem.count({ where: { empresaId: this.empresaId, estadoAprobacion: "PENDIENTE", ...(conjuntoId ? { conjuntoPropietarioId: conjuntoId } : {}), ...(this.actor.rol === "administrador" ? { creadoPorId: this.actor.id } : {}) } }),
    ]);
    return { maquinaria, herramientas, pendientes: maquinariaPendiente + herramientasPendientes };
  }

  private async resolverTipoMaquinaria(tx: Prisma.TransactionClient, dto: any, aprobada: boolean) {
    if (dto.tipoCatalogoId) {
      const type = await tx.tipoMaquinariaCatalogo.findFirst({
        where: { id: dto.tipoCatalogoId, empresaId: this.empresaId, activo: true, estadoAprobacion: "APROBADA" },
      });
      if (!type) throw httpError(404, "Tipo de maquinaria no encontrado.");
      return type;
    }
    const normalized = normalizarNombreCatalogo(dto.tipoPropuesto.nombre);
    const existing = await tx.tipoMaquinariaCatalogo.findUnique({
      where: { empresaId_nombreNormalizado: { empresaId: this.empresaId, nombreNormalizado: normalized } },
    });
    if (existing) {
      if (!existing.activo || (existing.estadoAprobacion !== "APROBADA" && !aprobada)) {
        throw httpError(409, "Ese tipo ya tiene una propuesta pendiente o inactiva.");
      }
      if (aprobada && existing.estadoAprobacion === "PENDIENTE") {
        return tx.tipoMaquinariaCatalogo.update({
          where: { id: existing.id },
          data: { estadoAprobacion: "APROBADA", aprobadoPorId: this.actor.id, aprobadoEn: new Date() },
        });
      }
      return existing;
    }
    return tx.tipoMaquinariaCatalogo.create({
      data: {
        empresaId: this.empresaId,
        nombre: dto.tipoPropuesto.nombre.trim(),
        nombreNormalizado: normalized,
        tipoLegacy: dto.tipoPropuesto.tipoLegacy ?? TipoMaquinaria.OTRO,
        estadoAprobacion: aprobada ? "APROBADA" : "PENDIENTE",
        creadoPorId: this.actor.id,
        ...(aprobada ? { aprobadoPorId: this.actor.id, aprobadoEn: new Date() } : {}),
      },
    });
  }

  async crearMaquinaria(dto: any, scope: Scope) {
    if (scope.conjuntoId) await this.asegurarConjunto(scope.conjuntoId);
    if (this.actor.rol === "administrador" && scope.propietarioTipo !== "CONJUNTO") {
      throw httpError(403, "El administrador solo puede registrar inventario de sus conjuntos.");
    }
    const approved = esAprobador(this.actor);
    return this.prisma.$transaction(async (tx) => {
      const type = await this.resolverTipoMaquinaria(tx, dto, approved);
      const created = await tx.maquinaria.create({
        data: {
          nombre: type.nombre,
          marca: dto.marca,
          tipo: type.tipoLegacy ?? TipoMaquinaria.OTRO,
          tipoCatalogoId: type.id,
          estado: dto.estado,
          propietarioTipo: scope.propietarioTipo,
          empresaId: this.empresaId,
          conjuntoPropietarioId: scope.conjuntoId,
          alias: texto(dto.alias),
          modelo: texto(dto.modelo),
          serial: texto(dto.serial),
          estadoAprobacion: approved ? "APROBADA" : "PENDIENTE",
          creadoPorId: this.actor.id,
          ...(approved ? { aprobadoPorId: this.actor.id, aprobadoEn: new Date() } : {}),
        },
      });
      const item = await tx.maquinaria.update({
        where: { id: created.id },
        data: { codigoInterno: `MAQ-${String(created.id).padStart(6, "0")}` },
        include: { tipoCatalogo: true, conjuntoPropietario: { select: { nit: true, nombre: true } } },
      });
      await new AuditoriaService(tx).registrarEstricto({
        modulo: "INVENTARIO_MAQUINARIA",
        entidad: "Maquinaria",
        entidadId: item.id,
        accion: "CREAR",
        empresaId: this.empresaId,
        conjuntoId: scope.conjuntoId,
        actor: this.actor,
        datosDespues: item,
        metadataJson: { aprobacionAutomatica: approved },
      });
      return serializarMaquinaria(item);
    });
  }

  private async resolverCatalogoHerramienta(tx: Prisma.TransactionClient, dto: any, approved: boolean) {
    if (dto.herramientaId) {
      const selected = await tx.herramienta.findFirst({
        where: { id: dto.herramientaId, empresaId: this.empresaId, activo: true, estadoAprobacion: "APROBADA" },
      });
      if (!selected) throw httpError(404, "Tipo de herramienta no encontrado.");
      return selected.canonicaId
        ? tx.herramienta.findFirstOrThrow({ where: { id: selected.canonicaId, empresaId: this.empresaId, activo: true } })
        : selected;
    }
    const proposal = dto.tipoPropuesto;
    const normalized = normalizarNombreCatalogo(proposal.nombre);
    const existing = await tx.herramienta.findFirst({
      where: { empresaId: this.empresaId, nombreNormalizado: normalized, canonicaId: null },
    });
    if (existing) {
      if (!existing.activo || (existing.estadoAprobacion !== "APROBADA" && !approved)) {
        throw httpError(409, "Ese tipo ya tiene una propuesta pendiente o inactiva.");
      }
      if (approved && existing.estadoAprobacion === "PENDIENTE") {
        return tx.herramienta.update({
          where: { id: existing.id },
          data: { estadoAprobacion: "APROBADA", aprobadoPorId: this.actor.id, aprobadoEn: new Date() },
        });
      }
      return existing;
    }
    return tx.herramienta.create({
      data: {
        empresaId: this.empresaId,
        nombre: proposal.nombre.trim(),
        nombreNormalizado: normalized,
        unidad: proposal.unidad,
        categoria: proposal.categoria,
        modoControl: proposal.modoControl,
        vidaUtilDias: proposal.vidaUtilDias ?? null,
        umbralBajo: proposal.umbralBajo ?? null,
        estadoAprobacion: approved ? "APROBADA" : "PENDIENTE",
        creadoPorId: this.actor.id,
        ...(approved ? { aprobadoPorId: this.actor.id, aprobadoEn: new Date() } : {}),
      },
    });
  }

  async crearHerramientas(dto: any, scope: Scope) {
    if (scope.conjuntoId) await this.asegurarConjunto(scope.conjuntoId);
    if (this.actor.rol === "administrador" && scope.propietarioTipo !== "CONJUNTO") {
      throw httpError(403, "El administrador solo puede registrar inventario de sus conjuntos.");
    }
    const approved = esAprobador(this.actor);
    const lote = crypto.randomUUID();
    return this.prisma.$transaction(async (tx) => {
      const catalog = await this.resolverCatalogoHerramienta(tx, dto, approved);
      const rows = Array.from({ length: dto.cantidad }, (_, index) => ({
        codigoInterno: `HER-${lote.slice(0, 8).toUpperCase()}-${String(index + 1).padStart(3, "0")}`,
        empresaId: this.empresaId,
        herramientaId: catalog.id,
        propietarioTipo: scope.propietarioTipo,
        conjuntoPropietarioId: scope.conjuntoId,
        estado: dto.estado,
        estadoAprobacion: approved ? EstadoAprobacionActivo.APROBADA : EstadoAprobacionActivo.PENDIENTE,
        registroLoteId: lote,
        creadoPorId: this.actor.id ?? null,
        aprobadoPorId: approved ? this.actor.id ?? null : null,
        aprobadoEn: approved ? new Date() : null,
        alias: texto(dto.alias),
        marca: texto(dto.marca),
        modelo: texto(dto.modelo),
        serial: texto(dto.serial),
      }));
      await tx.herramientaItem.createMany({ data: rows });
      const items = await tx.herramientaItem.findMany({
        where: { registroLoteId: lote },
        include: { herramienta: true, conjuntoPropietario: { select: { nit: true, nombre: true } } },
        orderBy: { id: "asc" },
      });
      await new AuditoriaService(tx).registrarEstricto({
        modulo: "INVENTARIO_HERRAMIENTAS",
        entidad: "HerramientaLote",
        entidadId: lote,
        accion: "CREAR",
        empresaId: this.empresaId,
        conjuntoId: scope.conjuntoId,
        actor: this.actor,
        metadataJson: { cantidad: items.length, catalogoId: catalog.id, aprobacionAutomatica: approved },
      });
      return { loteId: lote, data: items.map(serializarHerramienta) };
    });
  }

  private async editable(kind: ClaseActivo, id: number) {
    const item = kind === "maquinaria"
      ? await this.prisma.maquinaria.findFirst({ where: { id, empresaId: this.empresaId } })
      : await this.prisma.herramientaItem.findFirst({ where: { id, empresaId: this.empresaId } });
    if (!item) throw httpError(404, "Activo no encontrado.");
    if (!esAprobador(this.actor)) {
      if (
        item.estadoAprobacion !== "PENDIENTE" ||
        item.creadoPorId !== this.actor.id
      ) {
        throw httpError(403, "Solo puedes editar registros pendientes creados por ti.");
      }
      if (this.actor.rol === "administrador") {
        if (!item.conjuntoPropietarioId) {
          throw httpError(403, "Solo puedes editar registros pendientes creados por ti.");
        }
        await this.asegurarConjunto(item.conjuntoPropietarioId);
      }
    }
    return item as any;
  }

  async editar(kind: ClaseActivo, id: number, dto: any) {
    const before = await this.editable(kind, id);
    const data = {
      alias: dto.alias === undefined ? undefined : texto(dto.alias),
      marca: dto.marca === undefined ? undefined : texto(dto.marca),
      modelo: dto.modelo === undefined ? undefined : texto(dto.modelo),
      serial: dto.serial === undefined ? undefined : texto(dto.serial),
      actualizadoPorId: this.actor.id,
    };
    return this.prisma.$transaction(async (tx) => {
      const after = kind === "maquinaria"
        ? await tx.maquinaria.update({ where: { id }, data: { ...data, marca: data.marca ?? undefined } })
        : await tx.herramientaItem.update({ where: { id }, data });
      await new AuditoriaService(tx).registrarEstricto({
        modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS",
        entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem",
        entidadId: id,
        accion: "EDITAR",
        empresaId: this.empresaId,
        conjuntoId: before.conjuntoPropietarioId,
        actor: this.actor,
        datosAntes: before,
        datosDespues: after,
      });
      return after;
    });
  }

  async aprobar(kind: ClaseActivo, id: number, catalogoDestinoId?: number) {
    await this.asegurarAprobador();
    return this.prisma.$transaction(async (tx) => {
      const before: any = kind === "maquinaria"
        ? await tx.maquinaria.findFirst({ where: { id, empresaId: this.empresaId }, include: { tipoCatalogo: true } })
        : await tx.herramientaItem.findFirst({ where: { id, empresaId: this.empresaId }, include: { herramienta: true } });
      if (!before) throw httpError(404, "Activo no encontrado.");
      if (before.estadoAprobacion !== "PENDIENTE") throw httpError(409, "El activo ya fue resuelto.");

      let catalogId = kind === "maquinaria" ? before.tipoCatalogoId : before.herramientaId;
      const proposedCatalog: any = kind === "maquinaria" ? before.tipoCatalogo : before.herramienta;
      let catalogName = proposedCatalog?.nombre ?? before.nombre;
      // Sigue el tipo fijo (TipoMaquinaria) del catálogo elegido: si se fusiona con
      // otro catálogo hay que arrastrar su tipoLegacy, si no la máquina queda con el
      // tipo del catálogo viejo y desaparece de las necesidades de ese tipo real.
      let catalogTipoLegacy: TipoMaquinaria | null | undefined =
        kind === "maquinaria" ? proposedCatalog?.tipoLegacy : undefined;
      if (catalogoDestinoId) {
        const destination = kind === "maquinaria"
          ? await tx.tipoMaquinariaCatalogo.findFirst({ where: { id: catalogoDestinoId, empresaId: this.empresaId, activo: true, estadoAprobacion: "APROBADA" } })
          : await tx.herramienta.findFirst({ where: { id: catalogoDestinoId, empresaId: this.empresaId, activo: true, estadoAprobacion: "APROBADA" } });
        if (!destination) throw httpError(404, "Catálogo de destino no encontrado.");
        catalogId = destination.id;
        catalogName = destination.nombre;
        if (kind === "maquinaria") catalogTipoLegacy = (destination as any).tipoLegacy;
        if (proposedCatalog?.estadoAprobacion === "PENDIENTE") {
          if (kind === "maquinaria") {
            await tx.tipoMaquinariaCatalogo.update({ where: { id: proposedCatalog.id }, data: { activo: false, estadoAprobacion: "RECHAZADA", rechazadoPorId: this.actor.id, rechazadoEn: new Date(), motivoRechazo: `Fusionado con catálogo ${destination.id}`, fusionadoEnId: destination.id } });
          } else {
            await tx.herramienta.update({ where: { id: proposedCatalog.id }, data: { activo: false, estadoAprobacion: "RECHAZADA", rechazadoPorId: this.actor.id, rechazadoEn: new Date(), motivoRechazo: `Fusionado con catálogo ${destination.id}`, canonicaId: destination.id } });
          }
        }
      } else if (proposedCatalog?.estadoAprobacion === "PENDIENTE") {
        if (kind === "maquinaria") {
          await tx.tipoMaquinariaCatalogo.update({ where: { id: proposedCatalog.id }, data: { estadoAprobacion: "APROBADA", aprobadoPorId: this.actor.id, aprobadoEn: new Date() } });
        } else {
          await tx.herramienta.update({ where: { id: proposedCatalog.id }, data: { estadoAprobacion: "APROBADA", aprobadoPorId: this.actor.id, aprobadoEn: new Date() } });
        }
      } else if (proposedCatalog?.estadoAprobacion === "RECHAZADA") {
        const mergedId = kind === "maquinaria"
          ? proposedCatalog.fusionadoEnId
          : proposedCatalog.canonicaId;
        if (!mergedId) {
          throw httpError(409, "El tipo propuesto fue rechazado; selecciona un catálogo de destino.");
        }
        const merged: any = kind === "maquinaria"
          ? await tx.tipoMaquinariaCatalogo.findFirst({
              where: { id: mergedId, empresaId: this.empresaId, activo: true, estadoAprobacion: "APROBADA" },
            })
          : await tx.herramienta.findFirst({
              where: { id: mergedId, empresaId: this.empresaId, activo: true, estadoAprobacion: "APROBADA" },
            });
        if (!merged) throw httpError(409, "El catálogo fusionado ya no está disponible.");
        catalogId = merged.id;
        catalogName = merged.nombre;
        if (kind === "maquinaria") catalogTipoLegacy = (merged as any).tipoLegacy;
      }

      const data = {
        estadoAprobacion: EstadoAprobacionActivo.APROBADA,
        aprobadoPorId: this.actor.id,
        aprobadoEn: new Date(),
        actualizadoPorId: this.actor.id,
      };
      const after = kind === "maquinaria"
        ? await tx.maquinaria.update({
            where: { id },
            data: {
              ...data,
              tipoCatalogoId: catalogId,
              nombre: catalogName,
              tipo: catalogTipoLegacy ?? TipoMaquinaria.OTRO,
            },
          })
        : await tx.herramientaItem.update({ where: { id }, data: { ...data, herramientaId: catalogId } });
      await new AuditoriaService(tx).registrarEstricto({
        modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS",
        entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem",
        entidadId: id,
        accion: "APROBAR",
        empresaId: this.empresaId,
        conjuntoId: before.conjuntoPropietarioId,
        actor: this.actor,
        datosAntes: before,
        datosDespues: after,
      });
      return after;
    });
  }

  async aprobarLoteHerramientas(loteId: string) {
    await this.asegurarAprobador();
    return this.prisma.$transaction(async (tx) => {
      const pending = await tx.herramientaItem.findMany({
        where: {
          empresaId: this.empresaId,
          registroLoteId: loteId,
          estadoAprobacion: "PENDIENTE",
        },
        include: { herramienta: true },
        orderBy: { id: "asc" },
      });
      if (!pending.length) throw httpError(404, "Lote pendiente no encontrado.");

      const catalogIds = new Set(pending.map((item) => item.herramientaId));
      if (catalogIds.size !== 1) {
        throw httpError(409, "El lote contiene tipos de herramienta inconsistentes.");
      }
      const catalog = pending[0].herramienta;
      let approvedCatalogId = catalog.id;
      if (catalog.estadoAprobacion === "PENDIENTE") {
        await tx.herramienta.update({
          where: { id: catalog.id },
          data: {
            estadoAprobacion: "APROBADA",
            aprobadoPorId: this.actor.id,
            aprobadoEn: new Date(),
          },
        });
      } else if (!catalog.activo || catalog.estadoAprobacion !== "APROBADA") {
        if (!catalog.canonicaId) {
          throw httpError(409, "El tipo de herramienta del lote no puede aprobarse.");
        }
        const canonical = await tx.herramienta.findFirst({
          where: {
            id: catalog.canonicaId,
            empresaId: this.empresaId,
            activo: true,
            estadoAprobacion: "APROBADA",
          },
          select: { id: true },
        });
        if (!canonical) {
          throw httpError(409, "El catálogo fusionado ya no está disponible.");
        }
        approvedCatalogId = canonical.id;
      }

      const now = new Date();
      const result = await tx.herramientaItem.updateMany({
        where: {
          empresaId: this.empresaId,
          registroLoteId: loteId,
          estadoAprobacion: "PENDIENTE",
        },
        data: {
          estadoAprobacion: "APROBADA",
          aprobadoPorId: this.actor.id,
          aprobadoEn: now,
          actualizadoPorId: this.actor.id,
          herramientaId: approvedCatalogId,
        },
      });
      await new AuditoriaService(tx).registrarEstricto({
        modulo: "INVENTARIO_HERRAMIENTAS",
        entidad: "HerramientaLote",
        entidadId: loteId,
        accion: "APROBAR",
        empresaId: this.empresaId,
        conjuntoId: pending[0].conjuntoPropietarioId,
        actor: this.actor,
        metadataJson: {
          cantidad: result.count,
          ids: pending.map((item) => item.id),
          catalogoId: approvedCatalogId,
        },
      });
      return { loteId, aprobadas: result.count };
    });
  }

  async rechazarLoteHerramientas(loteId: string, motivo: string) {
    await this.asegurarAprobador();
    return this.prisma.$transaction(async (tx) => {
      const pending = await tx.herramientaItem.findMany({
        where: {
          empresaId: this.empresaId,
          registroLoteId: loteId,
          estadoAprobacion: "PENDIENTE",
        },
        include: { herramienta: true },
        orderBy: { id: "asc" },
      });
      if (!pending.length) throw httpError(404, "Lote pendiente no encontrado.");

      const catalogIds = new Set(pending.map((item) => item.herramientaId));
      if (catalogIds.size !== 1) {
        throw httpError(409, "El lote contiene tipos de herramienta inconsistentes.");
      }

      const now = new Date();
      const result = await tx.herramientaItem.updateMany({
        where: {
          empresaId: this.empresaId,
          registroLoteId: loteId,
          estadoAprobacion: "PENDIENTE",
        },
        data: {
          estadoAprobacion: "RECHAZADA",
          rechazadoPorId: this.actor.id,
          rechazadoEn: now,
          motivoRechazo: motivo,
          actualizadoPorId: this.actor.id,
        },
      });

      const catalog = pending[0].herramienta;
      if (catalog.estadoAprobacion === "PENDIENTE") {
        const remaining = await tx.herramientaItem.count({
          where: {
            empresaId: this.empresaId,
            herramientaId: catalog.id,
            estadoAprobacion: "PENDIENTE",
          },
        });
        if (remaining === 0) {
          await tx.herramienta.update({
            where: { id: catalog.id },
            data: {
              activo: false,
              estadoAprobacion: "RECHAZADA",
              rechazadoPorId: this.actor.id,
              rechazadoEn: now,
              motivoRechazo: motivo,
            },
          });
        }
      }

      await new AuditoriaService(tx).registrarEstricto({
        modulo: "INVENTARIO_HERRAMIENTAS",
        entidad: "HerramientaLote",
        entidadId: loteId,
        accion: "RECHAZAR",
        empresaId: this.empresaId,
        conjuntoId: pending[0].conjuntoPropietarioId,
        actor: this.actor,
        descripcion: motivo,
        metadataJson: {
          cantidad: result.count,
          ids: pending.map((item) => item.id),
          catalogoId: catalog.id,
        },
      });
      return { loteId, rechazadas: result.count };
    });
  }

  async rechazar(kind: ClaseActivo, id: number, motivo: string) {
    await this.asegurarAprobador();
    return this.prisma.$transaction(async (tx) => {
      const before: any = kind === "maquinaria"
        ? await tx.maquinaria.findFirst({ where: { id, empresaId: this.empresaId }, include: { tipoCatalogo: true } })
        : await tx.herramientaItem.findFirst({ where: { id, empresaId: this.empresaId }, include: { herramienta: true } });
      if (!before) throw httpError(404, "Activo no encontrado.");
      if (before.estadoAprobacion !== "PENDIENTE") throw httpError(409, "El activo ya fue resuelto.");
      const data = { estadoAprobacion: EstadoAprobacionActivo.RECHAZADA, rechazadoPorId: this.actor.id, rechazadoEn: new Date(), motivoRechazo: motivo, actualizadoPorId: this.actor.id };
      const after = kind === "maquinaria"
        ? await tx.maquinaria.update({ where: { id }, data })
        : await tx.herramientaItem.update({ where: { id }, data });
      const proposedCatalog: any = kind === "maquinaria"
        ? before.tipoCatalogo
        : before.herramienta;
      if (proposedCatalog?.estadoAprobacion === "PENDIENTE") {
        const remaining = kind === "maquinaria"
          ? await tx.maquinaria.count({
              where: {
                empresaId: this.empresaId,
                tipoCatalogoId: proposedCatalog.id,
                estadoAprobacion: "PENDIENTE",
              },
            })
          : await tx.herramientaItem.count({
              where: {
                empresaId: this.empresaId,
                herramientaId: proposedCatalog.id,
                estadoAprobacion: "PENDIENTE",
              },
            });
        if (remaining === 0) {
          const catalogRejection = {
            activo: false,
            estadoAprobacion: EstadoAprobacionActivo.RECHAZADA,
            rechazadoPorId: this.actor.id,
            rechazadoEn: new Date(),
            motivoRechazo: motivo,
          };
          if (kind === "maquinaria") {
            await tx.tipoMaquinariaCatalogo.update({
              where: { id: proposedCatalog.id },
              data: catalogRejection,
            });
          } else {
            await tx.herramienta.update({
              where: { id: proposedCatalog.id },
              data: catalogRejection,
            });
          }
        }
      }
      await new AuditoriaService(tx).registrarEstricto({
        modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS",
        entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem",
        entidadId: id,
        accion: "RECHAZAR",
        empresaId: this.empresaId,
        conjuntoId: before.conjuntoPropietarioId,
        actor: this.actor,
        descripcion: motivo,
        datosAntes: before,
        datosDespues: after,
      });
      return after;
    });
  }

  async cambiarEstado(kind: ClaseActivo, id: number, estado: string, motivo: string) {
    if (!esAprobador(this.actor)) throw httpError(403, "No autorizado para cambiar el estado del activo.");
    const before = await this.editable(kind, id);
    if (before.estadoAprobacion !== "APROBADA") throw httpError(409, "Solo se puede gestionar un activo aprobado.");
    return this.prisma.$transaction(async (tx) => {
      const retired = estado === "RETIRADA" || estado === "BAJA";
      const after = kind === "maquinaria"
        ? await tx.maquinaria.update({ where: { id }, data: { estado: estado as EstadoMaquinaria, actualizadoPorId: this.actor.id, retiradoPorId: retired ? this.actor.id : null, retiradoEn: retired ? new Date() : null } })
        : await tx.herramientaItem.update({ where: { id }, data: { estado: estado as EstadoHerramienta, actualizadoPorId: this.actor.id, retiradoPorId: retired ? this.actor.id : null, retiradoEn: retired ? new Date() : null } });
      await new AuditoriaService(tx).registrarEstricto({
        modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS",
        entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem",
        entidadId: id,
        accion: retired ? "RETIRAR" : "CAMBIAR_ESTADO",
        empresaId: this.empresaId,
        conjuntoId: before.conjuntoPropietarioId,
        actor: this.actor,
        descripcion: motivo,
        datosAntes: before,
        datosDespues: after,
      });
      return after;
    });
  }

  async prestar(kind: ClaseActivo, id: number, dto: any) {
    if (!esAprobador(this.actor)) throw httpError(403, "No autorizado para prestar activos empresariales.");
    await this.asegurarConjunto(dto.conjuntoId);
    return this.prisma.$transaction(async (tx) => {
      if (dto.responsableId) {
        const responsable = await tx.operario.findFirst({
          where: {
            id: dto.responsableId,
            empresaId: this.empresaId,
            conjuntos: { some: { nit: dto.conjuntoId } },
          },
          select: { id: true },
        });
        if (!responsable) {
          throw httpError(400, "El responsable no pertenece al conjunto de destino.");
        }
      }
      if (dto.tareaId) {
        const tarea = await tx.tarea.findFirst({
          where: {
            id: dto.tareaId,
            conjuntoId: dto.conjuntoId,
            borrador: false,
          },
          select: { id: true },
        });
        if (!tarea) {
          throw httpError(400, "La tarea no pertenece al conjunto o no está publicada.");
        }
      }
      const asset: any = kind === "maquinaria"
        ? await tx.maquinaria.findFirst({ where: { id, empresaId: this.empresaId } })
        : await tx.herramientaItem.findFirst({ where: { id, empresaId: this.empresaId } });
      if (!asset) throw httpError(404, "Activo no encontrado.");
      if (asset.propietarioTipo !== "EMPRESA") throw httpError(409, "Un conjunto no puede prestar activos a otro conjunto.");
      if (asset.estadoAprobacion !== "APROBADA" || asset.estado !== "OPERATIVA") throw httpError(409, "El activo no está aprobado y operativo.");
      const overlap = kind === "maquinaria"
        ? await tx.maquinariaConjunto.findFirst({ where: { maquinariaId: id, estado: { in: ["RESERVADA", "ACTIVA"] }, fechaInicio: { lt: dto.fechaDevolucionEstimada }, OR: [{ fechaFin: null }, { fechaFin: { gt: dto.fechaInicio } }] } })
        : await tx.herramientaItemConjunto.findFirst({ where: { herramientaItemId: id, estado: { in: ["RESERVADA", "ACTIVA"] }, fechaInicio: { lt: dto.fechaDevolucionEstimada }, OR: [{ fechaFin: null }, { fechaFin: { gt: dto.fechaInicio } }] } });
      if (overlap) throw httpError(409, "El activo ya está prestado o reservado en ese rango.");
      const assignment = kind === "maquinaria"
        ? await tx.maquinariaConjunto.create({ data: { maquinariaId: id, conjuntoId: dto.conjuntoId, tipoTenencia: "PRESTADA", estado: dto.fechaInicio > new Date() ? "RESERVADA" : "ACTIVA", fechaInicio: dto.fechaInicio, fechaDevolucionEstimada: dto.fechaDevolucionEstimada, operarioId: dto.responsableId ?? null, tareaId: dto.tareaId ?? null } })
        : await tx.herramientaItemConjunto.create({ data: { herramientaItemId: id, conjuntoId: dto.conjuntoId, estado: dto.fechaInicio > new Date() ? "RESERVADA" : "ACTIVA", fechaInicio: dto.fechaInicio, fechaDevolucionEstimada: dto.fechaDevolucionEstimada, responsableId: dto.responsableId ?? null, tareaId: dto.tareaId ?? null, creadoPorId: this.actor.id } });
      await new AuditoriaService(tx).registrarEstricto({ modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS", entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem", entidadId: id, accion: "PRESTAR", empresaId: this.empresaId, conjuntoId: dto.conjuntoId, actor: this.actor, datosDespues: assignment });
      return assignment;
    });
  }

  async devolver(kind: ClaseActivo, id: number) {
    if (!esAprobador(this.actor)) throw httpError(403, "No autorizado para devolver activos empresariales.");
    return this.prisma.$transaction(async (tx) => {
      const active: any = kind === "maquinaria"
        ? await tx.maquinariaConjunto.findFirst({ where: { maquinariaId: id, maquinaria: { empresaId: this.empresaId }, estado: "ACTIVA" } })
        : await tx.herramientaItemConjunto.findFirst({ where: { herramientaItemId: id, herramientaItem: { empresaId: this.empresaId }, estado: "ACTIVA" } });
      const assignment: any = active ?? (kind === "maquinaria"
        ? await tx.maquinariaConjunto.findFirst({ where: { maquinariaId: id, maquinaria: { empresaId: this.empresaId }, estado: "RESERVADA" }, orderBy: { fechaInicio: "asc" } })
        : await tx.herramientaItemConjunto.findFirst({ where: { herramientaItemId: id, herramientaItem: { empresaId: this.empresaId }, estado: "RESERVADA" }, orderBy: { fechaInicio: "asc" } }));
      if (!assignment) throw httpError(404, "El activo no tiene un préstamo abierto.");
      const closed = kind === "maquinaria"
        ? await tx.maquinariaConjunto.update({ where: { id: assignment.id }, data: { estado: "DEVUELTA", fechaFin: new Date(), tareaId: null } })
        : await tx.herramientaItemConjunto.update({ where: { id: assignment.id }, data: { estado: "DEVUELTA", fechaFin: new Date() } });
      await new AuditoriaService(tx).registrarEstricto({ modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS", entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem", entidadId: id, accion: "DEVOLVER", empresaId: this.empresaId, conjuntoId: assignment.conjuntoId, actor: this.actor, datosAntes: assignment, datosDespues: closed });
      return closed;
    });
  }

  private async referenciaFoto(kind: ClaseActivo, id: number) {
    const item = kind === "maquinaria"
      ? await this.prisma.maquinaria.findFirst({ where: { id, empresaId: this.empresaId }, select: { id: true, fotoDriveId: true, fotoNombre: true, fotoMimeType: true, conjuntoPropietarioId: true } })
      : await this.prisma.herramientaItem.findFirst({ where: { id, empresaId: this.empresaId }, select: { id: true, fotoDriveId: true, fotoNombre: true, fotoMimeType: true, conjuntoPropietarioId: true } });
    if (!item) throw httpError(404, "Activo no encontrado.");
    if (this.actor.rol === "administrador") {
      if (item.conjuntoPropietarioId) {
        await this.asegurarConjunto(item.conjuntoPropietarioId);
      } else {
        const asignacionVisible = kind === "maquinaria"
          ? await this.prisma.maquinariaConjunto.findFirst({
              where: {
                maquinariaId: id,
                estado: { in: ["RESERVADA", "ACTIVA"] },
                conjunto: {
                  empresaId: this.empresaId,
                  administradorId: this.actor.id,
                },
              },
              select: { id: true },
            })
          : await this.prisma.herramientaItemConjunto.findFirst({
              where: {
                herramientaItemId: id,
                estado: { in: ["RESERVADA", "ACTIVA"] },
                conjunto: {
                  empresaId: this.empresaId,
                  administradorId: this.actor.id,
                },
              },
              select: { id: true },
            });
        if (!asignacionVisible) throw httpError(404, "Activo no encontrado.");
      }
    }
    return item;
  }

  async obtenerFoto(kind: ClaseActivo, id: number) {
    const item = await this.referenciaFoto(kind, id);
    if (!item.fotoDriveId) throw httpError(404, "El activo no tiene fotografía.");
    return obtenerFotoInventario(item.fotoDriveId);
  }

  async guardarFoto(kind: ClaseActivo, id: number, file: FotoInput) {
    let newId: string | null = null;
    try {
      const before = await this.editable(kind, id);
      newId = await subirFotoInventario({ filePath: file.path, fileName: file.originalname, mimeType: file.mimetype, empresaId: this.empresaId, clase: kind === "maquinaria" ? "maquinaria" : "herramientas" });
      await this.prisma.$transaction(async (tx) => {
        const data = { fotoDriveId: newId, fotoNombre: file.originalname, fotoMimeType: file.mimetype, fotoTamano: file.size, fotoActualizadaEn: new Date(), actualizadoPorId: this.actor.id };
        if (kind === "maquinaria") await tx.maquinaria.update({ where: { id }, data });
        else await tx.herramientaItem.update({ where: { id }, data });
        await new AuditoriaService(tx).registrarEstricto({ modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS", entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem", entidadId: id, accion: "REEMPLAZAR_FOTO", empresaId: this.empresaId, conjuntoId: before.conjuntoPropietarioId, actor: this.actor, metadataJson: { nombre: file.originalname, mimeType: file.mimetype, tamano: file.size } });
      });
      if (before.fotoDriveId && before.fotoDriveId !== newId) await this.eliminarDriveSiNoReferenciado(before.fotoDriveId);
      return { fotoUrl: `/inventario/${kind === "maquinaria" ? "maquinaria" : "herramientas"}/${id}/foto` };
    } catch (error) {
      if (newId) await eliminarFotoInventario(newId).catch(() => undefined);
      throw error;
    } finally {
      await fs.promises.unlink(file.path).catch(() => undefined);
    }
  }

  async eliminarFoto(kind: ClaseActivo, id: number) {
    const before = await this.editable(kind, id);
    if (!before.fotoDriveId) return;
    await this.prisma.$transaction(async (tx) => {
      const data = { fotoDriveId: null, fotoNombre: null, fotoMimeType: null, fotoTamano: null, fotoActualizadaEn: null, actualizadoPorId: this.actor.id };
      if (kind === "maquinaria") await tx.maquinaria.update({ where: { id }, data });
      else await tx.herramientaItem.update({ where: { id }, data });
      await new AuditoriaService(tx).registrarEstricto({ modulo: kind === "maquinaria" ? "INVENTARIO_MAQUINARIA" : "INVENTARIO_HERRAMIENTAS", entidad: kind === "maquinaria" ? "Maquinaria" : "HerramientaItem", entidadId: id, accion: "ELIMINAR_FOTO", empresaId: this.empresaId, conjuntoId: before.conjuntoPropietarioId, actor: this.actor });
    });
    await this.eliminarDriveSiNoReferenciado(before.fotoDriveId);
  }

  private async eliminarDriveSiNoReferenciado(fileId: string) {
    const [machines, tools] = await Promise.all([
      this.prisma.maquinaria.count({ where: { fotoDriveId: fileId } }),
      this.prisma.herramientaItem.count({ where: { fotoDriveId: fileId } }),
    ]);
    if (machines + tools === 0) await eliminarFotoInventario(fileId).catch(() => undefined);
  }
}
