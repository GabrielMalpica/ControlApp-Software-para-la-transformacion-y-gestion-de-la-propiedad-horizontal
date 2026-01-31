import type { PrismaClient } from "../generated/prisma";
import { Rol, TipoFuncion, EstadoTarea } from "../generated/prisma";
import bcrypt from "bcrypt";
import { Prisma } from "../generated/prisma";

import {
  CrearUsuarioDTO,
  EditarUsuarioDTO,
  usuarioPublicSelect,
  toUsuarioPublico,
  UsuarioPublico,
} from "../model/Usuario";

import { CrearGerenteDTO, ListarUsuariosInput } from "../model/Gerente";
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
  buscarHuecoDiaConSplitEarliest,
  buscarSolapesEnConjunto,
  dateToDiaSemana,
  mergeIntervalos,
  solapa,
  toDateAtMin,
  toMin,
  toMinOfDay,
  ymdLocal,
} from "../utils/schedulerUtils";
import {
  CrearMaquinariaCatalogoDTO,
  EditarMaquinariaCatalogoDTO,
} from "../model/Maquinaria";
import { buildBloqueosPorDescanso } from "./DefinicionTareaPreventivaService";
import { Intervalo } from "../utils/agenda";

const AsignarAConjuntoDTO = z.object({
  operarioId: z.number().int().positive(),
  conjuntoId: z.string().min(3),
});

