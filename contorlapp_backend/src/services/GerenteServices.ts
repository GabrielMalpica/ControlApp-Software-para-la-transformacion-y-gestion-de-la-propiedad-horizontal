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
import { EmpresaService } from "./EmpresaServices";
import { AuthService } from "./authService";

export class GerenteService {
  constructor(private gerente: Gerente, private empresa: Empresa) {}

  crearAdministrador(id: number, nombre: string, correo: string, constrasena: string): Administrador {
    const administrador = new Administrador(id, nombre, correo, constrasena);
    const authService = new AuthService(this.empresa);
    authService.registrarUsuario(this.gerente, administrador);
    return administrador;
  }

  crearConjunto(id: number, nombre: string, direccion: string, correo: string): Conjunto {
    const conjunto = new Conjunto(id, nombre, direccion, correo);
    this.empresa.conjuntos.push(conjunto);
    return conjunto;
  }

  crearOperario(id: number, nombre: string, correo: string, constrasena: string, funciones: TipoFuncion[]): Operario {
    const operario = new Operario(id, nombre, correo, constrasena, funciones);
    const authService = new AuthService(this.empresa);
    authService.registrarUsuario(this.gerente, operario);
    return operario;
  }

  crearSupervisor(id: number, nombre: string, correo: string, constrasena: string): Supervisor {
    const supervisor = new Supervisor(id, nombre, correo, constrasena);
    const authService = new AuthService(this.empresa);
    authService.registrarUsuario(this.gerente, supervisor);
    return supervisor;
  }

  asignarOperarioAConjunto(operario: Operario, conjunto: Conjunto): void {
    const conjuntoService = new ConjuntoService(conjunto);
    conjuntoService.asignarOperario(operario);
  }

  asignarAdministradorAConjunto(administrador: Administrador, conjunto: Conjunto): void {
    const conjuntoService = new ConjuntoService(conjunto);
    conjuntoService.asignarAdministrador(administrador); 
  }

