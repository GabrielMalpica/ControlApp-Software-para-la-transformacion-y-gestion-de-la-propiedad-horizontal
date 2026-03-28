"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CumpleanosService = void 0;
const client_1 = require("@prisma/client");
function makeHttpError(status, message) {
    const err = new Error(message);
    err.status = status;
    return err;
}
class CumpleanosService {
    constructor(db) {
        this.db = db;
    }
    hoyBogota() {
        const now = new Date();
        const bogota = new Date(now.toLocaleString("en-US", { timeZone: "America/Bogota" }));
        return {
            dia: bogota.getDate(),
            mes: bogota.getMonth() + 1,
        };
    }
    async obtenerUsuarioActor(actorUserId) {
        const actor = await this.db.usuario.findUnique({
            where: { id: actorUserId },
            select: {
                id: true,
                rol: true,
                nombre: true,
                activo: true,
                fechaNacimiento: true,
            },
        });
        if (!actor) {
            throw makeHttpError(404, "Usuario no encontrado");
        }
        if (!actor.activo) {
            throw makeHttpError(403, "Usuario inactivo");
        }
        return actor;
    }
    async obtenerEmpresaIdActor(actorUserId) {
        const actor = await this.obtenerUsuarioActor(actorUserId);
        const rol = String(actor.rol).trim().toLowerCase();
        if (rol === "gerente") {
            const item = await this.db.gerente.findUnique({
                where: { id: actorUserId },
                select: { empresaId: true },
            });
            if (!item?.empresaId) {
                throw makeHttpError(400, "El gerente no tiene empresa asignada");
            }
            return item.empresaId;
        }
        if (rol === "jefe_operaciones") {
            const item = await this.db.jefeOperaciones.findUnique({
                where: { id: actorUserId },
                select: { empresaId: true },
            });
            return item.empresaId;
        }
        if (rol === "supervisor") {
            const item = await this.db.supervisor.findUnique({
                where: { id: actorUserId },
                select: { empresaId: true },
            });
            return item.empresaId;
        }
        if (rol === "operario") {
            const item = await this.db.operario.findUnique({
                where: { id: actorUserId },
                select: { empresaId: true },
            });
            return item.empresaId;
        }
        if (rol === "administrador") {
            const admin = await this.db.administrador.findUnique({
                where: { id: actorUserId },
                select: {
                    conjuntos: {
                        select: { empresaId: true },
                        where: { empresaId: { not: null } },
                        take: 1,
                    },
                },
            });
            const empresaId = admin?.conjuntos[0]?.empresaId;
            if (!empresaId) {
                throw makeHttpError(400, "El administrador no tiene empresa asociada");
            }
            return empresaId;
        }
        throw makeHttpError(403, "Rol no autorizado para consultar cumpleanos");
    }
    async listarCumpleanosEmpresa(empresaId, mes) {
        const rows = await this.db.$queryRaw(client_1.Prisma.sql `
      SELECT DISTINCT
        u."id",
        u."nombre",
        u."correo",
        u."rol",
        u."fechaNacimiento",
        EXTRACT(DAY FROM timezone('America/Bogota', u."fechaNacimiento"))::int AS "dia",
        EXTRACT(MONTH FROM timezone('America/Bogota', u."fechaNacimiento"))::int AS "mes"
      FROM "Usuario" u
      WHERE u."activo" = TRUE
        AND EXTRACT(MONTH FROM timezone('America/Bogota', u."fechaNacimiento"))::int = ${mes}
        AND (
          EXISTS (
            SELECT 1 FROM "Gerente" g
            WHERE g."id" = u."id" AND g."empresaId" = ${empresaId}
          )
          OR EXISTS (
            SELECT 1 FROM "JefeOperaciones" j
            WHERE j."id" = u."id" AND j."empresaId" = ${empresaId}
          )
          OR EXISTS (
            SELECT 1 FROM "Supervisor" s
            WHERE s."id" = u."id" AND s."empresaId" = ${empresaId}
          )
          OR EXISTS (
            SELECT 1 FROM "Operario" o
            WHERE o."id" = u."id" AND o."empresaId" = ${empresaId}
          )
          OR EXISTS (
            SELECT 1
            FROM "Administrador" a
            INNER JOIN "Conjunto" c ON c."administradorId" = a."id"
            WHERE a."id" = u."id" AND c."empresaId" = ${empresaId}
          )
        )
      ORDER BY "dia" ASC, u."nombre" ASC
    `);
        const hoy = this.hoyBogota();
        return rows.map((row) => ({
            ...row,
            esHoy: row.dia === hoy.dia && row.mes === hoy.mes,
        }));
    }
    async listarCumpleanosMesActor(actorUserId) {
        const actor = await this.obtenerUsuarioActor(actorUserId);
        const rol = String(actor.rol).trim().toLowerCase();
        if (!["gerente", "jefe_operaciones"].includes(rol)) {
            throw makeHttpError(403, "No autorizado para consultar cumpleanos del equipo");
        }
        const empresaId = await this.obtenerEmpresaIdActor(actorUserId);
        return this.listarCumpleanosEmpresa(empresaId, this.hoyBogota().mes);
    }
    async cumpleanosHoyActor(actorUserId) {
        const actor = await this.obtenerUsuarioActor(actorUserId);
        const hoy = this.hoyBogota();
        const fecha = new Date(actor.fechaNacimiento);
        const bogotaFecha = new Date(fecha.toLocaleString("en-US", { timeZone: "America/Bogota" }));
        const esCumpleanosHoy = bogotaFecha.getDate() === hoy.dia && bogotaFecha.getMonth() + 1 === hoy.mes;
        return {
            esCumpleanosHoy,
            nombre: actor.nombre,
            mensaje: esCumpleanosHoy
                ? "La empresa te desea un feliz cumpleanos, salud y un excelente dia."
                : null,
            fechaNacimiento: fecha,
        };
    }
    async existeNotificacionCumpleHoy(usuarioId, tipo, birthdayUserId) {
        const rows = await this.db.$queryRaw(client_1.Prisma.sql `
      SELECT COUNT(*)::int AS "total"
      FROM "Notificacion" n
      WHERE n."usuarioId" = ${usuarioId}
        AND n."tipo" = ${tipo}
        AND COALESCE(n."data"->>'birthdayUserId', '') = ${birthdayUserId}
        AND timezone('America/Bogota', n."creadaEn")::date = timezone('America/Bogota', NOW())::date
    `);
        return (rows[0]?.total ?? 0) > 0;
    }
    async asegurarNotificacionesCumpleanosHoy(actorUserId) {
        const empresaId = await this.obtenerEmpresaIdActor(actorUserId);
        const hoy = this.hoyBogota();
        const cumpleaneros = await this.listarCumpleanosEmpresa(empresaId, hoy.mes);
        const deHoy = cumpleaneros.filter((item) => item.dia == hoy.dia);
        if (!deHoy.length)
            return;
        const [gerentes, jefes] = await Promise.all([
            this.db.gerente.findMany({ where: { empresaId }, select: { id: true } }),
            this.db.jefeOperaciones.findMany({ where: { empresaId }, select: { id: true } }),
        ]);
        const destinatariosGestion = Array.from(new Set([...gerentes.map((x) => x.id), ...jefes.map((x) => x.id)]));
        for (const persona of deHoy) {
            for (const usuarioId of destinatariosGestion) {
                const existe = await this.existeNotificacionCumpleHoy(usuarioId, "CUMPLEANOS_EQUIPO", persona.id);
                if (!existe) {
                    await this.db.$executeRaw(client_1.Prisma.sql `
              INSERT INTO "Notificacion" (
                "usuarioId", "tipo", "titulo", "mensaje", "referenciaTipo", "referenciaId", "data"
              ) VALUES (
                ${usuarioId},
                ${"CUMPLEANOS_EQUIPO"},
                ${"Cumpleanos del equipo"},
                ${`${persona.nombre} esta cumpliendo anos hoy.`},
                ${"USUARIO"},
                NULL,
                ${JSON.stringify({ birthdayUserId: persona.id, birthdayRole: persona.rol })}::jsonb
              )
            `);
                }
            }
            const existePersonal = await this.existeNotificacionCumpleHoy(persona.id, "CUMPLEANOS_PERSONAL", persona.id);
            if (!existePersonal) {
                await this.db.$executeRaw(client_1.Prisma.sql `
            INSERT INTO "Notificacion" (
              "usuarioId", "tipo", "titulo", "mensaje", "referenciaTipo", "referenciaId", "data"
            ) VALUES (
              ${persona.id},
              ${"CUMPLEANOS_PERSONAL"},
              ${"Feliz cumpleanos"},
              ${"La empresa te desea un feliz cumpleanos y un excelente dia."},
              ${"USUARIO"},
              NULL,
              ${JSON.stringify({ birthdayUserId: persona.id })}::jsonb
            )
          `);
            }
        }
    }
}
exports.CumpleanosService = CumpleanosService;
