import type { PrismaClient } from "@prisma/client";
import {
  Rol,
  TipoFuncion,
  EstadoTarea,
  JornadaLaboral,
  PatronJornada,
} from "@prisma/client";
import bcrypt from "bcrypt";
import { Prisma } from "@prisma/client";

import {
  CrearUsuarioDTO,
  EditarUsuarioDTO,
  usuarioPublicSelect,
  toUsuarioPublico,
  UsuarioPublico,
} from "../model/Usuario";

import { CrearGerenteDTO } from "../model/Gerente";
import { CrearAdministradorDTO } from "../model/Administrador";
import { CrearJefeOperacionesDTO } from "../model/JefeOperaciones";
import { CrearSupervisorDTO } from "../model/Supervisor";
import { CrearOperarioDTO, EditarOperarioDTO } from "../model/Operario";

import {
  conjuntoPublicSelect,
  CrearConjuntoDTO,
  EditarConjuntoDTO,
  toConjuntoPublico,
} from "../model/Conjunto";

import { CrearTareaDTO, EditarTareaDTO } from "../model/Tarea";

import { CrearInsumoDTO, insumoPublicSelect } from "../model/Insumo";

import { z } from "zod";
import {
  Bloqueo,
  buildAgendaPorOperarioDia,
  buscarHuecoDiaConSplitEarliest,
  dateToDiaSemana,
  Intervalo,
  mergeIntervalos,
  toMin,
  toMinOfDaySafe,
} from "../utils/schedulerUtils";
import {
  buildBloqueosPorDescanso,
  buildBloqueosPorPatronJornada,
} from "./DefinicionTareaPreventivaService";
import { NotificacionService } from "./NotificacionService";

export const AsignarConReemplazoDTO = z.object({
  tarea: CrearTareaDTO,
  reemplazarIds: z.array(z.number().int().positive()).min(1),
  motivoReemplazo: z.string().trim().min(3).max(500).optional(),
});

const AsignarConReemplazoV2DTO = z.object({
  tarea: CrearTareaDTO,
  reemplazarIds: z.array(z.number().int().positive()).min(1),
  motivoReemplazo: z.string().trim().min(3).max(500).optional(),
  motivo: z.string().trim().min(3).max(500).optional(),
  accionReemplazadas: z.enum(["REPROGRAMAR", "CANCELAR"]).optional(),
});

