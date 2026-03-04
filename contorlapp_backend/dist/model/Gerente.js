"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ListarUsuariosDTO = exports.gerentePublicSelect = exports.EditarGerenteDTO = exports.CrearGerenteDTO = exports.UsuarioIdParam = void 0;
exports.toGerentePublico = toGerentePublico;
// src/models/gerente.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
exports.UsuarioIdParam = zod_1.z.object({
    id: zod_1.z.string().min(1, "El id de usuario (cédula) es obligatorio"),
});
/* ===================== DTOs ===================== */
/**
 * Crear gerente: requiere que ya exista el Usuario con ese id
 * y opcionalmente se asocie a una Empresa.
 */
exports.CrearGerenteDTO = zod_1.z.object({
    Id: zod_1.z.string().min(1, "El id (cédula) del usuario es obligatorio"),
    empresaId: zod_1.z.string().min(3).optional(),
});
/** Editar gerente (solo empresa por ahora) */
exports.EditarGerenteDTO = zod_1.z.object({
    empresaId: zod_1.z.string().min(3).optional().nullable(),
});
/* ===================== SELECT PARA PRISMA ===================== */
exports.gerentePublicSelect = {
    id: true,
    empresaId: true,
};
/** Helper para castear resultado Prisma al tipo público */
function toGerentePublico(row) {
    return row;
}
exports.ListarUsuariosDTO = zod_1.z.object({
    // ?rol=operario | administrador | jefe_operaciones | supervisor | gerente
    rol: zod_1.z.nativeEnum(client_1.Rol).optional(),
});
