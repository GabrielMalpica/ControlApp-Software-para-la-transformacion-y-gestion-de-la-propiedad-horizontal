import { Administrador } from "./administrador";
import { Conjunto } from "./conjunto";
import { EstadoMaquinaria } from "./enum/estadoMaquinaria";
import { EstadoTarea } from "./enum/estadoTarea";
import { TipoFuncion } from "./enum/tipoFuncion";
import { TipoMaquinaria } from "./enum/tipoMaquinaria";
import { Insumo } from "./insumo";
import { Maquinaria } from "./maquinaria";
import { Operario } from "./operario";
import { SolicitudTarea } from "./solicitudTarea";
import { Supervisor } from "./supervisor";
import { Tarea } from "./tarea";
import { Usuario } from "./usuario";

export class Gerente extends Usuario {
  stockMaquinaria: Maquinaria[] = [];
  solicitudesPendientes: SolicitudTarea[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'gerente');
  }

  // Administradores
  crearAdministrador(id: number, nombre: string, correo: string): Administrador {
    return new Administrador(id, nombre, correo);
  }

  // Conjuntos
  crearConjunto(id: number, nombre: string, direccion: string, admin: Administrador, correo: string): Conjunto {
    return new Conjunto(id, nombre, direccion, admin, correo);
  }

  // Operarios
  crearOperario(id: number, nombre: string, correo: string, funciones: TipoFuncion[]): Operario {
    return new Operario(id, nombre, correo, funciones);
  }

  crearSupervisor(id: number, nombre: string, correo: string): Supervisor {
    return new Supervisor(id, nombre, correo);
  }

  asignarOperarioAConjunto(operario: Operario, conjunto: Conjunto): void {
    conjunto.asignarOperario(operario);
  }

  // Insumos
  agregarInsumoAConjunto(conjunto: Conjunto, nombre: string, cantidad: number, unidad: string): void {
    const insumo = new Insumo(nombre, cantidad, unidad);
    conjunto.inventario.agregarInsumo(insumo);
  }

  // Maquinaria
  crearMaquinaria(nombre: string, marca: string, tipo: TipoMaquinaria): void {
    const id = this.stockMaquinaria.length + 1;
    const maquina = new Maquinaria(id, nombre, marca, tipo, EstadoMaquinaria.OPERATIVA, true);
    this.stockMaquinaria.push(maquina);
  }

  entregarMaquinariaAConjunto(nombre: string, conjunto: Conjunto): void {
    const maquina = this.stockMaquinaria.find(m => m.nombre === nombre && m.disponible);
    if (!maquina) throw new Error('Maquinaria no disponible u operativa');

    maquina.asignarAConjunto(conjunto);
    conjunto.agregarMaquinaria(maquina);
    this.stockMaquinaria = this.stockMaquinaria.filter(m => m !== maquina);
  }

  recibirMaquinariaDeConjunto(nombre: string, conjunto: Conjunto): void {
    const maquina = conjunto.entregarMaquinaria(nombre);
    if (!maquina) throw new Error('El conjunto no tiene esa maquinaria');

    maquina.devolver();
    this.stockMaquinaria.push(maquina);
  }

  // Consultas
  listarMaquinariaDisponible(): Maquinaria[] {
    return this.stockMaquinaria.filter(m => m.disponible);
  }

  maquinariaDisponible(id: number): boolean {
    const maquina = this.stockMaquinaria.find(m => m.id === id);
    return maquina !== undefined && maquina.disponible;
  }

  // Tareas
  asignarTarea(tarea: Tarea): void {
    const operario = tarea.asignadoA;
    const horasRestantes = operario.horasRestantesEnSemana(tarea.fechaInicio);

    if (tarea.duracionHoras > horasRestantes) {
      throw new Error(`❌ El operario ${operario.nombre} solo tiene ${horasRestantes}h disponibles esta semana.`);
    }

    operario.asignarTarea(tarea);
  }

  reprogramarTarea(tarea: Tarea, nuevaFechaInicio: Date, nuevaFechaFin: Date): void {
    tarea.fechaInicio = nuevaFechaInicio;
    tarea.fechaFin = nuevaFechaFin;
    tarea.estado = EstadoTarea.ASIGNADA;
    tarea.fechaCompletado = undefined;
    tarea.verificadaPor = undefined;
    tarea.fechaVerificacion = undefined;
    tarea.observacionesRechazo = undefined;
    tarea.evidencias = [];
  }

  recibirSolicitud(solicitud: SolicitudTarea): void {
    this.solicitudesPendientes.push(solicitud);
  }

  aprobarSolicitud(solicitudId: number, operario: Operario, fechaInicio: Date, fechaFin: Date): void {
  const solicitud = this.solicitudesPendientes.find(s => s.id === solicitudId);
  if (!solicitud) throw new Error("Solicitud no encontrada");

  solicitud.aprobar();

  const ubicacion = solicitud.conjunto.ubicaciones.find(u => u.nombre === solicitud.ubicacion);
  const elemento = ubicacion?.elementos.find(e => e.nombre === solicitud.elemento);
  if (!ubicacion || !elemento) throw new Error("Ubicación o elemento no encontrado");

  const tarea = new Tarea(
    solicitudId,
    solicitud.descripcion,
    fechaInicio,
    fechaFin,
    ubicacion,
    elemento,
    solicitud.duracionHoras,
    operario
  );

  this.asignarTarea(tarea); // ya hace la validación de horas y todo
  solicitud.conjunto.agregarTareaACronograma(tarea);

  // Eliminar de la bandeja
  this.solicitudesPendientes = this.solicitudesPendientes.filter(s => s.id !== solicitudId);
}
}
