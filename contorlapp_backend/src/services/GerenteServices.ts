// src/services/GerenteServices.ts
import {
  PrismaClient,
  Rol,
  TipoFuncion,
  TipoMaquinaria,
  EstadoMaquinaria,
} from "../generated/prisma";
import bcrypt from "bcrypt";
import { Prisma } from "../generated/prisma";

import {
  CrearUsuarioDTO,
  EditarUsuarioDTO,
  usuarioPublicSelect,
  toUsuarioPublico,
} from "../model/Usuario";

import { CrearGerenteDTO } from "../model/Gerente";
import { CrearAdministradorDTO } from "../model/Administrador";
import { CrearJefeOperacionesDTO } from "../model/JefeOperaciones";
import { CrearSupervisorDTO } from "../model/Supervisor";
import { CrearOperarioDTO, EditarOperarioDTO } from "../model/Operario";

import { CrearConjuntoDTO, EditarConjuntoDTO } from "../model/Conjunto";

import {
  CrearMaquinariaDTO,
  EditarMaquinariaDTO,
  maquinariaPublicSelect,
  toMaquinariaPublica,
} from "../model/Maquinaria";

import { CrearTareaDTO, EditarTareaDTO } from "../model/Tarea";

import { CrearInsumoDTO, insumoPublicSelect } from "../model/Insumo";

import { z } from "zod";

const AsignarAConjuntoDTO = z.object({
  operarioId: z.number().int().positive(),
  conjuntoId: z.string().min(3),
});

