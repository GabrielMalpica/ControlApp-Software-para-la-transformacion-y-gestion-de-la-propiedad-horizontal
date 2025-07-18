import express, { Request, Response } from 'express';
import bcrypt from 'bcrypt';

// ─── Modelos y Servicios ─────────────────────────────
import { Empresa } from './model/Empresa';
import { Gerente } from './model/Gerente';
import { JefeOperaciones } from './model/JefeOperaciones';
import { Administrador } from './model/Administrador';
import { Supervisor } from './model/Supervisor';
import { Operario } from './model/Operario';
import { Ubicacion } from './model/Ubicacion';
import { Elemento } from './model/Elemento';
import { Insumo } from './model/Insumo';
import { Tarea } from './model/Tarea';

import { EstadoTarea } from './model/enum/estadoTarea';
import { TipoFuncion } from './model/enum/tipoFuncion';
import { EstadoCivil } from './model/enum/estadoCivil';
import { EPS } from './model/enum/eps';
import { FondoPension } from './model/enum/fondePensiones';
import { TallaCamisa } from './model/enum/tallaCamisa';
import { TallaPantalon } from './model/enum/tallaPantalon';
import { TallaCalzado } from './model/enum/tallaCalzado';
import { TipoContrato } from './model/enum/tipoContrato';
import { JornadaLaboral } from './model/enum/jornadaLaboral';
import { TipoSangre } from './model/enum/tipoSangre';

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

const app = express();
app.use(express.json());

// ─── Crear Gerente y Empresa ─────────────────────────
const gerente = new Gerente(1, 'Frank', 'frank@gmail.com', "123", 312, new Date());

const empresa = new Empresa("Control Limpieza S.A.S", "900123456", gerente);
const authService = new AuthService(empresa);
const empresaServices = new EmpresaService(empresa);
const gerenteServices = new GerenteService(gerente, empresa, authService);
authService.preRegistrarGerente(gerente);

// ─── Crear y registrar usuarios ───────────────────────
const jefe1 = new JefeOperaciones(
  5, 'Jaime', 'jaime@gmail.com', 'claveOperario',
  3001234567, new Date("1992-08-20"), "Calle Falsa 123", EstadoCivil.CASADO,
  2, true, TipoSangre.A_NEGATIVO, EPS.SURA, FondoPension.PROTECCION,
  TallaCamisa.L, TallaPantalon.T_34, TallaCalzado.T_41,
  TipoContrato.TERMINO_FIJO, JornadaLaboral.MEDIO_TIEMPO
);
authService.registrarUsuario(gerente, jefe1);
empresaServices.agregarJefeOperaciones(jefe1);

const admin1 = new Administrador(3, "Patricia", "patricia@gmail.com", "patri123", 320000333, new Date("1985-07-10"));
authService.registrarUsuario(gerente, admin1);
const adminServices = new AdministradorService(admin1);

const supervisor = new Supervisor(
  5, 'Jaime', 'jaimes@gmail.com', 'claveOperario',
  3001234567, new Date("1992-08-20"), "Calle Falsa 123", EstadoCivil.CASADO,
  2, true, TipoSangre.A_NEGATIVO, EPS.SURA, FondoPension.PROTECCION,
  TallaCamisa.L, TallaPantalon.T_34, TallaCalzado.T_41,
  TipoContrato.TERMINO_FIJO, JornadaLaboral.MEDIO_TIEMPO
);
authService.registrarUsuario(gerente, supervisor);
const supervisorService = new SupervisorService(supervisor, empresa);

const operario = new Operario(
  1, 'jaime', 'jaimeo@gmail.com', '123', 123, new Date, 'carrera x',
  EstadoCivil.SOLTERO, 5, false, TipoSangre.AB_NEGATIVO, EPS.ANAS_WAIMAS,
  FondoPension.COLFONDOS, TallaCamisa.L, TallaPantalon.T_42, 
  TallaCalzado.T_41, TipoContrato.OBRA_LABOR, JornadaLaboral.COMPLETA, [TipoFuncion.ASEO],
  true, 'afsfa', true, 'lsfjdalñf', true, 'fadfafa', new Date()
);
authService.registrarUsuario(gerente, operario);

// ─── Crear Conjunto y Asignar Admin ──────────────────
const alborada = gerenteServices.crearConjunto(101, 'Alborada', 'Carrera X', 'alborada@gmail.com');
gerenteServices.asignarAdministradorAConjunto(admin1, alborada);

// ─── Ubicaciones y elementos ──────────────────────────
const salon = new Ubicacion("Salón Comunal", alborada);
const puerta = new Elemento(salon, "Puerta");
const ubicacionService = new UbicacionService(salon);
ubicacionService.agregarElemento(puerta);

const conjuntoService = new ConjuntoService(alborada);
conjuntoService.agregarUbicacion(salon);

// ─── Agregar insumos ──────────────────────────────────
const insumo1 = new Insumo(1, "Detergente", "Litros");
const insumo2 = new Insumo(2, "Cloro", "Litros");
empresaServices.agregarInsumoAlCatalogo(insumo1);
empresaServices.agregarInsumoAlCatalogo(insumo2);
gerenteServices.agregarInsumoAConjunto(alborada, insumo1, 10);
gerenteServices.agregarInsumoAConjunto(alborada, insumo2, 5);


const tarea = gerenteServices.crearYAsignarTarea(
  201,                            // ID de la tarea
  "Limpieza de entrada",         // Descripción
  new Date(),                    // Fecha inicio
  new Date(),                    // Fecha fin
  alborada,                      // Conjunto
  "Salón Comunal",               // Nombre de ubicación
  "Puerta",                      // Nombre de elemento
  2,                             // Duración en horas
  operario                       // Operario asignado
);


const operarioService = new OperarioService(operario, empresa);
operarioService.iniciarTarea(201);
console.log(operarioService.listarTareas())

// ─── Finalización y verificación de tarea ─────────────
operarioService.marcarComoCompletada(
  tarea.id,
  ["foto1.jpg", "foto2.jpg"],
  new InventarioService(alborada.inventario),
  [{ insumoId: 1, cantidad: 2 }]
);

supervisorService.recibirTareaFinalizada(tarea);
supervisorService.aprobarTarea(tarea);

// ─── Eliminar usuarios si ya no están asignados ───────
gerenteServices.reemplazarAdminEnVariosConjuntos([{ conjunto: alborada, nuevoAdmin: admin1 }]);
gerenteServices.eliminarOperario(operario);
gerenteServices.eliminarSupervisor(supervisor);

// ─── Reportes ─────────────────────────────────────────
const reporteService = new ReporteService(empresa);

// ─── Ruta de prueba ───────────────────────────────────
app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend actualizado funcionando.');
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
