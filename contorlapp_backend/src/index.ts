import express, { Request, Response } from 'express';
import bcrypt from 'bcrypt';

// ─── Modelos y Servicios ─────────────────────────────
import { Empresa } from './model/Empresa';
import { Gerente } from './model/gerente';
import { JefeOperaciones } from './model/jefeOperaciones';
import { Administrador } from './model/administrador';
import { Supervisor } from './model/supervisor';
import { Operario } from './model/operario';
import { Ubicacion } from './model/ubicacion';
import { Elemento } from './model/elemento';
import { Insumo } from './model/insumo';
import { Tarea } from './model/tarea';
import { EstadoTarea } from './model/enum/estadoTarea';
import { TipoFuncion } from './model/enum/tipoFuncion';

import { EmpresaService } from './services/EmpresaServices';
import { GerenteService } from './services/GerenteServices';
import { AdministradorService } from './services/AdministradorServices';
import { OperarioService } from './services/OperarioServices';
import { SupervisorService } from './services/SupervisorServices';
import { ConjuntoService } from './services/ConjuntoServices';
import { UbicacionService } from './services/UbicacionServices';
import { InventarioService } from './services/InventarioServices';
import { ReporteService } from './services/ReporteService';
import { AuthService } from './services/authService';

// ─── App Config ───────────────────────────────────────
const app = express();
app.use(express.json());

// ─── 1. Crear Gerente y Empresa ───────────────────────
const gerente = new Gerente(1, "Carlos Gerente", "gerente@empresa.com", bcrypt.hashSync("admin123", 10));
const empresa = new Empresa("Control Limpieza S.A.S", "900123456", gerente);
const empresaServices = new EmpresaService(empresa);
const authService = new AuthService(empresa);
const gerenteServices = new GerenteService(gerente, empresa, authService);

// Registrar al gerente (único que se registra manual)
authService.preRegistrarGerente(gerente); // Se autoincluye como usuario

// ─── 2. Registrar otros usuarios ───────────────────────
const jefe1 = new JefeOperaciones(2, "Luis Operaciones", "jefe1@empresa.com", "clave456");
authService.registrarUsuario(gerente, jefe1);
empresaServices.agregarJefeOperaciones(jefe1);

const admin1 = new Administrador(3, "Patricia", "patricia@gmail.com", "patri123");
const admin2 = new Administrador(4, "Jaime", "jaime@gmail.com", "patri123");
authService.registrarUsuario(gerente, admin1);
const adminServices = new AdministradorService(admin1);

const supervisor = new Supervisor(4, "Sandra", "supervisor@gmail.com", "sup321");
authService.registrarUsuario(gerente, supervisor);
const supervisorService = new SupervisorService(supervisor, empresa);

const operario = new Operario(5, 'Jaime', 'jaime@gmail.com', 'claveOperario', [TipoFuncion.ASEO]);
authService.registrarUsuario(gerente, operario);

// ─── 3. Crear Conjunto, Ubicación, Elemento ─────────────
const alborada = gerenteServices.crearConjunto(101, 'Alborada', 'Carrera x', 'alborada@gmail.com');

gerenteServices.asignarAdministradorAConjunto(admin1, alborada)
gerenteServices.reemplazarAdminEnVariosConjuntos([{
  conjunto: alborada, nuevoAdmin: admin2
}]);



console.log('Usuarios antes de borrar: ', authService.usuariosRegistrados)

gerenteServices.eliminarAdministrador(admin1)
gerenteServices.eliminarSupervisor(supervisor)
gerenteServices.eliminarOperario(operario);
console.log('Usuarios despues de borrar: ', authService.usuariosRegistrados)

const conjuntoService = new ConjuntoService(alborada);
const jardin = new Ubicacion('Salón Comunal', alborada);
const ubicacionService = new UbicacionService(jardin);
const puerta = new Elemento('Puerta');
ubicacionService.agregarElemento(puerta);

conjuntoService.agregarUbicacion(jardin);

// ─── 4. Crear Insumos y Asignar al Conjunto ─────────────
const detergente = new Insumo(1, 'Detergente', 'Litros');
const clorox = new Insumo(2, 'Clorox', 'Litros');

empresaServices.agregarInsumoAlCatalogo(detergente);
empresaServices.agregarInsumoAlCatalogo(clorox);

gerenteServices.agregarInsumoAConjunto(alborada, detergente, 5);
gerenteServices.agregarInsumoAConjunto(alborada, clorox, 3);

// ─── 5. Crear Tarea y asignar ───────────────────────────
const tarea = new Tarea(
  201,
  'Lavar área común',
  new Date(),
  new Date(),
  alborada.ubicaciones[0],
  alborada.ubicaciones[0].elementos[0],
  2,
  operario
);
gerenteServices.asignarTarea(tarea, alborada);

// ─── 6. Operario realiza la tarea ───────────────────────
const operarioService = new OperarioService(operario, empresa);

operarioService.marcarComoCompletada(
  tarea.id,
  ['foto1.jpg', 'foto2.jpg'],
  new InventarioService(alborada.inventario),
  [{ insumoId: 1, cantidad: 2 }]
);

// ─── 7. Supervisor verifica y aprueba ───────────────────
supervisorService.recibirTareaFinalizada(tarea);
supervisorService.aprobarTarea(tarea);

// ─── 8. Generar Reportes ────────────────────────────────
const reporteService = new ReporteService(empresa);


// ─── 9. Ruta básica de prueba ───────────────────────────
app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend funcionando. Verifica la consola para resultados.');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
