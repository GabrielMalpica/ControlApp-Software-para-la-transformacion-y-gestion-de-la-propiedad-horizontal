"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GerenteController = void 0;
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
const prisma_1 = require("../db/prisma");
const GerenteServices_1 = require("../services/GerenteServices");
const PermissionService_1 = require("../services/PermissionService");
const Gerente_1 = require("../model/Gerente");
// â”€â”€ Schemas de params simples â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const IdParam = zod_1.z.object({ id: zod_1.z.coerce.number().int().positive() });
const AdminIdParam = zod_1.z.object({ adminId: zod_1.z.coerce.number().int().positive() });
const OperarioIdParam = zod_1.z.object({
    operarioId: zod_1.z.coerce.number().int().positive(),
});
const SupervisorIdParam = zod_1.z.object({
    supervisorId: zod_1.z.coerce.number().int().positive(),
});
const TareaIdParam = zod_1.z.object({ tareaId: zod_1.z.coerce.number().int().positive() });
const MaquinariaIdParam = zod_1.z.object({
    maquinariaId: zod_1.z.coerce.number().int().positive(),
});
const ConjuntoIdParam = zod_1.z.object({ conjuntoId: zod_1.z.string().min(3) });
const EliminarConjuntoQuery = zod_1.z.object({
    confirmar: zod_1.z.coerce.boolean().optional().default(false),
});
// Para endpoints que agregan insumo a conjunto por URL + body
const AddInsumoBody = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.number().int().positive(),
});
// Para asignar operario a conjunto por URL + body
const AsignarOperarioBody = zod_1.z.object({
    operarioId: zod_1.z.number().int().positive(),
});
// Para reemplazos masivos de administradores
const ReemplazosBody = zod_1.z.object({
    reemplazos: zod_1.z.array(zod_1.z.object({
        conjuntoId: zod_1.z.string().min(3),
        nuevoAdminId: zod_1.z.number().int().positive(),
    })),
});
// Actualizar lÃ­mite de horas semanales
const LimiteHorasBody = zod_1.z.object({
    limiteHorasSemana: zod_1.z.coerce.number().int().min(1).max(84),
});
const QuitarOperarioBody = zod_1.z.object({
    operarioId: zod_1.z.string().min(1),
});
const ActualizarMatrizPermisosBody = zod_1.z.object({
    matrix: zod_1.z.record(zod_1.z.string(), zod_1.z.record(zod_1.z.string(), zod_1.z.boolean())),
});
const permissionService = new PermissionService_1.PermissionService(prisma_1.prisma);
function serviceFor(req) {
    return new GerenteServices_1.GerenteService(prisma_1.prisma, req.user?.empresaId);
}
class GerenteController {
    constructor() {
        this.obtenerCatalogoPermisos = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const empresaId = await permissionService.resolveEmpresaIdForUser(actorUserId, client_1.Rol.gerente);
                const matrix = await permissionService.getPermissionMatrix(empresaId);
                res.json(matrix);
            }
            catch (err) {
                next(err);
            }
        };
        this.actualizarMatrizPermisos = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const { matrix } = ActualizarMatrizPermisosBody.parse(req.body);
                const empresaId = await permissionService.resolveEmpresaIdForUser(actorUserId, client_1.Rol.gerente);
                const updated = await permissionService.replacePermissionMatrix(empresaId, matrix);
                res.json(updated);
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Empresa â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.crearEmpresa = async (req, res, next) => {
            try {
                const out = await serviceFor(req).crearEmpresa(req.body, req.user?.sub);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.actualizarLimiteHoras = async (req, res, next) => {
            try {
                const { limiteHorasSemana } = LimiteHorasBody.parse(req.body);
                const out = await serviceFor(req).actualizarLimiteHorasEmpresa(limiteHorasSemana);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Usuarios â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.crearUsuario = async (req, res, next) => {
            try {
                const out = await serviceFor(req).crearUsuario(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.editarUsuario = async (req, res, next) => {
            try {
                const { id } = Gerente_1.UsuarioIdParam.parse(req.params);
                const out = await serviceFor(req).editarUsuario(id, req.body);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarUsuarios = async (req, res, next) => {
            try {
                const dto = Gerente_1.ListarUsuariosDTO.parse(req.query);
                const usuarios = await serviceFor(req).listarUsuarios(dto.rol);
                res.json(usuarios);
            }
            catch (err) {
                next(err);
            }
        };
        this.crearResidenteManual = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const out = await serviceFor(req).crearResidenteManual(actorUserId, req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.cargarResidentesMasivo = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const out = await serviceFor(req).cargarResidentesMasivo(actorUserId, req.body, req.file);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarResidentes = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const out = await serviceFor(req).listarResidentes(actorUserId, req.query);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.editarResidente = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const residenteId = String(req.params.residenteId ?? "").trim();
                const out = await serviceFor(req).editarResidente(actorUserId, residenteId, req.body);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarResidenteGestion = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const residenteId = String(req.params.residenteId ?? "").trim();
                const conjuntoId = String(req.query.conjuntoId ?? "").trim();
                const out = await serviceFor(req).eliminarResidenteGestion(actorUserId, residenteId, conjuntoId);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Roles / Perfiles â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.asignarGerente = async (req, res, next) => {
            try {
                const out = await serviceFor(req).asignarGerente(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.asignarAdministrador = async (req, res, next) => {
            try {
                const out = await serviceFor(req).asignarAdministrador(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.asignarJefeOperaciones = async (req, res, next) => {
            try {
                const out = await serviceFor(req).asignarJefeOperaciones(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.asignarSupervisor = async (req, res, next) => {
            try {
                const out = await serviceFor(req).asignarSupervisor(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarSupervisores = async (req, res, next) => {
            try {
                const supervisores = await serviceFor(req).listarSupervisores();
                res.json(supervisores);
            }
            catch (err) {
                console.error("Error al listar supervisores:", err);
                next(err);
            }
        };
        this.listarTareasPorConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoIdParam.parse(req.params);
                const out = await serviceFor(req).listarTareasPorConjunto(conjuntoId);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.asignarOperario = async (req, res, next) => {
            try {
                const out = await serviceFor(req).asignarOperario(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Conjuntos â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.crearConjunto = async (req, res, next) => {
            try {
                const out = await serviceFor(req).crearConjunto(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.cargarConjuntoMasivo = async (req, res, next) => {
            try {
                const actorUserId = req.user?.sub;
                if (!actorUserId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const out = await serviceFor(req).cargarConjuntoMasivo(actorUserId, req.file);
                res.status(out.creado ? 201 : 422).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.descargarPlantillaConjunto = async (req, res, next) => {
            try {
                const buffer = await serviceFor(req).generarPlantillaConjunto();
                res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
                res.setHeader("Content-Disposition", 'attachment; filename="plantilla_conjunto.xlsx"');
                res.status(200).send(buffer);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarConjuntos = async (req, res, next) => {
            try {
                const out = await serviceFor(req).listarConjuntos();
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.obtenerConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoIdParam.parse(req.params);
                const out = await serviceFor(req).obtenerConjunto(conjuntoId);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.editarConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoIdParam.parse(req.params);
                const out = await serviceFor(req).editarConjunto(conjuntoId, req.body);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.asignarOperarioAConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoIdParam.parse(req.params);
                const { operarioId } = AsignarOperarioBody.parse(req.body);
                await serviceFor(req).asignarOperarioAConjunto({
                    conjuntoId,
                    operarioId,
                });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.quitarOperarioDeConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoIdParam.parse(req.params);
                const { operarioId } = QuitarOperarioBody.parse(req.body);
                await serviceFor(req).quitarOperarioDeConjunto({ conjuntoId, operarioId });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Inventario / Insumos â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.agregarInsumoAConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoIdParam.parse(req.params);
                const body = AddInsumoBody.parse(req.body);
                const out = await serviceFor(req).agregarInsumoAConjunto({
                    conjuntoId,
                    insumoId: body.insumoId,
                    cantidad: body.cantidad,
                });
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Tareas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.asignarTarea = async (req, res, next) => {
            try {
                const body = req.body ?? {};
                const tipo = String(body?.tipo ?? "CORRECTIVA").toUpperCase();
                const prioridad = Number(body?.prioridad ?? 2);
                // âœ… 1) Correctiva P1/P2/P3: entra por reglas de conflicto/reemplazo
                if (tipo === "CORRECTIVA" && [1, 2, 3].includes(prioridad)) {
                    const r = await serviceFor(req).crearCorrectivaConReglas(body);
                    // A) Creada sin reemplazo
                    if (r.ok && r.mode === "CREADA_SIN_REEMPLAZO") {
                        res.status(201).json({
                            ok: true,
                            tareaId: r.createdId ?? r.createdP1Id,
                            createdId: r.createdId ?? r.createdP1Id,
                            message: r.message,
                            ajustadaAutomaticamente: r.ajustadaAutomaticamente ?? false,
                            motivoAjuste: r.motivoAjuste ?? null,
                            solicitadaInicio: r.solicitadaInicio ?? null,
                            solicitadaFin: r.solicitadaFin ?? null,
                            asignadaInicio: r.asignadaInicio ?? null,
                            asignadaFin: r.asignadaFin ?? null,
                        });
                        return;
                    }
                    // B) Auto reemplazo
                    if (r.ok && (r.mode === "AUTO_REEMPLAZO" || r.mode === "AUTO_REEMPLAZO_P3")) {
                        res.status(200).json({
                            ok: true,
                            tareaId: r.createdId ?? r.createdP1Id,
                            createdId: r.createdId ?? r.createdP1Id,
                            autoReplaced: r.autoReplaced ?? r.info?.reemplazadas ?? [],
                            reemplazadasIds: r.reemplazadasIds ?? [],
                            reprogramadasIds: r.reprogramadasIds ?? [],
                            canceladasIds: r.canceladasIds ?? [],
                            canceladasSinCupoIds: r.canceladasSinCupoIds ?? [],
                            noCompletadasIds: r.noCompletadasIds ?? [],
                            message: r.message,
                        });
                        return;
                    }
                    // C) Requiere decisiÃ³n manual (mover/reemplazar o reemplazar directo)
                    if (r.ok &&
                        (r.mode === "REQUIERE_DECISION_REEMPLAZO" ||
                            r.mode === "REQUIERE_CONFIRMACION_P2" ||
                            r.mode === "REQUIERE_CONFIRMACION_P1")) {
                        const reemplazables = (r.opciones ?? []).flatMap((op) => {
                            return (op.tareas ?? []).map((t) => ({
                                id: t.id,
                                prioridad: t.prioridad,
                                descripcion: t.descripcion,
                                tipo: t.tipo ?? "PREVENTIVA",
                                fechaInicio: t.fechaInicio,
                                fechaFin: t.fechaFin,
                            }));
                        });
                        const replacementPriority = Number(r.prioridadObjetivo ?? prioridad);
                        const isCritical = replacementPriority === 1;
                        res.status(200).json({
                            needsReplacement: true,
                            ok: false,
                            message: r.message,
                            decisionMode: r.decisionMode ?? "REEMPLAZAR",
                            replacementPriority,
                            prioridadCorrectiva: Number(r.prioridadCorrectiva ?? prioridad),
                            replacementNoticeOnly: r.replacementNoticeOnly ?? false,
                            criticalConfirmation: isCritical,
                            confirmationVariant: r.confirmationVariant ?? r.estiloConfirmacion,
                            confirmationColor: (r.confirmationColor ?? r.colorConfirmacion) === "red"
                                ? "#DC2626"
                                : (r.confirmationColor ?? r.colorConfirmacion) === "blue"
                                    ? "#2563EB"
                                    : "#D97706",
                            confirmationTitle: r.confirmationTitle ?? r.tituloConfirmacion,
                            confirmationRequiresReason: r.confirmationRequiresReason ?? r.requiereMotivo ?? true,
                            requiresReplacementAction: r.requiresReplacementAction ?? true,
                            reasonHint: r.replacementNoticeOnly === true
                                ? "Se mostrara el detalle de las preventivas P3 que se reemplazaran antes de continuar."
                                : "Debes indicar por que se autoriza este reemplazo antes de confirmar.",
                            reemplazables,
                            reemplazablesP2: replacementPriority === 2 ? reemplazables : [],
                            reemplazablesP1: replacementPriority === 1 ? reemplazables : [],
                            opcionesAuto: r.opcionesAuto ?? [],
                            opcionesConfirmacion: r.opcionesConfirmacion ?? [],
                            suggestedInicio: r.suggestedInicio ?? r.slotSugerido?.fechaInicio ?? null,
                            suggestedFin: r.suggestedFin ?? r.slotSugerido?.fechaFin ?? null,
                        });
                        return;
                    }
                    // D) No se pudo
                    res.status(200).json({
                        ok: false,
                        reason: "reason" in r ? r.reason : "SIN_HUECO",
                        message: r.message,
                        suggestedInicio: r.suggestedInicio ?? null,
                        suggestedFin: r.suggestedFin ?? null,
                    });
                    return;
                }
                // âœ… 2) No es P1: asignaciÃ³n normal (incluye validaciÃ³n solapes/sugerencias)
                const out = await serviceFor(req).asignarTarea(body);
                const status = out?.ok === true ? 201 : 200;
                res.status(status).json(out);
                return;
            }
            catch (err) {
                next(err);
            }
        };
        this.asignarTareaConReemplazo = async (req, res) => {
            try {
                const out = await serviceFor(req).asignarTareaConReemplazoV2(req.body);
                if (out?.ok === false)
                    return res.status(400).json(out);
                return res.status(200).json(out);
            }
            catch (e) {
                return res
                    .status(400)
                    .json({ ok: false, message: e?.message ?? String(e) });
            }
        };
        this.editarTarea = async (req, res, next) => {
            try {
                const { tareaId } = TareaIdParam.parse(req.params);
                const out = await serviceFor(req).editarTarea(tareaId, req.body);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Eliminaciones con reglas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.eliminarAdministrador = async (req, res, next) => {
            try {
                const { adminId } = AdminIdParam.parse(req.params);
                await serviceFor(req).eliminarAdministrador(adminId.toString());
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.reemplazarAdminEnVariosConjuntos = async (req, res, next) => {
            try {
                const { reemplazos } = ReemplazosBody.parse(req.body);
                await serviceFor(req).reemplazarAdminEnVariosConjuntos(reemplazos);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarOperario = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                await serviceFor(req).eliminarOperario(operarioId.toString());
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarSupervisor = async (req, res, next) => {
            try {
                const { supervisorId } = SupervisorIdParam.parse(req.params);
                await serviceFor(req).eliminarSupervisor(supervisorId.toString());
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarUsuario = async (req, res, next) => {
            try {
                const { id } = Gerente_1.UsuarioIdParam.parse(req.params);
                await serviceFor(req).eliminarUsuario(id);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoIdParam.parse(req.params);
                const { confirmar } = EliminarConjuntoQuery.parse(req.query);
                const result = await serviceFor(req).eliminarConjunto(conjuntoId, { confirmar });
                if (!result.ok && result.requiresConfirmation) {
                    res.status(409).json(result);
                    return;
                }
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarMaquinaria = async (req, res, next) => {
            try {
                const { maquinariaId } = MaquinariaIdParam.parse(req.params);
                await serviceFor(req).eliminarMaquinaria(maquinariaId);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarTarea = async (req, res, next) => {
            try {
                const { tareaId } = TareaIdParam.parse(req.params);
                await serviceFor(req).eliminarTarea(prisma_1.prisma, tareaId);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // â”€â”€ Ediciones rÃ¡pidas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        this.editarAdministrador = async (req, res, next) => {
            try {
                const { adminId } = AdminIdParam.parse(req.params);
                await serviceFor(req).editarAdministrador(adminId, req.body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.editarOperario = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                await serviceFor(req).editarOperario(operarioId, req.body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        this.editarSupervisor = async (req, res, next) => {
            try {
                const { supervisorId } = SupervisorIdParam.parse(req.params);
                await serviceFor(req).editarSupervisor(supervisorId, req.body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.GerenteController = GerenteController;
