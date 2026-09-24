import fs from "fs";
import os from "os";
import path from "path";
import {
  construirInformeMensual,
  esFrecuenciaDiaria,
  posicionesRepartidas,
  type CronogramaInformeMes,
  type TareaDetalleInforme,
} from "../../src/services/InformeMensualModelo";
import { InformeMensualJobs } from "../../src/services/InformeMensualJobs";
import { extraerDriveId, mesesDelRango } from "../../src/services/InformeMensualService";
import { limpiarTexto, renderizarInformeMensual } from "../../src/services/InformeMensualPdf";

const DESDE = new Date("2026-09-01T05:00:00Z");
const HASTA = new Date("2026-10-01T04:59:59Z");

function tarea(over: Partial<TareaDetalleInforme> & { id: number }): TareaDetalleInforme {
  return {
    tipo: "PREVENTIVA",
    frecuencia: "DIARIA",
    descripcion: "Limpieza de pasillos",
    estado: "APROBADA",
    fechaInicio: new Date(Date.UTC(2026, 8, 1, 15)),
    fechaFin: new Date(Date.UTC(2026, 8, 1, 16)),
    conjunto: { id: "900", nombre: "Conjunto Demo" },
    ubicacion: { nombre: "Zonas comunes" },
    elemento: { nombre: "Pasillo" },
    evidencias: [],
    ...over,
  };
}

type Ocurrencias =
  CronogramaInformeMes["ubicaciones"][number]["definiciones"][number]["ocurrencias"];

function cronograma(
  ocurrencias: Ocurrencias,
  frecuencia = "DIARIA",
): CronogramaInformeMes[] {
  return [
    {
      conjuntoId: "900",
      ubicaciones: [
        {
          nombre: "Zonas comunes",
          definiciones: [
            {
              id: "def:1",
              descripcion: "Limpieza de pasillos",
              frecuencia,
              elementoNombre: "Pasillo",
              ocurrencias,
            },
          ],
        },
      ],
    },
  ];
}