export const AsignarConReemplazoDTO = z.object({
  tarea: CrearTareaDTO,
  reemplazarIds: z.array(z.number().int().positive()).min(1),
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

const EMPRESA_ID_FIJA = "901191875-4";

export class GerenteService {
  constructor(private prisma: PrismaClient) {}

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

    if (existeId) throw new Error("Ya existe un usuario con esa cédula.");
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
    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
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
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
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
      this.prisma.empresa.findFirst(), // 👈 toma la primera empresa registrada
      this.prisma.usuario.findUnique({ where: { id: dto.Id } }),
    ]);

    if (!empresa) throw new Error("❌ No hay empresa registrada.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
    if (usuario.rol !== Rol.jefe_operaciones)
      throw new Error("El usuario no tiene rol 'jefe_operaciones'.");

    return this.prisma.jefeOperaciones.create({
      data: {
        id: dto.Id, // FK al Usuario
        empresaId: empresa.nit, // 👈 usamos el NIT de la empresa
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

    if (!empresa) throw new Error("❌ No hay empresa registrada.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
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

    if (!empresa) throw new Error("❌ No hay empresa registrada.");
    if (!usuario) throw new Error("❌ Usuario no encontrado.");
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
        throw new Error("❌ El administrador seleccionado no existe.");
      }
      administradorId = dto.administradorId;
    }

    const creado = await this.prisma.conjunto.create({
      data: {
        nit: dto.nit,
        nombre: dto.nombre,
        direccion: dto.direccion,
        correo: dto.correo,

        empresaId: EMPRESA_ID_FIJA,
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
        empresaId: EMPRESA_ID_FIJA,
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
      throw new Error("❌ Conjunto no encontrado.");
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
      // si el front manda fechaFin explícita, la usamos tal cua
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
      throw new Error("❌ El conjunto tiene tareas pendientes.");
    if (maquinariaActivaEnConjunto.length > 0)
      throw new Error(
        "❌ El conjunto tiene maquinaria activa asignada (propia o prestada).",
      );

    await this.prisma.conjunto.delete({ where: { nit: conjuntoId } });
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
        `❌ No se encontró inventario para el conjunto ${dto.conjuntoId}`,
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

  /** Catálogo corporativo: empresaId = null (ajusta si usas catálogo por empresa) */
  async agregarInsumoAlCatalogo(payload: unknown, empresaId: string) {
    const dto = CrearInsumoDTO.parse(payload);

    const existe = await this.prisma.insumo.findFirst({
      where: { empresaId, nombre: dto.nombre, unidad: dto.unidad },
      select: { id: true },
    });
    if (existe)
      throw new Error(
        "🚫 Ya existe un insumo con ese nombre y unidad en el catálogo.",
      );

    return this.prisma.insumo.create({
      data: {
        nombre: dto.nombre,
        unidad: dto.unidad,
        empresaId, // ✅ ya no null
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

  async asignarTarea(payload: unknown) {
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
        message: "Debe indicar duración.",
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
    // Helpers de logística
    // =========================
    const LOGISTICA_DOW = new Set([1, 3, 6]); // lun, mié, sáb

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
    // TRANSACCIÓN
    // =========================
    return this.prisma.$transaction(async (tx) => {
      // 1️⃣ Crear la tarea
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

      // 2️⃣ Resolver maquinaria por conjunto
      if (dto.conjuntoId && maquinariaIds.length) {
        const registros = await tx.maquinariaConjunto.findMany({
          where: {
            conjuntoId: dto.conjuntoId,
            maquinariaId: { in: maquinariaIds },
            estado: "ACTIVA",
          },
          select: {
            maquinariaId: true,
            tipoTenencia: true,
          },
        });

        const tenenciaMap = new Map<number, any>();
        for (const r of registros) {
          tenenciaMap.set(r.maquinariaId, r.tipoTenencia);
        }

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
            obs = `Reserva logística (${entrega.toDateString()} → ${recogida.toDateString()})`;
          }

          // Validar solape REAL
          const choque = await tx.usoMaquinaria.findFirst({
            where: {
              maquinariaId: maqId,
              fechaInicio: { lt: reservaFin },
              fechaFin: { gt: reservaInicio },
            },
          });

          if (choque) {
            throw new Error(
              `MAQUINARIA_OCUPADA: maquinaria ${maqId} ya está reservada`,
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

          // Amarrar si existe registro en MaquinariaConjunto
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

      return {
        ok: true,
        message: "Tarea creada correctamente",
        tareaId: tarea.id,
      };
    });
  }

  async asignarTareaConReemplazo(payload: unknown) {
    const body = payload as any;

    const dto = CrearTareaDTO.parse(body.tarea);

    const reemplazarIds: number[] = Array.isArray(body.reemplazarIds)
      ? body.reemplazarIds
          .map((x: any) => Number(x))
          .filter((n: number) => Number.isFinite(n) && n > 0)
      : [];

    if (!reemplazarIds.length) {
      return {
        ok: false,
        reason: "SIN_REEMPLAZOS",
        message: "Debe indicar las tareas a reemplazar.",
      };
    }

    const tipo = (dto.tipo ?? "CORRECTIVA") as any;
    const prioridad = dto.prioridad ?? 2;

    if (tipo !== "CORRECTIVA" || prioridad !== 1) {
      return {
        ok: false,
        reason: "NO_ES_P1",
        message: "Solo se permite reemplazo para correctivas prioridad 1.",
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
        message: "Debe indicar duración.",
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

    // =========================
    // Helpers logística (MISMA lógica que asignarTarea)
    // =========================
    const LOGISTICA_DOW = new Set([1, 3, 6]); // lun, mié, sáb

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
    // TRANSACCIÓN
    // =========================
    return this.prisma.$transaction(async (tx) => {
      // 1️⃣ Validar tareas a reemplazar
      const tareasReemplazar = await tx.tarea.findMany({
        where: {
          id: { in: reemplazarIds },
          conjuntoId: dto.conjuntoId,
        },
        select: {
          id: true,
          prioridad: true,
          estado: true,
          fechaInicio: true,
          fechaFin: true,
        },
      });

      for (const t of tareasReemplazar) {
        if ((t.prioridad ?? 2) <= 1) {
          throw new Error("NO_REEMPLAZAR_P1");
        }
        if (t.estado === "COMPLETADA" || t.estado === "APROBADA") {
          throw new Error("NO_REEMPLAZAR_CERRADA");
        }
      }

      // 2️⃣ Crear la correctiva P1
      const p1 = await tx.tarea.create({
        data: {
          descripcion: dto.descripcion,
          fechaInicio: inicio,
          fechaFin: fin,
          duracionMinutos: durMin,
          tipo: "CORRECTIVA",
          prioridad: 1,
          estado: EstadoTarea.ASIGNADA,
          borrador: false,
          periodoAnio,
          periodoMes,
          ubicacionId: dto.ubicacionId,
          elementoId: dto.elementoId,
          conjuntoId: dto.conjuntoId,
          supervisorId:
            dto.supervisorId != null ? String(dto.supervisorId) : null,
          ...(operariosIds.length
            ? { operarios: { connect: operariosIds.map((id) => ({ id })) } }
            : {}),
        },
        select: { id: true },
      });

      // 3️⃣ Marcar reemplazadas
      const now = new Date();

      await tx.tarea.updateMany({
        where: { id: { in: reemplazarIds } },
        data: {
          estado: EstadoTarea.PENDIENTE_REPROGRAMACION,
          reprogramada: true,
          reprogramadaEn: now,
          reprogramadaMotivo: "Reemplazada por correctiva P1",
          reprogramadaPorTareaId: p1.id,
        } as any,
      });

      // 4️⃣ Reservar maquinaria (misma lógica que asignarTarea)
      if (maquinariaIds.length) {
        const registros = await tx.maquinariaConjunto.findMany({
          where: {
            conjuntoId: dto.conjuntoId!,
            maquinariaId: { in: maquinariaIds },
            estado: "ACTIVA",
          },
          select: {
            maquinariaId: true,
            tipoTenencia: true,
          },
        });

        const tenenciaMap = new Map<number, any>();
        for (const r of registros) {
          tenenciaMap.set(r.maquinariaId, r.tipoTenencia);
        }

        for (const maqId of maquinariaIds) {
          const propia = esPropia(tenenciaMap.get(maqId));

          let reservaInicio: Date;
          let reservaFin: Date;
          let obs: string;

          if (propia) {
            reservaInicio = inicio;
            reservaFin = fin;
            obs = "Reserva maquinaria propia (correctiva P1)";
          } else {
            const entrega = entregaLogistica(inicio);
            const recogida = recogidaLogistica(fin);
            reservaInicio = startDay(entrega);
            reservaFin = endDay(recogida);
            obs = `Reserva logística P1 (${entrega.toDateString()} → ${recogida.toDateString()})`;
          }

          const choque = await tx.usoMaquinaria.findFirst({
            where: {
              maquinariaId: maqId,
              fechaInicio: { lt: reservaFin },
              fechaFin: { gt: reservaInicio },
            },
          });

          if (choque) {
            throw new Error(`MAQUINARIA_OCUPADA_${maqId}`);
          }

          await tx.usoMaquinaria.create({
            data: {
              tarea: { connect: { id: p1.id } },
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
            data: { tareaId: p1.id },
          });
        }
      }

      return {
        ok: true,
        message: "Correctiva P1 creada y tareas reemplazadas.",
        createdP1Id: p1.id,
        reemplazadasIds: reemplazarIds,
      };
    });
  }

  async editarTarea(tareaId: number, payload: unknown) {
    const dto = EditarTareaDTO.parse(payload);
    const data: Prisma.TareaUpdateInput = {};

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

    // supervisorId ahora se guarda como String en la relación
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

    return this.prisma.tarea.update({ where: { id: tareaId }, data });
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

      // NO convertir a Number (cédulas)
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

        // USO/ASIGNACIÓN
        herramientasAsignadas,
        maquinariasAsignadas,

        // PLANIFICACIÓN (JSON)
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
      throw new Error("❌ El administrador tiene conjuntos asignados.");
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
    // 1) Verificar tareas pendientes donde el operario esté asignado
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
      throw new Error("❌ El operario tiene tareas pendientes.");
    }

    // 2) Borrar operario + usuario dentro de una misma transacción
    await this.prisma.$transaction(async (tx) => {
      // Borramos el operario (si existe). deleteMany evita P2025 si ya no está.
      await tx.operario.deleteMany({
        where: { id: operarioId },
      });

      // Borramos el usuario asociado (obligatorio que exista, si no → error lógico)
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

    // 🔒 Reglas de negocio (ajústalas a tu gusto)
    if (
      tarea.estado === EstadoTarea.COMPLETADA ||
      tarea.estado === EstadoTarea.APROBADA ||
      tarea.estado === EstadoTarea.PENDIENTE_APROBACION
    ) {
      throw new Error(
        "No se puede eliminar una tarea que ya fue ejecutada o está en aprobación.",
      );
    }

    await prisma.$transaction(async (tx) => {
      // 1) Liberar maquinaria asignada al conjunto por esta tarea (si existiera)
      // (tu relación tiene onDelete: SetNull, pero igual lo hacemos explícito)
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

      // 4) (Opcional) Desconectar relación M:N de operarios (normalmente Prisma lo limpia,
      // pero lo dejo por si tu DB tiene restricciones raras)
      await tx.tarea.update({
        where: { id },
        data: { operarios: { set: [] } },
      });

      // 5) Ahora sí, borrar la tarea
      await tx.tarea.delete({ where: { id } });
    });

    return { ok: true, message: "Tarea eliminada correctamente." };
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
