import {
  PrismaClient,
  Rol,
  TipoFuncion,
  TipoMaquinaria,
  EstadoMaquinaria,
  EstadoTarea,
} from "../generated/prisma";
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

import {
  CrearMaquinariaDTO,
  EditarMaquinariaDTO,
  maquinariaPublicSelect,
  toMaquinariaPublica,
} from "../model/Maquinaria";

import { CrearTareaDTO, EditarTareaDTO } from "../model/Tarea";

import { CrearInsumoDTO, insumoPublicSelect } from "../model/Insumo";

import { z } from "zod";
import {
  buscarSolapesEnConjunto,
  sugerirHuecoDia,
  toMinOfDay,
} from "../utils/schedulerUtils";

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
    const [tareasPendientes, maquinariaPrestada] = await Promise.all([
      this.prisma.tarea.findMany({
        where: {
          conjuntoId,
          estado: { in: ["ASIGNADA", "EN_PROCESO", "PENDIENTE_APROBACION"] },
        },
        select: { id: true },
      }),
      this.prisma.maquinaria.findMany({
        where: { conjuntoId, disponible: false },
        select: { id: true },
      }),
    ]);

    if (tareasPendientes.length > 0)
      throw new Error("❌ El conjunto tiene tareas pendientes.");
    if (maquinariaPrestada.length > 0)
      throw new Error("❌ El conjunto tiene maquinaria prestada.");

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
        `❌ No se encontró inventario para el conjunto ${dto.conjuntoId}`
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
  async agregarInsumoAlCatalogo(payload: unknown) {
    const dto = CrearInsumoDTO.parse(payload);
    const empresaId: string | null = null;

    const existe = await this.prisma.insumo.findFirst({
      where: { empresaId, nombre: dto.nombre, unidad: dto.unidad },
      select: { id: true },
    });
    if (existe)
      throw new Error(
        "🚫 Ya existe un insumo con ese nombre y unidad en el catálogo."
      );

    return this.prisma.insumo.create({
      data: {
        nombre: dto.nombre,
        unidad: dto.unidad,
        empresaId,
        categoria: dto.categoria,
        umbralBajo: dto.umbralBajo ?? null,
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
        operarioId: dto.operarioId!.toString() ?? null,
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

    const data: Prisma.MaquinariaUpdateInput = {};

    if (dto.nombre !== undefined) data.nombre = dto.nombre;
    if (dto.marca !== undefined) data.marca = dto.marca;
    if (dto.tipo !== undefined) data.tipo = dto.tipo; // enum TipoMaquinaria
    if (dto.estado !== undefined) data.estado = dto.estado;
    if (dto.disponible !== undefined) data.disponible = dto.disponible;

    // relaciones
    if (dto.conjuntoId !== undefined) {
      data.asignadaA =
        dto.conjuntoId === null
          ? { disconnect: true }
          : { connect: { nit: dto.conjuntoId } };
    }

    if (dto.operarioId !== undefined) {
      data.responsable =
        dto.operarioId === null
          ? { disconnect: true }
          : { connect: { id: dto.operarioId.toString() } };
    }

    if (dto.empresaId !== undefined) {
      data.empresa =
        dto.empresaId === null
          ? { disconnect: true }
          : { connect: { nit: dto.empresaId } };
    }

    if (dto.fechaPrestamo !== undefined) {
      data.fechaPrestamo = dto.fechaPrestamo;
    }

    if (dto.fechaDevolucionEstimada !== undefined) {
      data.fechaDevolucionEstimada = dto.fechaDevolucionEstimada;
    }

    const actualizado = await this.prisma.maquinaria.update({
      where: { id: maquinariaId },
      data,
      select: maquinariaPublicSelect,
    });

    return toMaquinariaPublica(actualizado);
  }

  /* ===================== TAREAS ===================== */

  async asignarTarea(payload: unknown) {
    const dto = CrearTareaDTO.parse(payload);

    const periodoAnio = dto.fechaInicio.getFullYear();
    const periodoMes = dto.fechaInicio.getMonth() + 1;

    const inicio = dto.fechaInicio;

    const durMin =
      dto.duracionMinutos ??
      Math.max(
        1,
        Math.round((dto.fechaFin.getTime() - dto.fechaInicio.getTime()) / 60000)
      );

    const fin = dto.fechaFin ?? new Date(inicio.getTime() + durMin * 60000);

    // Operarios
    const operariosIds =
      dto.operariosIds?.map(String) ??
      (dto.operarioId ? [String(dto.operarioId)] : []);

    // ✅ 1) sugerencia de hueco (si hay conjunto)
    let sugerencia: null | {
      startMin: number;
      endMin: number;
      suggestedInicio: Date;
      suggestedFin: Date;
      startHHmm: string;
    } = null;

    if (dto.conjuntoId && operariosIds.length) {
      const desiredStartMin = toMinOfDay(inicio);

      const sug = await sugerirHuecoDia({
        prisma: this.prisma,
        conjuntoId: dto.conjuntoId,
        fechaDia: inicio,
        desiredStartMin,
        durMin,
        operariosIds,
        incluirBorradorAgenda: true,
        excluirEstadosAgenda: ["PENDIENTE_REPROGRAMACION"],
      });

      if (sug.ok) {
        const sugIni = new Date(
          inicio.getFullYear(),
          inicio.getMonth(),
          inicio.getDate(),
          Math.floor(sug.startMin / 60),
          sug.startMin % 60,
          0,
          0
        );
        const sugFin = new Date(sugIni.getTime() + durMin * 60000);

        sugerencia = {
          startMin: sug.startMin,
          endMin: sug.endMin,
          suggestedInicio: sugIni,
          suggestedFin: sugFin,
          startHHmm: `${String(Math.floor(sug.startMin / 60)).padStart(
            2,
            "0"
          )}:${String(sug.startMin % 60).padStart(2, "0")}`,
        };
      }
    }

    // ✅ 2) solapes reales
    const solapes = dto.conjuntoId
      ? await buscarSolapesEnConjunto(this.prisma, {
          conjuntoId: dto.conjuntoId,
          fechaInicio: inicio,
          fechaFin: fin,
          incluirBorrador: true,
          excluirEstados: ["PENDIENTE_REPROGRAMACION"],
        })
      : [];

    if (solapes.length) {
      const esCorrectivaP1 =
        dto.tipo === "CORRECTIVA" && (dto.prioridad ?? 2) === 1;

      if (!esCorrectivaP1) {
        throw new Error("HAY_SOLAPE_CON_TAREAS_EXISTENTES");
      }

      const reemplazables = solapes.filter(
        (t) => t.tipo === "PREVENTIVA" && (t.prioridad ?? 2) > 1
      );

      return {
        needsReplacement: true,
        message:
          "La correctiva prioridad 1 se solapa. Puedes reemplazar una preventiva (prioridad 2 o 3) o usar el horario sugerido.",
        solapes,
        reemplazables,
        suggestedInicio: sugerencia?.suggestedInicio ?? null,
        suggestedFin: sugerencia?.suggestedFin ?? null,
        startHHmm: sugerencia?.startHHmm ?? null,
      };
    }

    // ✅ 3) crear si no hay solape
    return this.prisma.tarea.create({
      data: {
        descripcion: dto.descripcion,
        fechaInicio: inicio,
        fechaFin: fin,
        duracionMinutos: durMin,
        estado: EstadoTarea.ASIGNADA,
        tipo: (dto.tipo ?? "CORRECTIVA") as any,
        prioridad: dto.prioridad ?? 2,
        borrador: false,

        evidencias: dto.evidencias ?? [],
        insumosUsados: dto.insumosUsados ?? [],
        ubicacionId: dto.ubicacionId,
        elementoId: dto.elementoId,
        conjuntoId: dto.conjuntoId ?? null,
        supervisorId:
          dto.supervisorId != null ? String(dto.supervisorId) : null,

        periodoAnio,
        periodoMes,

        ...(dto.operariosIds?.length
          ? {
              operarios: {
                connect: dto.operariosIds.map((id) => ({ id: String(id) })),
              },
            }
          : dto.operarioId
          ? { operarios: { connect: { id: String(dto.operarioId) } } }
          : {}),
      },
    });
  }

  async asignarTareaConReemplazo(payload: unknown) {
    const { tarea, reemplazarIds } = AsignarConReemplazoDTO.parse(payload);
    const dto = CrearTareaDTO.parse(tarea);

    if (dto.tipo !== "CORRECTIVA" || (dto.prioridad ?? 2) !== 1) {
      throw new Error("Solo aplica para CORRECTIVA prioridad 1.");
    }
    if (!dto.conjuntoId) throw new Error("conjuntoId requerido.");

    return this.prisma.$transaction(async (tx) => {
      const targets = await tx.tarea.findMany({
        where: {
          id: { in: reemplazarIds },
          conjuntoId: dto.conjuntoId!,
          tipo: "PREVENTIVA" as any,
          borrador: false,
        },
        select: {
          id: true,
          fechaInicio: true,
          fechaFin: true,
          prioridad: true,
          tipo: true,
          descripcion: true,
        },
      });

      if (targets.length !== reemplazarIds.length) {
        throw new Error(
          "Algunas tareas a reemplazar no existen o no son preventivas publicadas."
        );
      }

      // Exigir que sean prioridad 2 o 3 y que choquen
      for (const t of targets) {
        if ((t.prioridad ?? 2) <= 1) {
          throw new Error(
            `La tarea ${t.id} es prioridad 1; NO se permite reemplazar.`
          );
        }
        const choca =
          t.fechaInicio < dto.fechaFin && t.fechaFin > dto.fechaInicio;
        if (!choca) {
          throw new Error(
            `La tarea ${t.id} no se solapa; no se puede reemplazar.`
          );
        }
      }

      await tx.tarea.updateMany({
        where: { id: { in: reemplazarIds } },
        data: {
          estado: EstadoTarea.PENDIENTE_REPROGRAMACION,
          observaciones: "Reemplazada por correctiva prioridad 1",
        },
      });

      // Crear correctiva
      const periodoAnio = dto.fechaInicio.getFullYear();
      const periodoMes = dto.fechaInicio.getMonth() + 1;

      const creada = await tx.tarea.create({
        data: {
          descripcion: dto.descripcion,
          fechaInicio: dto.fechaInicio,
          fechaFin: dto.fechaFin,
          duracionMinutos: dto.duracionMinutos,
          estado: EstadoTarea.ASIGNADA,
          tipo: "CORRECTIVA" as any,
          prioridad: 1,
          borrador: false,

          evidencias: dto.evidencias ?? [],
          insumosUsados: dto.insumosUsados ?? [],
          ubicacionId: dto.ubicacionId,
          elementoId: dto.elementoId,
          conjuntoId: dto.conjuntoId ?? null,
          supervisorId:
            dto.supervisorId != null ? String(dto.supervisorId) : null,
          periodoAnio,
          periodoMes,

          ...(dto.operariosIds?.length
            ? {
                operarios: {
                  connect: dto.operariosIds.map((id) => ({ id: String(id) })),
                },
              }
            : dto.operarioId
            ? { operarios: { connect: { id: String(dto.operarioId) } } }
            : {}),
        },
      });

      return {
        ok: true,
        creada,
        reemplazadas: targets,
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
        supervisor: {
          include: {
            usuario: true,
          },
        },
        operarios: {
          include: {
            usuario: true,
          },
        },
      },
      orderBy: { fechaInicio: "desc" },
    });

    return tareas.map((t) => {
      const operariosNombres =
        t.operarios
          ?.map((o) => o.usuario?.nombre)
          .filter((n): n is string => !!n) ?? [];

      const operariosIds = t.operarios?.map((o) => Number(o.id)) ?? [];

      const supervisorNombre = t.supervisor?.usuario?.nombre ?? null;

      return {
        id: t.id,
        descripcion: t.descripcion,
        fechaInicio: t.fechaInicio,
        fechaFin: t.fechaFin,
        duracionMinutos: t.duracionMinutos,
        estado: t.estado,
        evidencias: t.evidencias,
        insumosUsados: t.insumosUsados,
        observaciones: t.observaciones,
        observacionesRechazo: t.observacionesRechazo,
        tipo: t.tipo,
        frecuencia: t.frecuencia,
        conjuntoId: t.conjuntoId,
        supervisorId: t.supervisorId ? Number(t.supervisorId) : null,
        ubicacionId: t.ubicacionId,
        elementoId: t.elementoId,

        operariosIds,
        operariosNombres,
        supervisorNombre,
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
    reemplazos: { conjuntoId: string; nuevoAdminId: number }[]
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
