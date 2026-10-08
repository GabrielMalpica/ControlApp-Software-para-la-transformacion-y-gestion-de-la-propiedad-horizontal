// Agenda de recursos contra una base REAL de PostgreSQL (con las migraciones
// 20261008000000_agenda_recursos y 20261008000001_agenda_recursos_triggers).
// Se omite si TEST_DATABASE_URL no está definida. Por seguridad solo corre
// contra bases cuyo nombre contenga "test" (nunca contra controlapp_bd).
//
//   TEST_DATABASE_URL=postgresql://...:55432/controlapp_test?schema=public \
//     npx jest tests/integration/agenda-recursos.db.test.ts --runInBand
import { PrismaClient } from "@prisma/client";

import { AgendaRecursoService } from "../../src/services/AgendaRecursoService";
import { GerenteService } from "../../src/services/GerenteServices";
import {
  ReservaRecursoService,
  materializarNecesidadesDeTareas,
  registrarPrestamoEnAgenda,
} from "../../src/services/ReservaRecursoService";

const URL = process.env.TEST_DATABASE_URL;
const seguro = !!URL && /test/i.test(URL.split("/").pop() ?? "");
const suite = seguro ? describe : describe.skip;

const EMPRESA = "TEST-AGR-EMPRESA";
const OTRA_EMPRESA = "TEST-AGR-OTRA";
const A = "TEST-AGR-A";
const B = "TEST-AGR-B";
const C = "TEST-AGR-C";

/** Lunes base lejano (sin festivos sembrados) para que las ventanas no se crucen con datos reales. */
function lunesBase(): Date {
  const d = new Date(2031, 2, 3); // 3 mar 2031
  while (d.getDay() !== 1) d.setDate(d.getDate() + 1);
  return d;
}
const BASE = lunesBase();
/** Semana `s` (separadas 3 semanas para que ninguna ventana logística se cruce), día 1=lunes..6=sábado. */
function dia(s: number, dow: number, h = 0, m = 0): Date {
  return new Date(BASE.getFullYear(), BASE.getMonth(), BASE.getDate() + s * 21 + (dow - 1), h, m);
}

