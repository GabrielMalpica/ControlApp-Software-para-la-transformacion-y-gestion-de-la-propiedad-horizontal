import express, { Request, Response } from 'express';
import { Gerente } from './model/gerente';
import { Empresa } from './model/Empresa';
import { JefeOperaciones } from './model/jefeOperaciones';
import { GerenteService } from './services/GerenteServices';
import { EmpresaService } from './services/EmpresaServices';
import { Administrador } from './model/administrador';
import { Supervisor } from './model/supervisor';
import { Operario } from './model/operario';
import { Conjunto } from './model/conjunto';
import { TipoFuncion } from './model/enum/tipoFuncion';
import { ConjuntoService } from './services/ConjuntoServices';
import { Ubicacion } from './model/ubicacion';
import { Elemento } from './model/elemento';
import { UbicacionService } from './services/UbicacionServices';
import { Maquinaria } from './model/maquinaria';
import { TipoMaquinaria } from './model/enum/tipoMaquinaria';
import { EstadoMaquinaria } from './model/enum/estadoMaquinaria';
import { Insumo } from './model/insumo';
import { SolicitudInsumo } from './model/SolicitudInsumo';
import { InventarioService } from './services/InventarioServices';
import { SolicitudMaquinaria } from './model/SolicitudMaquinaria';
import { SolicitudTarea } from './model/solicitudTarea';
import { SolicitudTareaService } from './services/SolicitudTareaServices';
import { Tarea } from './model/tarea';
import { TareaService } from './services/TareaServices';
import { OperarioService } from './services/OperarioServices';
import { SupervisorService } from './services/SupervisorServices';
import { Cronograma } from './model/cronograma';
import { CronogramaService } from './services/CronogramaServices';
import { AdministradorService } from './services/AdministradorServices';

const app = express();
app.use(express.json());

const gerente = new Gerente(1, "Carlos Gerente", "gerente@empresa.com");
const empresa = new Empresa("Control Limpieza S.A.S", "900123456", gerente);
const gerenteServices = new GerenteService(gerente, empresa);
const empresaServices = new EmpresaService(empresa);
const jefe1 = new JefeOperaciones(2, "Luis Operaciones", "jefe1@empresa.com");
empresaServices.agregarJefeOperaciones(jefe1);

const admin1 = gerenteServices.crearAdministrador(1, 'Patricia', 'patricia@gmail.com')
const adminServices = new AdministradorService(admin1)

const alborada = gerenteServices.crearConjunto(1, 'Alborada', 'Carrera x', admin1, 'alborada@gmail.com');
console.log(alborada.ubicaciones)
const jardin = new Ubicacion('Salon comunal', alborada)
console.log(alborada.ubicaciones)
const jardinServie = new UbicacionService(jardin)
const puerta = new Elemento('puerta')
jardinServie.agregarElemento(puerta)
const conjuntoService = new ConjuntoService(alborada);
conjuntoService.agregarUbicacion(jardin)

const babiera = gerenteServices.crearConjunto(2, 'Babiera', 'Carrera y', admin1, 'babiera@gmail.com')

const detergente = new Insumo(1, 'Detergente', '5 Litros');
const clorox = new Insumo(2, 'Clorox', '1L')

empresaServices.agregarInsumoAlCatalogo(detergente);
empresaServices.agregarInsumoAlCatalogo(clorox);

gerenteServices.agregarInsumoAConjunto(alborada, detergente, 3);

const operario = new Operario(1, 'Jaime', 'jaime@gmail.com', [TipoFuncion.SALVAVIDAS]);
gerenteServices.asignarOperarioAConjunto(operario, alborada);

console.log(alborada.cronograma)

const tarea = new Tarea(1, 'adfadf', new Date(), new Date(), alborada.ubicaciones[0], alborada.ubicaciones[0].elementos[0], 1, operario);
gerenteServices.asignarTarea(tarea, operario.conjuntos[0])
console.log(alborada.cronograma)



// const admin = new Administrador(3, "Ana Admin", "admin@empresa.com");
// const supervisor = new Supervisor(4, "Sandra Supervisora", "supervisor@empresa.com");
// const operario = new Operario(5, "Juan Operario", "juan@empresa.com", [TipoFuncion.ASEO]);

// const conjunto = new Conjunto(1, "Conjunto Alborada", "Cra 123 #45-67", admin, "alborada@conjunto.com");
// const conjuntoService = new ConjuntoService(conjunto);
// gerenteServices.asignarOperarioAConjunto(operario, conjunto);

// const jardin = new Ubicacion("Jardín Central");
// const podadora = new Elemento("Bancas");
// const ubicacionService = new UbicacionService(jardin);
// ubicacionService.agregarElemento(podadora);
// conjuntoService.agregarUbicacion(jardin);

