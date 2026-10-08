import { estadoActualUnidad, estadoDelDia, parseFechaDia } from "../../src/services/AgendaRecursoService";
import { parseNecesidadesHerramienta } from "../../src/utils/herramientaNecesidades";
import {
  buildRecursoOcupadoError,
  compararCandidatos,
  evaluarConflictos,
  resolverOrigen,
  unidadReservable,
  type ReservaLite,
  type UnidadRecurso,
} from "../../src/utils/recursoAgendaCore";
import {
  calcularVentanaRecurso,
  esErrorExclusionReserva,
  normalizarConfigLogistica,
  normalizarUso,
} from "../../src/utils/ventanaRecurso";

// Semana de referencia: lunes 2 jun 2031.
const d = (dia: number, h = 0, m = 0) => new Date(2031, 5, dia, h, m);
const LUN = 2;
const MIE = 4;
const JUE = 5;
const SAB = 7;

const unidadBase: UnidadRecurso = {
  clase: "MAQUINARIA",
  id: 1,
  codigo: "PUL-01",
  nombre: "Pulidora",
  etiqueta: "Pulidora · PUL-01",
  alias: null,
  marca: null,
  modelo: null,
  serial: null,
  tipoId: 10,
  tipoNombre: "Pulidora",
  estado: "OPERATIVA",
  estadoAprobacion: "APROBADA",
  retirada: false,
  propietarioTipo: "EMPRESA",
  conjuntoPropietarioId: null,
  conjuntoPropietarioNombre: null,
};

function reserva(p: Partial<ReservaLite>): ReservaLite {
  return {
    id: 100,
    clase: "MAQUINARIA",
    unidadId: 1,
    tipo: "TAREA",
    estado: "RESERVADA",
    origen: "EMPRESA",
    conjuntoId: "A",
    conjuntoNombre: "Conjunto A",
    tareaId: 1,
    tareaDescripcion: "Pulido salón",
    necesidadId: 1,
    usoInicio: d(MIE, 7),
    usoFin: d(MIE, 12),
    bloqueoInicio: d(MIE, 7),
    bloqueoFin: d(MIE, 12),
    ...p,
  };
}

describe("Ventana de reserva (regla híbrida)", () => {
  const config = normalizarConfigLogistica({ diasEntregaRecursos: [1, 3, 6], margenTrasladoMinutos: 0 });

  test("PU-R1 - un recurso del conjunto se bloquea solo en sus horas", () => {
    const v = calcularVentanaRecurso({ origen: "CONJUNTO", usoInicio: d(MIE, 8), usoFin: d(MIE, 11), config });
    expect(v.bloqueoInicio).toEqual(d(MIE, 8));
    expect(v.bloqueoFin).toEqual(d(MIE, 11));
  });

  test("PU-R2 - un recurso de la empresa viaja: entrega el día logístico anterior y recogida el siguiente", () => {
    const v = calcularVentanaRecurso({ origen: "EMPRESA", usoInicio: d(JUE, 8), usoFin: d(JUE, 11), config });
    expect(v.bloqueoInicio).toEqual(d(MIE)); // miércoles 00:00
    expect(v.bloqueoFin.getDate()).toBe(SAB); // sábado fin del día
    expect(v.usoInicio).toEqual(d(JUE, 8));
  });

  test("PU-R3 - los festivos se saltan al buscar entrega/recogida", () => {
    const festivos = new Set(["2031-06-04"]); // miércoles festivo
    const v = calcularVentanaRecurso({
      origen: "EMPRESA",
      usoInicio: d(JUE, 8),
      usoFin: d(JUE, 11),
      config,
      festivosSet: festivos,
    });
    expect(v.bloqueoInicio).toEqual(d(LUN));
  });

  test("PU-R4 - sin días de entrega la empresa trabaja por horas + margen de traslado", () => {
    const porHoras = normalizarConfigLogistica({ diasEntregaRecursos: [], margenTrasladoMinutos: 90 });
    const v = calcularVentanaRecurso({ origen: "EMPRESA", usoInicio: d(MIE, 8), usoFin: d(MIE, 10), config: porHoras });
    expect(v.bloqueoInicio).toEqual(d(MIE, 6, 30));
    expect(v.bloqueoFin).toEqual(d(MIE, 11, 30));
  });

  test("PU-R5 - normaliza rangos vacíos o invertidos y la configuración inválida", () => {
    const u = normalizarUso(d(MIE, 10), d(MIE, 10));
    expect(+u.usoFin - +u.usoInicio).toBe(60_000);
    expect(normalizarConfigLogistica({ diasEntregaRecursos: [6, 1, 1, 9, -1], margenTrasladoMinutos: 5000 })).toEqual({
      diasEntregaRecursos: [1, 6],
      margenTrasladoMinutos: 1440,
    });
  });
});