const AgregarInsumoAConjuntoDTO = z.object({
  conjuntoId: z.string().min(3),
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

const EntregarMaquinariaDTO = z.object({
  maquinariaId: z.number().int().positive(),
  conjuntoId: z.string().min(3),
});

export class GerenteService {
  constructor(private prisma: PrismaClient) {}

  /* ===================== EMPRESA ===================== */

  async crearEmpresa(payload: unknown) {
    const dto = z.object({ nombre: z.string().min(3), nit: z.string().min(3) }).parse(payload);

    const existe = await this.prisma.empresa.findUnique({ where: { nit: dto.nit } });
    if (existe) throw new Error("Ya existe una empresa con este NIT.");

    return this.prisma.empresa.create({ data: { nombre: dto.nombre, nit: dto.nit } });
  }

  async actualizarLimiteHorasEmpresa(limiteHorasSemana: number) {
    const empresa = await this.prisma.empresa.findFirst();
    if (!empresa) throw new Error("No hay empresa registrada.");
    return this.prisma.empresa.update({
      where: { nit: empresa.nit },
      data: { limiteHorasSemana },
      select: { nit: true, limiteHorasSemana: true },
    });
  }

  /* ===================== USUARIOS & ROLES ===================== */

  async crearUsuario(payload: unknown) {
    const dto = CrearUsuarioDTO.parse(payload);

    const [existeId, existeCorreo] = await Promise.all([
      this.prisma.usuario.findUnique({ where: { id: dto.id } }),
      this.prisma.usuario.findUnique({ where: { correo: dto.correo } }),
    ]);
    if (existeId) throw new Error("Ya existe un usuario con esa cédula.");
    if (existeCorreo) throw new Error("Ya existe un usuario con ese correo.");

    const hash = await bcrypt.hash(dto.contrasena, 10);

    const creado = await this.prisma.usuario.create({
      data: { ...dto, contrasena: hash },
      select: usuarioPublicSelect,
    });

    return toUsuarioPublico(creado);
  }

  async editarUsuario(id: number, payload: unknown) {
    const dto = EditarUsuarioDTO.parse(payload);

    if (dto.correo) {
      const otro = await this.prisma.usuario.findUnique({ where: { correo: dto.correo } });
      if (otro && (otro as any).id !== id) throw new Error("EMAIL_YA_REGISTRADO");
    }

    const data: any = { ...dto };
    if (dto.contrasena) {
      data.contrasena = await bcrypt.hash(dto.contrasena, 10);
    } else {
      delete data.contrasena;
    }

    const actualizado = await this.prisma.usuario.update({
      where: { id },
      data,
      select: usuarioPublicSelect,
    });

    return actualizado;
  }

  async asignarGerente(payload: unknown) {
    const dto = CrearGerenteDTO.parse(payload);

    const [empresa, usuario] = await Promise.all([
      this.prisma.empresa.findUnique({ where: { nit: dto.empresaId! } }),
      this.prisma.usuario.findUnique({ where: { id: dto.id } }),
    ]);
    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
    if (usuario.rol !== Rol.gerente) throw new Error("El usuario no tiene rol 'gerente'.");

    return this.prisma.gerente.create({
      data: { id: dto.id, empresaId: dto.empresaId! },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarAdministrador(payload: unknown) {
    const dto = CrearAdministradorDTO.parse(payload);
    const usuario = await this.prisma.usuario.findUnique({ where: { id: dto.id } });
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
    if (usuario.rol !== Rol.administrador) throw new Error("El usuario no tiene rol 'administrador'.");

    return this.prisma.administrador.create({
      data: { id: dto.id },
      include: { usuario: true, conjuntos: true },
    });
  }

  async asignarJefeOperaciones(payload: unknown) {
    const dto = CrearJefeOperacionesDTO.parse(payload);

    const [empresa, usuario] = await Promise.all([
      this.prisma.empresa.findUnique({ where: { nit: dto.empresaId } }),
      this.prisma.usuario.findUnique({ where: { id: dto.id } }),
    ]);
    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
    if (usuario.rol !== Rol.jefe_operaciones)
      throw new Error("El usuario no tiene rol 'jefe_operaciones'.");

    return this.prisma.jefeOperaciones.create({
      data: { id: dto.id, empresaId: dto.empresaId },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarSupervisor(payload: unknown) {
    const dto = CrearSupervisorDTO.parse(payload);
    const [empresa, usuario] = await Promise.all([
      this.prisma.empresa.findUnique({ where: { nit: dto.empresaId } }),
      this.prisma.usuario.findUnique({ where: { id: dto.id } }),
    ]);
    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
    if (usuario.rol !== Rol.supervisor) throw new Error("El usuario no tiene rol 'supervisor'.");

    return this.prisma.supervisor.create({
      data: { id: dto.id, empresaId: dto.empresaId },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarOperario(payload: unknown) {
    const dto = CrearOperarioDTO.parse(payload);

    const [empresa, usuario] = await Promise.all([
      this.prisma.empresa.findUnique({ where: { nit: dto.empresaId } }),
      this.prisma.usuario.findUnique({ where: { id: dto.id } }),
    ]);
    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
    if (usuario.rol !== Rol.operario) throw new Error("El usuario no tiene rol 'operario'.");

    return this.prisma.operario.create({
      data: {
        id: dto.id,
        empresaId: dto.empresaId,
        funciones: dto.funciones as TipoFuncion[],
        cursoSalvamentoAcuatico: dto.cursoSalvamentoAcuatico,
        urlEvidenciaSalvamento: dto.urlEvidenciaSalvamento ?? null,
        cursoAlturas: dto.cursoAlturas,
        urlEvidenciaAlturas: dto.urlEvidenciaAlturas ?? null,
        examenIngreso: dto.examenIngreso,
        urlEvidenciaExamenIngreso: dto.urlEvidenciaExamenIngreso ?? null,
        fechaIngreso: dto.fechaIngreso,
        fechaSalida: dto.fechaSalida ?? null,
        fechaUltimasVacaciones: dto.fechaUltimasVacaciones ?? null,
        observaciones: dto.observaciones ?? null,
      },
      include: { usuario: true, empresa: true },
    });
  }

  /* ===================== CONJUNTOS ===================== */

  async crearConjunto(payload: unknown) {
    const dto = CrearConjuntoDTO.parse(payload);

    const creado = await this.prisma.conjunto.create({
      data: {
        nit: dto.nit,
        nombre: dto.nombre,
        direccion: dto.direccion,
        correo: dto.correo,
        empresaId: dto.empresaId ?? null,
        administradorId: dto.administradorId ?? null,
        fechaInicioContrato: dto.fechaInicioContrato ?? null,
        fechaFinContrato: dto.fechaFinContrato ?? null,
        activo: dto.activo,
        tipoServicio: dto.tipoServicio as any,
        valorMensual: dto.valorMensual != null ? new Prisma.Decimal(dto.valorMensual) : null,
        consignasEspeciales: dto.consignasEspeciales,
        valorAgregado: dto.valorAgregado,
        horarios:
          dto.horarios && dto.horarios.length
            ? {
                create: dto.horarios.map((h) => ({
                  dia: h.dia,
                  horaApertura: h.horaApertura,
                  horaCierre: h.horaCierre,
                })),
              }
            : undefined,
      },
    });

    return creado;
  }

  async editarConjunto(conjuntoId: string, payload: unknown) {
    const dto = EditarConjuntoDTO.parse(payload);

    const updated = await this.prisma.$transaction(async (tx) => {
      if (dto.horarios) {
        await tx.conjuntoHorario.deleteMany({ where: { conjuntoId } });
        if (dto.horarios.length) {
          await tx.conjuntoHorario.createMany({
            data: dto.horarios.map((h) => ({
              conjuntoId,
              dia: h.dia,
              horaApertura: h.horaApertura,
              horaCierre: h.horaCierre,
            })),
          });
        }
      }

      const data: any = {
        nombre: dto.nombre,
        direccion: dto.direccion,
        correo: dto.correo,
        administradorId: dto.administradorId ?? undefined,
        empresaId: dto.empresaId ?? undefined,
        fechaInicioContrato: dto.fechaInicioContrato ?? undefined,
        fechaFinContrato: dto.fechaFinContrato ?? undefined,
        activo: dto.activo ?? undefined,
        tipoServicio: dto.tipoServicio ?? undefined,
        valorMensual:
          dto.valorMensual === undefined
            ? undefined
            : dto.valorMensual === null
            ? null
            : new Prisma.Decimal(dto.valorMensual),
        consignasEspeciales: dto.consignasEspeciales ?? undefined,
        valorAgregado: dto.valorAgregado ?? undefined,
      };

      return tx.conjunto.update({ where: { nit: conjuntoId }, data });
    });

    return updated;
  }

  async asignarOperarioAConjunto(payload: unknown) {
    const dto = AsignarAConjuntoDTO.parse(payload);
    return this.prisma.operario.update({
      where: { id: dto.operarioId },
      data: { conjuntos: { connect: { nit: dto.conjuntoId } } },
    });
  }

  /* ===================== INVENTARIO / INSUMOS ===================== */

  async agregarInsumoAConjunto(payload: unknown) {
    const dto = AgregarInsumoAConjuntoDTO.parse(payload);

    const inventario = await this.prisma.inventario.findUnique({
      where: { conjuntoId: dto.conjuntoId },
    });
    if (!inventario) throw new Error(`❌ No se encontró inventario para el conjunto ${dto.conjuntoId}`);

    const existente = await this.prisma.inventarioInsumo.findUnique({
      where: { inventarioId_insumoId: { inventarioId: inventario.id, insumoId: dto.insumoId } },
    });

    if (existente) {
      return this.prisma.inventarioInsumo.update({
        where: { id: existente.id },
        data: { cantidad: { increment: dto.cantidad } },
      });
    }

    return this.prisma.inventarioInsumo.create({
      data: { inventarioId: inventario.id, insumoId: dto.insumoId, cantidad: dto.cantidad },
    });
  }

  /** Catálogo corporativo: empresaId = null (ajusta si usas catálogo por empresa) */
  async agregarInsumoAlCatalogo(payload: unknown) {
    const dto = CrearInsumoDTO.parse(payload);
    const empresaId: string | null = null;

    const existe = await this.prisma.insumo.findFirst({
      where: { empresaId, nombre: dto.nombre, unidad: dto.unidad },
      select: { id: true },
    });
    if (existe) throw new Error("🚫 Ya existe un insumo con ese nombre y unidad en el catálogo.");

    return this.prisma.insumo.create({
      data: {
        nombre: dto.nombre,
        unidad: dto.unidad,
        empresaId,
        categoria: dto.categoria,
        umbralBajo: dto.umbralGlobalMinimo ?? null,
      },
      select: insumoPublicSelect,
    });
  }

  async listarCatalogo() {
    const empresaId: string | null = null;
    return this.prisma.insumo.findMany({
      where: { empresaId },
      select: insumoPublicSelect,
    });
  }

  /* ===================== MAQUINARIA ===================== */

  async crearMaquinaria(payload: unknown) {
    const dto = CrearMaquinariaDTO.parse(payload);
    const creada = await this.prisma.maquinaria.create({
      data: {
        nombre: dto.nombre,
        marca: dto.marca,
        tipo: dto.tipo as TipoMaquinaria,
        estado: dto.estado ?? EstadoMaquinaria.OPERATIVA,
        disponible: dto.disponible ?? true,
        conjuntoId: dto.conjuntoId ?? null,
        operarioId: dto.operarioId ?? null,
        empresaId: dto.empresaId ?? null,
        fechaPrestamo: dto.fechaPrestamo ?? null,
        fechaDevolucionEstimada: dto.fechaDevolucionEstimada ?? null,
      },
      select: maquinariaPublicSelect,
    });
    return toMaquinariaPublica(creada);
  }

  async entregarMaquinariaAConjunto(payload: unknown) {
    const dto = EntregarMaquinariaDTO.parse(payload);
    return this.prisma.maquinaria.update({
      where: { id: dto.maquinariaId },
      data: {
        disponible: false,
        conjuntoId: dto.conjuntoId,
        fechaPrestamo: new Date(),
      },
      select: maquinariaPublicSelect,
    });
  }

  async editarMaquinaria(maquinariaId: number, payload: unknown) {
    const dto = EditarMaquinariaDTO.parse(payload);
    const actualizado = await this.prisma.maquinaria.update({
      where: { id: maquinariaId },
      data: { ...dto },
      select: maquinariaPublicSelect,
    });
    return toMaquinariaPublica(actualizado);
  }

  /* ===================== TAREAS ===================== */

  async asignarTarea(payload: unknown) {
    const dto = CrearTareaDTO.parse(payload);
    return this.prisma.tarea.create({
      data: {
        descripcion: dto.descripcion,
        fechaInicio: dto.fechaInicio,
        fechaFin: dto.fechaFin,
        duracionHoras: dto.duracionHoras,
        estado: "ASIGNADA",
        evidencias: dto.evidencias ?? [],
        insumosUsados: dto.insumosUsados ?? [],
        ubicacionId: dto.ubicacionId,
        elementoId: dto.elementoId,
        conjuntoId: dto.conjuntoId ?? null,
        supervisorId: dto.supervisorId ?? null,
        ...(dto.operariosIds?.length
          ? { operarios: { connect: dto.operariosIds.map((id) => ({ id })) } }
          : dto.operarioId
          ? { operarios: { connect: { id: dto.operarioId } } }
          : {}),
      },
    });
  }

  async editarTarea(tareaId: number, payload: unknown) {
    const dto = EditarTareaDTO.parse(payload);

    // Usar TareaUpdateInput (no Unchecked) para poder actualizar relaciones (operarios)
    const data: Prisma.TareaUpdateInput = {};

    if (dto.descripcion !== undefined) data.descripcion = dto.descripcion;
    if (dto.fechaInicio !== undefined) data.fechaInicio = dto.fechaInicio as any;
    if (dto.fechaFin !== undefined) data.fechaFin = dto.fechaFin as any;
    if (dto.duracionHoras !== undefined) data.duracionHoras = dto.duracionHoras;
    if (dto.estado !== undefined) data.estado = dto.estado as any;
    if (dto.evidencias !== undefined) data.evidencias = dto.evidencias as any;
    if (dto.insumosUsados !== undefined) data.insumosUsados = dto.insumosUsados as any;
    if (dto.observacionesRechazo !== undefined) data.observacionesRechazo = dto.observacionesRechazo;

    if (dto.supervisorId !== undefined) {
      data.supervisor = dto.supervisorId === null ? { disconnect: true } : { connect: { id: dto.supervisorId } };
    }
    if (dto.ubicacionId !== undefined) data.ubicacion = { connect: { id: dto.ubicacionId } };
    if (dto.elementoId !== undefined) data.elemento = { connect: { id: dto.elementoId } };
    if (dto.conjuntoId !== undefined) {
      data.conjunto = dto.conjuntoId === null ? { disconnect: true } : { connect: { nit: dto.conjuntoId } };
    }

    // reemplazar asignación de operarios si llega el arreglo
    if (dto.operariosIds !== undefined) {
      data.operarios = { set: dto.operariosIds.map((id) => ({ id })) };
    }

    return this.prisma.tarea.update({ where: { id: tareaId }, data });
  }

  /* ===================== ELIMINACIONES con REGLAS ===================== */

  async eliminarAdministrador(adminId: number) {
    const asignaciones = await this.prisma.conjunto.findMany({
      where: { administradorId: adminId },
    });
    if (asignaciones.length > 0) {
      throw new Error("❌ El administrador tiene conjuntos asignados.");
    }
    await this.prisma.usuario.delete({ where: { id: adminId } });
  }

  async reemplazarAdminEnVariosConjuntos(reemplazos: { conjuntoId: string; nuevoAdminId: number }[]) {
    if (reemplazos.length === 0) return;
    for (const { conjuntoId, nuevoAdminId } of reemplazos) {
      await this.prisma.conjunto.update({
        where: { nit: conjuntoId },
        data: { administradorId: nuevoAdminId },
      });
    }
  }

  async eliminarOperario(operarioId: number) {
    // Con relación M:N, revisar tareas pendientes donde el operario esté asignado
    const tareasPendientes = await this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: operarioId } },
        estado: { in: ["ASIGNADA", "EN_PROCESO", "PENDIENTE_APROBACION"] },
      },
      select: { id: true },
    });
    if (tareasPendientes.length > 0) {
      throw new Error("❌ El operario tiene tareas pendientes.");
    }
    await this.prisma.operario.delete({ where: { id: operarioId } });
  }

  async eliminarSupervisor(supervisorId: number) {
    await this.prisma.supervisor.delete({ where: { id: supervisorId } });
  }

  async eliminarConjunto(conjuntoId: string) {
    const [tareasPendientes, maquinariaPrestada] = await Promise.all([
      this.prisma.tarea.findMany({
        where: {
          conjuntoId,
          estado: { in: ["ASIGNADA", "EN_PROCESO", "PENDIENTE_APROBACION"] },
        },
        select: { id: true },
      }),
      this.prisma.maquinaria.findMany({ where: { conjuntoId, disponible: false }, select: { id: true } }),
    ]);

    if (tareasPendientes.length > 0) throw new Error("❌ El conjunto tiene tareas pendientes.");
    if (maquinariaPrestada.length > 0) throw new Error("❌ El conjunto tiene maquinaria prestada.");

    await this.prisma.conjunto.delete({ where: { nit: conjuntoId } });
  }

  async eliminarMaquinaria(maquinariaId: number) {
    await this.prisma.maquinaria.delete({ where: { id: maquinariaId } });
  }

  async eliminarTarea(tareaId: number) {
    await this.prisma.tarea.delete({ where: { id: tareaId } });
  }

  /* ===================== EDICIONES RÁPIDAS (compat) ===================== */

  async editarAdministrador(adminId: number, payload: unknown) {
    const dto = EditarUsuarioDTO.parse(payload);
    const data: any = { ...dto };
    if (dto.contrasena) {
      data.contrasena = await bcrypt.hash(dto.contrasena, 10);
    } else {
      delete data.contrasena;
    }
    await this.prisma.usuario.update({ where: { id: adminId }, data });
  }

  async editarOperario(operarioId: number, payload: unknown) {
    const dto = EditarOperarioDTO.parse(payload);

    const data: any = {};
    if (dto.funciones) data.funciones = dto.funciones as TipoFuncion[];

    if ((payload as any).nombre || (payload as any).correo) {
      const uData: any = {};
      if ((payload as any).nombre) uData.nombre = (payload as any).nombre;
      if ((payload as any).correo) uData.correo = (payload as any).correo;
      await this.prisma.usuario.update({ where: { id: operarioId }, data: uData });
    }

    if (Object.keys(data).length === 0) return;
    await this.prisma.operario.update({ where: { id: operarioId }, data });
  }

  async editarSupervisor(supervisorId: number, payload: unknown) {
    const dto = z
      .object({
        empresaId: z.string().min(3).optional(),
        nombre: z.string().optional(),
        correo: z.string().email().optional(),
      })
      .parse(payload);

    if (dto.nombre || dto.correo) {
      const uData: any = {};
      if (dto.nombre) uData.nombre = dto.nombre;
      if (dto.correo) uData.correo = dto.correo;
      await this.prisma.usuario.update({ where: { id: supervisorId }, data: uData });
    }

    if (dto.empresaId) {
      await this.prisma.supervisor.update({
        where: { id: supervisorId },
        data: { empresaId: dto.empresaId },
      });
    }
  }
}