suite("Agenda de recursos (PostgreSQL real)", () => {
  const prisma = new PrismaClient({ datasourceUrl: URL });
  const svc = new ReservaRecursoService(prisma, EMPRESA, { id: "test-actor", nombre: "Tester" });
  const agenda = new AgendaRecursoService(prisma, EMPRESA);

  const ids = {
    ubic: {} as Record<string, number>,
    elem: {} as Record<string, number>,
    tipoGuadana: 0,
    tipoPulidora: 0,
    herrEscalera: 0,
    guadanaA1: 0,
    guadana01: 0,
    guadana02: 0,
    pulidora01: 0,
    pulidora02: 0,
    pulidora03: 0,
    escEmpresa: 0,
    escA: 0,
  };

  async function limpiar() {
    for (const nit of [EMPRESA, OTRA_EMPRESA]) {
      await prisma.reservaRecurso.deleteMany({ where: { empresaId: nit } });
      await prisma.necesidadRecursoTarea.deleteMany({ where: { tarea: { conjunto: { empresaId: nit } } } });
      await prisma.tarea.deleteMany({ where: { conjunto: { empresaId: nit } } });
      await prisma.elemento.deleteMany({ where: { ubicacion: { conjunto: { empresaId: nit } } } });
      await prisma.ubicacion.deleteMany({ where: { conjunto: { empresaId: nit } } });
      await prisma.maquinaria.deleteMany({ where: { empresaId: nit } });
      await prisma.herramientaItem.deleteMany({ where: { empresaId: nit } });
      await prisma.herramienta.deleteMany({ where: { empresaId: nit } });
      await prisma.tipoMaquinariaCatalogo.deleteMany({ where: { empresaId: nit } });
      await prisma.conjunto.deleteMany({ where: { empresaId: nit } });
      await prisma.empresa.deleteMany({ where: { nit } });
    }
  }

  async function crearMaquina(codigo: string, tipoId: number, tipo: "GUADANIA" | "PULIDORA", conjunto?: string) {
    const m = await prisma.maquinaria.create({
      data: {
        nombre: tipo === "GUADANIA" ? "Guadaña" : "Pulidora",
        marca: "Test",
        tipo,
        tipoCatalogoId: tipoId,
        codigoInterno: codigo,
        empresaId: EMPRESA,
        propietarioTipo: conjunto ? "CONJUNTO" : "EMPRESA",
        conjuntoPropietarioId: conjunto ?? null,
        estadoAprobacion: "APROBADA",
      },
    });
    return m.id;
  }

  async function crearTarea(params: {
    conjunto: string;
    inicio: Date;
    fin: Date;
    descripcion: string;
    maquinaria?: unknown[];
    herramientas?: unknown[];
    grupoPlanId?: string;
  }) {
    const t = await prisma.tarea.create({
      data: {
        descripcion: params.descripcion,
        fechaInicio: params.inicio,
        fechaFin: params.fin,
        duracionMinutos: Math.round((+params.fin - +params.inicio) / 60000),
        tipo: "PREVENTIVA",
        estado: "ASIGNADA",
        borrador: false,
        conjuntoId: params.conjunto,
        ubicacionId: ids.ubic[params.conjunto],
        elementoId: ids.elem[params.conjunto],
        periodoAnio: params.inicio.getFullYear(),
        periodoMes: params.inicio.getMonth() + 1,
        grupoPlanId: params.grupoPlanId ?? null,
        maquinariaPlanJson: (params.maquinaria ?? null) as any,
        herramientasPlanJson: (params.herramientas ?? null) as any,
      },
    });
    await materializarNecesidadesDeTareas(prisma, [t.id]);
    return t.id;
  }

  async function necesidadDe(tareaId: number) {
    return prisma.necesidadRecursoTarea.findFirstOrThrow({ where: { tareaId } });
  }

  beforeAll(async () => {
    await limpiar();
    await prisma.empresa.create({ data: { nombre: "Empresa agenda", nit: EMPRESA } });
    await prisma.empresa.create({ data: { nombre: "Otra empresa", nit: OTRA_EMPRESA } });
    for (const [nit, nombre] of [
      [A, "Conjunto A"],
      [B, "Conjunto B"],
      [C, "Conjunto C"],
    ] as const) {
      await prisma.conjunto.create({
        data: { nit, nombre, direccion: "Calle 1", correo: `${nit.toLowerCase()}@test.local`, empresaId: EMPRESA },
      });
      const u = await prisma.ubicacion.create({ data: { nombre: "Zonas comunes", conjuntoId: nit } });
      const e = await prisma.elemento.create({ data: { nombre: "Prado", ubicacionId: u.id } });
      ids.ubic[nit] = u.id;
      ids.elem[nit] = e.id;
    }

    ids.tipoGuadana = (
      await prisma.tipoMaquinariaCatalogo.create({
        data: { empresaId: EMPRESA, nombre: "Guadaña", nombreNormalizado: "guadana", tipoLegacy: "GUADANIA" },
      })
    ).id;
    ids.tipoPulidora = (
      await prisma.tipoMaquinariaCatalogo.create({
        data: { empresaId: EMPRESA, nombre: "Pulidora", nombreNormalizado: "pulidora", tipoLegacy: "PULIDORA" },
      })
    ).id;

    ids.guadanaA1 = await crearMaquina("GUA-A1", ids.tipoGuadana, "GUADANIA", A);
    ids.guadana01 = await crearMaquina("GUA-01", ids.tipoGuadana, "GUADANIA");
    ids.guadana02 = await crearMaquina("GUA-02", ids.tipoGuadana, "GUADANIA");
    ids.pulidora01 = await crearMaquina("PUL-01", ids.tipoPulidora, "PULIDORA");
    ids.pulidora02 = await crearMaquina("PUL-02", ids.tipoPulidora, "PULIDORA");
    ids.pulidora03 = await crearMaquina("PUL-03", ids.tipoPulidora, "PULIDORA");

    ids.herrEscalera = (
      await prisma.herramienta.create({ data: { empresaId: EMPRESA, nombre: "Escalera", nombreNormalizado: "escalera" } })
    ).id;
    ids.escEmpresa = (
      await prisma.herramientaItem.create({
        data: {
          empresaId: EMPRESA,
          herramientaId: ids.herrEscalera,
          codigoInterno: "ESC-0001",
          propietarioTipo: "EMPRESA",
          estadoAprobacion: "APROBADA",
        },
      })
    ).id;
    ids.escA = (
      await prisma.herramientaItem.create({
        data: {
          empresaId: EMPRESA,
          herramientaId: ids.herrEscalera,
          codigoInterno: "ESC-A-0001",
          propietarioTipo: "CONJUNTO",
          conjuntoPropietarioId: A,
          estadoAprobacion: "APROBADA",
        },
      })
    ).id;
  });

  afterAll(async () => {
    await limpiar();
    await prisma.$disconnect();
  });

  /* ------------------------------------------------------------------ */
  /* Restricciones de base de datos                                      */
  /* ------------------------------------------------------------------ */

  describe("restricciones en PostgreSQL", () => {
    const base = () => ({
      empresaId: EMPRESA,
      clase: "MAQUINARIA" as const,
      maquinariaId: ids.pulidora03,
      tipo: "TAREA" as const,
      origen: "CONJUNTO" as const,
      recursoEtiqueta: "PUL-03",
    });

    afterEach(async () => {
      await prisma.reservaRecurso.deleteMany({ where: { maquinariaId: ids.pulidora03 } });
    });

    it("rechaza dos usos simultáneos de la misma unidad aunque sea en el mismo conjunto", async () => {
      await prisma.reservaRecurso.create({
        data: { ...base(), conjuntoId: A, usoInicio: dia(0, 1, 8), usoFin: dia(0, 1, 12), bloqueoInicio: dia(0, 1, 8), bloqueoFin: dia(0, 1, 12) },
      });
      await expect(
        prisma.reservaRecurso.create({
          data: { ...base(), conjuntoId: A, usoInicio: dia(0, 1, 10), usoFin: dia(0, 1, 13), bloqueoInicio: dia(0, 1, 10), bloqueoFin: dia(0, 1, 13) },
        }),
      ).rejects.toThrow(/ReservaRecurso_maquinaria_uso_excl/);
    });

    it("permite usos contiguos [8,12) y [12,14)", async () => {
      await prisma.reservaRecurso.create({
        data: { ...base(), conjuntoId: A, usoInicio: dia(0, 1, 8), usoFin: dia(0, 1, 12), bloqueoInicio: dia(0, 1, 8), bloqueoFin: dia(0, 1, 12) },
      });
      await expect(
        prisma.reservaRecurso.create({
          data: { ...base(), conjuntoId: A, usoInicio: dia(0, 1, 12), usoFin: dia(0, 1, 14), bloqueoInicio: dia(0, 1, 12), bloqueoFin: dia(0, 1, 14) },
        }),
      ).resolves.toBeTruthy();
    });

    it("rechaza la misma unidad en otro conjunto si las ventanas físicas (traslado) se cruzan", async () => {
      await prisma.reservaRecurso.create({
        data: { ...base(), origen: "EMPRESA", conjuntoId: A, usoInicio: dia(0, 3, 8), usoFin: dia(0, 3, 10), bloqueoInicio: dia(0, 1), bloqueoFin: dia(0, 6, 23, 59) },
      });
      // Usos distintos (jueves) pero la unidad sigue comprometida con A.
      await expect(
        prisma.reservaRecurso.create({
          data: { ...base(), origen: "EMPRESA", conjuntoId: B, usoInicio: dia(0, 4, 8), usoFin: dia(0, 4, 10), bloqueoInicio: dia(0, 4, 8), bloqueoFin: dia(0, 4, 10) },
        }),
      ).rejects.toThrow(/ReservaRecurso_maquinaria_ubicacion_excl/);
      // En el MISMO conjunto sí puede encadenarse.
      await expect(
        prisma.reservaRecurso.create({
          data: { ...base(), origen: "EMPRESA", conjuntoId: A, usoInicio: dia(0, 4, 8), usoFin: dia(0, 4, 10), bloqueoInicio: dia(0, 3), bloqueoFin: dia(0, 6, 23, 59) },
        }),
      ).resolves.toBeTruthy();
    });

    it("las reservas CANCELADAS no bloquean", async () => {
      const r = await prisma.reservaRecurso.create({
        data: { ...base(), conjuntoId: A, usoInicio: dia(0, 2, 8), usoFin: dia(0, 2, 12), bloqueoInicio: dia(0, 2, 8), bloqueoFin: dia(0, 2, 12) },
      });
      await prisma.reservaRecurso.update({ where: { id: r.id }, data: { estado: "CANCELADA" } });
      await expect(
        prisma.reservaRecurso.create({
          data: { ...base(), conjuntoId: B, usoInicio: dia(0, 2, 8), usoFin: dia(0, 2, 12), bloqueoInicio: dia(0, 2, 8), bloqueoFin: dia(0, 2, 12) },
        }),
      ).resolves.toBeTruthy();
    });

    it("CHECK: la reserva debe apuntar a la unidad de su clase y el bloqueo debe contener al uso", async () => {
      await expect(
        prisma.reservaRecurso.create({
          data: { ...base(), clase: "HERRAMIENTA", conjuntoId: A, usoInicio: dia(0, 5, 8), usoFin: dia(0, 5, 9), bloqueoInicio: dia(0, 5, 8), bloqueoFin: dia(0, 5, 9) },
        }),
      ).rejects.toThrow(/ReservaRecurso_clase_check/);
      await expect(
        prisma.reservaRecurso.create({
          data: { ...base(), conjuntoId: A, usoInicio: dia(0, 5, 8), usoFin: dia(0, 5, 9), bloqueoInicio: dia(0, 5, 8, 30), bloqueoFin: dia(0, 5, 9) },
        }),
      ).rejects.toThrow(/ReservaRecurso_rangos_check/);
    });
  });

  /* ------------------------------------------------------------------ */
  /* Necesidades                                                          */
  /* ------------------------------------------------------------------ */

  it("materializa necesidades desde el plan (enum legado y catálogo), sumando repetidos", async () => {
    const tareaId = await crearTarea({
      conjunto: A,
      inicio: dia(1, 1, 7),
      fin: dia(1, 1, 9),
      descripcion: "Poda general",
      maquinaria: [
        { tipo: "GUADANIA", cantidad: 1 },
        { tipoCatalogoId: ids.tipoGuadana, cantidad: 1 },
        { tipo: "SOPLADORA", cantidad: 1, obligatorio: false },
      ],
      herramientas: [{ herramientaId: ids.herrEscalera, cantidad: 1.5 }],
    });
    const ns = await prisma.necesidadRecursoTarea.findMany({
      where: { tareaId },
      include: { tipoMaquinaria: true },
      orderBy: { id: "asc" },
    });
    const guadana = ns.find((n) => n.tipoMaquinariaId === ids.tipoGuadana)!;
    expect(guadana.cantidad).toBe(2);
    expect(guadana.obligatorio).toBe(true);
    // SOPLADORA no existía en el catálogo de la empresa: se crea por tipoLegacy.
    const sopladora = ns.find((n) => n.tipoMaquinaria?.tipoLegacy === "SOPLADORA")!;
    expect(sopladora.obligatorio).toBe(false);
    expect(ns.find((n) => n.herramientaId === ids.herrEscalera)!.cantidad).toBe(2);

    // Idempotente.
    const otra = await materializarNecesidadesDeTareas(prisma, [tareaId]);
    expect(otra.creadas).toBe(0);
  });

  /* ------------------------------------------------------------------ */
  /* Casos obligatorios                                                   */
  /* ------------------------------------------------------------------ */

  it("CASO 1: el conjunto con Guadaña A1 la recibe como primera opción", async () => {
    const tareaId = await crearTarea({
      conjunto: A,
      inicio: dia(2, 3, 7),
      fin: dia(2, 3, 9),
      descripcion: "Poda zonas comunes",
      maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 1 }],
    });
    const n = await necesidadDe(tareaId);
    const out = await svc.candidatos(n.id);
    expect(out.candidatos[0].unidadId).toBe(ids.guadanaA1);
    expect(out.candidatos[0].grupo).toBe("CONJUNTO");
    expect(out.candidatos[0].sugerida).toBe(true);
    // Las de la empresa vienen después, como respaldo.
    expect(out.candidatos.slice(1).every((c) => c.grupo === "EMPRESA")).toBe(true);
  });

  it("CASO 2: Guadaña 01 ocupada miércoles 7-12 no se puede elegir; Guadaña 02 sí", async () => {
    // Guadaña 01 ocupada en C miércoles 7:00-12:00.
    const ocupante = await crearTarea({
      conjunto: C,
      inicio: dia(3, 3, 7),
      fin: dia(3, 3, 12),
      descripcion: "Poda C",
      maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 1 }],
    });
    await svc.reservar({ necesidadId: (await necesidadDe(ocupante)).id, unidades: [{ clase: "MAQUINARIA", id: ids.guadana01 }] });

    const tareaB = await crearTarea({
      conjunto: B,
      inicio: dia(3, 3, 8),
      fin: dia(3, 3, 10),
      descripcion: "Poda B",
      maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 1 }],
    });
    const nB = await necesidadDe(tareaB);
    const cands = await svc.candidatos(nB.id);
    const g01 = cands.candidatos.find((c) => c.unidadId === ids.guadana01)!;
    const g02 = cands.candidatos.find((c) => c.unidadId === ids.guadana02)!;
    const gA1 = cands.candidatos.find((c) => c.unidadId === ids.guadanaA1)!;
    expect(g01.disponible).toBe(false);
    expect(g01.motivo).toMatch(/Poda C/);
    expect(g02.disponible).toBe(true);
    expect(g02.sugerida).toBe(true);
    expect(gA1.disponible).toBe(false); // propia de A, no se presta a B

    await expect(
      svc.reservar({ necesidadId: nB.id, unidades: [{ clase: "MAQUINARIA", id: ids.guadana01 }] }),
    ).rejects.toMatchObject({ status: 409, reason: "RECURSO_OCUPADO" });
    const ok = await svc.reservar({ necesidadId: nB.id, unidades: [{ clase: "MAQUINARIA", id: ids.guadana02 }] });
    expect(ok.reservas).toHaveLength(1);
    expect(ok.reservas[0].origen).toBe("EMPRESA");
  });

  it("CASO 3: buscar 'Pulidora' en una semana muestra todas las pulidoras con sus reservas", async () => {
    const t = await crearTarea({
      conjunto: A,
      inicio: dia(4, 1, 7),
      fin: dia(4, 1, 10),
      descripcion: "Pulido salón social",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    await svc.reservar({ necesidadId: (await necesidadDe(t)).id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora01 }] });

    const out = await agenda.agenda({ desde: dia(4, 1), hasta: dia(4, 7), q: "Pulidora" });
    const grupo = out.grupos.find((g) => g.tipoNombre === "Pulidora")!;
    expect(grupo.unidades.map((u) => u.codigo).sort()).toEqual(["PUL-01", "PUL-02", "PUL-03"]);
    const p1 = grupo.unidades.find((u) => u.id === ids.pulidora01)!;
    expect(p1.reservas).toHaveLength(1);
    expect(p1.reservas[0].conjuntoNombre).toBe("Conjunto A");
    expect(p1.reservas[0].tareaDescripcion).toBe("Pulido salón social");
    expect(p1.dias[0]).toMatchObject({ estado: "RESERVADO", conjuntoNombre: "Conjunto A" });
    expect(grupo.unidades.find((u) => u.id === ids.pulidora02)!.dias.every((d) => d.estado === "DISPONIBLE")).toBe(true);

    // Búsqueda por código específico.
    const solo = await agenda.agenda({ desde: dia(4, 1), hasta: dia(4, 7), q: "PUL-02" });
    expect(solo.totalUnidades).toBe(1);
  });

  it("CASO 4: reprogramar mueve la reserva; si la pulidora está ocupada bloquea, y se puede liberar a propósito", async () => {
    const gerente = new GerenteService(prisma, EMPRESA);
    const t = await crearTarea({
      conjunto: A,
      inicio: dia(5, 3, 8),
      fin: dia(5, 3, 10),
      descripcion: "Pulido piso",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    await svc.reservar({ necesidadId: (await necesidadDe(t)).id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora01 }] });

    // (a) Jueves 10:00 libre -> la reserva se mueve.
    await gerente.editarTarea(t, { fechaInicio: dia(5, 4, 10), fechaFin: dia(5, 4, 12) });
    const movida = await prisma.reservaRecurso.findFirstOrThrow({ where: { tareaId: t, estado: "RESERVADA" } });
    expect(+movida.usoInicio).toBe(+dia(5, 4, 10));
    expect(+movida.usoFin).toBe(+dia(5, 4, 12));

    // (b) Pulidora 01 queda ocupada en B la semana siguiente; mover allá -> 409 y nada cambia.
    const otra = await crearTarea({
      conjunto: B,
      inicio: dia(6, 3, 8),
      fin: dia(6, 3, 12),
      descripcion: "Pulido B",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    await svc.reservar({ necesidadId: (await necesidadDe(otra)).id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora01 }] });

    await expect(
      gerente.editarTarea(t, { fechaInicio: dia(6, 3, 9), fechaFin: dia(6, 3, 11) }),
    ).rejects.toMatchObject({ status: 409, reason: "RECURSO_OCUPADO" });
    const sinCambio = await prisma.tarea.findUniqueOrThrow({ where: { id: t } });
    expect(+sinCambio.fechaInicio).toBe(+dia(5, 4, 10));

    // (c) El usuario decide liberar el recurso: la tarea se mueve y la reserva queda CANCELADA en el histórico.
    await gerente.editarTarea(t, {
      fechaInicio: dia(6, 3, 9),
      fechaFin: dia(6, 3, 11),
      liberarRecursosOcupados: true,
    });
    const liberada = await prisma.reservaRecurso.findFirstOrThrow({ where: { tareaId: t } });
    expect(liberada.estado).toBe("CANCELADA");
    expect(liberada.motivoCancelacion).toMatch(/reprogramar/i);
    const necesidad = (await agenda.necesidades({ desde: dia(6, 1), hasta: dia(6, 7), conjuntoId: A })).necesidades.find(
      (n) => n.tarea.id === t,
    )!;
    expect(necesidad.cobertura).toBe("PENDIENTE");
  });

  it("CASO 5: 2 guadañas = 1 propia del conjunto + 1 de la empresa", async () => {
    const t = await crearTarea({
      conjunto: A,
      inicio: dia(7, 2, 7),
      fin: dia(7, 2, 11),
      descripcion: "Poda general",
      maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 2 }],
    });
    const n = await necesidadDe(t);
    const out = await svc.reservar({
      necesidadId: n.id,
      unidades: [
        { clase: "MAQUINARIA", id: ids.guadanaA1 },
        { clase: "MAQUINARIA", id: ids.guadana02 },
      ],
    });
    expect(out.reservas.map((r) => r.origen).sort()).toEqual(["CONJUNTO", "EMPRESA"]);
    const propia = out.reservas.find((r) => r.origen === "CONJUNTO")!;
    // La propia se bloquea solo en sus horas; la de la empresa en su ventana logística.
    expect(+propia.bloqueoInicio).toBe(+dia(7, 2, 7));
    const empresa = out.reservas.find((r) => r.origen === "EMPRESA")!;
    expect(+empresa.bloqueoInicio).toBeLessThan(+dia(7, 2, 7));

    const cobertura = (await agenda.necesidades({ desde: dia(7, 1), hasta: dia(7, 7), conjuntoId: A })).necesidades.find(
      (x) => x.id === n.id,
    )!;
    expect(cobertura).toMatchObject({ cobertura: "CUBIERTA", asignadas: 2, pendientes: 0 });
    await expect(
      svc.reservar({ necesidadId: n.id, unidades: [{ clase: "MAQUINARIA", id: ids.guadana01 }] }),
    ).rejects.toMatchObject({ status: 409 });
  });

  /* ------------------------------------------------------------------ */
  /* Concurrencia, estados, préstamo, mantenimiento, histórico           */
  /* ------------------------------------------------------------------ */

  it("dos usuarios reservando la misma unidad a la vez: solo uno gana", async () => {
    const t1 = await crearTarea({
      conjunto: A,
      inicio: dia(8, 3, 8),
      fin: dia(8, 3, 10),
      descripcion: "Pulido A",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    const t2 = await crearTarea({
      conjunto: B,
      inicio: dia(8, 3, 9),
      fin: dia(8, 3, 11),
      descripcion: "Pulido B",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    const otroUsuario = new ReservaRecursoService(new PrismaClient({ datasourceUrl: URL }), EMPRESA);
    const resultados = await Promise.allSettled([
      svc.reservar({ necesidadId: (await necesidadDe(t1)).id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora02 }] }),
      otroUsuario.reservar({ necesidadId: (await necesidadDe(t2)).id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora02 }] }),
    ]);
    expect(resultados.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const fallo = resultados.find((r) => r.status === "rejected") as PromiseRejectedResult;
    expect(fallo.reason).toMatchObject({ status: 409, reason: "RECURSO_OCUPADO" });
    const vigentes = await prisma.reservaRecurso.count({
      where: { maquinariaId: ids.pulidora02, estado: "RESERVADA", usoInicio: { gte: dia(8, 1) }, usoFin: { lte: dia(8, 7) } },
    });
    expect(vigentes).toBe(1);
  });

  it("una unidad dañada no se ofrece ni se reserva, y sus reservas vigentes generan alerta", async () => {
    const t = await crearTarea({
      conjunto: C,
      inicio: dia(9, 2, 8),
      fin: dia(9, 2, 10),
      descripcion: "Pulido C",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    const n = await necesidadDe(t);
    await svc.reservar({ necesidadId: n.id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora03 }] });
    await prisma.maquinaria.update({ where: { id: ids.pulidora03 }, data: { estado: "DANADA" } });
    try {
      const alertas = await agenda.alertas({ desde: dia(9, 1), hasta: dia(9, 7) });
      expect(alertas.alertas.some((a) => a.tipo === "RECURSO_NO_OPERATIVO" && a.tareaId === t)).toBe(true);

      const t2 = await crearTarea({
        conjunto: C,
        inicio: dia(9, 4, 8),
        fin: dia(9, 4, 10),
        descripcion: "Pulido C 2",
        maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
      });
      const n2 = await necesidadDe(t2);
      const cands = await svc.candidatos(n2.id);
      expect(cands.candidatos.find((c) => c.unidadId === ids.pulidora03)).toMatchObject({
        disponible: false,
        motivo: expect.stringMatching(/dañada/),
      });
      await expect(
        svc.reservar({ necesidadId: n2.id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora03 }] }),
      ).rejects.toMatchObject({ status: 409 });

      // Reemplazo: se cambia la unidad dañada por otra.
      const reserva = await prisma.reservaRecurso.findFirstOrThrow({ where: { tareaId: t, estado: "RESERVADA" } });
      const cambio = await svc.reemplazar(reserva.id, { unidadId: ids.pulidora01, motivo: "La 03 se dañó" });
      expect(cambio.reserva.unidadId).toBe(ids.pulidora01);
      expect((await prisma.reservaRecurso.findUniqueOrThrow({ where: { id: reserva.id } })).estado).toBe("CANCELADA");
    } finally {
      await prisma.maquinaria.update({ where: { id: ids.pulidora03 }, data: { estado: "OPERATIVA" } });
    }
  });

  it("un préstamo largo ubica la unidad en el conjunto: bloquea a otros, permite al conjunto que la tiene", async () => {
    await prisma.$transaction((tx) =>
      registrarPrestamoEnAgenda(tx, {
        empresaId: EMPRESA,
        clase: "MAQUINARIA",
        unidadId: ids.pulidora02,
        conjuntoId: C,
        desde: dia(10, 1),
        hasta: dia(10, 6, 23),
        prestamoId: 999001,
      }),
    );
    const tB = await crearTarea({
      conjunto: B,
      inicio: dia(10, 3, 8),
      fin: dia(10, 3, 10),
      descripcion: "Pulido B",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    const candB = await svc.candidatos((await necesidadDe(tB)).id);
    expect(candB.candidatos.find((c) => c.unidadId === ids.pulidora02)!.disponible).toBe(false);

    const tC = await crearTarea({
      conjunto: C,
      inicio: dia(10, 3, 8),
      fin: dia(10, 3, 10),
      descripcion: "Pulido C",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    const candC = await svc.candidatos((await necesidadDe(tC)).id);
    const p2 = candC.candidatos.find((c) => c.unidadId === ids.pulidora02)!;
    expect(p2).toMatchObject({ disponible: true, grupo: "CUSTODIA", origen: "CONJUNTO" });
    expect(candC.candidatos[0].unidadId).toBe(ids.pulidora02); // en custodia va antes que las de la empresa
    const res = await svc.reservar({ necesidadId: (await necesidadDe(tC)).id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora02 }] });
    // Ya está en el conjunto: se bloquea solo en sus horas.
    expect(+res.reservas[0].bloqueoInicio).toBe(+dia(10, 3, 8));

    const out = await agenda.agenda({ desde: dia(10, 1), hasta: dia(10, 6), unidadId: ids.pulidora02, clase: "MAQUINARIA" });
    const dias = out.grupos[0].unidades[0].dias;
    expect(dias[0]).toMatchObject({ estado: "PRESTADO", conjuntoNombre: "Conjunto C" });
    expect(dias[2]).toMatchObject({ estado: "RESERVADO", conjuntoNombre: "Conjunto C" });
  });

  it("mantenimiento programado bloquea la unidad y aparece en la agenda", async () => {
    await svc.bloquearMantenimiento({
      clase: "MAQUINARIA",
      unidadId: ids.guadana02,
      desde: dia(11, 4),
      hasta: dia(11, 5),
      motivo: "Cambio de cuchilla",
    });
    const t = await crearTarea({
      conjunto: B,
      inicio: dia(11, 4, 8),
      fin: dia(11, 4, 10),
      descripcion: "Poda B jueves",
      maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 1 }],
    });
    const cands = await svc.candidatos((await necesidadDe(t)).id);
    expect(cands.candidatos.find((c) => c.unidadId === ids.guadana02)!.disponible).toBe(false);
    const out = await agenda.agenda({ desde: dia(11, 1), hasta: dia(11, 6), unidadId: ids.guadana02, clase: "MAQUINARIA" });
    expect(out.grupos[0].unidades[0].dias[3].estado).toBe("MANTENIMIENTO");
  });

  it("herramientas por unidad física: primero la del conjunto, luego la de la empresa", async () => {
    const t = await crearTarea({
      conjunto: A,
      inicio: dia(12, 2, 8),
      fin: dia(12, 2, 10),
      descripcion: "Limpieza de canales",
      herramientas: [{ herramientaId: ids.herrEscalera, cantidad: 1 }],
    });
    const n = await necesidadDe(t);
    const cands = await svc.candidatos(n.id);
    expect(cands.candidatos.map((c) => c.codigo)).toEqual(["ESC-A-0001", "ESC-0001"]);
    const res = await svc.reservar({ necesidadId: n.id, unidades: [{ clase: "HERRAMIENTA", id: ids.escA }] });
    expect(res.reservas[0]).toMatchObject({ clase: "HERRAMIENTA", unidadId: ids.escA, origen: "CONJUNTO" });
  });

  it("cerrar, no completar y eliminar la tarea actualizan la reserva sin perder el histórico", async () => {
    const mk = async (dow: number, desc: string) => {
      const t = await crearTarea({
        conjunto: B,
        inicio: dia(13, dow, 8),
        fin: dia(13, dow, 9),
        descripcion: desc,
        maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 1 }],
      });
      await svc.reservar({ necesidadId: (await necesidadDe(t)).id, unidades: [{ clase: "MAQUINARIA", id: ids.guadana01 }] });
      return t;
    };
    const cerrada = await mk(2, "Poda cerrada");
    const noCompletada = await mk(3, "Poda no completada");
    const eliminada = await mk(4, "Poda eliminada");

    await prisma.tarea.update({ where: { id: cerrada }, data: { estado: "PENDIENTE_APROBACION" } });
    await prisma.tarea.update({ where: { id: noCompletada }, data: { estado: "NO_COMPLETADA" } });
    await new GerenteService(prisma, EMPRESA).eliminarTarea(prisma, eliminada);

    const r1 = await prisma.reservaRecurso.findFirstOrThrow({ where: { tareaId: cerrada } });
    expect(r1.estado).toBe("FINALIZADA");
    expect(r1.finalizadaEn).not.toBeNull();
    const r2 = await prisma.reservaRecurso.findFirstOrThrow({ where: { tareaId: noCompletada } });
    expect(r2.estado).toBe("CANCELADA");
    const r3 = await prisma.reservaRecurso.findFirstOrThrow({
      where: { maquinariaId: ids.guadana01, tareaDescripcion: "Poda eliminada" },
    });
    expect(r3).toMatchObject({ estado: "CANCELADA", tareaId: null, conjuntoNombre: "Conjunto B" });

    const hist = await agenda.historialUnidad("MAQUINARIA", ids.guadana01);
    const descripciones = hist.reservas.map((r) => r.tareaDescripcion);
    expect(descripciones).toEqual(expect.arrayContaining(["Poda cerrada", "Poda no completada", "Poda eliminada"]));
    expect(hist.resumen.finalizadas).toBeGreaterThanOrEqual(1);
  });

  it("cancelar una reserva libera la unidad y la deja en el histórico", async () => {
    const t = await crearTarea({
      conjunto: A,
      inicio: dia(14, 3, 8),
      fin: dia(14, 3, 10),
      descripcion: "Pulido cancelable",
      maquinaria: [{ tipoCatalogoId: ids.tipoPulidora, cantidad: 1 }],
    });
    const n = await necesidadDe(t);
    const res = await svc.reservar({ necesidadId: n.id, unidades: [{ clase: "MAQUINARIA", id: ids.pulidora03 }] });
    await svc.cancelar(res.reservas[0].id, { motivo: "Se envía a otro conjunto" });
    const cands = await svc.candidatos(n.id);
    expect(cands.candidatos.find((c) => c.unidadId === ids.pulidora03)!.disponible).toBe(true);
    await expect(svc.cancelar(res.reservas[0].id, { motivo: "otra vez" })).rejects.toMatchObject({ status: 409 });
  });

  it("aplicar a todo el grupo reserva la misma unidad en los bloques del mismo conjunto", async () => {
    const grupo = "test-agr-grupo-1";
    const t1 = await crearTarea({
      conjunto: C,
      inicio: dia(15, 2, 8),
      fin: dia(15, 2, 12),
      descripcion: "Poda grande (1/2)",
      maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 1 }],
      grupoPlanId: grupo,
    });
    const t2 = await crearTarea({
      conjunto: C,
      inicio: dia(15, 3, 8),
      fin: dia(15, 3, 12),
      descripcion: "Poda grande (2/2)",
      maquinaria: [{ tipoCatalogoId: ids.tipoGuadana, cantidad: 1 }],
      grupoPlanId: grupo,
    });
    const res = await svc.reservar({
      necesidadId: (await necesidadDe(t1)).id,
      unidades: [{ clase: "MAQUINARIA", id: ids.guadana01 }],
      aplicarAGrupo: true,
    });
    expect(res.reservas.map((r) => r.tareaId).sort()).toEqual([t1, t2].sort());
  });

  it("no expone recursos de otra empresa", async () => {
    const otra = new ReservaRecursoService(prisma, OTRA_EMPRESA);
    const n = await prisma.necesidadRecursoTarea.findFirstOrThrow({ where: { tarea: { conjuntoId: A } } });
    await expect(otra.candidatos(n.id)).rejects.toMatchObject({ status: 404 });
    const out = await new AgendaRecursoService(prisma, OTRA_EMPRESA).agenda({ desde: dia(4, 1), hasta: dia(4, 7) });
    expect(out.totalUnidades).toBe(0);
  });
});
