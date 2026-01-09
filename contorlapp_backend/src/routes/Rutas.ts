import { Router } from "express";
import AdministradorRoutes from "./Administradores"
import ConjuntoRoutes from "./Conjuntos"
import CronogramaRoutes from "./Cronograma"
import DefinicionPreventivaRoutes from "./DefinicionPreventiva"
import EmpresaRoutes from "./Empresa"
import GerenteRoutes from "./Gerente"
import InventarioRoutes from "./Inventario"
import MaquinariaRoutes from "./Maquinaria"
import MetaRoutes from "./Meta"
import OperarioRoutes from "./Operario"
import ReportesRoutes from "./Reportes"
import SolicitudInsumoRoutes from "./SolicitudesInsumos"
import SolicitudMaquinariaRoutes from "./SolicitudesMaquinaria"
import SolicitudTareaRoutes from "./SolicitudesTarea"
import SupervisorRoutes from "./Supervisores"
import TareaRoutes from "./Tarea"
import TareaCorrectivaRoutes from "./TareasCorrectivas"
import UbicacionesRoutes from "./Ubicaciones"

const rutas = Router();

rutas.use('/administrador', AdministradorRoutes);
rutas.use('/conjunto', ConjuntoRoutes);
rutas.use('/cronograma', CronogramaRoutes);
rutas.use('/definicion-preventiva', DefinicionPreventivaRoutes);
rutas.use('/empresa', EmpresaRoutes);
rutas.use('/gerente', GerenteRoutes);
rutas.use('/inventario', InventarioRoutes);
rutas.use('/maquinarias', MaquinariaRoutes);
rutas.use('/meta', MetaRoutes)
rutas.use('/operario', OperarioRoutes);
rutas.use('/reporte', ReportesRoutes);
rutas.use('/solicitud-insumo', SolicitudInsumoRoutes);
rutas.use('/solicitud-maquinaria', SolicitudMaquinariaRoutes);
rutas.use('/solicitud-tarea', SolicitudTareaRoutes);
rutas.use('/supervisor', SupervisorRoutes);
rutas.use('/tarea', TareaRoutes);
rutas.use('/tarea-correctiva', TareaCorrectivaRoutes);
rutas.use('/ubicacion', UbicacionesRoutes);

export default rutas;