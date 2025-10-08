// src/index.ts
import express, { Request, Response, NextFunction } from "express";
import {
  PrismaClient,
  TipoMaquinaria,
  EstadoMaquinaria,
  Rol,
} from "./generated/prisma";

// Services (usa la misma ruta/nombre que tienes en tu proyecto)
import { GerenteService } from "./services/GerenteServices";
import { EmpresaService } from "./services/EmpresaServices";
import { ConjuntoService } from "./services/ConjuntoServices";
import { AdministradorService } from "./services/AdministradorServices";
import { OperarioService } from "./services/OperarioServices";
import { SupervisorService } from "./services/SupervisorServices";
import { UbicacionService } from "./services/UbicacionServices";
import { InventarioService } from "./services/InventarioServices";
import { TareaService } from "./services/TareaServices";
import { ReporteService } from "./services/ReporteService";
import { SolicitudTareaService } from "./services/SolicitudTareaServices";

const app = express();
app.use(express.json());

const prisma = new PrismaClient();

// Instancias base
const gerenteService = new GerenteService(prisma);
const empresaService = new EmpresaService(prisma, "901191875-4");
const reporteService = new ReporteService(prisma);

// ───────────────────────── Rutas simples de verificación ─────────────────────────
app.get("/", (_req: Request, res: Response) => {
  res.send("🚀 Backend funcionando (demo end-to-end).");
});


app.get("/ping", async (_req, res) => {
  try {
    const empresa = await prisma.empresa.findUnique({ where: { nit: "901191875-4" } });
    const maquinas = await empresaService.listarMaquinariaDisponible();
    res.json({ ok: true, empresa, maquinas });
  } catch (e: any) {
    res.status(500).json({ error: e.message });
  }
});

