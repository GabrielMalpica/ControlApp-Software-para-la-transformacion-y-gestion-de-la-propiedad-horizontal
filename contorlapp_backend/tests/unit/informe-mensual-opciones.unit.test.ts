import fs from "fs";
import os from "os";
import path from "path";
import {
  actividadesDelCuerpo,
  construirInformeMensual,
  puntualidadDeTarea,
  type CronogramaInformeMes,
  type EntradaInforme,
  type TareaDetalleInforme,
} from "../../src/services/InformeMensualModelo";
import { InformeMensualJobs } from "../../src/services/InformeMensualJobs";
import {
  OpcionesInformeSchema,
  hashOpciones,
  normalizarOpciones,
  opcionesPorDefecto,
  type OpcionesInforme,
} from "../../src/services/InformeMensualOpciones";
import { renderizarInformeMensual } from "../../src/services/InformeMensualPdf";

const DESDE = new Date("2026-09-01T05:00:00Z");
const HASTA = new Date("2026-10-01T04:59:59Z");

function tarea(over: Partial<TareaDetalleInforme> & { id: number }): TareaDetalleInforme {
  return {
    tipo: "PREVENTIVA",
    frecuencia: "SEMANAL",
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

function foto(n: string | number) {
  return `https://drive.google.com/file/d/foto${n}xxxxxxxxxxxxxxxxxxxx/view`;
}

function entrada(tareas: TareaDetalleInforme[], over: Partial<EntradaInforme> = {}): EntradaInforme {
  return {
    conjuntoNombre: "Conjunto Demo",
    desde: DESDE,
    hasta: HASTA,
    tareas,
    reemplazos: [],
    cronogramas: [],
    ...over,
  };
}

/** Opciones como las mandaria el cliente, ya validadas y normalizadas. */
function opciones(raw: unknown, rol = "gerente"): OpcionesInforme {
  return normalizarOpciones(OpcionesInformeSchema.parse(raw), rol);
}

describe("informe detallado: opciones", () => {
  it("sin opciones o con un objeto vacio da las de siempre", () => {
    const def = opcionesPorDefecto();
    expect(def.organizacion).toBe("ACTIVIDAD");
    expect(def.secciones).toMatchObject({
      resumen: true,
      detalle: true,
      reemplazadas: true,
      cumplimiento: false,
      novedades: false,
      consolidadoRecursos: false,
      anexoTareas: false,
    });
    expect(def.fotos).toEqual({
      incluir: true,
      porTarea: null,
      registrosPorActividad: "AUTO",
      tamano: "AUTO",
      calidad: "ESTANDAR",
    });
    // Los objetos anidados parciales tambien reciben sus defaults.
    expect(OpcionesInformeSchema.parse({ fotos: { porTarea: 2 } }).fotos).toMatchObject({
      incluir: true,
      porTarea: 2,
      calidad: "ESTANDAR",
    });
  });

  it("valida limites y exige al menos una seccion con contenido", () => {
    expect(() => OpcionesInformeSchema.parse({ fotos: { porTarea: 13 } })).toThrow();
    expect(() => OpcionesInformeSchema.parse({ textos: { titulo: "x".repeat(81) } })).toThrow();
    expect(() =>
      OpcionesInformeSchema.parse({
        secciones: { resumen: false, detalle: false, reemplazadas: false },
      }),
    ).toThrow(/al menos una sección/);
    expect(() => OpcionesInformeSchema.parse({ filtros: { estados: ["INVENTADO"] } })).toThrow();
  });

  it("no tiene hoja de firmas: si un cliente viejo la manda, se ignora", () => {
    const o = OpcionesInformeSchema.parse({
      secciones: { firmas: true },
      textos: { firmas: { reviso: "Ana" } },
    });
    expect(o.secciones).not.toHaveProperty("firmas");
    expect(o.textos).not.toHaveProperty("firmas");
  });

  it("al administrador nunca le deja lo interno, aunque lo pida", () => {
    const pedido = { campos: { motivoRechazo: true, cerradoPor: true } };
    expect(opciones(pedido, "administrador").campos).toMatchObject({
      motivoRechazo: false,
      cerradoPor: false,
    });
    expect(opciones(pedido, "gerente").campos).toMatchObject({
      motivoRechazo: true,
      cerradoPor: true,
    });
  });

  it("la huella no cambia con el orden y si con el contenido", () => {
    const a = opciones({
      filtros: { estados: ["APROBADA", "COMPLETADA"], ubicaciones: ["Torre 2", "Torre 1"] },
    });
    const b = opciones({
      filtros: { ubicaciones: ["Torre 1", "Torre 2", "torre 1"], estados: ["COMPLETADA", "APROBADA"] },
    });
    expect(hashOpciones(a)).toBe(hashOpciones(b));
    expect(hashOpciones(a)).not.toBe(hashOpciones(opciones({})));
    // Un filtro que incluye todo equivale a no filtrar.
    expect(hashOpciones(opciones({ filtros: { tipos: ["PREVENTIVA", "CORRECTIVA"] } }))).toBe(
      hashOpciones(opciones({})),
    );
  });
});

describe("informe detallado: filtros", () => {
  const tareas = [
    tarea({ id: 1, estado: "APROBADA", evidencias: [foto(1)] }),
    tarea({ id: 2, estado: "NO_COMPLETADA", ubicacion: { nombre: "Torre 1" } }),
    tarea({ id: 3, tipo: "CORRECTIVA", frecuencia: null, descripcion: "Reparar fuga" }),
    tarea({ id: 4, frecuencia: "DIARIA", descripcion: "Barrido", evidencias: [foto(4)] }),
  ];

  it("sin filtros incluye todo y no marca el informe como filtrado", () => {
    const informe = construirInformeMensual(entrada(tareas), opciones({}));
    expect(informe.filtrado).toBe(false);
    expect(informe.resumen.totalTareas).toBe(4);
  });

  it("filtra por tipo, estado, ubicacion, frecuencia y evidencia", () => {
    const porTipo = construirInformeMensual(
      entrada(tareas),
      opciones({ filtros: { tipos: ["CORRECTIVA"] } }),
    );
    expect(porTipo.filtrado).toBe(true);
    expect(porTipo.preventivas).toHaveLength(0);
    expect(porTipo.correctivas.map((a) => a.ids[0])).toEqual([3]);
    expect(porTipo.secciones.map((s) => s.tipo)).toEqual(["CORRECTIVAS"]);

    const porEstado = construirInformeMensual(
      entrada(tareas),
      opciones({ filtros: { estados: ["NO_COMPLETADA"] } }),
    );
    expect(porEstado.anexo.map((t) => t.tareaId)).toEqual([2]);

    const porUbicacion = construirInformeMensual(
      entrada(tareas),
      opciones({ filtros: { ubicaciones: ["torre 1"] } }),
    );
    expect(porUbicacion.anexo.map((t) => t.tareaId)).toEqual([2]);

    // La frecuencia solo filtra preventivas: la correctiva sigue.
    const porFrecuencia = construirInformeMensual(
      entrada(tareas),
      opciones({ filtros: { frecuencias: ["DIARIA"] } }),
    );
    expect(porFrecuencia.anexo.map((t) => t.tareaId).sort()).toEqual([3, 4]);

    const conEvidencia = construirInformeMensual(
      entrada(tareas),
      opciones({ filtros: { soloConEvidencia: true } }),
    );
    expect(conEvidencia.anexo.map((t) => t.tareaId).sort()).toEqual([1, 4]);
  });

  it("con filtros omite actividades del cronograma sin tareas que los cumplan", () => {
    const cronogramas: CronogramaInformeMes[] = [
      {
        conjuntoId: "900",
        ubicaciones: [
          {
            nombre: "Zonas comunes",
            definiciones: [
              {
                id: "def:1",
                descripcion: "Lavado de fachada",
                frecuencia: "MENSUAL",
                elementoNombre: null,
                ocurrencias: [
                  { fechaObjetivo: new Date(Date.UTC(2026, 8, 10, 15)), minutosProgramados: 0, bloques: [] },
                ],
              },
            ],
          },
        ],
      },
    ];
    const sinFiltro = construirInformeMensual(entrada([], { cronogramas }), opciones({}));
    expect(sinFiltro.preventivas).toHaveLength(1);
    const filtrado = construirInformeMensual(
      entrada([], { cronogramas }),
      opciones({ filtros: { estados: ["APROBADA"] } }),
    );
    expect(filtrado.preventivas).toHaveLength(0);
    expect(filtrado.resumen.hayCronograma).toBe(false);
  });
});

describe("informe detallado: fotos", () => {
  const diarias = Array.from({ length: 10 }, (_, i) =>
    tarea({
      id: i + 1,
      frecuencia: "DIARIA",
      fechaInicio: new Date(Date.UTC(2026, 8, i + 1, 15)),
      evidencias: [foto(`${i}a`), foto(`${i}b`), foto(`${i}c`)],
    }),
  );

  it("respeta fotos por tarea y registros por actividad", () => {
    const auto = construirInformeMensual(entrada(diarias), opciones({}));
    expect(auto.preventivas[0].fotos).toHaveLength(3);

    const dosPorTarea = construirInformeMensual(
      entrada(diarias),
      opciones({ fotos: { porTarea: 2, registrosPorActividad: 5 } }),
    );
    const a = dosPorTarea.preventivas[0];
    expect(a.fotos).toHaveLength(10);
    expect(new Set(a.fotos.map((f) => f.tareaId)).size).toBe(5);
    // Primera y ultima foto de cada tarea (antes y despues).
    expect(a.fotos.slice(0, 2).map((f) => f.raw)).toEqual([foto("0a"), foto("0c")]);

    const todos = construirInformeMensual(
      entrada(diarias),
      opciones({ fotos: { registrosPorActividad: "TODOS" } }),
    );
    expect(todos.preventivas[0].fotos).toHaveLength(30);
    expect(todos.preventivas[0].fotosOmitidas).toBe(0);
  });

  it("sin fotos no carga ninguna pero conserva cuantas hay", () => {
    const informe = construirInformeMensual(entrada(diarias), opciones({ fotos: { incluir: false } }));
    expect(actividadesDelCuerpo(informe).flatMap((a) => a.fotos)).toHaveLength(0);
    expect(informe.preventivas[0].fotosTotales).toBe(30);
    expect(informe.fotos.incluidas).toBe(0);
  });

  it("recorta de forma pareja cuando el informe supera el tope de fotos", () => {
    const muchas = Array.from({ length: 50 }, (_, i) =>
      tarea({
        id: i + 1,
        tipo: "CORRECTIVA",
        frecuencia: null,
        descripcion: `Arreglo ${i + 1}`,
        evidencias: Array.from({ length: 10 }, (_, j) => foto(`${i}-${j}`)),
      }),
    );
    const estandar = construirInformeMensual(entrada(muchas), opciones({}));
    expect(estandar.fotos).toMatchObject({ incluidas: 400, omitidasPorLimite: 100, limite: 400 });
    expect(estandar.correctivas.every((a) => a.fotos.length === 8)).toBe(true);

    const alta = construirInformeMensual(entrada(muchas), opciones({ fotos: { calidad: "ALTA" } }));
    expect(alta.fotos).toMatchObject({ incluidas: 250, limite: 250 });
  });
});

describe("informe detallado: organizacion y secciones de auditoria", () => {
  const tareas = [
    tarea({
      id: 1,
      ubicacion: { nombre: "Torre 2" },
      fechaInicio: new Date(Date.UTC(2026, 8, 3, 13)),
      fechaFin: new Date(Date.UTC(2026, 8, 3, 14)),
      fechaIniciarTarea: new Date(Date.UTC(2026, 8, 3, 13, 10)),
      fechaFinalizarTarea: new Date(Date.UTC(2026, 8, 3, 13, 55)),
      duracionMinutos: 60,
      insumos: [{ nombre: "Jabón", unidad: "L", cantidad: 2 }],
      maquinaria: [{ nombre: "Hidrolavadora" }],
    }),
    tarea({
      id: 2,
      ubicacion: { nombre: "Torre 1" },
      fechaInicio: new Date(Date.UTC(2026, 8, 3, 15)),
      fechaFin: new Date(Date.UTC(2026, 8, 3, 16)),
      // Cerrada dos dias despues.
      fechaFinalizarTarea: new Date(Date.UTC(2026, 8, 5, 15)),
      insumos: [{ nombre: "jabón", unidad: "l", cantidad: 1.5 }],
      maquinaria: [{ nombre: "Hidrolavadora" }],
    }),
    tarea({
      id: 3,
      tipo: "CORRECTIVA",
      frecuencia: null,
      descripcion: "Cambiar bombillo",
      estado: "RECHAZADA",
      observacionesRechazo: "Foto borrosa",
      ubicacion: { nombre: "Torre 1" },
      fechaInicio: new Date(Date.UTC(2026, 8, 4, 15)),
      fechaFin: new Date(Date.UTC(2026, 8, 4, 16)),
    }),
    tarea({
      id: 4,
      descripcion: "Revisar bombas",
      estado: "ASIGNADA",
      fechaInicio: new Date(Date.UTC(2026, 8, 6, 15)),
      fechaFin: new Date(Date.UTC(2026, 8, 6, 16)),
    }),
    tarea({
      id: 5,
      descripcion: "Revisar citofonos",
      estado: "ASIGNADA",
      fechaInicio: new Date(Date.UTC(2026, 8, 28, 15)),
      fechaFin: new Date(Date.UTC(2026, 8, 28, 16)),
    }),
  ];
  const ahora = new Date(Date.UTC(2026, 8, 20, 12));

  it("agrupa por ubicacion en orden alfabetico", () => {
    const informe = construirInformeMensual(
      entrada(tareas, { ahora }),
      opciones({ organizacion: "UBICACION" }),
    );
    expect(informe.secciones.map((s) => (s.tipo === "UBICACION" ? s.titulo : s.tipo))).toEqual([
      "Torre 1",
      "Torre 2",
      "Zonas comunes",
    ]);
  });

  it("en orden cronologico arma un bloque por tarea agrupado por dia", () => {
    const informe = construirInformeMensual(
      entrada(tareas, { ahora }),
      opciones({ organizacion: "CRONOLOGICO" }),
    );
    expect(informe.secciones.map((s) => s.tipo)).toEqual(["DIA", "DIA", "DIA", "DIA"]);
    expect(informe.secciones[0].actividades.map((a) => a.tarea?.id)).toEqual([1, 2]);
    expect(actividadesDelCuerpo(informe).every((a) => a.tarea != null)).toBe(true);
  });

  it("mide la puntualidad contra el dia programado", () => {
    const [aTiempo, tarde] = tareas.map(puntualidadDeTarea);
    expect(aTiempo).toMatchObject({ diasRetraso: 0, duracionRealMin: 45, duracionProgramadaMin: 60 });
    expect(tarde.diasRetraso).toBe(2);
    expect(puntualidadDeTarea(tareas[3]).diasRetraso).toBeNull();

    // Misma actividad en dos fechas: una a tiempo y otra tarde.
    const informe = construirInformeMensual(
      entrada([tareas[0], { ...tareas[1], ubicacion: { nombre: "Torre 2" } }], { ahora }),
      opciones({}),
    );
    expect(informe.preventivas).toHaveLength(1);
    expect(informe.preventivas[0].puntualidad).toEqual({
      cerradas: 2,
      aTiempo: 1,
      conRetraso: 1,
    });
  });

  it("lista novedades con motivo y oculta el rechazo interno si no se pidio", () => {
    const interno = construirInformeMensual(
      entrada(tareas, { ahora }),
      opciones({ campos: { motivoRechazo: true } }),
    );
    // La 5 todavia no vence; la 4 si.
    expect(interno.novedades.map((n) => [n.tareaId, n.novedad])).toEqual([
      [3, "RECHAZADA"],
      [4, "VENCIDA"],
    ]);
    expect(interno.novedades[0].motivo).toBe("Foto borrosa");

    const cliente = construirInformeMensual(
      entrada(tareas, { ahora }),
      opciones({ campos: { motivoRechazo: true } }, "administrador"),
    );
    expect(cliente.novedades[0].motivo).toBe("Devuelta para corrección.");
    expect(cliente.correctivas[0].motivosRechazo).toEqual([]);
  });

  it("consolida recursos, arma el anexo y la tabla de cumplimiento", () => {
    const informe = construirInformeMensual(entrada(tareas, { ahora }), opciones({}));
    expect(informe.consolidado.insumos).toEqual([
      { nombre: "Jabón", unidad: "L", cantidad: 3.5, tareas: 2 },
    ]);
    expect(informe.consolidado.maquinaria).toEqual([
      { nombre: "Hidrolavadora", unidad: "", cantidad: 2, tareas: 2 },
    ]);
    expect(informe.anexo.map((t) => t.tareaId)).toEqual([1, 2, 3, 4, 5]);
    expect(informe.anexo[0].cierre).toEqual(new Date(Date.UTC(2026, 8, 3, 13, 55)));
    expect(informe.cumplimiento.length).toBe(informe.preventivas.length);
    expect(informe.cumplimiento.every((c) => c.previstas == null)).toBe(true);
  });

  it("genera un PDF valido con todas las secciones, en cada organizacion", async () => {
    for (const organizacion of ["ACTIVIDAD", "UBICACION", "CRONOLOGICO"]) {
      const informe = construirInformeMensual(
        entrada(tareas, { ahora }),
        opciones({
          organizacion,
          secciones: {
            cumplimiento: true,
            novedades: true,
            consolidadoRecursos: true,
            anexoTareas: true,
          },
          campos: { estado: true, puntualidad: true, motivoRechazo: true },
          fotos: { tamano: "PEQUENA" },
          textos: {
            titulo: "Informe de auditoría",
            observacionesGenerales: "Sin novedades mayores.",
          },
        }),
      );
      const destino = path.join(os.tmpdir(), `informe-opciones-${organizacion}-${Date.now()}.pdf`);
      await renderizarInformeMensual(informe, {
        archivoDestino: destino,
        cargarFoto: () => null,
        generadoPor: "Gerente Demo",
        idInforme: "0f6c2b9a-1111-4222-8333-444455556666",
      });
      const bytes = fs.readFileSync(destino);
      fs.unlinkSync(destino);
      expect(bytes.subarray(0, 5).toString()).toBe("%PDF-");
      // Marcadores para navegar el informe.
      expect(bytes.includes(Buffer.from("/Outlines"))).toBe(true);
    }
  });

  it("genera un PDF valido sin fotos y solo con secciones de tabla", async () => {
    const informe = construirInformeMensual(
      entrada(tareas, { ahora }),
      opciones({
        secciones: { resumen: false, detalle: false, reemplazadas: false, anexoTareas: true },
        fotos: { incluir: false },
      }),
    );
    const destino = path.join(os.tmpdir(), `informe-opciones-tabla-${Date.now()}.pdf`);
    await renderizarInformeMensual(informe, { archivoDestino: destino, cargarFoto: () => null });
    const bytes = fs.readFileSync(destino);
    fs.unlinkSync(destino);
    expect(bytes.subarray(0, 5).toString()).toBe("%PDF-");
  });
});

describe("informe detallado: retomar el informe", () => {
  const carpeta = path.join(os.tmpdir(), `informes-retomar-test-${process.pid}`);
  const esperar = (ms = 20) => new Promise((r) => setTimeout(r, ms));

  afterAll(() => fs.rmSync(carpeta, { recursive: true, force: true }));

  it("devuelve el informe en curso y luego el listo hasta que se descarga", async () => {
    const jobs = new InformeMensualJobs(carpeta);
    expect(jobs.ultimoDelUsuario("u1")).toBeUndefined();

    let liberar!: () => void;
    const bloqueo = new Promise<void>((r) => (liberar = r));
    const job = jobs.iniciar({
      usuarioId: "u1",
      clave: "a",
      ejecutar: async ({ jobId, archivoDestino }) => {
        expect(jobId).toBeTruthy();
        await bloqueo;
        fs.writeFileSync(archivoDestino, "%PDF-1.4");
        return { nombreArchivo: "x.pdf" };
      },
    });
    expect(jobs.ultimoDelUsuario("u1")).toBe(job);
    expect(jobs.ultimoDelUsuario("otro")).toBeUndefined();

    liberar();
    await esperar();
    expect(job.estado).toBe("LISTO");
    expect(jobs.ultimoDelUsuario("u1")).toBe(job);

    jobs.marcarDescargado(job.id);
    expect(jobs.ultimoDelUsuario("u1")).toBeUndefined();
  });
});
