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
import { ReporteService } from './services/ReporteService';
import { EstadoTarea } from './model/enum/estadoTarea';

const app = express();
app.use(express.json());

// Crear empresa y gerente
const gerente = new Gerente(1, "Carlos Gerente", "gerente@empresa.com");
const empresa = new Empresa("Control Limpieza S.A.S", "900123456", gerente);
const gerenteServices = new GerenteService(gerente, empresa);
const empresaServices = new EmpresaService(empresa);

// Jefe de operaciones
const jefe1 = new JefeOperaciones(2, "Luis Operaciones", "jefe1@empresa.com");
empresaServices.agregarJefeOperaciones(jefe1);

// Administrador y conjunto
const admin1 = gerenteServices.crearAdministrador(1, 'Patricia', 'patricia@gmail.com');
const alborada = gerenteServices.crearConjunto(1, 'Alborada', 'Carrera x', admin1, 'alborada@gmail.com');

// Crear ubicación y elemento
const jardin = new Ubicacion('Salón Comunal', alborada);
const jardinServie = new UbicacionService(jardin);
const puerta = new Elemento('Puerta');
jardinServie.agregarElemento(puerta);
const conjuntoService = new ConjuntoService(alborada);
conjuntoService.agregarUbicacion(jardin);

// Crear insumos y agregar al catálogo de la empresa
const detergente = new Insumo(1, 'Detergente', 'Litros');
const clorox = new Insumo(2, 'Clorox', 'Litros');
empresaServices.agregarInsumoAlCatalogo(detergente);
empresaServices.agregarInsumoAlCatalogo(clorox);

// Agregar insumo al inventario del conjunto
gerenteServices.agregarInsumoAConjunto(alborada, detergente, 5);
gerenteServices.agregarInsumoAConjunto(alborada, clorox, 3);


// Crear operario y asignarlo al conjunto
const operario = new Operario(1, 'Jaime', 'jaime@gmail.com', [TipoFuncion.ASEO]);
gerenteServices.asignarOperarioAConjunto(operario, alborada);

// Crear tarea y asignarla
const tarea = new Tarea(
  1,
  'Lavar área común',
  new Date(),
  new Date(),
  alborada.ubicaciones[0],
  alborada.ubicaciones[0].elementos[0],
  2,
  operario
);
gerenteServices.asignarTarea(tarea, alborada);

console.log(operario.tareas)


// Operario completa la tarea usando insumos
const operarioService = new OperarioService(operario, empresa);
operarioService.marcarComoCompletada(
  tarea.id,
  ['foto1.jpg', 'foto2.jpg'],
  new InventarioService(alborada.inventario),
  [{ insumoId: 1, cantidad: 2 }]
);

// Supervisor verifica la tarea
const supervisor = new Supervisor(4, "Sandra", "supervisor@gmail.com");
const supervisorService = new SupervisorService(supervisor, empresa);
supervisorService.recibirTareaFinalizada(tarea);
supervisorService.aprobarTarea(tarea);

const reporteService = new ReporteService(empresa);

console.log(reporteService.tareasPorEstado(alborada, EstadoTarea.ASIGNADA, new Date(), new Date()))

app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend funcionando. Verifica la consola para resultados.');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