  agregarInsumoAConjunto(conjunto: Conjunto, insumo: Insumo, cantidad: number): void {
    const inventarioService = new InventarioService(conjunto.inventario);
    inventarioService.agregarInsumo(insumo, cantidad);
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

  asignarTarea(tarea: Tarea, conjunto: Conjunto): void {
    const operario = tarea.asignadoA;
    const operarioService = new OperarioService(operario, this.empresa);
    const horasRestantes = operarioService.horasRestantesEnSemana(tarea.fechaInicio);

    if (tarea.duracionHoras > horasRestantes) {
      throw new Error(`❌ El operario ${operario.nombre} solo tiene ${horasRestantes}h disponibles esta semana.`);
    }

    operarioService.asignarTarea(tarea);

    const conjuntoService = new ConjuntoService(conjunto);
    conjuntoService.agregarTareaACronograma(tarea);
  }


  reprogramarTarea(tarea: Tarea, nuevaFechaInicio: Date, nuevaFechaFin: Date): void {
    tarea.fechaInicio = nuevaFechaInicio;
    tarea.fechaFin = nuevaFechaFin;
    tarea.estado = EstadoTarea.ASIGNADA;
    tarea.fechaFinalizarTarea = undefined;
    tarea.verificadaPor = undefined;
    tarea.fechaVerificacion = undefined;
    tarea.observacionesRechazo = undefined;
    tarea.evidencias = [];
  }

  recibirSolicitud(solicitud: SolicitudTarea): void {
    this.empresa.solicitudesTareas.push(solicitud);
  }

  aprobarSolicitud(solicitudId: number, operario: Operario, conjunto: Conjunto, fechaInicio: Date, fechaFin: Date): void {
    const solicitud = this.empresa.solicitudesTareas.find(s => s.id === solicitudId);
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

    this.asignarTarea(tarea, conjunto);
    conjuntoService.agregarTareaACronograma(tarea);

    this.empresa.solicitudesTareas = this.empresa.solicitudesTareas.filter(s => s.id !== solicitudId);
  }

  verMaquinariaDisponible(): string[] {
    const servicio = new EmpresaService(this.empresa);
    return servicio.obtenerMaquinariaDisponible().map(m =>
      `🔹 ${m.nombre} (${m.marca}) - ${m.tipo}`
    );
  }

  verMaquinariaPrestada(): string[] {
    const servicio = new EmpresaService(this.empresa);
    return servicio.obtenerMaquinariaPrestada().map(info =>
      `🔧 ${info.maquina.nombre} → Conjunto: ${info.conjunto}, Responsable: ${info.responsable}, Prestada desde: ${info.fechaPrestamo.toLocaleDateString()}`
    );
  }

  // ─── Eliminaciones ──────────────────────────────────────

  eliminarAdministrador(admin: Administrador): void {
    const sigueAsignado = admin.conjuntos.length > 0;

    if (sigueAsignado) {
      throw new Error(`❌ No se puede eliminar a ${admin.nombre} porque está asignado a un conjunto.`);
    }

    const authService = new AuthService(this.empresa);
    authService.usuariosRegistrados = authService.usuariosRegistrados.filter(
      u => u.correo !== admin.correo
    );
  }


  reemplazarAdminEnVariosConjuntos(
    reemplazos: { conjunto: Conjunto; nuevoAdmin: Administrador }[]
  ): void {
    if (reemplazos.length === 0) return;

    const anteriorAdmin = reemplazos[0].conjunto.administrador;
    if (!anteriorAdmin) return;

    for (const { conjunto, nuevoAdmin } of reemplazos) {
      const conjuntoService = new ConjuntoService(conjunto);
      conjuntoService.eliminarAdministrador();     // ✅ elimina vínculo si lo había
      conjuntoService.asignarAdministrador(nuevoAdmin); // ✅ asigna el nuevo
    }

    // Solo eliminamos si ya no tiene conjuntos asignados
    const sigueEnUso = anteriorAdmin.conjuntos.length > 0;

    if (!sigueEnUso) {
      const authService = new AuthService(this.empresa);
      authService.usuariosRegistrados = authService.usuariosRegistrados.filter(
        u => u !== anteriorAdmin
      );
    }
  }


  eliminarOperario(operario: Operario): void {
    const tieneTareasPendientes = operario.tareas.some(t =>
      [EstadoTarea.ASIGNADA, EstadoTarea.EN_PROCESO, EstadoTarea.PENDIENTE_APROBACION].includes(t.estado)
    );

    if (tieneTareasPendientes) {
      throw new Error(`❌ No se puede eliminar a ${operario.nombre} porque tiene tareas pendientes.`);
    }

    const authService = new AuthService(this.empresa);
    authService.usuariosRegistrados = authService.usuariosRegistrados.filter(u => u !== operario);
    operario.conjuntos.forEach(c => {
      c.operarios = c.operarios.filter(o => o !== operario);
    });
  }

  eliminarSupervisor(supervisor: Supervisor): void {
    const authService = new AuthService(this.empresa);
    authService.usuariosRegistrados = authService.usuariosRegistrados.filter(
      u => u.correo !== supervisor.correo
    );
  }

  eliminarConjunto(conjunto: Conjunto): void {
    const tieneTareasPendientes = conjunto.cronograma.some(t =>
      [EstadoTarea.ASIGNADA, EstadoTarea.EN_PROCESO, EstadoTarea.PENDIENTE_APROBACION].includes(t.estado)
    );

    const tieneMaquinaria = conjunto.maquinariaPrestada.length > 0;

    if (tieneTareasPendientes) {
      throw new Error(`❌ No se puede eliminar el conjunto ${conjunto.nombre} porque tiene tareas pendientes.`);
    }

    if (tieneMaquinaria) {
      throw new Error(`❌ No se puede eliminar el conjunto ${conjunto.nombre} porque tiene maquinaria prestada.`);
    }

    this.empresa.conjuntos = this.empresa.conjuntos.filter(c => c !== conjunto);
  }


  eliminarMaquinaria(maquinariaId: number): void {
    this.empresa.stockMaquinaria = this.empresa.stockMaquinaria.filter(m => m.id !== maquinariaId);
  }

  eliminarTarea(tarea: Tarea, conjunto: Conjunto): void {
    conjunto.cronograma = conjunto.cronograma.filter(t => t !== tarea);
    const operario = tarea.asignadoA;
    operario.tareas = operario.tareas.filter(t => t !== tarea);
  }


  // ─── Ediciones ──────────────────────────────────────────

  editarAdministrador(admin: Administrador, nuevosDatos: Partial<Administrador>): void {
    if (nuevosDatos.nombre) admin.nombre = nuevosDatos.nombre;
    if (nuevosDatos.correo) admin.correo = nuevosDatos.correo;
  }

  editarOperario(operario: Operario, nuevosDatos: Partial<Operario>): void {
    if (nuevosDatos.nombre) operario.nombre = nuevosDatos.nombre;
    if (nuevosDatos.correo) operario.correo = nuevosDatos.correo;
    if (nuevosDatos.funciones) operario.funciones = nuevosDatos.funciones;
  }

  editarSupervisor(supervisor: Supervisor, nuevosDatos: Partial<Supervisor>): void {
    if (nuevosDatos.nombre) supervisor.nombre = nuevosDatos.nombre;
    if (nuevosDatos.correo) supervisor.correo = nuevosDatos.correo;
  }

  editarConjunto(conjunto: Conjunto, nuevosDatos: Partial<Conjunto>): void {
    if (nuevosDatos.nombre) conjunto.nombre = nuevosDatos.nombre;
    if (nuevosDatos.direccion) conjunto.direccion = nuevosDatos.direccion;
    if (nuevosDatos.correo) conjunto.correo = nuevosDatos.correo;
  }

  editarMaquinaria(maquina: Maquinaria, nuevosDatos: Partial<Maquinaria>): void {
    if (nuevosDatos.nombre) maquina.nombre = nuevosDatos.nombre;
    if (nuevosDatos.marca) maquina.marca = nuevosDatos.marca;
    if (nuevosDatos.tipo) maquina.tipo = nuevosDatos.tipo;
  }

  editarTarea(tarea: Tarea, nuevosDatos: Partial<Tarea>): void {
    if (nuevosDatos.descripcion) tarea.descripcion = nuevosDatos.descripcion;
    if (nuevosDatos.fechaInicio) tarea.fechaInicio = nuevosDatos.fechaInicio;
    if (nuevosDatos.fechaFin) tarea.fechaFin = nuevosDatos.fechaFin;
    if (nuevosDatos.duracionHoras) tarea.duracionHoras = nuevosDatos.duracionHoras;
  }

}
