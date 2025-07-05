import { Administrador } from "../model/administrador";
import { Conjunto } from "../model/conjunto";
import { Insumo } from "../model/insumo";
import { Maquinaria } from "../model/maquinaria";
import { Operario } from "../model/operario";
import { SolicitudTarea } from "../model/solicitudTarea";
import { Supervisor } from "../model/supervisor";
import { Tarea } from "../model/tarea";
import { Gerente } from "../model/gerente";
import { EstadoMaquinaria } from "../model/enum/estadoMaquinaria";
import { EstadoTarea } from "../model/enum/estadoTarea";
import { TipoFuncion } from "../model/enum/tipoFuncion";
import { TipoMaquinaria } from "../model/enum/tipoMaquinaria";
import { ConjuntoService } from "./ConjuntoServices";
import { InventarioService } from "./InventarioServices";
import { MaquinariaService } from "./MaquinariaServices";
import { OperarioService } from "./OperarioServices";
import { SolicitudTareaService } from "./SolicitudTareaServices";
import { Empresa } from "../model/Empresa";

export class GerenteService {
  constructor(private gerente: Gerente, private empresa: Empresa) {}

  crearAdministrador(id: number, nombre: string, correo: string): Administrador {
    return new Administrador(id, nombre, correo);
  }

  crearConjunto(id: number, nombre: string, direccion: string, admin: Administrador, correo: string): Conjunto {
    return new Conjunto(id, nombre, direccion, admin, correo);
  }

  crearOperario(id: number, nombre: string, correo: string, funciones: TipoFuncion[]): Operario {
    return new Operario(id, nombre, correo, funciones);
  }

  crearSupervisor(id: number, nombre: string, correo: string): Supervisor {
    return new Supervisor(id, nombre, correo);
  }

  asignarOperarioAConjunto(operario: Operario, conjunto: Conjunto): void {
    const conjuntoService = new ConjuntoService(conjunto);
    conjuntoService.asignarOperario(operario);
  }

  asignarAdministradorAConjunto(administrador: Administrador, conjunto: Conjunto): void {
    const conjuntoService = new ConjuntoService(conjunto);
    conjuntoService.asignarAdministrador(administrador); 
  }

  agregarInsumoAConjunto(conjunto: Conjunto, nombre: string, cantidad: number, unidad: string): void {
    const insumo = new Insumo(nombre, cantidad, unidad);
    const inventarioService = new InventarioService(conjunto.inventario);
    inventarioService.agregarInsumo(insumo);
  }

  crearMaquinaria(nombre: string, marca: string, tipo: TipoMaquinaria): void {
    const id = this.empresa.stockMaquinaria.length + 1;
    const maquina = new Maquinaria(id, nombre, marca, tipo, EstadoMaquinaria.OPERATIVA, true);
    this.empresa.stockMaquinaria.push(maquina);
  }

  entregarMaquinariaAConjunto(nombre: string, conjunto: Conjunto): void {
    const maquina = this.empresa.stockMaquinaria.find(m => m.nombre === nombre && m.disponible);
    if (!maquina) throw new Error('Maquinaria no disponible u operativa');

    const maquinariaService = new MaquinariaService(maquina);
    maquinariaService.asignarAConjunto(conjunto);

    const conjuntoService = new ConjuntoService(conjunto);
    conjuntoService.agregarMaquinaria(maquina);

    this.empresa.stockMaquinaria = this.empresa.stockMaquinaria.filter(m => m !== maquina);
  }

  recibirMaquinariaDeConjunto(nombre: string, conjunto: Conjunto): void {
    const conjuntoService = new ConjuntoService(conjunto);
    const maquina = conjuntoService.entregarMaquinaria(nombre);

    if (!maquina) throw new Error('El conjunto no tiene esa maquinaria');

    const maquinariaService = new MaquinariaService(maquina);
    maquinariaService.devolver();

    this.empresa.stockMaquinaria.push(maquina);
  }

  listarMaquinariaDisponible(): Maquinaria[] {
    return this.empresa.stockMaquinaria.filter(m => m.disponible);
  }

  maquinariaDisponible(id: number): boolean {
    const maquina = this.empresa.stockMaquinaria.find(m => m.id === id);
    return maquina !== undefined && maquina.disponible;
  }

  asignarTarea(tarea: Tarea): void {
    const operario = tarea.asignadoA;
    const operarioService = new OperarioService(operario);
    const horasRestantes = operarioService.horasRestantesEnSemana(tarea.fechaInicio);
    
    if (tarea.duracionHoras > horasRestantes) {
      throw new Error(`❌ El operario ${operario.nombre} solo tiene ${horasRestantes}h disponibles esta semana.`);
    }

    operarioService.asignarTarea(tarea);
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
    this.gerente.solicitudesPendientes.push(solicitud);
  }

  aprobarSolicitud(solicitudId: number, operario: Operario, fechaInicio: Date, fechaFin: Date): void {
    const solicitud = this.gerente.solicitudesPendientes.find(s => s.id === solicitudId);
    if (!solicitud) throw new Error("Solicitud no encontrada");

    const solicitudService = new SolicitudTareaService(solicitud);
    solicitudService.aprobar();

    const conjuntoService = new ConjuntoService(solicitud.conjunto);
    const ubicacion = conjuntoService.buscarUbicacion(solicitud.ubicacion.nombre);
    const elemento = ubicacion?.elementos.find(e => e.nombre === solicitud.elemento.nombre);
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

    this.asignarTarea(tarea);
    conjuntoService.agregarTareaACronograma(tarea);

    this.gerente.solicitudesPendientes = this.gerente.solicitudesPendientes.filter(s => s.id !== solicitudId);
  }
}