describe("informe mensual: modelo", () => {
  it("cuenta previstas, programadas y realizadas por actividad (22/22 y 20/22)", () => {
    const tareas: TareaDetalleInforme[] = [];
    const ocurrencias: Ocurrencias = [];
    for (let d = 1; d <= 22; d++) {
      const hecha = d <= 20;
      tareas.push(
        tarea({
          id: d,
          estado: hecha ? "APROBADA" : "NO_COMPLETADA",
          fechaInicio: new Date(Date.UTC(2026, 8, d, 15)),
          evidencias: hecha ? [`https://drive.google.com/file/d/foto${d}xxxxxxxxxxxxxxxxxx/view`] : [],
        }),
      );
      ocurrencias.push({
        fechaObjetivo: new Date(Date.UTC(2026, 8, d, 15)),
        minutosProgramados: 60,
        bloques: [{ tareaId: d, estado: hecha ? "APROBADA" : "NO_COMPLETADA" }],
      });
    }
    const informe = construirInformeMensual({
      conjuntoNombre: "Conjunto Demo",
      desde: DESDE,
      hasta: HASTA,
      tareas,
      reemplazos: [],
      cronogramas: cronograma(ocurrencias),
    });

    expect(informe.preventivas).toHaveLength(1);
    const a = informe.preventivas[0];
    expect(a.previstas).toBe(22);
    expect(a.programadas).toBe(22);
    expect(a.realizadas).toBe(20);
    expect(a.baseRealizadas).toBe(22);
    expect(a.noCompletadas).toBe(2);
    expect(informe.resumen).toMatchObject({ previstas: 22, programadas: 22, realizadas: 20 });
  });

  it("en actividades diarias con muchas tareas solo muestra 3 fotos repartidas", () => {
    const tareas = Array.from({ length: 31 }, (_, i) =>
      tarea({
        id: i + 1,
        fechaInicio: new Date(Date.UTC(2026, 8, i + 1, 15)),
        evidencias: [`https://drive.google.com/file/d/dia${i + 1}xxxxxxxxxxxxxxxxxxx/view`],
      }),
    );
    const informe = construirInformeMensual({
      conjuntoNombre: "Conjunto Demo",
      desde: DESDE,
      hasta: HASTA,
      tareas,
      reemplazos: [],
      cronogramas: [],
    });
    const a = informe.preventivas[0];
    expect(a.fotos).toHaveLength(3);
    expect(a.fotosTotales).toBe(31);
    expect(a.fotosOmitidas).toBe(28);
    // primera, intermedia y ultima del mes
    expect(a.fotos.map((f) => f.tareaId)).toEqual([1, 16, 31]);
  });

  it("en el resto de frecuencias muestra todas las fotos", () => {
    const tareas = [1, 2, 3, 4].map((n) =>
      tarea({
        id: n,
        frecuencia: "SEMANAL",
        fechaInicio: new Date(Date.UTC(2026, 8, n * 7 - 5, 15)),
        evidencias: [
          `https://drive.google.com/file/d/a${n}xxxxxxxxxxxxxxxxxxxxx/view`,
          `https://drive.google.com/file/d/b${n}xxxxxxxxxxxxxxxxxxxxx/view`,
        ],
      }),
    );
    const informe = construirInformeMensual({
      conjuntoNombre: "Conjunto Demo",
      desde: DESDE,
      hasta: HASTA,
      tareas,
      reemplazos: [],
      cronogramas: [],
    });
    const a = informe.preventivas[0];
    expect(a.registros).toBe(4);
    expect(a.fotos).toHaveLength(8);
    expect(a.fotosOmitidas).toBe(0);
  });

  it("incluye actividades previstas que nunca se programaron, sin evidencia", () => {
    const informe = construirInformeMensual({
      conjuntoNombre: "Conjunto Demo",
      desde: DESDE,
      hasta: HASTA,
      tareas: [],
      reemplazos: [],
      cronogramas: cronograma(
        [
          { fechaObjetivo: new Date(Date.UTC(2026, 8, 10, 15)), minutosProgramados: 0, bloques: [] },
          { fechaObjetivo: new Date(Date.UTC(2026, 8, 24, 15)), minutosProgramados: 0, bloques: [] },
        ],
        "QUINCENAL",
      ),
    });
    const a = informe.preventivas[0];
    expect(a).toMatchObject({ previstas: 2, programadas: 0, realizadas: 0 });
    expect(a.fotos).toHaveLength(0);
  });

  it("ignora del cronograma las ocurrencias fuera del rango pedido", () => {
    const informe = construirInformeMensual({
      conjuntoNombre: "Conjunto Demo",
      desde: new Date("2026-09-01T05:00:00Z"),
      hasta: new Date("2026-09-15T04:59:59Z"),
      tareas: [],
      reemplazos: [],
      cronogramas: cronograma([
        { fechaObjetivo: new Date(Date.UTC(2026, 8, 10, 15)), minutosProgramados: 30, bloques: [] },
        { fechaObjetivo: new Date(Date.UTC(2026, 8, 20, 15)), minutosProgramados: 30, bloques: [] },
      ]),
    });
    expect(informe.preventivas[0].previstas).toBe(1);
  });

  it("relaciona correctivas y preventivas reemplazadas con id, nombre y motivo", () => {
    const informe = construirInformeMensual({
      conjuntoNombre: "Conjunto Demo",
      desde: DESDE,
      hasta: HASTA,
      tareas: [
        tarea({
          id: 10,
          frecuencia: "MENSUAL",
          descripcion: "Lavado de tanque",
          estado: "NO_COMPLETADA",
        }),
        tarea({
          id: 11,
          tipo: "CORRECTIVA",
          frecuencia: null,
          descripcion: "Reparar fuga",
          reemplazaPreventivas: [{ tareaId: 10, descripcion: "Lavado de tanque" }],
        }),
      ],
      reemplazos: [
        {
          tareaPreventivaId: 10,
          descripcion: "Lavado de tanque",
          motivoUsuario: "Fuga urgente",
          resultado: "CANCELADA_SIN_CUPO",
          estadoActual: "NO_COMPLETADA",
          reemplazadaPor: { tareaId: 11, descripcion: "Reparar fuga" },
        },
      ],
      cronogramas: [],
    });

    expect(informe.correctivas).toHaveLength(1);
    expect(informe.correctivas[0].reemplazaA[0]).toMatchObject({
      tareaId: 10,
      descripcion: "Lavado de tanque",
      motivo: "Fuga urgente",
    });
    expect(informe.reemplazadas).toEqual([
      expect.objectContaining({
        tareaId: 10,
        porTareaId: 11,
        porDescripcion: "Reparar fuga",
        motivo: "Fuga urgente",
      }),
    ]);
    expect(informe.preventivas[0].reemplazadas[0].porTareaId).toBe(11);
    expect(informe.resumen).toMatchObject({ correctivas: 1, reemplazadas: 1, noCompletadas: 1 });
  });

  it("reconoce variantes de frecuencia diaria", () => {
    expect(esFrecuenciaDiaria("DIARIA")).toBe(true);
    expect(esFrecuenciaDiaria("Diario")).toBe(true);
    expect(esFrecuenciaDiaria("DIARIA_LUNES_A_SABADO")).toBe(true);
    expect(esFrecuenciaDiaria("SEMANAL")).toBe(false);
  });

  it("reparte posiciones de forma pareja", () => {
    expect(posicionesRepartidas(2, 3)).toEqual([0, 1]);
    expect(posicionesRepartidas(5, 3)).toEqual([0, 2, 4]);
    expect(posicionesRepartidas(4, 3)).toEqual([0, 2, 3]);
    expect(posicionesRepartidas(0, 3)).toEqual([]);
  });
});

