// Planilla de personal (vista de tabla de "Gestión de usuarios"): bloques de
// vacaciones, fechas como día puro, alcance por empresa/conjuntos y que nunca
// salga la contraseña. Regla completa en docs/planilla-personal.md.
import {
  agruparDiasVacaciones,
  diaYmd,
  filaPlanilla,
  hoyYmdBogota,
  periodoVigente,
  planillaSelect,
  PlanillaPersonalService,
  type UsuarioPlanillaRow,
} from "../../src/services/PlanillaPersonalService";

function fila(overrides: Partial<UsuarioPlanillaRow> = {}): UsuarioPlanillaRow {
  return {
    id: "1001",
    nombre: "Ana Operaria",
    correo: "ana@x.co",
    rol: "operario",
    activo: true,
    telefono: BigInt("3001234567"),
    fechaNacimiento: new Date("1990-03-15T05:00:00.000Z"),
    direccion: "Calle 1",
    estadoCivil: null,
    numeroHijos: 2,
    padresVivos: true,
    tipoSangre: "O_POSITIVO",
    eps: "SURA",
    fondoPensiones: "PORVENIR",
    arl: "POSITIVA",
    cajaCompensacion: "COMPENSAR",
    contactoEmergenciaNombre: "Luis Operario",
    contactoEmergenciaParentesco: "Hermano",
    contactoEmergenciaTelefono: "310 555 1234",
    tallaCamisa: "M",
    tallaPantalon: "T_32",
    tallaCalzado: "T_38",
    tipoContrato: "TERMINO_FIJO",
    jornadaLaboral: "COMPLETA",
    patronJornada: null,
    operario: {
      funciones: ["ASEO"],
      cursoAlturas: true,
      cursoSalvamentoAcuatico: false,
      examenIngreso: true,
      fechaIngreso: new Date("2022-05-01T05:00:00.000Z"),
      fechaSalida: null,
      fechaUltimasVacaciones: null,
      observaciones: null,
      conjuntos: [
        { nit: "C-1", nombre: "Bosque", empresaId: "EMP-1" },
        { nit: "C-OTRA", nombre: "De otra empresa", empresaId: "EMP-2" },
      ],
      necesidadesOcupadas: [
        {
          etiqueta: "Aseo #1",
          conjunto: { nit: "C-1", nombre: "Bosque", empresaId: "EMP-1" },
          perfil: { nombre: "Aseo" },
        },
      ],
      disponibilidadPeriodos: [],
    },
    administrador: null,
    ...overrides,
  } as UsuarioPlanillaRow;
}

describe("agruparDiasVacaciones", () => {
  test("une días seguidos y tolera hasta 2 días sin marcar en medio", () => {
    expect(
      agruparDiasVacaciones([
        "2026-09-07",
        "2026-09-08",
        "2026-09-11", // 2 días sin marcar (9 y 10): mismo bloque
        "2026-09-14",
      ]),
    ).toEqual([{ desde: "2026-09-07", hasta: "2026-09-14" }]);
  });

  test("tres o más días sin marcar separan bloques", () => {
    expect(agruparDiasVacaciones(["2026-01-05", "2026-01-09"])).toEqual([
      { desde: "2026-01-05", hasta: "2026-01-05" },
      { desde: "2026-01-09", hasta: "2026-01-09" },
    ]);
  });

  test("ignora duplicados y el orden de entrada, y cruza meses", () => {
    expect(
      agruparDiasVacaciones(["2026-11-02", "2026-10-31", "2026-11-01", "2026-11-01"]),
    ).toEqual([{ desde: "2026-10-31", hasta: "2026-11-02" }]);
    expect(agruparDiasVacaciones([])).toEqual([]);
  });
});