// const m1 = new Maquinaria(1, "BadBoy", "BadBrand", TipoMaquinaria.CORTASETOS_ALTURA, EstadoMaquinaria.OPERATIVA);
// empresaServices.agregarMaquinaria(m1);
// console.log("✅ Maquinaria registrada en empresa:", m1.nombre);
// const cronograma = new Cronograma(conjunto);

// console.log('---------------------------------------')
// console.log('Inventario conjunto:',conjunto.inventario)
// console.log('Maquinaria conjunto conjunto:',conjunto.maquinariaPrestada)
// console.log('Cronograma conjunto conjunto:',conjunto.cronograma)

// const insumo = new Insumo("Detergente", 10, "litros");
// const solicitudInsumo = new SolicitudInsumo(1, [insumo], conjunto);
// empresa.solicitudesInsumos.push(solicitudInsumo);
// console.log("📦 Solicitud de insumos enviada por administrador.");

// console.log('---------------------------------------')
// console.log('Inventario conjunto:',conjunto.inventario)
// console.log('Maquinaria conjunto conjunto:',conjunto.maquinariaPrestada)
// console.log('Cronograma conjunto conjunto:',conjunto.cronograma)

// solicitudInsumo.aprobar();
// console.log("✅ Solicitud de insumos aprobada. Inventario actualizado:");
// const intentarioServices = new InventarioService(conjunto.inventario);
// intentarioServices.listarInsumos().forEach(i => console.log("🔹", i));

// console.log('---------------------------------------')
// console.log('Inventario conjunto:',conjunto.inventario)
// console.log('Maquinaria conjunto conjunto:',conjunto.maquinariaPrestada)
// console.log('Cronograma conjunto conjunto:',conjunto.cronograma)

// const solicitudMaq = new SolicitudMaquinaria(1, conjunto, m1, operario, new Date(), new Date());
// empresa.solicitudesMaquinaria.push(solicitudMaq);
// solicitudMaq.aprobar();
// console.log("🚜 Maquinaria prestada al conjunto. Responsable:", operario.nombre);

// console.log('---------------------------------------')
// console.log('Inventario conjunto:',conjunto.inventario)
// console.log('Maquinaria conjunto conjunto:',conjunto.maquinariaPrestada)
// console.log('Cronograma conjunto conjunto:',conjunto.cronograma)

// const solicitudTarea = new SolicitudTarea(1, "Corte de césped", conjunto, jardin, podadora, 4);
// empresa.solicitudesTareas.push(solicitudTarea);
// const solicitudTareaServices = new SolicitudTareaService(solicitudTarea);
// solicitudTareaServices.aprobar();

// console.log('---------------------------------------')
// console.log('Inventario conjunto:',conjunto.inventario)
// console.log('Maquinaria conjunto conjunto:',conjunto.maquinariaPrestada)
// console.log('Cronograma conjunto conjunto:',conjunto.cronograma)

// console.log('---------------------------------------')
// console.log(operario.tareas)
// const tarea = new Tarea(1, solicitudTarea.descripcion, new Date(), new Date(), jardin, podadora, 4, operario);
// gerenteServices.asignarTarea(tarea);
// conjuntoService.agregarTareaACronograma(tarea);
// console.log('+++++++++++++++++++++++')
// console.log('Cronograma conjunto: ', conjunto.cronograma)
// const tareaService = new TareaService(tarea);
// console.log("📝 Tarea asignada al operario:", tareaService.resumen());
// console.log('---------------------------------------')
// console.log(operario.tareas)

// const operarioService = new OperarioService(operario)
// operarioService.marcarComoCompletada(1, ["evidencia1.jpg"], new InventarioService(conjunto.inventario));
// console.log("✅ Tarea marcada como completada por operario.");
// console.log('---------------------------------------')
// console.log(operario.tareas)


// console.log('---------------------------------------')
// console.log(supervisor.tareasPorVerificar)

// const supervisorService = new SupervisorService(supervisor);
// supervisorService.recibirTareaFinalizada(tarea);
// console.log(supervisor.tareasPorVerificar)
// supervisorService.aprobarTarea(tarea);
// console.log("🔍 Tarea verificada y aprobada por supervisor.");
// console.log(supervisor.tareasPorVerificar)

// console.log("📋 Maquinaria disponible:", empresaServices.listarMaquinariaDisponible().map(m => m.nombre));
// console.log("📋 Maquinaria prestada:", empresa.stockMaquinaria.filter(m => !m.disponible).map(m => `${m.nombre} ➡️ ${m.asignadaA?.nombre} (${m.responsable?.nombre})`));

// console.log("📅 Cronograma del conjunto:");
// const cronogramaServices = new CronogramaService(cronograma);
// cronogramaServices.exportarComoEventosCalendario().forEach(e => console.log("📌", e));

app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend funcionando. Verifica la consola para resultados.');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