describe("Conflictos (réplica de las restricciones de exclusión)", () => {
  const ventana = (ini: Date, fin: Date, bi = ini, bf = fin) => ({ usoInicio: ini, usoFin: fin, bloqueoInicio: bi, bloqueoFin: bf });

  test("PU-R6 - mismo horario en otro conjunto: conflicto de USO", () => {
    const c = evaluarConflictos({
      tipo: "TAREA",
      conjuntoId: "B",
      ventana: ventana(d(MIE, 8), d(MIE, 10)),
      existentes: [reserva({})],
    });
    expect(c).toHaveLength(1);
    expect(c[0].tipoSolape).toBe("USO");
    expect(c[0].motivo).toMatch(/Pulido salón/);
  });

  test("PU-R7 - horas distintas pero ventana física cruzada con otro conjunto: conflicto de UBICACIÓN", () => {
    const c = evaluarConflictos({
      tipo: "TAREA",
      conjuntoId: "B",
      ventana: ventana(d(JUE, 8), d(JUE, 10)),
      existentes: [reserva({ bloqueoInicio: d(LUN), bloqueoFin: d(SAB, 23, 59) })],
    });
    expect(c.map((x) => x.tipoSolape)).toEqual(["UBICACION"]);
  });

  test("PU-R8 - el mismo conjunto puede encadenar la unidad; contiguos y cancelados no chocan", () => {
    expect(
      evaluarConflictos({
        tipo: "TAREA",
        conjuntoId: "A",
        ventana: ventana(d(JUE, 8), d(JUE, 10), d(MIE), d(SAB)),
        existentes: [reserva({ bloqueoInicio: d(LUN), bloqueoFin: d(SAB) })],
      }),
    ).toEqual([]);
    expect(
      evaluarConflictos({
        tipo: "TAREA",
        conjuntoId: "B",
        ventana: ventana(d(MIE, 12), d(MIE, 14)),
        existentes: [reserva({})],
      }),
    ).toEqual([]);
    expect(
      evaluarConflictos({
        tipo: "TAREA",
        conjuntoId: "B",
        ventana: ventana(d(MIE, 8), d(MIE, 10)),
        existentes: [reserva({ estado: "CANCELADA" })],
      }),
    ).toEqual([]);
  });

  test("PU-R9 - un préstamo no 'usa' la unidad: el conjunto que la tiene puede usarla; otro no", () => {
    const prestamo = reserva({ tipo: "PRESTAMO", tareaId: null, bloqueoInicio: d(LUN), bloqueoFin: d(SAB), usoInicio: d(LUN), usoFin: d(SAB) });
    expect(
      evaluarConflictos({ tipo: "TAREA", conjuntoId: "A", ventana: ventana(d(MIE, 8), d(MIE, 10)), existentes: [prestamo] }),
    ).toEqual([]);
    expect(
      evaluarConflictos({ tipo: "TAREA", conjuntoId: "B", ventana: ventana(d(MIE, 8), d(MIE, 10)), existentes: [prestamo] }),
    ).toHaveLength(1);
  });

  test("PU-R10 - al mover una tarea, sus propias reservas no cuentan como conflicto", () => {
    expect(
      evaluarConflictos({
        tipo: "TAREA",
        conjuntoId: "B",
        ventana: ventana(d(MIE, 8), d(MIE, 10)),
        existentes: [reserva({ id: 7 })],
        excluirIds: new Set([7]),
      }),
    ).toEqual([]);
  });
});