describe("fechas", () => {
  test("una fecha sin hora es el mismo día guardada a medianoche UTC o de Bogotá", () => {
    expect(diaYmd(new Date("2022-05-01T00:00:00.000Z"))).toBe("2022-05-01");
    expect(diaYmd(new Date("2022-05-01T05:00:00.000Z"))).toBe("2022-05-01");
    expect(diaYmd(null)).toBeNull();
  });

  test("hoy se calcula en Colombia aunque en UTC ya sea mañana", () => {
    expect(hoyYmdBogota(new Date("2026-10-23T03:00:00.000Z"))).toBe("2026-10-22");
    expect(hoyYmdBogota(new Date("2026-10-23T06:00:00.000Z"))).toBe("2026-10-23");
  });

  test("el descanso es el del período que rige hoy (el más reciente si se cruzan)", () => {
    const periodos = [
      { fechaInicio: new Date("2025-01-01T05:00:00Z"), fechaFin: null, trabajaDomingo: false, diaDescanso: "LUNES" },
      { fechaInicio: new Date("2026-10-01T05:00:00Z"), fechaFin: null, trabajaDomingo: true, diaDescanso: "MARTES" },
      { fechaInicio: new Date("2026-12-01T05:00:00Z"), fechaFin: null, trabajaDomingo: false, diaDescanso: "JUEVES" },
    ];
    expect(periodoVigente(periodos, "2026-10-22")?.diaDescanso).toBe("MARTES");
    expect(periodoVigente(periodos, "2025-06-01")?.diaDescanso).toBe("LUNES");
    expect(
      periodoVigente(
        [{ fechaInicio: new Date("2025-01-01T05:00:00Z"), fechaFin: new Date("2025-12-31T05:00:00Z"), trabajaDomingo: false, diaDescanso: "LUNES" }],
        "2026-10-22",
      ),
    ).toBeNull();
  });
});

describe("filaPlanilla", () => {
  test("el select nunca pide contraseña ni datos de sesión", () => {
    const claves = Object.keys(planillaSelect);
    expect(claves).not.toContain("contrasena");
    expect(claves).not.toContain("versionSesion");
    expect(claves).not.toContain("requiereCambioContrasena");
    expect(JSON.stringify(planillaSelect)).not.toMatch(/urlEvidencia/);
  });

  test("arma la fila con fechas como día y solo conjuntos de la empresa", () => {
    const out = filaPlanilla(fila(), {
      empresaId: "EMP-1",
      alcance: null,
      hoy: "2026-10-22",
      diasVacaciones: ["2026-09-07", "2026-09-08"],
    });
    expect(out).toMatchObject({
      cedula: "1001",
      telefono: "3001234567",
      fechaNacimiento: "1990-03-15",
      fechaIngreso: "2022-05-01",
      conjuntos: [{ nit: "C-1", nombre: "Bosque" }],
      plazas: [{ etiqueta: "Aseo #1", conjuntoNit: "C-1", conjuntoNombre: "Bosque", perfil: "Aseo" }],
      vacaciones: [{ desde: "2026-09-07", hasta: "2026-09-08" }],
      cursoAlturas: true,
    });
    expect(out).not.toHaveProperty("contrasena");
  });

  test("incluye ARL, caja de compensación y contacto de emergencia (null si faltan)", () => {
    const opciones = { empresaId: "EMP-1", alcance: null, hoy: "2026-10-22", diasVacaciones: [] };
    expect(filaPlanilla(fila(), opciones)).toMatchObject({
      arl: "POSITIVA",
      cajaCompensacion: "COMPENSAR",
      contactoEmergenciaNombre: "Luis Operario",
      contactoEmergenciaParentesco: "Hermano",
      contactoEmergenciaTelefono: "310 555 1234",
    });
    const sinDatos = filaPlanilla(
      fila({
        arl: null,
        cajaCompensacion: null,
        contactoEmergenciaNombre: null,
        contactoEmergenciaParentesco: null,
        contactoEmergenciaTelefono: null,
      }),
      opciones,
    );
    expect(sinDatos.arl).toBeNull();
    expect(sinDatos.cajaCompensacion).toBeNull();
    expect(sinDatos.contactoEmergenciaTelefono).toBeNull();
    for (const campo of [
      "arl",
      "cajaCompensacion",
      "contactoEmergenciaNombre",
      "contactoEmergenciaParentesco",
      "contactoEmergenciaTelefono",
    ]) {
      expect(planillaSelect).toHaveProperty(campo, true);
    }
  });

  test("un administrador (cliente) solo ve sus conjuntos en las filas", () => {
    const admin = fila({
      id: "ADM",
      rol: "administrador",
      operario: null,
      administrador: {
        conjuntos: [
          { nit: "C-1", nombre: "Bosque", empresaId: "EMP-1" },
          { nit: "C-2", nombre: "Lago", empresaId: "EMP-1" },
        ],
      },
    } as Partial<UsuarioPlanillaRow>);
    const out = filaPlanilla(admin, {
      empresaId: "EMP-1",
      alcance: ["C-2"],
      hoy: "2026-10-22",
      diasVacaciones: [],
    });
    expect(out.conjuntos).toEqual([{ nit: "C-2", nombre: "Lago" }]);
    expect(out.fechaIngreso).toBeNull();
    expect(out.funciones).toEqual([]);
  });
});