const AgregarInsumoAConjuntoDTO = z.object({
  conjuntoId: z.string().min(3),
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

type ReemplazoPropuesta =
  | {
      ok: true;
      mode: "CREADA_SIN_REEMPLAZO";
      createdP1Id: number;
      message: string;

      // âœ… NUEVO: info UX (solo si se moviÃ³)
      ajustadaAutomaticamente?: boolean;
      motivoAjuste?: string;

      // âœ… NUEVO: solicitado vs asignado
      solicitadaInicio?: Date;
      solicitadaFin?: Date;
      asignadaInicio?: Date;
      asignadaFin?: Date;
    }
  | {
      ok: true;
      mode: "AUTO_REEMPLAZO_P3";
      createdP1Id: number;
      reemplazadasIds: number[];
      info: {
        motivo: string;
        reemplazadas: Array<{
          id: number;
          prioridad: number;
          descripcion: string;
          fechaInicio: Date;
          fechaFin: Date;
        }>;
      };
    }
  | {
      ok: true;
      mode: "REQUIERE_CONFIRMACION_P2" | "REQUIERE_CONFIRMACION_P1";
      message: string;
      prioridadObjetivo: 1 | 2;
      estiloConfirmacion: "warning" | "danger";
      colorConfirmacion: "amber" | "red";
      tituloConfirmacion: string;
      requiereMotivo: boolean;
      opciones: Array<{
        reemplazarIds: number[];
        resumen: string;
        tareas: Array<{
          id: number;
          tipo: string;
          prioridad: number;
          descripcion: string;
          fechaInicio: Date;
          fechaFin: Date;
        }>;
      }>;
      slotSugerido?: { fechaInicio: Date; fechaFin: Date };
    }
  | {
      ok: false;
      reason: "NO_ES_P1" | "SIN_CONJUNTO" | "SIN_HUECO";
      message: string;
    };

const EMPRESA_ID_FIJA = "901191875-4";

function normalizarPatronJornada(
  jornadaLaboral: JornadaLaboral | null | undefined,
  patronJornada: PatronJornada | null | undefined,
): PatronJornada | null {
  return jornadaLaboral === JornadaLaboral.MEDIO_TIEMPO
    ? (patronJornada ?? null)
    : null;
}

const ESTADOS_NO_BLOQUEAN_AGENDA = [
  EstadoTarea.PENDIENTE_REPROGRAMACION,
  EstadoTarea.COMPLETADA,
  EstadoTarea.APROBADA,
  EstadoTarea.RECHAZADA,
  EstadoTarea.NO_COMPLETADA,
  EstadoTarea.PENDIENTE_APROBACION,
] as const;

const ESTADOS_REEMPLAZABLES = [
  EstadoTarea.ASIGNADA,
  EstadoTarea.EN_PROCESO,
] as const;

const ESTADOS_BLOQUEADOS_PARA_REEMPLAZO = [
  EstadoTarea.APROBADA,
  EstadoTarea.PENDIENTE_REPROGRAMACION,
] as const;

export class GerenteService {
  constructor(private prisma: PrismaClient) {}

  private async resolverEmpresaNit(): Promise<string> {
    const empresaFija = await this.prisma.empresa.findUnique({
      where: { nit: EMPRESA_ID_FIJA },
      select: { nit: true },
    });

    if (empresaFija) return empresaFija.nit;

    const primeraEmpresa = await this.prisma.empresa.findFirst({
      select: { nit: true },
      orderBy: { id: "asc" },
    });

    if (primeraEmpresa) return primeraEmpresa.nit;

    throw new Error("No hay empresa registrada. Crea primero una empresa para poder crear/listar conjuntos.");
  }

  private extraerAsignadorId(payload: unknown): string | null {
    if (!payload || typeof payload !== "object") return null;
    const raw = (payload as { asignadorId?: unknown }).asignadorId;
    if (raw == null) return null;
    const id = String(raw).trim();
    return id.length > 0 ? id : null;
  }

  /* ===================== EMPRESA ===================== */

  async crearEmpresa(payload: unknown) {
    const dto = z
      .object({ nombre: z.string().min(3), nit: z.string().min(3) })
      .parse(payload);

    const existe = await this.prisma.empresa.findUnique({
      where: { nit: dto.nit },
    });
    if (existe) throw new Error("Ya existe una empresa con este NIT.");

    return this.prisma.empresa.create({
      data: { nombre: dto.nombre, nit: dto.nit },
    });
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

    if (existeId) throw new Error("Ya existe un usuario con esa cÃ©dula.");
    if (existeCorreo) throw new Error("Ya existe un usuario con ese correo.");

    const hash = await bcrypt.hash(dto.contrasena, 10);

    const creado = await this.prisma.usuario.create({
      data: {
        id: dto.id,
        nombre: dto.nombre,
        correo: dto.correo,
        contrasena: hash,
        rol: dto.rol,
        telefono: dto.telefono,
        fechaNacimiento: dto.fechaNacimiento,
        direccion: dto.direccion,
        estadoCivil: dto.estadoCivil,
        numeroHijos: dto.numeroHijos,
        padresVivos: dto.padresVivos,
        tipoSangre: dto.tipoSangre,
        eps: dto.eps,
        fondoPensiones: dto.fondoPensiones,
        tallaCamisa: dto.tallaCamisa,
        tallaPantalon: dto.tallaPantalon,
        tallaCalzado: dto.tallaCalzado,
        tipoContrato: dto.tipoContrato,
        jornadaLaboral: dto.jornadaLaboral,
        activo: dto.activo ?? true,
        patronJornada: normalizarPatronJornada(dto.jornadaLaboral, dto.patronJornada),
      },
      select: usuarioPublicSelect,
    });

    return toUsuarioPublico(creado);
  }

  async editarUsuario(id: string, payload: unknown) {
    const dto = EditarUsuarioDTO.parse(payload);

    if (dto.correo) {
      const otro = await this.prisma.usuario.findUnique({
        where: { correo: dto.correo },
      });
      if (otro && (otro as any).id !== id)
        throw new Error("EMAIL_YA_REGISTRADO");
    }

    const data: any = { ...dto };

    if (Object.prototype.hasOwnProperty.call(dto, "jornadaLaboral")) {
      data.patronJornada = normalizarPatronJornada(
        dto.jornadaLaboral ?? null,
        dto.patronJornada ?? null,
      );
    } else if (Object.prototype.hasOwnProperty.call(dto, "patronJornada")) {
      data.patronJornada = dto.patronJornada ?? null;
    }
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
      this.prisma.usuario.findUnique({ where: { id: dto.Id } }),
    ]);
    if (!empresa) throw new Error("âŒ Empresa no encontrada con ese NIT.");
    if (!usuario) throw new Error("âŒ Usuario no encontrado.");
    if (usuario.rol !== Rol.gerente)
      throw new Error("El usuario no tiene rol 'gerente'.");

    return this.prisma.gerente.create({
      data: { id: dto.Id, empresaId: dto.empresaId! },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarAdministrador(payload: unknown) {
    const dto = CrearAdministradorDTO.parse(payload);
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: dto.Id },
    });
    if (!usuario) throw new Error("âŒ Usuario no encontrado.");
    if (usuario.rol !== Rol.administrador)
      throw new Error("El usuario no tiene rol 'administrador'.");

    return this.prisma.administrador.create({
      data: { id: dto.Id },
      include: { usuario: true, conjuntos: true },
    });
  }

  async asignarJefeOperaciones(payload: unknown) {
    const dto = CrearJefeOperacionesDTO.parse(payload);

    const [empresa, usuario] = await Promise.all([
      this.prisma.empresa.findFirst(), // ðŸ‘ˆ toma la primera empresa registrada
      this.prisma.usuario.findUnique({ where: { id: dto.Id } }),
    ]);

    if (!empresa) throw new Error("âŒ No hay empresa registrada.");
    if (!usuario) throw new Error("âŒ Usuario no encontrado.");
    if (usuario.rol !== Rol.jefe_operaciones)
      throw new Error("El usuario no tiene rol 'jefe_operaciones'.");

    return this.prisma.jefeOperaciones.create({
      data: {
        id: dto.Id, // FK al Usuario
        empresaId: empresa.nit, // ðŸ‘ˆ usamos el NIT de la empresa
      },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarSupervisor(payload: unknown) {
    const dto = CrearSupervisorDTO.parse(payload);

    const [empresa, usuario] = await Promise.all([
      this.prisma.empresa.findFirst(),
      this.prisma.usuario.findUnique({ where: { id: dto.Id } }),
    ]);

    if (!empresa) throw new Error("âŒ No hay empresa registrada.");
    if (!usuario) throw new Error("âŒ Usuario no encontrado.");
    if (usuario.rol !== Rol.supervisor)
      throw new Error("El usuario no tiene rol 'supervisor'.");

    return this.prisma.supervisor.create({
      data: {
        id: dto.Id,
        empresaId: empresa.nit,
      },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarOperario(payload: unknown) {
    const dto = CrearOperarioDTO.parse(payload);

    const [empresa, usuario] = await Promise.all([
      this.prisma.empresa.findFirst(),
      this.prisma.usuario.findUnique({ where: { id: dto.Id } }),
    ]);

    if (!empresa) throw new Error("âŒ No hay empresa registrada.");
    if (!usuario) throw new Error("âŒ Usuario no encontrado.");
    if (usuario.rol !== Rol.operario)
      throw new Error("El usuario no tiene rol 'operario'.");

    return this.prisma.operario.create({
      data: {
        id: dto.Id,
        empresaId: empresa.nit,
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

  async listarUsuarios(rol?: Rol): Promise<UsuarioPublico[]> {
    const where: { rol?: Rol } = rol ? { rol } : {};

    const usuarios = await this.prisma.usuario.findMany({
      where,
      select: usuarioPublicSelect,
      orderBy: { nombre: "asc" },
    });

    return usuarios.map(toUsuarioPublico);
  }

  /* ===================== CONJUNTOS ===================== */

  async crearConjunto(payload: unknown) {
    const dto = CrearConjuntoDTO.parse(payload);

    let administradorId: string | null = null;
    if (dto.administradorId) {
      const admin = await this.prisma.administrador.findUnique({
        where: { id: dto.administradorId },
      });
      if (!admin) {
        throw new Error("âŒ El administrador seleccionado no existe.");
      }
      administradorId = dto.administradorId;
    }

    const creado = await this.prisma.conjunto.create({
      data: {
        nit: dto.nit,
        nombre: dto.nombre,
        direccion: dto.direccion,
        correo: dto.correo,

        empresaId: await this.resolverEmpresaNit(),
        administradorId,

        fechaInicioContrato: dto.fechaInicioContrato ?? null,
        fechaFinContrato: dto.fechaFinContrato ?? null,
        activo: dto.activo,
        tipoServicio: dto.tipoServicio as any,
        valorMensual:
          dto.valorMensual != null
            ? new Prisma.Decimal(dto.valorMensual)
            : null,
        consignasEspeciales: dto.consignasEspeciales,
        valorAgregado: dto.valorAgregado,

        horarios:
          dto.horarios && dto.horarios.length
            ? {
                create: dto.horarios.map((h) => ({
                  dia: h.dia,
                  horaApertura: h.horaApertura,
                  horaCierre: h.horaCierre,

                  descansoInicio: h.descansoInicio ?? null,
                  descansoFin: h.descansoFin ?? null,
                })),
              }
            : undefined,

        ubicaciones:
          dto.ubicaciones && dto.ubicaciones.length
            ? {
                create: dto.ubicaciones.map((u) => ({
                  nombre: u.nombre,
                  elementos:
                    u.elementos && u.elementos.length
                      ? {
                          create: u.elementos.map((nombreElem) => ({
                            nombre: nombreElem,
                          })),
                        }
                      : undefined,
                })),
              }
            : undefined,
      },
      select: conjuntoPublicSelect,
    });

    return toConjuntoPublico(creado);
  }

  async listarConjuntos() {
    const conjuntos = await this.prisma.conjunto.findMany({
      where: {
        empresaId: await this.resolverEmpresaNit(),
      },
      include: {
        administrador: {
          include: { usuario: true },
        },
        operarios: {
          include: { usuario: true },
        },
        horarios: true,
        ubicaciones: {
          include: { elementos: true },
        },
      },
      orderBy: { nombre: "asc" },
    });

    return conjuntos;
  }

  async obtenerConjunto(conjuntoId: string) {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      include: {
        administrador: {
          include: {
            usuario: true,
          },
        },
        operarios: {
          include: {
            usuario: true,
          },
        },
        horarios: true,
        ubicaciones: {
          include: {
            elementos: true,
          },
        },
      },
    });

    if (!conjunto) {
      throw new Error("âŒ Conjunto no encontrado.");
    }

    return conjunto;
  }

  async editarConjunto(conjuntoId: string, payload: unknown) {
    const dto = EditarConjuntoDTO.parse(payload);

    const data: Prisma.ConjuntoUpdateInput = {};

    if (dto.nombre !== undefined) data.nombre = dto.nombre;
    if (dto.direccion !== undefined) data.direccion = dto.direccion;
    if (dto.correo !== undefined) data.correo = dto.correo;

    if (dto.administradorId !== undefined) {
      data.administrador = dto.administradorId
        ? {
            connect: { id: dto.administradorId },
          }
        : {
            disconnect: true,
          };
    }

    if (dto.empresaId !== undefined) {
      data.empresa = dto.empresaId
        ? {
            connect: { nit: dto.empresaId },
          }
        : {
            disconnect: true,
          };
    }

    if (dto.fechaInicioContrato !== undefined) {
      data.fechaInicioContrato = dto.fechaInicioContrato;
    }

    if (dto.fechaFinContrato !== undefined) {
      // si el front manda fechaFin explÃ­cita, la usamos tal cua
      data.fechaFinContrato = dto.fechaFinContrato;
    }

    if (dto.activo !== undefined) {
      data.activo = dto.activo;

      if (dto.activo === false && dto.fechaFinContrato === undefined) {
        data.fechaFinContrato = new Date();
      }
    }

    if (dto.valorMensual !== undefined) {
      data.valorMensual =
        dto.valorMensual != null ? new Prisma.Decimal(dto.valorMensual) : null;
    }

    if (dto.tipoServicio !== undefined) {
      data.tipoServicio = dto.tipoServicio as any;
    }

    if (dto.consignasEspeciales !== undefined) {
      data.consignasEspeciales = dto.consignasEspeciales;
    }

    if (dto.valorAgregado !== undefined) {
      data.valorAgregado = dto.valorAgregado;
    }

    if (dto.horarios !== undefined) {
      await this.prisma.conjuntoHorario.deleteMany({ where: { conjuntoId } });

      if (dto.horarios.length > 0) {
        data.horarios = {
          create: dto.horarios.map((h) => ({
            dia: h.dia,
            horaApertura: h.horaApertura,
            horaCierre: h.horaCierre,

            descansoInicio: h.descansoInicio ?? null,
            descansoFin: h.descansoFin ?? null,
          })),
        };
      }
    }

    if (dto.operariosIds !== undefined) {
      data.operarios = {
        set: dto.operariosIds.map((id) => ({ id })),
      };
    }

    if (dto.ubicaciones !== undefined) {
      data.ubicaciones = {
        deleteMany: {},
        create: dto.ubicaciones.map((u) => ({
          nombre: u.nombre,
          elementos:
            u.elementos && u.elementos.length
              ? {
                  create: u.elementos.map((nombreElem) => ({
                    nombre: nombreElem,
                  })),
                }
              : undefined,
        })),
      };
    }

    const actualizado = await this.prisma.conjunto.update({
      where: { nit: conjuntoId },
      data,
      select: conjuntoPublicSelect,
    });

    return toConjuntoPublico(actualizado);
  }

  async eliminarConjunto(conjuntoId: string) {
    const [tareasPendientes, maquinariaActivaEnConjunto] = await Promise.all([
      this.prisma.tarea.findMany({
        where: {
          conjuntoId,
          estado: { in: ["ASIGNADA", "EN_PROCESO", "PENDIENTE_APROBACION"] },
        },
        select: { id: true },
      }),
      this.prisma.maquinariaConjunto.findMany({
        where: {
          conjuntoId,
          estado: "ACTIVA",
        },
        select: { id: true },
      }),
    ]);

    if (tareasPendientes.length > 0)
      throw new Error("âŒ El conjunto tiene tareas pendientes.");
    if (maquinariaActivaEnConjunto.length > 0)
      throw new Error(
        "âŒ El conjunto tiene maquinaria activa asignada (propia o prestada).",
      );

    await this.prisma.$transaction(async (tx) => {
      const inventario = await tx.inventario.findUnique({
        where: { conjuntoId },
        select: { id: true },
      });

      if (inventario) {
        await tx.inventarioInsumo.deleteMany({
          where: { inventarioId: inventario.id },
        });

        await tx.inventario.delete({ where: { conjuntoId } });
      }

      await tx.maquinariaConjunto.deleteMany({ where: { conjuntoId } });
      await tx.solicitudInsumo.deleteMany({ where: { conjuntoId } });
      await tx.solicitudMaquinaria.deleteMany({ where: { conjuntoId } });
      await tx.solicitudTarea.deleteMany({ where: { conjuntoId } });

      await tx.conjunto.delete({ where: { nit: conjuntoId } });
    });
  }

  async asignarOperarioAConjunto(args: {
    conjuntoId: string;
    operarioId: string | number;
  }) {
    const { conjuntoId, operarioId } = args;

    return this.prisma.operario.update({
      where: { id: operarioId.toString() },
      data: {
        conjuntos: {
          connect: { nit: conjuntoId },
        },
      },
    });
  }

  async quitarOperarioDeConjunto(params: {
    conjuntoId: string;
    operarioId: string;
  }) {
    const { conjuntoId, operarioId } = params;

    await this.prisma.conjunto.update({
      where: { nit: conjuntoId },
      data: {
        operarios: {
          disconnect: { id: operarioId },
        },
      },
    });
  }

  /* ===================== INVENTARIO / INSUMOS ===================== */

  async agregarInsumoAConjunto(payload: unknown) {
    const dto = AgregarInsumoAConjuntoDTO.parse(payload);

    const inventario = await this.prisma.inventario.findUnique({
      where: { conjuntoId: dto.conjuntoId },
    });
    if (!inventario)
      throw new Error(
        `âŒ No se encontrÃ³ inventario para el conjunto ${dto.conjuntoId}`,
      );

    const existente = await this.prisma.inventarioInsumo.findUnique({
      where: {
        inventarioId_insumoId: {
          inventarioId: inventario.id,
          insumoId: dto.insumoId,
        },
      },
    });

    if (existente) {
      return this.prisma.inventarioInsumo.update({
        where: { id: existente.id },
        data: { cantidad: { increment: dto.cantidad } },
      });
    }

    return this.prisma.inventarioInsumo.create({
      data: {
        inventarioId: inventario.id,
        insumoId: dto.insumoId,
        cantidad: dto.cantidad,
      },
    });
  }

  /** CatÃ¡logo corporativo: empresaId = null (ajusta si usas catÃ¡logo por empresa) */
  async agregarInsumoAlCatalogo(payload: unknown, empresaId: string) {
    const dto = CrearInsumoDTO.parse(payload);

    const existe = await this.prisma.insumo.findFirst({
      where: { empresaId, nombre: dto.nombre, unidad: dto.unidad },
      select: { id: true },
    });
    if (existe)
      throw new Error(
        "ðŸš« Ya existe un insumo con ese nombre y unidad en el catÃ¡logo.",
      );

    return this.prisma.insumo.create({
      data: {
        nombre: dto.nombre,
        unidad: dto.unidad,
        empresaId, // âœ… ya no null
        categoria: dto.categoria,
        umbralBajo: dto.umbralBajo ?? null,
      },
      select: insumoPublicSelect,
    });
  }

  async listarCatalogo(empresaId: string) {
    return this.prisma.insumo.findMany({
      where: { empresaId },
      select: insumoPublicSelect,
    });
  }

  async listarSupervisores() {
    const supervisores = await this.prisma.usuario.findMany({
      where: {
        rol: Rol.supervisor, // ya importaste Rol arriba
      },
      select: usuarioPublicSelect,
      orderBy: { nombre: "asc" },
    });

    return supervisores.map(toUsuarioPublico);
  }

  /* ===================== TAREAS ===================== */

  private prioridadesPreventivaReemplazables(prioridadCorrectiva: number): number[] {
    if (prioridadCorrectiva <= 1) return [1, 2, 3];
    if (prioridadCorrectiva === 2) return [2, 3];
    return [3];
  }

  private tipoOpcionReemplazo(
    prioridadCorrectiva: number,
    prioridadPreventiva: number,
  ): "AUTO" | "CONFIRM_WARN" | "CONFIRM_DANGER" | null {
    const permitidas =
      this.prioridadesPreventivaReemplazables(prioridadCorrectiva);
    if (!permitidas.includes(prioridadPreventiva)) return null;
    if (prioridadPreventiva === 3) return "AUTO";
    if (prioridadPreventiva === 2) return "CONFIRM_WARN";
    if (prioridadPreventiva === 1) return "CONFIRM_DANGER";
    return null;
  }

  private dateAtMinute(base: Date, minute: number) {
    const d = new Date(base);
    d.setHours(0, 0, 0, 0);
    d.setMinutes(Math.max(0, Math.min(1440, minute)));
    return d;
  }

  private isSameDay(a: Date, b: Date) {
    return (
      a.getFullYear() === b.getFullYear() &&
      a.getMonth() === b.getMonth() &&
      a.getDate() === b.getDate()
    );
  }

  private buildReemplazoMotivo(params: {
    prioridadCorrectiva: number;
    prioridadPreventiva: number;
    resultado:
      | "CANCELADA_AUTO"
      | "CANCELADA_MANUAL"
      | "CANCELADA_SIN_CUPO"
      | "REPROGRAMADA";
    motivoUsuario?: string | null;
    accion?: "CANCELAR" | "REPROGRAMAR";
  }) {
    const { prioridadCorrectiva, prioridadPreventiva, resultado, motivoUsuario, accion } =
      params;
    const motivo = (motivoUsuario ?? "").trim();
    const parts = [
      `REEMPLAZO_CORRECTIVA_P${prioridadCorrectiva}`,
      `PREVENTIVA_P${prioridadPreventiva}`,
      `RESULTADO:${resultado}`,
      `ACCION:${accion ?? (resultado === "REPROGRAMADA" ? "REPROGRAMAR" : "CANCELAR")}`,
    ];
    if (motivo) parts.push(`MOTIVO_USUARIO:${motivo}`);
    return parts.join("; ");
  }

  private async buscarOpcionesReemplazoParaCorrectiva(params: {
    prisma: PrismaClient;
    conjuntoId: string;
    inicio: Date;
    fin: Date;
    prioridadCorrectiva: number;
    operariosIds: string[];
  }): Promise<{
    autoOptions: Array<{
      reemplazarIds: number[];
      prioridadObjetivo: number;
      resumen: string;
      tareas: Array<{
        id: number;
        tipo: string;
        prioridad: number;
        descripcion: string;
        fechaInicio: Date;
        fechaFin: Date;
      }>;
    }>;
    confirmOptions: Array<{
      reemplazarIds: number[];
      prioridadObjetivo: number;
      tipoConfirmacion: "CONFIRM_WARN" | "CONFIRM_DANGER";
      resumen: string;
      tareas: Array<{
        id: number;
        tipo: string;
        prioridad: number;
        descripcion: string;
        fechaInicio: Date;
        fechaFin: Date;
      }>;
    }>;
  }> {
    const {
      prisma,
      conjuntoId,
      inicio,
      fin,
      prioridadCorrectiva,
      operariosIds,
    } = params;

    const prioridadesPermitidas =
      this.prioridadesPreventivaReemplazables(prioridadCorrectiva);

    const candidatas = await prisma.tarea.findMany({
      where: {
        conjuntoId,
        tipo: "PREVENTIVA" as any,
        prioridad: { in: prioridadesPermitidas },
        fechaInicio: { lt: fin },
        fechaFin: { gt: inicio },
        estado: { in: ESTADOS_REEMPLAZABLES as any },
        ...(operariosIds.length
          ? { operarios: { some: { id: { in: operariosIds } } } }
          : {}),
      },
      select: {
        id: true,
        tipo: true,
        prioridad: true,
        descripcion: true,
        fechaInicio: true,
        fechaFin: true,
        grupoPlanId: true,
      },
      orderBy: [{ prioridad: "desc" }, { fechaInicio: "asc" }],
    });

    const autoOptions: Array<{
      reemplazarIds: number[];
      prioridadObjetivo: number;
      resumen: string;
      tareas: Array<{
        id: number;
        tipo: string;
        prioridad: number;
        descripcion: string;
        fechaInicio: Date;
        fechaFin: Date;
      }>;
    }> = [];

    const confirmOptions: Array<{
      reemplazarIds: number[];
      prioridadObjetivo: number;
      tipoConfirmacion: "CONFIRM_WARN" | "CONFIRM_DANGER";
      resumen: string;
      tareas: Array<{
        id: number;
        tipo: string;
        prioridad: number;
        descripcion: string;
        fechaInicio: Date;
        fechaFin: Date;
      }>;
    }> = [];

    const seen = new Set<string>();
    const gruposElegibles: Array<{
      ids: number[];
      tareas: Array<{
        id: number;
        tipo: string;
        prioridad: number;
        descripcion: string;
        fechaInicio: Date;
        fechaFin: Date;
      }>;
      prioridadObjetivo: number;
      tipoOpcion: "AUTO" | "CONFIRM_WARN" | "CONFIRM_DANGER";
    }> = [];

    for (const cand of candidatas) {
      const idsAExcluir = cand.grupoPlanId
        ? (
            await prisma.tarea.findMany({
              where: { grupoPlanId: cand.grupoPlanId },
              select: { id: true },
            })
          ).map((x) => x.id)
        : [cand.id];

      const key = idsAExcluir.slice().sort((a, b) => a - b).join(",");
      if (seen.has(key)) continue;
      seen.add(key);

      const tareas = await prisma.tarea.findMany({
        where: { id: { in: idsAExcluir } },
        select: {
          id: true,
          tipo: true,
          prioridad: true,
          descripcion: true,
          fechaInicio: true,
          fechaFin: true,
        },
        orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
      });

      if (!tareas.length) continue;
      if (
        !tareas.every(
          (t) =>
            t.tipo === "PREVENTIVA" &&
            prioridadesPermitidas.includes(t.prioridad ?? 2),
        )
      ) {
        continue;
      }

      const prioridadObjetivo = Math.min(...tareas.map((t) => t.prioridad ?? 2));
      const tipoOpcion = this.tipoOpcionReemplazo(
        prioridadCorrectiva,
        prioridadObjetivo,
      );
      if (!tipoOpcion) continue;
      gruposElegibles.push({
        ids: idsAExcluir,
        tareas,
        prioridadObjetivo,
        tipoOpcion,
      });

      const conflictoRestante = await prisma.tarea.findFirst({
        where: {
          conjuntoId,
          id: { notIn: idsAExcluir },
          fechaInicio: { lt: fin },
          fechaFin: { gt: inicio },
          estado: { notIn: ESTADOS_NO_BLOQUEAN_AGENDA as any },
          ...(operariosIds.length
            ? { operarios: { some: { id: { in: operariosIds } } } }
            : {}),
        },
        select: { id: true },
      });
      if (conflictoRestante) continue;

      const first = tareas[0];
      const resumen =
        tareas.length === 1
          ? `Reemplazar [P${prioridadObjetivo}] ${first.descripcion} (${first.fechaInicio.toISOString()} - ${first.fechaFin.toISOString()})`
          : `Reemplazar grupo (${tareas.length} tareas) - Ej: ${first.descripcion}`;

      if (tipoOpcion === "AUTO") {
        autoOptions.push({
          reemplazarIds: idsAExcluir,
          prioridadObjetivo,
          resumen,
          tareas,
        });
      } else {
        confirmOptions.push({
          reemplazarIds: idsAExcluir,
          prioridadObjetivo,
          tipoConfirmacion: tipoOpcion,
          resumen,
          tareas,
        });
      }

      if (autoOptions.length + confirmOptions.length >= 20) break;
    }

    // Si ninguna opcion individual libera completamente el horario,
    // probar la combinacion de todas las preventivas bloqueantes elegibles.
    if (!autoOptions.length && !confirmOptions.length && gruposElegibles.length >= 2) {
      const idsCombinados = Array.from(
        new Set(gruposElegibles.flatMap((g) => g.ids)),
      ).sort((a, b) => a - b);

      if (idsCombinados.length) {
        const keyCombo = idsCombinados.join(",");
        if (!seen.has(keyCombo)) {
          const tareasCombo = await prisma.tarea.findMany({
            where: { id: { in: idsCombinados } },
            select: {
              id: true,
              tipo: true,
              prioridad: true,
              descripcion: true,
              fechaInicio: true,
              fechaFin: true,
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
          });

          const conflictoRestante = await prisma.tarea.findFirst({
            where: {
              conjuntoId,
              id: { notIn: idsCombinados },
              fechaInicio: { lt: fin },
              fechaFin: { gt: inicio },
              estado: { notIn: ESTADOS_NO_BLOQUEAN_AGENDA as any },
              ...(operariosIds.length
                ? { operarios: { some: { id: { in: operariosIds } } } }
                : {}),
            },
            select: { id: true },
          });

          if (!conflictoRestante && tareasCombo.length) {
            const prioridadObjetivo = Math.min(
              ...tareasCombo.map((t) => t.prioridad ?? 2),
            );
            const tipoOpcion = this.tipoOpcionReemplazo(
              prioridadCorrectiva,
              prioridadObjetivo,
            );

            if (tipoOpcion) {
              const listado = tareasCombo
                .map((t) => `#${t.id}(P${t.prioridad ?? 2})`)
                .join(", ");
              const resumen =
                `Reemplazar ${tareasCombo.length} preventivas que bloquean el horario: ` +
                listado;

              if (tipoOpcion === "AUTO") {
                autoOptions.push({
                  reemplazarIds: idsCombinados,
                  prioridadObjetivo,
                  resumen,
                  tareas: tareasCombo,
                });
              } else {
                confirmOptions.push({
                  reemplazarIds: idsCombinados,
                  prioridadObjetivo,
                  tipoConfirmacion: tipoOpcion,
                  resumen,
                  tareas: tareasCombo,
                });
              }
            }
          }
        }
      }
    }

    return { autoOptions, confirmOptions };
  }

  private async buscarHuecoReprogramacionEnMes(params: {
    tx: Prisma.TransactionClient;
    conjuntoId: string;
    tarea: {
      id: number;
      fechaInicio: Date;
      fechaFin: Date;
      duracionMinutos: number | null;
      operarios: Array<{ id: string }>;
    };
    fechaDesde: Date;
  }): Promise<{ fechaInicio: Date; fechaFin: Date } | null> {
    const { tx, conjuntoId, tarea, fechaDesde } = params;
    const durMin = Math.max(
      1,
      tarea.duracionMinutos ??
        Math.round((tarea.fechaFin.getTime() - tarea.fechaInicio.getTime()) / 60000),
    );

    const base = new Date(
      Math.max(tarea.fechaInicio.getTime(), fechaDesde.getTime()),
    );
    base.setHours(0, 0, 0, 0);

    const targetYear = tarea.fechaInicio.getFullYear();
    const targetMonth = tarea.fechaInicio.getMonth();

    const operariosIds = tarea.operarios.map((o) => String(o.id));
    const estadosNoBloqueantes = ESTADOS_NO_BLOQUEAN_AGENDA as any;

    for (let guard = 0; guard < 40; guard++) {
      if (
        base.getFullYear() !== targetYear ||
        base.getMonth() !== targetMonth
      ) {
        return null;
      }

      const dia = dateToDiaSemana(base);
      const horario = await tx.conjuntoHorario.findFirst({
        where: { conjuntoId, dia: dia as any },
      });
      if (horario) {
        const startMin = toMin(horario.horaApertura);
        const endMin = toMin(horario.horaCierre);
        const desiredStartMin = this.isSameDay(base, fechaDesde)
          ? Math.max(startMin, toMinOfDaySafe(fechaDesde))
          : startMin;

        if (desiredStartMin < endMin) {
          const bloqueosDescanso = buildBloqueosPorDescanso({
            startMin,
            endMin,
            descansoStartMin: horario.descansoInicio
              ? toMin(horario.descansoInicio)
              : undefined,
            descansoEndMin: horario.descansoFin
              ? toMin(horario.descansoFin)
              : undefined,
          } as any);

          const bloqueosPatron = await buildBloqueosPorPatronJornada({
            prisma: tx as any,
            fechaDia: base,
            horarioDia: { startMin, endMin } as any,
            operariosIds,
          });
          const bloqueos = [...bloqueosDescanso, ...bloqueosPatron];

          const iniDia = new Date(
            base.getFullYear(),
            base.getMonth(),
            base.getDate(),
            0,
            0,
            0,
            0,
          );
          const finDia = new Date(
            base.getFullYear(),
            base.getMonth(),
            base.getDate(),
            23,
            59,
            59,
            999,
          );

          const ocupadas = await tx.tarea.findMany({
            where: {
              conjuntoId,
              id: { not: tarea.id },
              fechaInicio: { lte: finDia },
              fechaFin: { gte: iniDia },
              estado: { notIn: estadosNoBloqueantes },
              ...(operariosIds.length
                ? { operarios: { some: { id: { in: operariosIds } } } }
                : {}),
            },
            select: { fechaInicio: true, fechaFin: true },
          });

          const ocupados = mergeIntervalos(
            ocupadas.map((t) => ({
              i: toMinOfDaySafe(t.fechaInicio),
              f: toMinOfDaySafe(t.fechaFin),
            })),
          );

          const bloque = buscarHuecoDiaConSplitEarliest({
            startMin,
            endMin,
            durMin,
            ocupados,
            bloqueos,
            desiredStartMin,
            maxBloques: 1,
          });

          if (bloque?.length) {
            return {
              fechaInicio: this.dateAtMinute(base, bloque[0].i),
              fechaFin: this.dateAtMinute(base, bloque[0].f),
            };
          }
        }
      }

      base.setDate(base.getDate() + 1);
      base.setHours(0, 0, 0, 0);
    }

    return null;
  }

  async asignarTarea(payload: unknown) {
    const asignadorId = this.extraerAsignadorId(payload);
    const dto = CrearTareaDTO.parse(payload);

    const inicio = dto.fechaInicio;
    const periodoAnio = inicio.getFullYear();
    const periodoMes = inicio.getMonth() + 1;

    const durMin =
      dto.duracionMinutos ??
      (dto.duracionHoras
        ? Math.max(1, Math.round(dto.duracionHoras * 60))
        : undefined) ??
      (dto.fechaFin
        ? Math.max(
            1,
            Math.round((dto.fechaFin.getTime() - inicio.getTime()) / 60000),
          )
        : undefined);

    if (!durMin) {
      return {
        ok: false,
        reason: "FALTA_DURACION",
        message: "Debe indicar duraciÃ³n.",
      };
    }

    const fin = dto.fechaFin ?? new Date(inicio.getTime() + durMin * 60000);

    const operariosIds =
      dto.operariosIds?.map(String) ??
      (dto.operarioId ? [String(dto.operarioId)] : []);

    const tipo = (dto.tipo ?? "CORRECTIVA") as any;
    const prioridad = dto.prioridad ?? 2;

    const maquinariaIds: number[] = Array.isArray((dto as any).maquinariaIds)
      ? (dto as any).maquinariaIds
          .map((x: any) => Number(x))
          .filter((n: number) => Number.isFinite(n) && n > 0)
      : [];

    // =========================
    // Helpers de logÃ­stica (maquinaria)
    // =========================
    const LOGISTICA_DOW = new Set([1, 3, 6]); // lun, miÃ©, sÃ¡b

    const startDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
    const endDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);

    const isLogistica = (d: Date) => LOGISTICA_DOW.has(d.getDay());

    const entregaLogistica = (uso: Date) => {
      const base = startDay(uso);
      if (isLogistica(base)) return base;
      for (let i = 1; i <= 7; i++) {
        const d = new Date(base);
        d.setDate(d.getDate() - i);
        if (isLogistica(d)) return startDay(d);
      }
      return base;
    };

    const recogidaLogistica = (uso: Date) => {
      const base = startDay(uso);
      for (let i = 1; i <= 14; i++) {
        const d = new Date(base);
        d.setDate(d.getDate() + i);
        if (isLogistica(d)) return startDay(d);
      }
      return base;
    };

    const esPropia = (tipoTenencia: any) => {
      const v = String(tipoTenencia ?? "").toUpperCase();
      return v.includes("PROPIA") || v.includes("CONJUNTO");
    };

    // =========================
    // TRANSACCIÃ“N
    // =========================
    return this.prisma.$transaction(async (tx) => {
      // âœ… 0) Validar solape de operarios (bloque duro)
      if (dto.conjuntoId && operariosIds.length) {
        const choqueOperario = await tx.tarea.findFirst({
          where: {
            conjuntoId: dto.conjuntoId,
            borrador: false,
            estado: {
              notIn: ESTADOS_NO_BLOQUEAN_AGENDA as any,
            },
            // solape
            fechaInicio: { lt: fin },
            fechaFin: { gt: inicio },
            operarios: { some: { id: { in: operariosIds } } },
          },
          select: { id: true, fechaInicio: true, fechaFin: true },
        });

        if (choqueOperario) {
          // âœ… 0.1) Intentar sugerir hueco en el dÃ­a (si hay conjunto y horario)
          const ds = dateToDiaSemana(inicio);
          const horario = await tx.conjuntoHorario.findFirst({
            where: { conjuntoId: dto.conjuntoId, dia: ds as any },
          });

          if (horario) {
            const startMin = toMin(horario.horaApertura);
            const endMin = toMin(horario.horaCierre);

            const bloqueosDescanso = buildBloqueosPorDescanso({
              startMin,
              endMin,
              descansoStartMin: horario.descansoInicio
                ? toMin(horario.descansoInicio)
                : undefined,
              descansoEndMin: horario.descansoFin
                ? toMin(horario.descansoFin)
                : undefined,
            } as any);

            const bloqueosPatron = await buildBloqueosPorPatronJornada({
              prisma: tx as any,
              fechaDia: inicio,
              horarioDia: { startMin, endMin } as any,
              operariosIds,
            });

            const bloqueos = [...bloqueosDescanso, ...bloqueosPatron];

            const agenda = await buildAgendaPorOperarioDia({
              prisma: tx as any,
              conjuntoId: dto.conjuntoId,
              fechaDia: inicio,
              operariosIds,
              incluirBorrador: false,
              bloqueosGlobales: bloqueos,
              excluirEstados: ESTADOS_NO_BLOQUEAN_AGENDA as any,
            });

            const all: Intervalo[] = [];
            for (const opId of Object.keys(agenda)) all.push(...agenda[opId]);
            const ocupadosGlobal = mergeIntervalos(all);

            const desiredStartMin = toMinOfDaySafe(inicio);

            const bloques = buscarHuecoDiaConSplitEarliest({
              startMin,
              endMin,
              durMin,
              ocupados: ocupadosGlobal,
              bloqueos,
              desiredStartMin,
              maxBloques: 2,
            });

            if (bloques) {
              const sugStart = bloques[0].i;
              const sugEnd = bloques[bloques.length - 1].f;

              const sugIni = new Date(inicio);
              sugIni.setHours(0, 0, 0, 0);
              sugIni.setMinutes(sugStart);

              const sugFin = new Date(inicio);
              sugFin.setHours(0, 0, 0, 0);
              sugFin.setMinutes(sugEnd);

              return {
                ok: false,
                reason: "HAY_SOLAPE_CON_TAREAS_EXISTENTES",
                message: "Ese horario ya estÃ¡ ocupado por otra tarea.",
                suggestedInicio: sugIni,
                suggestedFin: sugFin,
              };
            }
          }

          // sin hueco sugerible
          return {
            ok: false,
            reason: "HAY_SOLAPE_CON_TAREAS_EXISTENTES",
            message:
              "Ese horario ya estÃ¡ ocupado y no se encontrÃ³ hueco en el dÃ­a.",
          };
        }
      }

      // 1ï¸âƒ£ Crear la tarea
      const tarea = await tx.tarea.create({
        data: {
          descripcion: dto.descripcion,
          fechaInicio: inicio,
          fechaFin: fin,
          duracionMinutos: durMin,
          tipo,
          prioridad,
          estado: EstadoTarea.ASIGNADA,
          borrador: false,
          periodoAnio,
          periodoMes,
          ubicacionId: dto.ubicacionId,
          elementoId: dto.elementoId,
          conjuntoId: dto.conjuntoId ?? null,
          supervisorId:
            dto.supervisorId != null ? String(dto.supervisorId) : null,
          ...(operariosIds.length
            ? { operarios: { connect: operariosIds.map((id) => ({ id })) } }
            : {}),
        },
        select: { id: true },
      });

      // 2ï¸âƒ£ Resolver maquinaria por conjunto
      if (dto.conjuntoId && maquinariaIds.length) {
        const registros = await tx.maquinariaConjunto.findMany({
          where: {
            conjuntoId: dto.conjuntoId,
            maquinariaId: { in: maquinariaIds },
            estado: "ACTIVA",
          },
          select: { maquinariaId: true, tipoTenencia: true },
        });

        const tenenciaMap = new Map<number, any>();
        for (const r of registros)
          tenenciaMap.set(r.maquinariaId, r.tipoTenencia);

        for (const maqId of maquinariaIds) {
          const propia = esPropia(tenenciaMap.get(maqId));

          let reservaInicio: Date;
          let reservaFin: Date;
          let obs: string;

          if (propia) {
            reservaInicio = inicio;
            reservaFin = fin;
            obs = "Reserva maquinaria propia (uso real)";
          } else {
            const entrega = entregaLogistica(inicio);
            const recogida = recogidaLogistica(fin);
            reservaInicio = startDay(entrega);
            reservaFin = endDay(recogida);
            obs = `Reserva logÃ­stica (${entrega.toDateString()} â†’ ${recogida.toDateString()})`;
          }

          // Validar solape REAL maquinaria
          const choque = await tx.usoMaquinaria.findFirst({
            where: {
              maquinariaId: maqId,
              fechaInicio: { lt: reservaFin },
              fechaFin: { gt: reservaInicio },
            },
          });

          if (choque) {
            throw new Error(
              `MAQUINARIA_OCUPADA: maquinaria ${maqId} ya estÃ¡ reservada`,
            );
          }

          // Crear uso
          await tx.usoMaquinaria.create({
            data: {
              tarea: { connect: { id: tarea.id } },
              maquinaria: { connect: { id: maqId } },
              fechaInicio: reservaInicio,
              fechaFin: reservaFin,
              observacion: obs,
            },
          });

          await tx.maquinariaConjunto.updateMany({
            where: {
              conjuntoId: dto.conjuntoId,
              maquinariaId: maqId,
              estado: "ACTIVA",
            },
            data: { tareaId: tarea.id },
          });
        }
      }

      if (operariosIds.length) {
        const notificaciones = new NotificacionService(tx as any);
        await notificaciones.notificarAsignacionTareaOperarios({
          tareaId: tarea.id,
          descripcionTarea: dto.descripcion,
          conjuntoId: dto.conjuntoId ?? null,
          operariosIds,
          asignadorId,
        });
      }

      return {
        ok: true,
        message: "Tarea creada correctamente",
        tareaId: tarea.id,
      };
    });
  }

  async crearCorrectivaConReglas(payload: unknown): Promise<any> {
    const dto = CrearTareaDTO.parse(payload);
    const tipo = String(dto.tipo ?? "CORRECTIVA").toUpperCase();
    const prioridad = Number(dto.prioridad ?? 2);

    if (tipo !== "CORRECTIVA") {
      return {
        ok: false,
        reason: "NO_ES_CORRECTIVA",
        message: "Solo aplica para tareas correctivas.",
      };
    }
    if (!dto.conjuntoId) {
      return {
        ok: false,
        reason: "SIN_CONJUNTO",
        message: "conjuntoId es obligatorio.",
      };
    }

    const inicio = dto.fechaInicio;
    const durMin =
      dto.duracionMinutos ??
      (dto.duracionHoras
        ? Math.max(1, Math.round(dto.duracionHoras * 60))
        : undefined) ??
      (dto.fechaFin
        ? Math.max(
            1,
            Math.round((dto.fechaFin.getTime() - inicio.getTime()) / 60000),
          )
        : undefined);
    if (!durMin) {
      return {
        ok: false,
        reason: "FALTA_DURACION",
        message: "Debe indicar duraciÃ³n.",
      };
    }
    const fin = dto.fechaFin ?? new Date(inicio.getTime() + durMin * 60000);
    const operariosIds =
      dto.operariosIds?.map(String) ??
      (dto.operarioId ? [String(dto.operarioId)] : []);

    // 1) Intentar creación normal exacta en el horario solicitado.
    let intento: any = await this.asignarTarea(dto);
    if (intento?.ok === true) {
      // Validación defensiva: no dejar superposiciones reales por operario.
      const createdId = Number(intento?.tareaId ?? 0);
      if (createdId > 0 && dto.conjuntoId && operariosIds.length) {
        const solapeInconsistente = await this.prisma.tarea.findFirst({
          where: {
            id: { not: createdId },
            conjuntoId: dto.conjuntoId,
            fechaInicio: { lt: fin },
            fechaFin: { gt: inicio },
            estado: {
              notIn: ESTADOS_NO_BLOQUEAN_AGENDA as any,
            },
            operarios: { some: { id: { in: operariosIds } } },
          },
          select: { id: true },
        });

        if (solapeInconsistente) {
          try {
            await this.eliminarTarea(this.prisma as any, createdId);
          } catch {
            return {
              ok: false,
              reason: "SOLAPE_POST_CREACION",
              message:
                "Se detecto superposicion despues de crear la tarea y no fue posible revertirla automaticamente.",
            };
          }

          intento = {
            ok: false,
            reason: "HAY_SOLAPE_CON_TAREAS_EXISTENTES",
            message:
              "Ese horario ya esta ocupado por otra tarea del operario seleccionado.",
          };
        }
      }
    }

    if (intento?.ok === true) {
      return {
        ok: true,
        mode: "CREADA_SIN_REEMPLAZO",
        createdId: intento.tareaId,
        message: intento.message ?? "Tarea creada correctamente.",
      };
    }

    // 2) Si no falló por solape, devolver error normal.
    if (intento?.reason !== "HAY_SOLAPE_CON_TAREAS_EXISTENTES") {
      return {
        ok: false,
        reason: intento?.reason ?? "SIN_HUECO",
        message: intento?.message ?? "No se pudo crear la tarea.",
      };
    }

    // 3) Buscar opciones de reemplazo permitidas por prioridad.
    const opciones = await this.buscarOpcionesReemplazoParaCorrectiva({
      prisma: this.prisma,
      conjuntoId: dto.conjuntoId,
      inicio,
      fin,
      prioridadCorrectiva: prioridad,
      operariosIds,
    });

    const suggestedInicio = intento?.suggestedInicio ?? null;
    const suggestedFin = intento?.suggestedFin ?? null;
    const hasSuggested = Boolean(suggestedInicio && suggestedFin);

    if (!opciones.autoOptions.length && !opciones.confirmOptions.length) {
      return {
        ok: false,
        reason: intento?.reason ?? "SIN_HUECO",
        message:
          intento?.message ??
          "No hay hueco y no hay reemplazos viables.",
        suggestedInicio,
        suggestedFin,
      };
    }

    // 4) Auto reemplazo solo cuando no hay hueco sugerido alterno.
    if (
      !hasSuggested &&
      opciones.autoOptions.length > 0 &&
      opciones.confirmOptions.length === 0
    ) {
      const autoPick = opciones.autoOptions[0];
      const autoResult = await this.asignarTareaConReemplazoV2({
        tarea: dto,
        reemplazarIds: autoPick.reemplazarIds,
        accionReemplazadas: "CANCELAR",
      });

      if (autoResult?.ok) {
        return {
          ok: true,
          mode: "AUTO_REEMPLAZO",
          message:
            "Se reemplazÃ³ automÃ¡ticamente una preventiva de menor prioridad.",
          createdId: autoResult.createdCorrectivaId,
          reemplazos: autoResult.reemplazos ?? [],
          autoReplaced: autoResult.reemplazos ?? [],
          reemplazadasIds: autoResult.reemplazadasIds ?? [],
          reprogramadasIds: autoResult.reprogramadasIds ?? [],
          canceladasIds: autoResult.canceladasIds ?? [],
          canceladasSinCupoIds: autoResult.canceladasSinCupoIds ?? [],
          noCompletadasIds: autoResult.noCompletadasIds ?? [],
        };
      }

      return {
        ok: false,
        reason: autoResult?.reason ?? "SIN_HUECO",
        message: autoResult?.message ?? "No fue posible aplicar el reemplazo.",
      };
    }

    const esCritica = opciones.confirmOptions.some(
      (o) => o.tipoConfirmacion === "CONFIRM_DANGER",
    );
    const prioridadObjetivo =
      opciones.confirmOptions
        .map((o) => o.prioridadObjetivo)
        .sort((a, b) => a - b)[0] ??
      opciones.autoOptions.map((o) => o.prioridadObjetivo).sort((a, b) => a - b)[0] ??
      prioridad;
    const requiereMotivo = opciones.confirmOptions.some(
      (o) => o.prioridadObjetivo <= 2,
    );

    return {
      ok: true,
      mode: "REQUIERE_DECISION_REEMPLAZO",
      message: hasSuggested
        ? "No hay espacio a esa hora. Puedes mover la correctiva al siguiente hueco o reemplazar una preventiva."
        : "No hay espacio a esa hora. Puedes reemplazar una preventiva segÃºn prioridad.",
      decisionMode: hasSuggested ? "MOVER_O_REEMPLAZAR" : "REEMPLAZAR",
      prioridadCorrectiva: prioridad,
      prioridadObjetivo,
      criticalConfirmation: esCritica,
      confirmationVariant: esCritica ? "danger" : "warning",
      confirmationColor: esCritica ? "red" : "amber",
      confirmationTitle: esCritica
        ? "Alerta crÃ­tica: reemplazo sobre preventiva prioridad 1"
        : "ConfirmaciÃ³n de reemplazo por prioridad",
      confirmationRequiresReason: requiereMotivo,
      requiresReplacementAction: true,
      suggestedInicio,
      suggestedFin,
      opcionesAuto: opciones.autoOptions,
      opcionesConfirmacion: opciones.confirmOptions,
      opciones: [...opciones.confirmOptions, ...opciones.autoOptions],
    };
  }

  async asignarTareaConReemplazoV2(payload: unknown): Promise<any> {
    const asignadorId = this.extraerAsignadorId(payload);
    const parsed = AsignarConReemplazoV2DTO.safeParse(payload);
    if (!parsed.success) {
      return {
        ok: false,
        reason: "PAYLOAD_INVALIDO",
        message: parsed.error.issues[0]?.message ?? "Payload invÃ¡lido.",
      };
    }

    const {
      tarea: dto,
      reemplazarIds,
      accionReemplazadas,
      motivoReemplazo,
      motivo,
    } = parsed.data;
    const motivoUsuario = (motivoReemplazo ?? motivo ?? "").trim() || null;

    const tipo = String(dto.tipo ?? "CORRECTIVA").toUpperCase();
    const prioridad = Number(dto.prioridad ?? 2);

    if (tipo !== "CORRECTIVA") {
      return {
        ok: false,
        reason: "NO_ES_CORRECTIVA",
        message: "Solo se permite reemplazo para tareas correctivas.",
      };
    }
    if (!dto.conjuntoId) {
      return {
        ok: false,
        reason: "SIN_CONJUNTO",
        message: "conjuntoId es obligatorio para reemplazo.",
      };
    }

    const inicio = dto.fechaInicio;
    const durMin =
      dto.duracionMinutos ??
      (dto.duracionHoras
        ? Math.max(1, Math.round(dto.duracionHoras * 60))
        : undefined) ??
      (dto.fechaFin
        ? Math.max(
            1,
            Math.round((dto.fechaFin.getTime() - inicio.getTime()) / 60000),
          )
        : undefined);
    if (!durMin) {
      return {
        ok: false,
        reason: "FALTA_DURACION",
        message: "Debe indicar duraciÃ³n.",
      };
    }
    const fin = dto.fechaFin ?? new Date(inicio.getTime() + durMin * 60000);

    const operariosIds =
      dto.operariosIds?.map(String) ??
      (dto.operarioId ? [String(dto.operarioId)] : []);

    const maquinariaIds: number[] = Array.isArray((dto as any).maquinariaIds)
      ? (dto as any).maquinariaIds
          .map((x: any) => Number(x))
          .filter((n: number) => Number.isFinite(n) && n > 0)
      : [];

    const prioridadesPermitidas =
      this.prioridadesPreventivaReemplazables(prioridad);

    return this.prisma.$transaction(async (tx) => {
      const tareasReemplazar = await tx.tarea.findMany({
        where: {
          id: { in: reemplazarIds },
          conjuntoId: dto.conjuntoId!,
        },
        select: {
          id: true,
          tipo: true,
          prioridad: true,
          estado: true,
          fechaInicio: true,
          fechaFin: true,
          duracionMinutos: true,
          descripcion: true,
          fechaInicioOriginal: true,
          fechaFinOriginal: true,
          operarios: { select: { id: true } },
        },
      });

      if (tareasReemplazar.length !== reemplazarIds.length) {
        return {
          ok: false,
          reason: "REEMPLAZOS_INVALIDOS",
          message:
            "Una o mÃ¡s tareas a reemplazar no pertenecen al conjunto indicado.",
        };
      }

      for (const t of tareasReemplazar) {
        if (t.tipo !== "PREVENTIVA") {
          return {
            ok: false,
            reason: "REEMPLAZO_SOLO_PREVENTIVA",
            message: "Solo se pueden reemplazar tareas preventivas.",
          };
        }
        if (
          (ESTADOS_BLOQUEADOS_PARA_REEMPLAZO as readonly string[]).includes(
            t.estado as any,
          )
        ) {
          return {
            ok: false,
            reason: "NO_REEMPLAZAR_NO_ACTIVA",
            message:
              "No se pueden reemplazar tareas preventivas en estado APROBADA o PENDIENTE_REPROGRAMACION.",
          };
        }
        if (!prioridadesPermitidas.includes(t.prioridad ?? 2)) {
          return {
            ok: false,
            reason: "PRIORIDAD_NO_PERMITE_REEMPLAZO",
            message:
              "La prioridad de esta correctiva no permite reemplazar una preventiva con esa prioridad.",
          };
        }
        if (!(ESTADOS_REEMPLAZABLES as readonly string[]).includes(t.estado)) {
          return {
            ok: false,
            reason: "NO_REEMPLAZAR_NO_ACTIVA",
            message:
              "Solo se pueden reemplazar tareas preventivas en estado ASIGNADA o EN_PROCESO.",
          };
        }
      }

      const tiposDecision = tareasReemplazar.map((t) =>
        this.tipoOpcionReemplazo(prioridad, t.prioridad ?? 2),
      );
      if (tiposDecision.some((x) => x == null)) {
        return {
          ok: false,
          reason: "REEMPLAZO_NO_VALIDO",
          message: "La selecciÃ³n contiene tareas no reemplazables para esa prioridad.",
        };
      }

      const requiereConfirmacion = tiposDecision.some((x) => x !== "AUTO");
      const requiereMotivoConfirmacion =
        requiereConfirmacion &&
        tareasReemplazar.some((t) => (t.prioridad ?? 2) <= 2);
      if (requiereMotivoConfirmacion && !motivoUsuario) {
        return {
          ok: false,
          reason: "MOTIVO_REQUERIDO",
          message:
            "Debe indicar un motivo para confirmar reemplazos de prioridad 1 o 2.",
        };
      }

      if (requiereConfirmacion && !accionReemplazadas) {
        return {
          ok: false,
          reason: "ACCION_REEMPLAZO_REQUERIDA",
          message:
            "Debe indicar si las preventivas reemplazadas se reprograman o se cancelan.",
        };
      }

      const conflictoRestante = await tx.tarea.findFirst({
        where: {
          conjuntoId: dto.conjuntoId!,
          id: { notIn: reemplazarIds },
          fechaInicio: { lt: fin },
          fechaFin: { gt: inicio },
          estado: { notIn: ESTADOS_NO_BLOQUEAN_AGENDA as any },
          ...(operariosIds.length
            ? { operarios: { some: { id: { in: operariosIds } } } }
            : {}),
        },
        select: { id: true },
      });

      if (conflictoRestante) {
        return {
          ok: false,
          reason: "REEMPLAZOS_NO_LIBERAN_ESPACIO",
          message:
            "Las tareas seleccionadas no liberan completamente el horario solicitado.",
        };
      }

      const periodoAnio = inicio.getFullYear();
      const periodoMes = inicio.getMonth() + 1;

      const nuevaCorrectiva = await tx.tarea.create({
        data: {
          descripcion: dto.descripcion,
          fechaInicio: inicio,
          fechaFin: fin,
          duracionMinutos: durMin,
          tipo: "CORRECTIVA",
          prioridad,
          estado: EstadoTarea.ASIGNADA,
          borrador: false,
          periodoAnio,
          periodoMes,
          ubicacionId: dto.ubicacionId,
          elementoId: dto.elementoId,
          conjuntoId: dto.conjuntoId!,
          supervisorId:
            dto.supervisorId != null ? String(dto.supervisorId) : null,
          ...(operariosIds.length
            ? { operarios: { connect: operariosIds.map((id) => ({ id })) } }
            : {}),
        },
        select: { id: true },
      });

      const reprogramadasIds: number[] = [];
      const canceladasIds: number[] = [];
      const canceladasSinCupoIds: number[] = [];
      const reemplazosDetalle: Array<{
        id: number;
        prioridad: number;
        tipo: string;
        resultado: string;
      }> = [];

      for (const t of tareasReemplazar) {
        const tipoDecision = this.tipoOpcionReemplazo(prioridad, t.prioridad ?? 2);
        const accionFinal = accionReemplazadas ?? "CANCELAR";

        if (accionFinal === "REPROGRAMAR") {
          const hueco = await this.buscarHuecoReprogramacionEnMes({
            tx,
            conjuntoId: dto.conjuntoId!,
            tarea: {
              id: t.id,
              fechaInicio: t.fechaInicio,
              fechaFin: t.fechaFin,
              duracionMinutos: t.duracionMinutos,
              operarios: t.operarios,
            },
            fechaDesde: fin,
          });

          if (hueco) {
            const motivoRegistro = this.buildReemplazoMotivo({
              prioridadCorrectiva: prioridad,
              prioridadPreventiva: t.prioridad ?? 2,
              resultado: "REPROGRAMADA",
              motivoUsuario,
              accion: "REPROGRAMAR",
            });

            await tx.tarea.update({
              where: { id: t.id },
              data: {
                estado: EstadoTarea.ASIGNADA,
                fechaInicio: hueco.fechaInicio,
                fechaFin: hueco.fechaFin,
                duracionMinutos: Math.max(
                  1,
                  Math.round(
                    (hueco.fechaFin.getTime() - hueco.fechaInicio.getTime()) / 60000,
                  ),
                ),
                reprogramada: true,
                reprogramadaEn: new Date(),
                reprogramadaMotivo: motivoRegistro,
                reprogramadaPorTareaId: nuevaCorrectiva.id,
                fechaInicioOriginal: t.fechaInicioOriginal ?? t.fechaInicio,
                fechaFinOriginal: t.fechaFinOriginal ?? t.fechaFin,
              } as any,
            });
            reprogramadasIds.push(t.id);
            reemplazosDetalle.push({
              id: t.id,
              prioridad: t.prioridad ?? 2,
              tipo: t.tipo,
              resultado: "REPROGRAMADA",
            });
            continue;
          }

          const motivoSinCupo = this.buildReemplazoMotivo({
            prioridadCorrectiva: prioridad,
            prioridadPreventiva: t.prioridad ?? 2,
            resultado: "CANCELADA_SIN_CUPO",
            motivoUsuario,
            accion: "REPROGRAMAR",
          });

          await tx.tarea.update({
            where: { id: t.id },
            data: {
              estado: EstadoTarea.NO_COMPLETADA,
              reprogramada: true,
              reprogramadaEn: new Date(),
              reprogramadaMotivo: motivoSinCupo,
              reprogramadaPorTareaId: nuevaCorrectiva.id,
              fechaInicioOriginal: t.fechaInicioOriginal ?? t.fechaInicio,
              fechaFinOriginal: t.fechaFinOriginal ?? t.fechaFin,
            } as any,
          });
          canceladasSinCupoIds.push(t.id);
          reemplazosDetalle.push({
            id: t.id,
            prioridad: t.prioridad ?? 2,
            tipo: t.tipo,
            resultado: "CANCELADA_SIN_CUPO",
          });
          continue;
        }

        const motivoCancelacion = this.buildReemplazoMotivo({
          prioridadCorrectiva: prioridad,
          prioridadPreventiva: t.prioridad ?? 2,
          resultado:
            tipoDecision === "AUTO" ? "CANCELADA_AUTO" : "CANCELADA_MANUAL",
          motivoUsuario,
          accion: "CANCELAR",
        });

        await tx.tarea.update({
          where: { id: t.id },
          data: {
            estado: EstadoTarea.NO_COMPLETADA,
            reprogramada: true,
            reprogramadaEn: new Date(),
            reprogramadaMotivo: motivoCancelacion,
            reprogramadaPorTareaId: nuevaCorrectiva.id,
            fechaInicioOriginal: t.fechaInicioOriginal ?? t.fechaInicio,
            fechaFinOriginal: t.fechaFinOriginal ?? t.fechaFin,
          } as any,
        });
        canceladasIds.push(t.id);
        reemplazosDetalle.push({
          id: t.id,
          prioridad: t.prioridad ?? 2,
          tipo: t.tipo,
          resultado: tipoDecision === "AUTO" ? "CANCELADA_AUTO" : "CANCELADA_MANUAL",
        });
      }

      // reserva maquinaria (mismo comportamiento de asignaciÃ³n normal)
      const noCompletadasIds = Array.from(
        new Set([...canceladasIds, ...canceladasSinCupoIds]),
      );

      const LOGISTICA_DOW = new Set([1, 3, 6]);
      const startDay = (d: Date) =>
        new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
      const endDay = (d: Date) =>
        new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
      const isLogistica = (d: Date) => LOGISTICA_DOW.has(d.getDay());
      const entregaLogistica = (uso: Date) => {
        const base = startDay(uso);
        if (isLogistica(base)) return base;
        for (let i = 1; i <= 7; i++) {
          const d = new Date(base);
          d.setDate(d.getDate() - i);
          if (isLogistica(d)) return startDay(d);
        }
        return base;
      };
      const recogidaLogistica = (uso: Date) => {
        const base = startDay(uso);
        for (let i = 1; i <= 14; i++) {
          const d = new Date(base);
          d.setDate(d.getDate() + i);
          if (isLogistica(d)) return startDay(d);
        }
        return base;
      };
      const esPropia = (tipoTenencia: any) => {
        const v = String(tipoTenencia ?? "").toUpperCase();
        return v.includes("PROPIA") || v.includes("CONJUNTO");
      };

      if (maquinariaIds.length) {
        const registros = await tx.maquinariaConjunto.findMany({
          where: {
            conjuntoId: dto.conjuntoId!,
            maquinariaId: { in: maquinariaIds },
            estado: "ACTIVA",
          },
          select: { maquinariaId: true, tipoTenencia: true },
        });
        const tenenciaMap = new Map<number, any>();
        for (const r of registros) tenenciaMap.set(r.maquinariaId, r.tipoTenencia);

        for (const maqId of maquinariaIds) {
          const propia = esPropia(tenenciaMap.get(maqId));
          let reservaInicio: Date;
          let reservaFin: Date;
          let obs: string;

          if (propia) {
            reservaInicio = inicio;
            reservaFin = fin;
            obs = `Reserva maquinaria propia (correctiva P${prioridad})`;
          } else {
            const entrega = entregaLogistica(inicio);
            const recogida = recogidaLogistica(fin);
            reservaInicio = startDay(entrega);
            reservaFin = endDay(recogida);
            obs = `Reserva logÃ­stica correctiva P${prioridad} (${entrega.toDateString()} -> ${recogida.toDateString()})`;
          }

          const choque = await tx.usoMaquinaria.findFirst({
            where: {
              maquinariaId: maqId,
              fechaInicio: { lt: reservaFin },
              fechaFin: { gt: reservaInicio },
            },
          });
          if (choque) throw new Error(`MAQUINARIA_OCUPADA_${maqId}`);

          await tx.usoMaquinaria.create({
            data: {
              tarea: { connect: { id: nuevaCorrectiva.id } },
              maquinaria: { connect: { id: maqId } },
              fechaInicio: reservaInicio,
              fechaFin: reservaFin,
              observacion: obs,
            },
          });
          await tx.maquinariaConjunto.updateMany({
            where: {
              conjuntoId: dto.conjuntoId!,
              maquinariaId: maqId,
              estado: "ACTIVA",
            },
            data: { tareaId: nuevaCorrectiva.id },
          });
        }
      }

      if (operariosIds.length) {
        const notificaciones = new NotificacionService(tx as any);
        await notificaciones.notificarAsignacionTareaOperarios({
          tareaId: nuevaCorrectiva.id,
          descripcionTarea: dto.descripcion,
          conjuntoId: dto.conjuntoId,
          operariosIds,
          asignadorId,
        });
      }

      return {
        ok: true,
        message: "Correctiva creada y reemplazos procesados.",
        createdCorrectivaId: nuevaCorrectiva.id,
        reemplazadasIds: reemplazarIds,
        reprogramadasIds,
        canceladasIds,
        canceladasSinCupoIds,
        noCompletadasIds,
        reemplazos: reemplazosDetalle,
      };
    });
  }

  async asignarTareaConReemplazo(payload: unknown) {
    return this.asignarTareaConReemplazoV2(payload);
  }

  async sugerirReemplazoParaCorrectivaP1(params: {
    prisma: PrismaClient;
    conjuntoId: string;
    fechaDia: Date;

    // intervalos jornada
    startMin: number;
    endMin: number;

    // bloqueos (descanso, patrÃ³n, etc)
    bloqueos: Bloqueo[];

    // nueva tarea P1
    durMin: number;
    operariosIds: string[];
  }): Promise<{
    huecoNormal?: Intervalo[];
    autoP3?: { reemplazarIds: number[]; bloques: Intervalo[]; tareas: any[] };
    opcionesP2?: Array<{
      reemplazarIds: number[];
      bloques: Intervalo[];
      tareas: any[];
    }>;
    opcionesP1?: Array<{
      reemplazarIds: number[];
      bloques: Intervalo[];
      tareas: any[];
    }>;
  }> {
    const {
      prisma,
      conjuntoId,
      fechaDia,
      startMin,
      endMin,
      bloqueos,
      durMin,
      operariosIds,
    } = params;

    const ini = new Date(
      fechaDia.getFullYear(),
      fechaDia.getMonth(),
      fechaDia.getDate(),
      0,
      0,
      0,
      0,
    );
    const fin = new Date(
      fechaDia.getFullYear(),
      fechaDia.getMonth(),
      fechaDia.getDate(),
      23,
      59,
      59,
      999,
    );

    // 1) Agenda actual (incluye bloqueos)
    const agenda = operariosIds.length
      ? await buildAgendaPorOperarioDia({
          prisma,
          conjuntoId,
          fechaDia,
          operariosIds,
          incluirBorrador: false,
          bloqueosGlobales: bloqueos,
          excluirEstados: ESTADOS_NO_BLOQUEAN_AGENDA as any,
        })
      : null;

    let ocupadosGlobal: Intervalo[] = [];
    if (agenda) {
      const all: Intervalo[] = [];
      for (const opId of Object.keys(agenda)) all.push(...agenda[opId]);
      ocupadosGlobal = mergeIntervalos(all);
    } else {
      ocupadosGlobal = mergeIntervalos(
        bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })),
      );
    }

    // 2) Intento normal
    const normal = buscarHuecoDiaConSplitEarliest({
      startMin,
      endMin,
      durMin,
      ocupados: ocupadosGlobal,
      bloqueos,
      desiredStartMin: startMin,
      maxBloques: 2,
    });
    if (normal) return { huecoNormal: normal };

    // 3) Candidatas del dÃ­a P2/P3 (NO cerradas, NO ya reprogramadas)
    const candidatas = await prisma.tarea.findMany({
      where: {
        conjuntoId,
        fechaInicio: { lte: fin },
        fechaFin: { gte: ini },
        estado: { in: ESTADOS_REEMPLAZABLES as any },
        OR: [
          { prioridad: { in: [2, 3] } },
          { prioridad: 1, tipo: "PREVENTIVA" as any },
        ],
        // MUY IMPORTANTE: que afecten a los operarios de la P1 (si tu reemplazo es por agenda/operario)
        ...(operariosIds.length
          ? { operarios: { some: { id: { in: operariosIds } } } }
          : {}),
      },
      select: {
        id: true,
        tipo: true,
        prioridad: true,
        descripcion: true,
        fechaInicio: true,
        fechaFin: true,
        grupoPlanId: true,
      },
      orderBy: [{ prioridad: "desc" }, { fechaInicio: "asc" }], // primero P3
    });

    if (!candidatas.length) return {};

    const excluyeIds = async (t: (typeof candidatas)[number]) => {
      if (!t.grupoPlanId) return new Set([t.id]);
      const grupo = await prisma.tarea.findMany({
        where: {
          grupoPlanId: t.grupoPlanId,
          conjuntoId,
          estado: { in: ESTADOS_REEMPLAZABLES as any },
        },
        select: {
          id: true,
          tipo: true,
          prioridad: true,
          descripcion: true,
          fechaInicio: true,
          fechaFin: true,
        },
      });
      return new Set(grupo.map((x) => x.id));
    };

    // helper: recalcular ocupados SIN ciertas ids
    const buildOcupadosSin = async (idsAExcluir: Set<number>) => {
      const tareasDia = await prisma.tarea.findMany({
        where: {
          conjuntoId,
          fechaInicio: { lte: fin },
          fechaFin: { gte: ini },
          id: { notIn: Array.from(idsAExcluir) },
          estado: { notIn: ESTADOS_NO_BLOQUEAN_AGENDA as any },
          ...(operariosIds.length
            ? { operarios: { some: { id: { in: operariosIds } } } }
            : {}),
        },
        select: { fechaInicio: true, fechaFin: true },
      });

      const all: Intervalo[] = tareasDia.map((t) => ({
        i: toMinOfDaySafe(t.fechaInicio),
        f: toMinOfDaySafe(t.fechaFin),
      }));
      for (const b of bloqueos) all.push({ i: b.startMin, f: b.endMin });
      return mergeIntervalos(all);
    };

    // 4) Primero probar P3 (auto)
    for (const cand of candidatas.filter((x) => x.prioridad === 3)) {
      const idsAExcluir = await excluyeIds(cand);
      const ocup = await buildOcupadosSin(idsAExcluir);

      const bloques = buscarHuecoDiaConSplitEarliest({
        startMin,
        endMin,
        durMin,
        ocupados: ocup,
        bloqueos,
        desiredStartMin: startMin,
        maxBloques: 2,
      });

      if (bloques) {
        // capturamos info de tareas que se reemplazarÃ­an (para informar)
        const tareas = await prisma.tarea.findMany({
          where: { id: { in: Array.from(idsAExcluir) } },
          select: {
            id: true,
            tipo: true,
            prioridad: true,
            descripcion: true,
            fechaInicio: true,
            fechaFin: true,
          },
        });

        return {
          autoP3: { reemplazarIds: Array.from(idsAExcluir), bloques, tareas },
        };
      }
    }

    // 5) Si no hubo P3, armar opciones P2 (para que el usuario escoja)
    const opcionesP2: Array<{
      reemplazarIds: number[];
      bloques: Intervalo[];
      tareas: any[];
    }> = [];

    for (const cand of candidatas.filter((x) => x.prioridad === 2)) {
      const idsAExcluir = await excluyeIds(cand);
      const ocup = await buildOcupadosSin(idsAExcluir);

      const bloques = buscarHuecoDiaConSplitEarliest({
        startMin,
        endMin,
        durMin,
        ocupados: ocup,
        bloqueos,
        desiredStartMin: startMin,
        maxBloques: 2,
      });

      if (!bloques) continue;

      const tareas = await prisma.tarea.findMany({
        where: { id: { in: Array.from(idsAExcluir) } },
        select: {
          id: true,
          tipo: true,
          prioridad: true,
          descripcion: true,
          fechaInicio: true,
          fechaFin: true,
        },
      });

      opcionesP2.push({
        reemplazarIds: Array.from(idsAExcluir),
        bloques,
        tareas,
      });

      // Si te preocupa rendimiento, puedes cortar a 10 opciones
      if (opcionesP2.length >= 10) break;
    }

    const opcionesP1: Array<{
      reemplazarIds: number[];
      bloques: Intervalo[];
      tareas: any[];
    }> = [];

    for (const cand of candidatas.filter(
      (x) => x.prioridad === 1 && x.tipo === "PREVENTIVA",
    )) {
      const idsAExcluir = await excluyeIds(cand);
      const ocup = await buildOcupadosSin(idsAExcluir);

      const bloques = buscarHuecoDiaConSplitEarliest({
        startMin,
        endMin,
        durMin,
        ocupados: ocup,
        bloqueos,
        desiredStartMin: startMin,
        maxBloques: 2,
      });

      if (!bloques) continue;

      const tareas = await prisma.tarea.findMany({
        where: { id: { in: Array.from(idsAExcluir) } },
        select: {
          id: true,
          tipo: true,
          prioridad: true,
          descripcion: true,
          fechaInicio: true,
          fechaFin: true,
        },
      });

      const todasPreventivasP1 = tareas.every(
        (t) => t.tipo === "PREVENTIVA" && (t.prioridad ?? 2) === 1,
      );
      if (!todasPreventivasP1) continue;

      opcionesP1.push({
        reemplazarIds: Array.from(idsAExcluir),
        bloques,
        tareas,
      });

      if (opcionesP1.length >= 10) break;
    }

    return {
      opcionesP2: opcionesP2.length ? opcionesP2 : undefined,
      opcionesP1: opcionesP1.length ? opcionesP1 : undefined,
    };
  }

  async crearCorrectivaP1ConReglas(
    payload: unknown,
  ): Promise<ReemplazoPropuesta> {
    return this.crearCorrectivaConReglas(payload);
  }

  async editarTarea(tareaId: number, payload: unknown) {
    const asignadorId = this.extraerAsignadorId(payload);
    const dto = EditarTareaDTO.parse(payload);
    const data: Prisma.TareaUpdateInput = {};

    const tareaAntes =
      dto.operariosIds !== undefined
        ? await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: {
              descripcion: true,
              conjuntoId: true,
              operarios: { select: { id: true } },
            },
          })
        : null;

    if (dto.descripcion !== undefined) data.descripcion = dto.descripcion;
    if (dto.fechaInicio !== undefined)
      data.fechaInicio = dto.fechaInicio as any;
    if (dto.fechaFin !== undefined) data.fechaFin = dto.fechaFin as any;
    if (dto.duracionMinutos !== undefined)
      data.duracionMinutos = dto.duracionMinutos;
    if (dto.estado !== undefined) data.estado = dto.estado as any;
    if (dto.evidencias !== undefined) data.evidencias = dto.evidencias as any;
    if (dto.insumosUsados !== undefined)
      data.insumosUsados = dto.insumosUsados as any;
    if (dto.observacionesRechazo !== undefined)
      data.observacionesRechazo = dto.observacionesRechazo;

    // supervisorId ahora se guarda como String en la relaciÃ³n
    if (dto.supervisorId !== undefined) {
      data.supervisor =
        dto.supervisorId === null
          ? { disconnect: true }
          : { connect: { id: dto.supervisorId.toString() } };
    }

    if (dto.ubicacionId !== undefined) {
      data.ubicacion = { connect: { id: dto.ubicacionId } };
    }

    if (dto.elementoId !== undefined) {
      data.elemento = { connect: { id: dto.elementoId } };
    }

    if (dto.conjuntoId !== undefined) {
      data.conjunto =
        dto.conjuntoId === null
          ? { disconnect: true }
          : { connect: { nit: dto.conjuntoId } };
    }

    // Reemplazar operarios por los que lleguen en el arreglo
    if (dto.operariosIds !== undefined) {
      data.operarios = {
        set: dto.operariosIds.map((id) => ({ id: id.toString() })),
      };
    }

    const updated = await this.prisma.tarea.update({
      where: { id: tareaId },
      data,
    });

    if (dto.operariosIds !== undefined) {
      const anteriores = new Set(
        (tareaAntes?.operarios ?? []).map((o) => o.id.toString()),
      );
      const actuales = dto.operariosIds.map((id) => id.toString());
      const nuevosAsignados = actuales.filter((id) => !anteriores.has(id));

      if (nuevosAsignados.length > 0) {
        try {
          const notificaciones = new NotificacionService(this.prisma);
          await notificaciones.notificarAsignacionTareaOperarios({
            tareaId,
            descripcionTarea:
              updated.descripcion ?? tareaAntes?.descripcion ?? `Tarea ${tareaId}`,
            conjuntoId: updated.conjuntoId ?? tareaAntes?.conjuntoId ?? null,
            operariosIds: nuevosAsignados,
            asignadorId,
          });
        } catch (e) {
          console.error(
            "No se pudo notificar asignacion de tarea en edicion:",
            e,
          );
        }
      }
    }

    return updated;
  }

  async listarTareasPorConjunto(conjuntoId: string) {
    const tareas = await this.prisma.tarea.findMany({
      where: { conjuntoId, borrador: false },
      include: {
        supervisor: { include: { usuario: true } },
        operarios: { include: { usuario: true } },

        ubicacion: true,
        elemento: true,

        usoHerramientas: {
          include: { herramienta: { select: { id: true, nombre: true } } },
        },
        usoMaquinarias: {
          include: { maquinaria: { select: { id: true, nombre: true } } },
        },

        insumoPrincipal: true,
      },
      orderBy: { fechaInicio: "desc" },
    });

    return tareas.map((t) => {
      const operariosNombres =
        t.operarios
          ?.map((o) => o.usuario?.nombre)
          .filter((n): n is string => !!n) ?? [];

      // NO convertir a Number (cÃ©dulas)
      const operariosIds = t.operarios?.map((o) => o.id) ?? [];
      const supervisorNombre = t.supervisor?.usuario?.nombre ?? null;

      const herramientasAsignadas =
        t.usoHerramientas?.map((u) => ({
          herramientaId: u.herramientaId,
          nombre: u.herramienta?.nombre ?? "",
          cantidad: Number(u.cantidad ?? 1),
          estado: u.estado ?? null,
        })) ?? [];

      const maquinariasAsignadas =
        t.usoMaquinarias?.map((u) => ({
          maquinariaId: u.maquinariaId,
          nombre: u.maquinaria?.nombre ?? "",
        })) ?? [];

      return {
        id: t.id,
        descripcion: t.descripcion,
        fechaInicio: t.fechaInicio,
        fechaFin: t.fechaFin,
        duracionMinutos: t.duracionMinutos,
        prioridad: t.prioridad,
        estado: t.estado,

        evidencias: t.evidencias ?? [],
        insumosUsados: t.insumosUsados ?? null,

        observaciones: t.observaciones,
        observacionesRechazo: t.observacionesRechazo,
        tipo: t.tipo,
        frecuencia: t.frecuencia,

        conjuntoId: t.conjuntoId,

        supervisorId: t.supervisorId ?? null,
        supervisorNombre,

        ubicacionId: t.ubicacionId,
        ubicacionNombre: t.ubicacion?.nombre ?? null,

        elementoId: t.elementoId,
        elementoNombre: t.elemento?.nombre ?? null,

        operariosIds,
        operariosNombres,

        // USO/ASIGNACIÃ“N
        herramientasAsignadas,
        maquinariasAsignadas,

        // PLANIFICACIÃ“N (JSON)
        herramientasPlanJson: t.herramientasPlanJson ?? null,
        maquinariaPlanJson: t.maquinariaPlanJson ?? null,
        insumosPlanJson: t.insumosPlanJson ?? null,

        // Opcional
        insumoPrincipalId: t.insumoPrincipalId ?? null,
        insumoPrincipalNombre: t.insumoPrincipal?.nombre ?? null,
        consumoPrincipalPorUnidad: t.consumoPrincipalPorUnidad ?? null,
        consumoTotalEstimado: t.consumoTotalEstimado ?? null,
      };
    });
  }

  /* ===================== ELIMINACIONES con REGLAS ===================== */

  async eliminarAdministrador(adminId: string) {
    const asignaciones = await this.prisma.conjunto.findMany({
      where: { administradorId: adminId.toString() },
    });
    if (asignaciones.length > 0) {
      throw new Error("âŒ El administrador tiene conjuntos asignados.");
    }
    await this.prisma.usuario.delete({ where: { id: adminId.toString() } });
  }

  async reemplazarAdminEnVariosConjuntos(
    reemplazos: { conjuntoId: string; nuevoAdminId: number }[],
  ) {
    if (reemplazos.length === 0) return;
    for (const { conjuntoId, nuevoAdminId } of reemplazos) {
      await this.prisma.conjunto.update({
        where: { nit: conjuntoId },
        data: { administradorId: nuevoAdminId.toString() },
      });
    }
  }

  async eliminarOperario(operarioId: string) {
    // 1) Verificar tareas pendientes donde el operario estÃ© asignado
    const tareasPendientes = await this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: operarioId } }, // ya es string, no hace falta toString()
        estado: {
          in: ["ASIGNADA", "EN_PROCESO", "PENDIENTE_APROBACION"],
        },
      },
      select: { id: true },
    });

    if (tareasPendientes.length > 0) {
      throw new Error("âŒ El operario tiene tareas pendientes.");
    }

    // 2) Borrar operario + usuario dentro de una misma transacciÃ³n
    await this.prisma.$transaction(async (tx) => {
      // Borramos el operario (si existe). deleteMany evita P2025 si ya no estÃ¡.
      await tx.operario.deleteMany({
        where: { id: operarioId },
      });

      // Borramos el usuario asociado (obligatorio que exista, si no â†’ error lÃ³gico)
      await tx.usuario.delete({
        where: { id: operarioId },
      });
    });
  }

  async eliminarSupervisor(supervisorId: string) {
    await this.prisma.$transaction(async (tx) => {
      // 1) Borrar el JefeOperaciones (si existe)
      await tx.supervisor.deleteMany({
        where: { id: supervisorId },
      }); // deleteMany NO lanza P2025 si no hay registro

      // 2) Borrar siempre el usuario asociado
      await tx.usuario.delete({
        where: { id: supervisorId },
      });
    });
  }

  async eliminarJefeOperaciones(jefeOperacionesId: string) {
    await this.prisma.$transaction(async (tx) => {
      // 1) Borrar el JefeOperaciones (si existe)
      await tx.jefeOperaciones.deleteMany({
        where: { id: jefeOperacionesId },
      }); // deleteMany NO lanza P2025 si no hay registro

      // 2) Borrar siempre el usuario asociado
      await tx.usuario.delete({
        where: { id: jefeOperacionesId },
      });
    });
  }

  async eliminarUsuario(id: string): Promise<void> {
    const usuario = await this.prisma.usuario.findUnique({ where: { id } });
    if (!usuario) return;

    switch (usuario.rol as Rol) {
      case Rol.administrador:
        await this.eliminarAdministrador(id);
        break;
      case Rol.operario:
        await this.eliminarOperario(id);
        break;
      case Rol.supervisor:
        await this.eliminarSupervisor(id);
        break;
      case Rol.jefe_operaciones:
        await this.eliminarJefeOperaciones(id);
        break;
      default:
        await this.prisma.usuario.delete({ where: { id } });
        break;
    }
  }

  async eliminarMaquinaria(maquinariaId: number) {
    await this.prisma.maquinaria.delete({ where: { id: maquinariaId } });
  }

  async eliminarTarea(prisma: PrismaClient, id: number) {
    const tarea = await prisma.tarea.findUnique({
      where: { id },
      select: {
        id: true,
        estado: true,
        borrador: true,
      },
    });

    if (!tarea) throw new Error("Tarea no encontrada.");

    // ðŸ”’ Reglas de negocio (ajÃºstalas a tu gusto)
    if (
      tarea.estado === EstadoTarea.COMPLETADA ||
      tarea.estado === EstadoTarea.APROBADA ||
      tarea.estado === EstadoTarea.PENDIENTE_APROBACION
    ) {
      throw new Error(
        "No se puede eliminar una tarea que ya fue ejecutada o estÃ¡ en aprobaciÃ³n.",
      );
    }

    await prisma.$transaction(async (tx) => {
      // 1) Liberar maquinaria asignada al conjunto por esta tarea (si existiera)
      // (tu relaciÃ³n tiene onDelete: SetNull, pero igual lo hacemos explÃ­cito)
      await tx.maquinariaConjunto.updateMany({
        where: { tareaId: id },
        data: { tareaId: null },
      });

      // 2) Borrar usos de maquinaria/herramienta ligados a la tarea (FK dura)
      await tx.usoMaquinaria.deleteMany({
        where: { tareaId: id },
      });

      await tx.usoHerramienta.deleteMany({
        where: { tareaId: id },
      });

      // 3) Borrar consumos ligados a la tarea (si aplica en tu schema real)
      await tx.consumoInsumo.deleteMany({
        where: { tareaId: id },
      });

      // 4) (Opcional) Desconectar relaciÃ³n M:N de operarios (normalmente Prisma lo limpia,
      // pero lo dejo por si tu DB tiene restricciones raras)
      await tx.tarea.update({
        where: { id },
        data: { operarios: { set: [] } },
      });

      // 5) Ahora sÃ­, borrar la tarea
      await tx.tarea.delete({ where: { id } });
    });

    return { ok: true, message: "Tarea eliminada correctamente." };
  }

  /* ===================== EDICIONES RÃPIDAS (compat) ===================== */

  async editarAdministrador(adminId: number, payload: unknown) {
    const dto = EditarUsuarioDTO.parse(payload);
    const data: any = { ...dto };
    if (dto.contrasena) {
      data.contrasena = await bcrypt.hash(dto.contrasena, 10);
    } else {
      delete data.contrasena;
    }
    await this.prisma.usuario.update({
      where: { id: adminId.toString() },
      data,
    });
  }

  async editarOperario(operarioId: number, payload: unknown) {
    const dto = EditarOperarioDTO.parse(payload);

    const data: any = {};
    if (dto.funciones) data.funciones = dto.funciones as TipoFuncion[];

    if ((payload as any).nombre || (payload as any).correo) {
      const uData: any = {};
      if ((payload as any).nombre) uData.nombre = (payload as any).nombre;
      if ((payload as any).correo) uData.correo = (payload as any).correo;
      await this.prisma.usuario.update({
        where: { id: operarioId.toString() },
        data: uData,
      });
    }

    if (Object.keys(data).length === 0) return;
    await this.prisma.operario.update({
      where: { id: operarioId.toString() },
      data,
    });
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
      await this.prisma.usuario.update({
        where: { id: supervisorId.toString() },
        data: uData,
      });
    }

    if (dto.empresaId) {
      await this.prisma.supervisor.update({
        where: { id: supervisorId.toString() },
        data: { empresaId: dto.empresaId },
      });
    }
  }
}