describe("Origen y orden de candidatos", () => {
  test("PU-R11 - propia del conjunto, de otro conjunto, en custodia y de la empresa", () => {
    const propia = { ...unidadBase, propietarioTipo: "CONJUNTO" as const, conjuntoPropietarioId: "A" };
    expect(resolverOrigen({ unidad: propia, conjuntoId: "A", usoInicio: d(MIE, 8), usoFin: d(MIE, 9), prestamos: [] })).toMatchObject({
      permitido: true,
      origen: "CONJUNTO",
      grupo: "CONJUNTO",
    });
    expect(resolverOrigen({ unidad: propia, conjuntoId: "B", usoInicio: d(MIE, 8), usoFin: d(MIE, 9), prestamos: [] }).permitido).toBe(false);

    const prestamo = reserva({ tipo: "PRESTAMO", conjuntoId: "B", bloqueoInicio: d(LUN), bloqueoFin: d(SAB) });
    expect(
      resolverOrigen({ unidad: unidadBase, conjuntoId: "B", usoInicio: d(MIE, 8), usoFin: d(MIE, 9), prestamos: [prestamo] }),
    ).toMatchObject({ origen: "CONJUNTO", grupo: "CUSTODIA" });
    expect(
      resolverOrigen({ unidad: unidadBase, conjuntoId: "C", usoInicio: d(MIE, 8), usoFin: d(MIE, 9), prestamos: [prestamo] }),
    ).toMatchObject({ origen: "EMPRESA", grupo: "EMPRESA" });
  });

  test("PU-R12 - orden: disponibles; conjunto > custodia > empresa; cerca del conjunto; menos usada", () => {
    const base = { disponible: true, cercaDelConjunto: false, usosEnPeriodo: 0 };
    const lista = [
      { ...base, grupo: "EMPRESA" as const, etiqueta: "E2", usosEnPeriodo: 3 },
      { ...base, grupo: "EMPRESA" as const, etiqueta: "E1", usosEnPeriodo: 1 },
      { ...base, grupo: "CONJUNTO" as const, etiqueta: "C1", disponible: false },
      { ...base, grupo: "CUSTODIA" as const, etiqueta: "K1" },
      { ...base, grupo: "CONJUNTO" as const, etiqueta: "C2" },
      { ...base, grupo: "EMPRESA" as const, etiqueta: "E3", cercaDelConjunto: true, usosEnPeriodo: 9 },
    ];
    expect(lista.sort(compararCandidatos).map((c) => c.etiqueta)).toEqual(["C2", "K1", "E3", "E1", "E2", "C1"]);
  });

  test("PU-R13 - solo una unidad aprobada, operativa y no retirada es reservable", () => {
    expect(unidadReservable(unidadBase).ok).toBe(true);
    expect(unidadReservable({ ...unidadBase, estado: "EN_MANTENIMIENTO" })).toEqual({
      ok: false,
      motivo: "No está operativa (en mantenimiento).",
    });
    expect(unidadReservable({ ...unidadBase, estado: "DANADA" }).ok).toBe(false);
    expect(unidadReservable({ ...unidadBase, estado: "FUERA_DE_SERVICIO" }).ok).toBe(false);
    expect(unidadReservable({ ...unidadBase, estadoAprobacion: "PENDIENTE" }).ok).toBe(false);
    expect(unidadReservable({ ...unidadBase, retirada: true }).ok).toBe(false);
  });
});