describe("PlanillaPersonalService.listar", () => {
  function db(usuarios: UsuarioPlanillaRow[] = [fila()]) {
    return {
      conjunto: {
        findFirst: jest.fn(async ({ where }: any) =>
          where.nit === "C-1" && where.empresaId === "EMP-1" ? { nit: "C-1" } : null,
        ),
      },
      usuario: { findMany: jest.fn(async (_args: any) => usuarios) },
      registroAsistencia: {
        findMany: jest.fn(async (_args: any) => [
          { operarioId: "1001", fecha: new Date("2026-09-07T00:00:00Z") },
          { operarioId: "1001", fecha: new Date("2026-09-08T00:00:00Z") },
        ]),
      },
    };
  }

  test("excluye residentes, busca vacaciones de la empresa y arma bloques", async () => {
    const fake = db();
    const filas = await new PlanillaPersonalService(fake as any).listar({
      empresaId: "EMP-1",
      alcance: null,
      ahora: new Date("2026-10-22T15:00:00Z"),
    });
    const where = fake.usuario.findMany.mock.calls[0][0].where;
    expect(where.AND).toContainEqual({ rol: { not: "residente" } });
    const consulta = fake.registroAsistencia.findMany.mock.calls[0][0];
    expect(consulta.where.operarioId).toEqual({ in: ["1001"] });
    expect(consulta.where.concepto.empresaId).toBe("EMP-1");
    // 400 días antes de hoy (22/10/2026) = 17/09/2025.
    expect(consulta.where.fecha.gte.toISOString().slice(0, 10)).toBe("2025-09-17");
    expect(filas[0].vacaciones).toEqual([{ desde: "2026-09-07", hasta: "2026-09-08" }]);
  });

  test("con conjunto: filtra a su administrador y operarios", async () => {
    const fake = db();
    await new PlanillaPersonalService(fake as any).listar({
      empresaId: "EMP-1",
      alcance: null,
      conjuntoId: "C-1",
    });
    const filtros = fake.usuario.findMany.mock.calls[0][0].where.AND;
    expect(JSON.stringify(filtros)).toContain('"administrador":{"conjuntos":{"some":{"nit":"C-1"}}}');
    expect(JSON.stringify(filtros)).toContain('"necesidadesOcupadas":{"some":{"conjuntoId":"C-1","activo":true}}');
  });

  test("conjunto de otra empresa o fuera del alcance: 404 sin consultar usuarios", async () => {
    const fake = db();
    const service = new PlanillaPersonalService(fake as any);
    await expect(
      service.listar({ empresaId: "EMP-1", alcance: null, conjuntoId: "C-OTRA" }),
    ).rejects.toMatchObject({ status: 404 });
    await expect(
      service.listar({ empresaId: "EMP-1", alcance: ["C-2"], conjuntoId: "C-1" }),
    ).rejects.toMatchObject({ status: 404 });
    expect(fake.usuario.findMany).not.toHaveBeenCalled();
  });

  test("un administrador solo recibe personas de sus conjuntos", async () => {
    const fake = db();
    await new PlanillaPersonalService(fake as any).listar({
      empresaId: "EMP-1",
      alcance: ["C-2"],
    });
    const filtros = JSON.stringify(fake.usuario.findMany.mock.calls[0][0].where.AND);
    expect(filtros).toContain('"operario":{"conjuntos":{"some":{"nit":{"in":["C-2"]}}}}');
  });

  test("sin operarios no consulta la asistencia", async () => {
    const fake = db([fila({ id: "G", rol: "gerente", operario: null })]);
    await new PlanillaPersonalService(fake as any).listar({ empresaId: "EMP-1", alcance: null });
    expect(fake.registroAsistencia.findMany).not.toHaveBeenCalled();
  });
});