// ───────────────────────── DEMO COMPLETA (main) ─────────────────────────
async function main() {
  try {
    console.log("🏁 Iniciando DEMO end-to-end…");

    // 0) Confirmar Empresa
    const empresa = await prisma.empresa.findUnique({ where: { nit: "901191875-4" } });
    if (!empresa) {
      throw new Error("La empresa 901191875-4 no existe. Crea o importa esa fila antes de correr la demo.");
    }
    console.log("🏢 Empresa:", empresa.nombre, empresa.nit);

    // 1) Crear 4 usuarios base con roles (ids que no choquen en tu BD)
    const adminId = 200000001;
    const operarioId = 200000002;
    const supervisorId = 200000003;
    const jefeOpsId = 200000004;

    // crearUsuario (usa DTO Zod internamente)
    await safeCreateUser({
    id: adminId,
    nombre: "Admin Demo",
    correo: "admin.demo@acme.com",
    contrasena: "Admin#1234", // ← ✅ 10 caracteres
    telefono: 3001112222,
    fechaNacimiento: new Date("1990-01-01"),
    rol: Rol.administrador,
  });

  await safeCreateUser({
    id: operarioId,
    nombre: "Operario Demo",
    correo: "operario.demo@acme.com",
    contrasena: "Oper#1234",
    telefono: 3002223333,
    fechaNacimiento: new Date("1992-02-02"),
    rol: Rol.operario,
  });

  await safeCreateUser({
    id: supervisorId,
    nombre: "Supervisor Demo",
    correo: "supervisor.demo@acme.com",
    contrasena: "Sup#1234",
    telefono: 3003334444,
    fechaNacimiento: new Date("1988-03-03"),
    rol: Rol.supervisor,
  });

  await safeCreateUser({
    id: jefeOpsId,
    nombre: "JefeOps Demo",
    correo: "jefeops.demo@acme.com",
    contrasena: "Jefe#1234",
    telefono: 3004445555,
    fechaNacimiento: new Date("1985-04-04"),
    rol: Rol.jefe_operaciones,
  });

    // 2) Asignar roles entidad-relación
    await safeRun("asignarAdministrador", () =>
      gerenteService.asignarAdministrador({ id: adminId })
    );
    await safeRun("asignarOperario", () =>
      gerenteService.asignarOperario({
        id: operarioId,
        empresaId: empresa.nit,
        funciones: ["TODERO"], // enum TipoFuncion string[] (DTO valida)
        cursoSalvamentoAcuatico: false,
        cursoAlturas: false,
        examenIngreso: false,
        fechaIngreso: new Date(),
      })
    );
    await safeRun("asignarSupervisor", () =>
      gerenteService.asignarSupervisor({ id: supervisorId, empresaId: empresa.nit })
    );
    await safeRun("asignarJefeOperaciones", () =>
      gerenteService.asignarJefeOperaciones({ id: jefeOpsId, empresaId: empresa.nit })
    );

    // 3) Crear Conjunto
    const conjunto = await safeRun("crearConjunto", () =>
      gerenteService.crearConjunto({
        nit: "CONJ-DEM-001",
        nombre: "Conjunto DEMO",
        direccion: "Cra 123 # 45-67",
        correo: "admin-conjunto@demo.com",
        empresaId: empresa.nit,
        administradorId: adminId,
      })
    );
    const conjuntoNit = conjunto.nit as string;
    console.log("🏘️ Conjunto creado:", conjuntoNit);

    // 4) Asegurar Inventario del Conjunto
    let inventario = await prisma.inventario.findUnique({ where: { conjuntoId: conjuntoNit } });
    if (!inventario) {
      inventario = await prisma.inventario.create({
        data: { conjunto: { connect: { nit: conjuntoNit } } },
      });
      console.log("📦 Inventario creado:", inventario.id);
    }

    // 5) Agregar Ubicación + Elemento
    const conjuntoService = new ConjuntoService(prisma, conjuntoNit);
    await safeRun("agregarUbicacion", () => conjuntoService.agregarUbicacion({ nombre: "Salón Comunal" }));
    const ubicacion = await conjuntoService.buscarUbicacion({ nombre: "Salón Comunal" });
    if (!ubicacion) throw new Error("Ubicación no encontrada tras crearla.");
    const ubicacionId = ubicacion.id as number;

    const ubicacionService = new UbicacionService(prisma, ubicacionId);
    await ubicacionService.agregarElemento({ nombre: "Jardín Frontal" });
    const elemento = await ubicacionService.buscarElementoPorNombre({ nombre: "Jardín Frontal" });
    if (!elemento) throw new Error("Elemento no encontrado tras crearlo.");
    const elementoId = elemento.id;

    // 6) Agregar Insumo a catálogo de la Empresa y cargar Inventario
    const insumo = await safeRun("agregarInsumoAlCatalogo", () =>
      empresaService.agregarInsumoAlCatalogo({ nombre: "Fertilizante", unidad: "kg" })
    );
    const inventarioService = new InventarioService(prisma, inventario.id);
    await safeRun("inventario.agregarInsumo", () =>
      inventarioService.agregarInsumo({ insumoId: insumo.id, cantidad: 10 })
    );

    // 7) Crear Maquinaria (Empresa/Stock)
    const maquina = await safeRun("empresa.agregarMaquinaria", () =>
      empresaService.agregarMaquinaria({
        nombre: "Cortasetos",
        marca: "Pollito",
        tipo: TipoMaquinaria.CORTASETOS_MANO,
      })
    );
    console.log("🛠️ Maquinaria creada:", maquina.id);

    // 8) Asignar Operario al Conjunto
    await safeRun("conjunto.asignarOperario", () => conjuntoService.asignarOperario({ operarioId }));

    // 9) Asignar Tarea (Gerente)
    const tarea = await safeRun("gerente.asignarTarea", () =>
      gerenteService.asignarTarea({
        descripcion: "Poda y limpieza del jardín",
        fechaInicio: new Date(),
        fechaFin: new Date(Date.now() + 1000 * 60 * 60 * 4),
        duracionHoras: 4,
        operarioId,
        ubicacionId,
        elementoId,
        conjuntoId: conjuntoNit,
      })
    );
    const tareaId = tarea.id as number;
    console.log("📝 Tarea creada:", tareaId);

    // 10) Operario: iniciar y completar tarea con consumo de insumos
    const operarioService = new OperarioService(prisma, operarioId);
    await operarioService.iniciarTarea({ tareaId });

    await operarioService.marcarComoCompletada(
      {
        tareaId,
        evidencias: ["https://cdn.demo/evidencias/poda1.jpg"],
        insumosUsados: [{ insumoId: insumo.id, cantidad: 2 }],
      },
      inventarioService
    );

    // 11) Supervisor: aprobar tarea
    const supervisorService = new SupervisorService(prisma, supervisorId);
    await supervisorService.recibirTareaFinalizada({ tareaId });
    await supervisorService.aprobarTarea({ tareaId });
    console.log("✅ Tarea aprobada por Supervisor.");

    // 12) Reportes: tareas aprobadas en rango
    const desde = new Date(Date.now() - 1000 * 60 * 60 * 24);
    const hasta = new Date(Date.now() + 1000 * 60 * 60 * 24);
    const aprobadas = await reporteService.tareasAprobadasPorFecha({ desde, hasta });
    console.log("📊 Tareas aprobadas en rango:", aprobadas.length);

    // 13) Export tipo resumen tarea (TareaService)
    const tareaService = new TareaService(prisma, tareaId);
    console.log(await tareaService.resumen());

    // 14) Flujo de rechazo → crear solicitud de tarea automáticamente
    // (Para probarlo, crea otra tarea y recházala.)
    const tarea2 = await gerenteService.asignarTarea({
      descripcion: "Riego jardines",
      fechaInicio: new Date(),
      fechaFin: new Date(Date.now() + 1000 * 60 * 60),
      duracionHoras: 1,
      operarioId,
      ubicacionId,
      elementoId,
      conjuntoId: conjuntoNit,
    });
    const tarea2Id = tarea2.id;
    await new TareaService(prisma, tarea2Id).marcarNoCompletada(); // simula flujo diferente
    await new TareaService(prisma, tarea2Id).rechazarTarea({
      supervisorId,
      observacion: "Trabajo inconcluso",
    });
    console.log("❌ Tarea 2 rechazada por supervisor.");

    // (Opcional) Revisa solicitudes creadas
    const solicitudes = await prisma.solicitudTarea.findMany({
      where: { conjuntoId: conjuntoNit, estado: "PENDIENTE" },
    });
    console.log("🗂️ Solicitudes pendientes generadas:", solicitudes.length);

    // 15) Maquinaria → asignar y devolver (MaquinariaService o Conjunto/Empresa)
    // aquí probamos ConjuntoService.agregarMaquinaria y liberar
    await safeRun("conjunto.agregarMaquinaria", () => conjuntoService.agregarMaquinaria({ maquinariaId: maquina.id }));
    await safeRun("conjunto.entregarMaquinaria", () => conjuntoService.entregarMaquinaria({ maquinariaId: maquina.id }));
    console.log("🔁 Maquinaria asignada y devuelta.");

    console.log("🎉 DEMO end-to-end finalizada sin errores.");
  } catch (error: any) {
    console.error("💥 Error en DEMO end-to-end:", error.message);
  }
}