describe("Errores y estados derivados", () => {
  test("PU-R14 - detecta la violación de exclusión que entrega Prisma", () => {
    expect(
      esErrorExclusionReserva(new Error('violates exclusion constraint "ReservaRecurso_maquinaria_uso_excl"')),
    ).toBe(true);
    expect(esErrorExclusionReserva(new Error("otro error"))).toBe(false);
  });

  test("PU-R15 - el 409 RECURSO_OCUPADO viaja con detalle y pista para reprogramar", () => {
    const e = buildRecursoOcupadoError({
      contexto: "REPROGRAMAR",
      conflictos: [
        {
          clase: "MAQUINARIA",
          unidadId: 1,
          unidadEtiqueta: "PUL-01",
          reservaId: 5,
          tareaId: 9,
          tareaDescripcion: "x",
          tipoSolape: "USO",
          motivo: "PUL-01: ocupada",
          ocupadoPor: null,
        },
      ],
    });
    expect(e).toMatchObject({ status: 409, ok: false, reason: "RECURSO_OCUPADO", message: "PUL-01: ocupada" });
    expect(e.userHint).toMatch(/liberar/);
  });

  test("PU-R16 - estado por día: mantenimiento > no operativa > reservado > prestado > traslado > disponible", () => {
    const base = { conjuntoNombre: "Conjunto A", conjuntoId: "A", estado: "RESERVADA" };
    const reservas = [
      { ...base, tipo: "TAREA", usoInicio: d(MIE, 8), usoFin: d(MIE, 10), bloqueoInicio: d(MIE), bloqueoFin: d(SAB, 23) },
      { ...base, tipo: "MANTENIMIENTO", conjuntoNombre: null, conjuntoId: null, usoInicio: d(SAB + 2), usoFin: d(SAB + 3), bloqueoInicio: d(SAB + 2), bloqueoFin: d(SAB + 3) },
    ];
    expect(estadoDelDia({ dia: d(MIE), unidad: unidadBase, reservas }).estado).toBe("RESERVADO");
    expect(estadoDelDia({ dia: d(JUE), unidad: unidadBase, reservas })).toMatchObject({ estado: "EN_TRASLADO", conjuntoNombre: "Conjunto A" });
    expect(estadoDelDia({ dia: d(SAB + 2), unidad: unidadBase, reservas }).estado).toBe("MANTENIMIENTO");
    expect(estadoDelDia({ dia: d(LUN), unidad: unidadBase, reservas }).estado).toBe("DISPONIBLE");
    expect(estadoDelDia({ dia: d(LUN), unidad: { ...unidadBase, estado: "DANADA" }, reservas }).estado).toBe("NO_OPERATIVA");
  });

  test("PU-R17 - estado actual: en uso en el conjunto y libre al terminar la cadena de bloqueos", () => {
    const pub = (p: any) => ({
      id: 1,
      clase: "MAQUINARIA" as const,
      unidadId: 1,
      recursoEtiqueta: "PUL-01",
      origen: "EMPRESA",
      tareaId: 1,
      tareaDescripcion: "x",
      tareaEstado: "ASIGNADA",
      necesidadId: 1,
      responsables: [],
      supervisor: null,
      observacion: null,
      motivoCancelacion: null,
      duracionMinutos: 60,
      creadoEn: d(LUN),
      canceladoEn: null,
      finalizadaEn: null,
      estado: "RESERVADA",
      tipo: "TAREA",
      conjuntoId: "A",
      conjuntoNombre: "Conjunto A",
      ...p,
    });
    const reservas = [
      pub({ usoInicio: d(MIE, 8), usoFin: d(MIE, 10), bloqueoInicio: d(LUN), bloqueoFin: d(MIE, 23) }),
      pub({ id: 2, usoInicio: d(JUE, 8), usoFin: d(JUE, 10), bloqueoInicio: d(MIE), bloqueoFin: d(SAB, 23) }),
    ];
    const out = estadoActualUnidad({ ahora: d(MIE, 9), unidad: unidadBase, reservas });
    expect(out.estado).toBe("EN_USO");
    expect(out.ubicacion).toMatchObject({ tipo: "CONJUNTO", nombre: "Conjunto A" });
    expect(out.libreDesde).toEqual(d(SAB, 23));
    expect(estadoActualUnidad({ ahora: d(LUN, 9), unidad: unidadBase, reservas: [] })).toMatchObject({
      estado: "DISPONIBLE",
      ubicacion: { tipo: "BODEGA" },
    });
  });

  test("PU-R18 - herramientas: cantidades enteras, obligatoria por defecto", () => {
    expect(parseNecesidadesHerramienta([{ herramientaId: 2, cantidad: 0.4 }, { herramientaId: 3, obligatorio: false }])).toEqual([
      { herramientaId: 2, cantidad: 1, obligatorio: true },
      { herramientaId: 3, cantidad: 1, obligatorio: false },
    ]);
  });
});

describe("Fechas de consulta de la agenda", () => {
  test("PU-R19 - 'YYYY-MM-DD' es el día local (no UTC, que corre la semana un día)", () => {
    const d = parseFechaDia("2026-10-05") as Date;
    expect([d.getFullYear(), d.getMonth(), d.getDate(), d.getHours()]).toEqual([2026, 9, 5, 0]);
    expect(parseFechaDia("2026-10-05T12:00:00.000Z")).toBe("2026-10-05T12:00:00.000Z");
  });
});