describe("informe mensual: utilidades", () => {
  it("extrae el id de Drive de enlaces, del proxy y de ids sueltos", () => {
    const id = "1AbCdEfGhIjKlMnOpQrStUvWxYz";
    expect(extraerDriveId(`https://drive.google.com/file/d/${id}/view`)).toBe(id);
    expect(extraerDriveId(`https://drive.google.com/uc?id=${id}&export=view`)).toBe(id);
    expect(extraerDriveId(`https://api.ejemplo.com/evidencias/${id}`)).toBe(id);
    expect(extraerDriveId(id)).toBe(id);
    expect(extraerDriveId("https://otro.com/foto.jpg")).toBeNull();
  });

  it("calcula los meses que toca un rango", () => {
    expect(mesesDelRango(new Date("2026-09-01T05:00:00Z"), new Date("2026-10-01T04:59:59Z"))).toEqual([
      { anio: 2026, mes: 9 },
    ]);
    expect(mesesDelRango(new Date("2026-11-20T15:00:00Z"), new Date("2027-01-05T15:00:00Z"))).toEqual([
      { anio: 2026, mes: 11 },
      { anio: 2026, mes: 12 },
      { anio: 2027, mes: 1 },
    ]);
  });

  it("limpia caracteres que Helvetica no puede dibujar", () => {
    expect(limpiarTexto("Ñandú → ≥ 5 ✅ 🚀")).toBe("Ñandú -> >= 5");
  });

  it("genera un PDF valido con y sin fotos", async () => {
    const informe = construirInformeMensual({
      conjuntoNombre: "Conjunto Demo",
      desde: DESDE,
      hasta: HASTA,
      tareas: [tarea({ id: 1 }), tarea({ id: 2, tipo: "CORRECTIVA", frecuencia: null })],
      reemplazos: [],
      cronogramas: [],
    });
    const destino = path.join(os.tmpdir(), `informe-test-${Date.now()}.pdf`);
    await renderizarInformeMensual(informe, { archivoDestino: destino, cargarFoto: () => null });
    const bytes = fs.readFileSync(destino);
    fs.unlinkSync(destino);
    expect(bytes.subarray(0, 5).toString()).toBe("%PDF-");
  });
});