// Helpers de demo
async function safeCreateUser(u: {
  id: number;
  nombre: string;
  correo: string;
  contrasena: string;
  telefono: number;
  fechaNacimiento: Date;
  rol: Rol;
}) {
  const exist = await prisma.usuario.findUnique({ where: { id: u.id } });
  if (exist) {
    console.log(`ℹ️ Usuario ${u.id} ya existía, se omite creación.`);
    return exist;
  }
  const created = await gerenteService.crearUsuario({
    ...u,
    // el DTO convierte telefono a bigint y valida todo
  });
  console.log("👤 Usuario creado:", created.id, created.nombre, created.rol);
  return created;
}

async function safeRun<T>(label: string, fn: () => Promise<T>): Promise<T> {
  try {
    const r = await fn();
    console.log(`✅ ${label}`);
    return r;
  } catch (e: any) {
    console.warn(`⚠️ ${label}:`, e.message);
    // Re-lanza para cortar el flujo si es crítico o continúa si no lo es.
    return Promise.reject(e);
  }
}

// Rutas de inspección de reportes (útiles en Postman)
app.get("/reportes/aprobadas", async (req, res) => {
  try {
    const desde = req.query.desde ? new Date(String(req.query.desde)) : new Date(Date.now() - 86400000);
    const hasta = req.query.hasta ? new Date(String(req.query.hasta)) : new Date(Date.now() + 86400000);
    const data = await reporteService.tareasAprobadasPorFecha({ desde, hasta });
    res.json({ desde, hasta, total: data.length, data });
  } catch (e: any) {
    res.status(500).json({ error: e.message });
  }
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
  void main(); // Ejecuta la simulación end-to-end al arrancar
});
