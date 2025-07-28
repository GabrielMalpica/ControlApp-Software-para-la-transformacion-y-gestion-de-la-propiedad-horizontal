import { PrismaClient, EstadoMaquinaria, EstadoTarea, TipoMaquinaria, TipoFuncion } from '../generated/prisma';
import bcrypt from "bcrypt";
import { FileStorageService } from "./FileStorageService";

export class GerenteService {
  constructor(private prisma: PrismaClient) {}

  async crearUsuario(
    id: number,
    nombre: string,
    correo: string,
    contrasenaPlano: string,
    telefono: number,
    fechaNacimiento: Date,
    rol: string
  ) {
    const existe = await this.prisma.usuario.findUnique({ where: { id } });
    if (existe) throw new Error("Ya existe un usuario con esa cédula.");

    const hash = await bcrypt.hash(contrasenaPlano, 10);

    return await this.prisma.usuario.create({
      data: {
        id,
        nombre,
        correo,
        contrasena: hash,
        telefono,
        fechaNacimiento,
        rol
      },
    });
  }

  async asignarGerente(usuarioId: number, nit: string) {
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit },
    });

    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");

    const gerente = await this.prisma.gerente.create({
      data: {
        id: usuarioId,
        empresaId: empresa.nit,
      },
      include: {
        usuario: true,
        empresa: true,
      },
    });

    return gerente;
  }

  async asignarAdministrador(usuarioId: number) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: usuarioId },
    });

    if (!usuario) throw new Error("❌ Usuario no encontrado.");

    const administrador = await this.prisma.administrador.create({
      data: {
        id: usuarioId,
      },
      include: {
        usuario: true,
        conjuntos: true,
      },
    });

    return administrador;
  }

  async asignarJefeOperaciones(usuarioId: number, nit: string) {
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit },
    });

    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");

    return await this.prisma.jefeOperaciones.create({
      data: {
        id: usuarioId,
        empresaId: empresa.nit,
      },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarSupervisor(usuarioId: number, nit: string) {
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit },
    });

    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");

    return await this.prisma.supervisor.create({
      data: {
        id: usuarioId,
        empresaId: empresa.nit,
      },
      include: { usuario: true, empresa: true },
    });
  }

  async asignarOperario(
    usuarioId: number,
    funciones: TipoFuncion[]
  ) {
    const nit = '901191875-4'
    const empresa = await this.prisma.empresa.findUnique({
      where: { nit },
    });

    if (!empresa) throw new Error("❌ Empresa no encontrada con ese NIT.");

    return await this.prisma.operario.create({
      data: {
        id: usuarioId,
        empresaId: empresa.nit,
        funciones,
        cursoSalvamentoAcuatico: false,
        cursoAlturas: false,
        examenIngreso: false,
        fechaIngreso: new Date(),
      },
      include: {
        usuario: true,
        empresa: true,
      },
    });
  }

  async crearAdministrador(
    id: number,
    nombre: string,
    correo: string,
    contrasena: string,
    telefono: number,
    fechaNacimiento: Date,
  ) {
    const existente = await this.prisma.usuario.findUnique({
      where: { id: id }
    });

    if (existente) {
      throw new Error(`⚠️ Ya existe un usuario con la cédula ${id}`);
    }

    const hash = await bcrypt.hash(contrasena, 10);

    return await this.prisma.usuario.create({
      data: {
        id: id,
        nombre: nombre,
        correo: correo,
        contrasena: hash,
        telefono: telefono,
        fechaNacimiento: fechaNacimiento,
        rol: "ADMINISTRADOR",
      },
    });
  }



  async crearConjunto(data: {
    nit: string;
    nombre: string;
    direccion: string;
    correo: string;
  }) {
    return await this.prisma.conjunto.create({
      data: {
        nit: data.nit,
        nombre: data.nombre,
        direccion: data.direccion,
        empresaId: '901191875-4',
        correo: data.correo
        
      },
    });
  }

  async asignarOperarioAConjunto(operarioId: number, conjuntoId: string) {
    return await this.prisma.operario.update({
      where: { id: operarioId },
      data: {
        conjuntos: {
          connect: { nit: conjuntoId },
        },
      },
    });
  }

  async agregarInsumoAConjunto(conjuntoId: string, insumoId: number, cantidad: number) {
    // Buscar el inventario del conjunto
    const inventario = await this.prisma.inventario.findUnique({
      where: { conjuntoId },
    });

    if (!inventario) {
      throw new Error(`❌ No se encontró inventario para el conjunto con ID ${conjuntoId}`);
    }

    // Buscar si ya existe el insumo en el inventario
    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: {
        inventarioId: inventario.id,
        insumoId: insumoId,
      },
    });

    if (existente) {
      // Incrementar cantidad
      return await this.prisma.inventarioInsumo.update({
        where: { id: existente.id },
        data: {
          cantidad: {
            increment: cantidad,
          },
        },
      });
    }

    // Si no existe, crear nuevo registro
    return await this.prisma.inventarioInsumo.create({
      data: {
        inventarioId: inventario.id,
        insumoId: insumoId,
        cantidad: cantidad,
      },
    });
  }

  async crearMaquinaria(nombre: string, marca: string, tipo: TipoMaquinaria, empresaId: number) {
    return await this.prisma.maquinaria.create({
      data: {
        nombre: nombre,
        marca: marca,
        tipo,
        estado: "OPERATIVA", // o EstadoMaquinaria.OPERATIVA si usas enum
        disponible: true,
        empresa: {
          connect: { id: empresaId }
        }
      }
    });
  }


  async entregarMaquinariaAConjunto(maquinariaId: number, conjuntoId: string) {
    return await this.prisma.maquinaria.update({
      where: { id: maquinariaId },
      data: {
        disponible: false,
        asignadaA: { connect: { nit: conjuntoId } },
      },
    });
  }

  async asignarTarea(data: {
    descripcion: string;
    fechaInicio: Date;
    fechaFin: Date;
    duracionHoras: number;
    operarioId: number;
    ubicacionId: number;
    elementoId: number;
    conjuntoId: string;
  }) {
    return await this.prisma.tarea.create({
      data: {
        ...data,
        estado: "ASIGNADA",
        insumosUsados: {
          create: []
        }
      },
    });
  }


  async eliminarAdministrador(adminId: number) {
    const asignaciones = await this.prisma.conjunto.findMany({
      where: { administradorId: adminId },
    });

    if (asignaciones.length > 0) {
      throw new Error("❌ El administrador tiene conjuntos asignados.");
    }

    await this.prisma.usuario.delete({ where: { id: adminId } });
  }

  async reemplazarAdminEnVariosConjuntos(
    reemplazos: { conjuntoId: string; nuevoAdminId: number }[]
  ) {
    if (reemplazos.length === 0) return;

    for (const { conjuntoId, nuevoAdminId } of reemplazos) {
      await this.prisma.conjunto.update({
        where: { nit: conjuntoId },
        data: { administradorId: nuevoAdminId },
      });
    }
  }

  async eliminarOperario(operarioId: number) {
    const tareasPendientes = await this.prisma.tarea.findMany({
      where: {
        operarioId: operarioId,
        estado: {
          in: ["ASIGNADA", "EN_PROCESO", "PENDIENTE_APROBACION"]
        }
      }
    });

    if (tareasPendientes.length > 0) {
      throw new Error("❌ El operario tiene tareas pendientes.");
    }

    await this.prisma.operario.delete({ where: { id: operarioId } });
  }

  async eliminarSupervisor(supervisorId: number) {
    await this.prisma.supervisor.delete({
      where: { id: supervisorId }
    });
  }

  async eliminarConjunto(conjuntoId: string) {
    const tareasPendientes = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        estado: {
          in: ["ASIGNADA", "EN_PROCESO", "PENDIENTE_APROBACION"]
        }
      }
    });

    const maquinariaPrestada = await this.prisma.maquinaria.findMany({
      where: {
        conjuntoId: conjuntoId,
        disponible: false
      }
    });

    if (tareasPendientes.length > 0) {
      throw new Error("❌ El conjunto tiene tareas pendientes.");
    }

    if (maquinariaPrestada.length > 0) {
      throw new Error("❌ El conjunto tiene maquinaria prestada.");
    }

    await this.prisma.conjunto.delete({
      where: { nit: conjuntoId }
    });
  }

  async eliminarMaquinaria(maquinariaId: number) {
    await this.prisma.maquinaria.delete({
      where: { id: maquinariaId }
    });
  }

  async eliminarTarea(tareaId: number) {
    await this.prisma.tarea.delete({
      where: { id: tareaId }
    });
  }

  async editarAdministrador(adminId: number, nuevosDatos: Partial<{ nombre: string; correo: string }>) {
    await this.prisma.usuario.update({
      where: { id: adminId },
      data: nuevosDatos
    });
  }

  async editarOperario(
    operarioId: number,
    nuevosDatos: Partial<{
      nombre: string;
      correo: string;
      funciones: TipoFuncion[];
    }>
  ) {
    const data: any = {};

    if (nuevosDatos.nombre) data.nombre = nuevosDatos.nombre;
    if (nuevosDatos.correo) data.correo = nuevosDatos.correo;

    if (nuevosDatos.funciones) {
      // Validamos que cada string sea un valor válido del enum
      const funcionesValidas = nuevosDatos.funciones.filter(f =>
        Object.values(TipoFuncion).includes(f as TipoFuncion)
      );

      data.funciones = funcionesValidas as TipoFuncion[];
    }

    await this.prisma.operario.update({
      where: { id: operarioId },
      data
    });
  }

  async editarSupervisor(
    supervisorId: number,
    nuevosDatos: Partial<{ nombre: string; correo: string }>
  ) {
    const data: any = {};

    if (nuevosDatos.nombre) {
      data.nombre = nuevosDatos.nombre;
    }

    if (nuevosDatos.correo) {
      data.correo = nuevosDatos.correo;
    }

    if (Object.keys(data).length === 0) {
      throw new Error("❗ Debes proporcionar al menos un dato para actualizar.");
    }

    return await this.prisma.supervisor.update({
      where: { id: supervisorId },
      data
    });
  }


  async editarConjunto(conjuntoId: string, nuevosDatos: Partial<{ nombre: string; direccion: string; correo: string }>) {
    await this.prisma.conjunto.update({
      where: { nit: conjuntoId },
      data: nuevosDatos
    });
  }

  async editarMaquinaria(
    maquinariaId: number,
    nuevosDatos: Partial<{ nombre: string; marca: string; tipo: TipoMaquinaria }>
  ) {
    const data: any = {};

    if (nuevosDatos.nombre) data.nombre = nuevosDatos.nombre;
    if (nuevosDatos.marca) data.marca = nuevosDatos.marca;
    if (nuevosDatos.tipo) data.tipo = { set: nuevosDatos.tipo };

    if (Object.keys(data).length === 0) {
      throw new Error("❗ Debes proporcionar al menos un campo para actualizar.");
    }

    return await this.prisma.maquinaria.update({
      where: { id: maquinariaId },
      data
    });
  }

  async editarTarea(tareaId: number, nuevosDatos: Partial<{ descripcion: string; fechaInicio: Date; fechaFin: Date; duracionHoras: number }>) {
    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: nuevosDatos
    });
  }

}