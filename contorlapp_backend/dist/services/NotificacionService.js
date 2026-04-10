"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotificacionService = void 0;
exports.bootstrapNotificacionesSchema = bootstrapNotificacionesSchema;
const client_1 = require("@prisma/client");
async function bootstrapNotificacionesSchema(db) {
    await db.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS "Notificacion" (
      "id" SERIAL PRIMARY KEY,
      "usuarioId" TEXT NOT NULL REFERENCES "Usuario"("id") ON DELETE CASCADE,
      "tipo" TEXT NOT NULL,
      "titulo" TEXT NOT NULL,
      "mensaje" TEXT NOT NULL,
      "referenciaTipo" TEXT,
      "referenciaId" INTEGER,
      "data" JSONB,
      "leida" BOOLEAN NOT NULL DEFAULT FALSE,
      "leidaEn" TIMESTAMPTZ,
      "creadaEn" TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
    await db.$executeRawUnsafe(`
    CREATE INDEX IF NOT EXISTS "idx_notificacion_usuario_leida"
    ON "Notificacion" ("usuarioId", "leida");
  `);
    await db.$executeRawUnsafe(`
    CREATE INDEX IF NOT EXISTS "idx_notificacion_usuario_creada"
    ON "Notificacion" ("usuarioId", "creadaEn" DESC);
  `);
}
class NotificacionService {
    constructor(db) {
        this.db = db;
    }
    async crearParaUsuarios(input) {
        const usuarioIds = Array.from(new Set(input.usuarioIds
            .map((id) => id.trim())
            .filter((id) => id.length > 0)));
        if (usuarioIds.length === 0)
            return 0;
        const dataJson = input.data == null ? null : JSON.stringify(input.data);
        const dataSql = dataJson == null ? client_1.Prisma.sql `NULL` : client_1.Prisma.sql `${dataJson}::jsonb`;
        const inserted = await this.db.$executeRaw(client_1.Prisma.sql `
        INSERT INTO "Notificacion" (
          "usuarioId",
          "tipo",
          "titulo",
          "mensaje",
          "referenciaTipo",
          "referenciaId",
          "data"
        )
        SELECT
          u."id",
          ${input.tipo},
          ${input.titulo},
          ${input.mensaje},
          ${input.referenciaTipo ?? null},
          ${input.referenciaId ?? null},
          ${dataSql}
        FROM "Usuario" u
        WHERE u."id" IN (${client_1.Prisma.join(usuarioIds)})
      `);
        return Number(inserted);
    }
    async listarUsuario(usuarioId, opts = {}) {
        const limit = Math.min(Math.max(opts.limit ?? 30, 1), 100);
        const whereNoLeidas = opts.soloNoLeidas
            ? client_1.Prisma.sql `AND n."leida" = FALSE`
            : client_1.Prisma.sql ``;
        const rows = await this.db.$queryRaw(client_1.Prisma.sql `
        SELECT
          n."id",
          n."tipo",
          n."titulo",
          n."mensaje",
          n."referenciaTipo",
          n."referenciaId",
          n."data",
          n."leida",
          n."leidaEn",
          n."creadaEn"
        FROM "Notificacion" n
        WHERE n."usuarioId" = ${usuarioId}
        ${whereNoLeidas}
        ORDER BY n."creadaEn" DESC
        LIMIT ${limit}
      `);
        return rows.map((row) => ({
            id: row.id,
            tipo: row.tipo,
            titulo: row.titulo,
            mensaje: row.mensaje,
            referenciaTipo: row.referenciaTipo,
            referenciaId: row.referenciaId,
            data: this.parseData(row.data),
            leida: row.leida,
            leidaEn: row.leidaEn,
            creadaEn: row.creadaEn,
        }));
    }
    async contarNoLeidas(usuarioId) {
        const rows = await this.db.$queryRaw(client_1.Prisma.sql `
        SELECT COUNT(*)::int AS "total"
        FROM "Notificacion" n
        WHERE n."usuarioId" = ${usuarioId}
          AND n."leida" = FALSE
      `);
        return rows[0]?.total ?? 0;
    }
    async marcarLeida(usuarioId, id) {
        const updated = await this.db.$executeRaw(client_1.Prisma.sql `
        UPDATE "Notificacion"
        SET
          "leida" = TRUE,
          "leidaEn" = COALESCE("leidaEn", NOW())
        WHERE "id" = ${id}
          AND "usuarioId" = ${usuarioId}
      `);
        return Number(updated) > 0;
    }
    async marcarTodasLeidas(usuarioId) {
        const updated = await this.db.$executeRaw(client_1.Prisma.sql `
        UPDATE "Notificacion"
        SET
          "leida" = TRUE,
          "leidaEn" = COALESCE("leidaEn", NOW())
        WHERE "usuarioId" = ${usuarioId}
          AND "leida" = FALSE
      `);
        return Number(updated);
    }
    async notificarAsignacionTareaOperarios(input) {
        const operariosIds = Array.from(new Set(input.operariosIds
            .map((id) => id.trim())
            .filter((id) => id.length > 0 && id !== input.asignadorId)));
        if (operariosIds.length === 0)
            return;
        const [asignador, conjunto] = await Promise.all([
            input.asignadorId
                ? this.db.usuario.findUnique({
                    where: { id: input.asignadorId },
                    select: { nombre: true },
                })
                : Promise.resolve(null),
            input.conjuntoId
                ? this.db.conjunto.findUnique({
                    where: { nit: input.conjuntoId },
                    select: { nombre: true },
                })
                : Promise.resolve(null),
        ]);
        const nombreAsignadorRaw = asignador?.nombre?.trim() ?? "";
        const nombreAsignador = nombreAsignadorRaw.length > 0 ? nombreAsignadorRaw : null;
        const parteConjunto = conjunto?.nombre
            ? ` en ${conjunto.nombre}`
            : input.conjuntoId
                ? ` en conjunto ${input.conjuntoId}`
                : "";
        const mensaje = nombreAsignador != null
            ? `${nombreAsignador} te asigno la tarea "${input.descripcionTarea}"${parteConjunto}.`
            : `Se te asigno la tarea "${input.descripcionTarea}"${parteConjunto}.`;
        await this.crearParaUsuarios({
            usuarioIds: operariosIds,
            tipo: "TAREA_ASIGNADA",
            titulo: "Nueva tarea asignada",
            mensaje,
            referenciaTipo: "TAREA",
            referenciaId: input.tareaId,
            data: {
                tareaId: input.tareaId,
                conjuntoId: input.conjuntoId ?? null,
            },
        });
    }
    async notificarCierreTarea(input) {
        const [actor, conjunto] = await Promise.all([
            this.db.usuario.findUnique({
                where: { id: input.actorId },
                select: { nombre: true },
            }),
            this.db.conjunto.findUnique({
                where: { nit: input.conjuntoId },
                select: { nombre: true, empresaId: true, administradorId: true },
            }),
        ]);
        if (!conjunto)
            return;
        const destinatarios = new Set();
        if (conjunto.administradorId)
            destinatarios.add(conjunto.administradorId);
        if (input.supervisorId)
            destinatarios.add(input.supervisorId);
        if (conjunto.empresaId) {
            const [gerentes, jefes] = await Promise.all([
                this.db.gerente.findMany({
                    where: { empresaId: conjunto.empresaId },
                    select: { id: true },
                }),
                this.db.jefeOperaciones.findMany({
                    where: { empresaId: conjunto.empresaId },
                    select: { id: true },
                }),
            ]);
            for (const g of gerentes)
                destinatarios.add(g.id);
            for (const j of jefes)
                destinatarios.add(j.id);
        }
        destinatarios.delete(input.actorId);
        if (destinatarios.size === 0)
            return;
        const actorNombreRaw = actor?.nombre?.trim() ?? "";
        const actorNombre = actorNombreRaw.length > 0
            ? actorNombreRaw
            : input.actorRol === "SUPERVISOR"
                ? "Un supervisor"
                : input.actorRol === "OPERARIO"
                    ? "Un operario"
                    : input.actorRol === "GERENTE"
                        ? "Un gerente"
                        : "Un jefe de operaciones";
        const nombreConjunto = conjunto.nombre ?? input.conjuntoId;
        const mensaje = `${actorNombre} cerro la tarea "${input.descripcionTarea}" del conjunto ${nombreConjunto}.`;
        await this.crearParaUsuarios({
            usuarioIds: Array.from(destinatarios),
            tipo: "TAREA_CERRADA",
            titulo: "Tarea cerrada",
            mensaje,
            referenciaTipo: "TAREA",
            referenciaId: input.tareaId,
            data: {
                tareaId: input.tareaId,
                conjuntoId: input.conjuntoId,
                actorId: input.actorId,
                actorRol: input.actorRol,
            },
        });
    }
    async notificarSolicitudInsumosCreada(input) {
        const [actor, conjunto] = await Promise.all([
            input.actorId
                ? this.db.usuario.findUnique({
                    where: { id: input.actorId },
                    select: { nombre: true },
                })
                : Promise.resolve(null),
            this.db.conjunto.findUnique({
                where: { nit: input.conjuntoId },
                select: { nombre: true, empresaId: true, administradorId: true },
            }),
        ]);
        if (!conjunto)
            return;
        const destinatarios = new Set();
        if (conjunto.administradorId)
            destinatarios.add(conjunto.administradorId);
        if (conjunto.empresaId) {
            const [gerentes, jefes, supervisores] = await Promise.all([
                this.db.gerente.findMany({
                    where: { empresaId: conjunto.empresaId },
                    select: { id: true },
                }),
                this.db.jefeOperaciones.findMany({
                    where: { empresaId: conjunto.empresaId },
                    select: { id: true },
                }),
                this.db.supervisor.findMany({
                    where: { empresaId: conjunto.empresaId },
                    select: { id: true },
                }),
            ]);
            for (const g of gerentes)
                destinatarios.add(g.id);
            for (const j of jefes)
                destinatarios.add(j.id);
            for (const s of supervisores)
                destinatarios.add(s.id);
        }
        if (input.actorId)
            destinatarios.delete(input.actorId);
        if (destinatarios.size === 0)
            return;
        const actorNombreRaw = actor?.nombre?.trim() ?? "";
        const actorNombre = actorNombreRaw.length > 0 ? actorNombreRaw : null;
        const nombreConjunto = conjunto.nombre ?? input.conjuntoId;
        const mensaje = actorNombre != null
            ? `${actorNombre} registro una solicitud de insumos (${input.totalItems} items) para ${nombreConjunto}.`
            : `Se registro una solicitud de insumos (${input.totalItems} items) para ${nombreConjunto}.`;
        await this.crearParaUsuarios({
            usuarioIds: Array.from(destinatarios),
            tipo: "SOLICITUD_INSUMOS_CREADA",
            titulo: "Nueva solicitud de insumos",
            mensaje,
            referenciaTipo: "SOLICITUD_INSUMO",
            referenciaId: input.solicitudId,
            data: {
                solicitudId: input.solicitudId,
                conjuntoId: input.conjuntoId,
                totalItems: input.totalItems,
                actorId: input.actorId ?? null,
            },
        });
    }
    async notificarPqrsCreadaPorAdministrador(input) {
        const [actor, conjunto] = await Promise.all([
            input.actorId
                ? this.db.usuario.findUnique({
                    where: { id: input.actorId },
                    select: { nombre: true },
                })
                : Promise.resolve(null),
            this.db.conjunto.findUnique({
                where: { nit: input.conjuntoId },
                select: { nombre: true, empresaId: true },
            }),
        ]);
        if (!conjunto?.empresaId)
            return;
        const [gerentes, jefes] = await Promise.all([
            this.db.gerente.findMany({
                where: { empresaId: conjunto.empresaId },
                select: { id: true },
            }),
            this.db.jefeOperaciones.findMany({
                where: { empresaId: conjunto.empresaId },
                select: { id: true },
            }),
        ]);
        const destinatarios = new Set();
        for (const g of gerentes)
            destinatarios.add(g.id);
        for (const j of jefes)
            destinatarios.add(j.id);
        if (input.actorId)
            destinatarios.delete(input.actorId);
        if (destinatarios.size === 0)
            return;
        const actorNombreRaw = actor?.nombre?.trim() ?? "";
        const actorNombre = actorNombreRaw.length > 0 ? actorNombreRaw : "Un administrador";
        const nombreConjunto = conjunto.nombre?.trim() ?? input.conjuntoId;
        const mensaje = `${actorNombre} creo una PQRS en ${nombreConjunto}: "${input.titulo}".`;
        await this.crearParaUsuarios({
            usuarioIds: Array.from(destinatarios),
            tipo: "PQRS_ADMIN_CREADA",
            titulo: "Nueva PQRS registrada",
            mensaje,
            referenciaTipo: "COMPROMISO_CONJUNTO",
            referenciaId: input.compromisoId,
            data: {
                compromisoId: input.compromisoId,
                conjuntoId: input.conjuntoId,
                titulo: input.titulo,
                actorId: input.actorId ?? null,
            },
        });
    }
    parseData(value) {
        if (value == null)
            return null;
        if (typeof value === "object" && !Array.isArray(value)) {
            return value;
        }
        if (typeof value === "string") {
            try {
                const parsed = JSON.parse(value);
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                    return parsed;
                }
            }
            catch {
                return null;
            }
        }
        return null;
    }
}
exports.NotificacionService = NotificacionService;