describe("informe mensual: cola de trabajos", () => {
  const carpeta = path.join(os.tmpdir(), `informes-jobs-test-${process.pid}`);
  const esperar = (ms = 5) => new Promise((r) => setTimeout(r, ms));

  afterAll(() => fs.rmSync(carpeta, { recursive: true, force: true }));

  it("ejecuta el informe en segundo plano y deja el archivo listo", async () => {
    const jobs = new InformeMensualJobs(carpeta);
    const job = jobs.iniciar({
      usuarioId: "u1",
      clave: "a",
      ejecutar: async ({ archivoDestino, reportar }) => {
        reportar(50, "mitad");
        fs.writeFileSync(archivoDestino, "%PDF-1.4");
        return { nombreArchivo: "x.pdf" };
      },
    });
    // Responde de inmediato: el informe todavia no termina.
    expect(["EN_COLA", "GENERANDO"]).toContain(job.estado);
    await esperar(20);
    expect(job.estado).toBe("LISTO");
    expect(job.progreso).toBe(100);
    expect(job.nombreArchivo).toBe("x.pdf");
    expect(fs.existsSync(job.archivo)).toBe(true);
  });

  it("solo el dueño puede consultar su informe", async () => {
    const jobs = new InformeMensualJobs(carpeta);
    const job = jobs.iniciar({
      usuarioId: "u1",
      clave: "a",
      ejecutar: async () => ({ nombreArchivo: "x.pdf" }),
    });
    expect(jobs.obtener(job.id, "u1")).toBe(job);
    expect(jobs.obtener(job.id, "otro")).toBeUndefined();
  });

  it("un usuario no puede tener dos informes distintos a la vez, pero repetir el mismo reutiliza el job", async () => {
    const jobs = new InformeMensualJobs(carpeta);
    let liberar!: () => void;
    const bloqueo = new Promise<void>((r) => (liberar = r));
    const ejecutar = async () => {
      await bloqueo;
      return { nombreArchivo: "x.pdf" };
    };
    const primero = jobs.iniciar({ usuarioId: "u1", clave: "a", ejecutar });
    expect(jobs.iniciar({ usuarioId: "u1", clave: "a", ejecutar })).toBe(primero);
    expect(() => jobs.iniciar({ usuarioId: "u1", clave: "b", ejecutar })).toThrow(/ya tienes un informe/i);
    liberar();
    await esperar(20);
    expect(primero.estado).toBe("LISTO");
    // Terminado el anterior ya puede pedir otro.
    expect(() => jobs.iniciar({ usuarioId: "u1", clave: "b", ejecutar: async () => ({ nombreArchivo: "y.pdf" }) })).not.toThrow();
  });

  it("limita cuantos informes se generan a la vez y el resto espera en cola", async () => {
    const jobs = new InformeMensualJobs(carpeta);
    let activos = 0;
    let maxActivos = 0;
    const liberadores: Array<() => void> = [];
    const ejecutar = async () => {
      activos += 1;
      maxActivos = Math.max(maxActivos, activos);
      await new Promise<void>((r) => liberadores.push(r));
      activos -= 1;
      return { nombreArchivo: "x.pdf" };
    };
    const lista = ["u1", "u2", "u3", "u4"].map((u) =>
      jobs.iniciar({ usuarioId: u, clave: u, ejecutar }),
    );
    await esperar();
    expect(maxActivos).toBe(2);
    expect(lista.map((j) => j.estado)).toEqual(["GENERANDO", "GENERANDO", "EN_COLA", "EN_COLA"]);
    expect(jobs.posicionEnCola(lista[2].id)).toBe(1);
    while (lista.some((j) => j.estado !== "LISTO")) {
      liberadores.splice(0).forEach((l) => l());
      await esperar();
    }
    expect(maxActivos).toBe(2);
  });

  it("marca el error sin exponer detalles tecnicos", async () => {
    const jobs = new InformeMensualJobs(carpeta);
    jest.spyOn(console, "error").mockImplementation(() => undefined);
    const job = jobs.iniciar({
      usuarioId: "u1",
      clave: "a",
      ejecutar: async () => {
        throw new Error("ECONNRESET secreto interno");
      },
    });
    await esperar(20);
    expect(job.estado).toBe("ERROR");
    expect(job.error).not.toMatch(/ECONNRESET|secreto/);
  });
});
