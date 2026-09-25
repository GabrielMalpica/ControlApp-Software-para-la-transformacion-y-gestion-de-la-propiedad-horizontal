import { DiaSemana, TipoFuncion } from "@prisma/client";
import { ConjuntoNecesidadService } from "../../src/services/ConjuntoNecesidadService";
import { CrearNecesidadDTO, EditarNecesidadDTO } from "../../src/model/ConjuntoNecesidad";

/**
 * Fake in-memory de Prisma acotado a las tablas que toca
 * ConjuntoNecesidadService, suficiente para probar las reglas de negocio
 * (unicidad de etiqueta, validación de rol, ocupación exclusiva, invariante
 * de horario especial) sin levantar Postgres.
 */
function makeFakePrisma() {
  const conjuntos = new Map<string, { nit: string; operariosIds: Set<string> }>();
  const operarios = new Map<string, { id: string; funciones: TipoFuncion[] }>();
  let nextId = 1;
  const necesidades = new Map<
    number,
    {
      id: number;
      conjuntoId: string;
      roles: TipoFuncion[];
      etiqueta: string;
      orden: number;
      horarioEspecial: boolean;
      operarioId: string | null;
      activo: boolean;
      observaciones: string | null;
    }
  >();
  const horarios = new Map<
    number,
    Array<{ necesidadId: number; dia: DiaSemana; horaApertura: string; horaCierre: string }>
  >();

  function proyectar(n: (typeof necesidades extends Map<number, infer V> ? V : never)) {
    return {
      ...n,
      horarios: horarios.get(n.id) ?? [],
      operario: n.operarioId ? { id: n.operarioId, usuario: { nombre: "Op" } } : null,
    };
  }

  const conjuntoNecesidadOperario = {
    findMany: jest.fn(async ({ where }: any) => {
      let out = Array.from(necesidades.values()).filter(
        (n) => n.conjuntoId === where.conjuntoId,
      );
      if (where.operarioId) {
        const ids: string[] = where.operarioId.in ?? [where.operarioId];
        out = out.filter((n) => n.operarioId && ids.includes(n.operarioId));
      }
      if (where.activo != null) out = out.filter((n) => n.activo === where.activo);
      return out.map(proyectar);
    }),
    findFirst: jest.fn(async ({ where }: any) => {
      const out = Array.from(necesidades.values()).find((n) => {
        if (where.id != null && n.id !== where.id) return false;
        if (where.conjuntoId != null && n.conjuntoId !== where.conjuntoId) return false;
        if (where.etiqueta != null && n.etiqueta !== where.etiqueta) return false;
        if (where.id?.not != null && n.id === where.id.not) return false;
        return true;
      });
      if (!out) return null;
      const proyectado: any = proyectar(out);
      if (out.id) {
        proyectado._count = {
          definiciones: 0,
        };
      }
      return proyectado;
    }),
    create: jest.fn(async ({ data }: any) => {
      const id = nextId++;
      const registro = {
        id,
        conjuntoId: data.conjuntoId,
        roles: data.roles,
        etiqueta: data.etiqueta,
        orden: data.orden ?? 0,
        horarioEspecial: data.horarioEspecial ?? false,
        trabajaFestivos: data.trabajaFestivos ?? false,
        festivoHoraApertura: data.festivoHoraApertura ?? null,
        festivoHoraCierre: data.festivoHoraCierre ?? null,
        festivoDescansoInicio: data.festivoDescansoInicio ?? null,
        festivoDescansoFin: data.festivoDescansoFin ?? null,
        descansoCompensatorio: data.descansoCompensatorio ?? false,
        diasDescansoCompensatorio: data.diasDescansoCompensatorio ?? 1,
        operarioId: data.operarioId ?? null,
        activo: true,
        observaciones: data.observaciones ?? null,
      };
      necesidades.set(id, registro);
      if (data.horarios?.create) {
        horarios.set(
          id,
          data.horarios.create.map((h: any) => ({ necesidadId: id, ...h })),
        );
      }
      return proyectar(registro);
    }),
    update: jest.fn(async ({ where, data }: any) => {
      const actual = necesidades.get(where.id);
      if (!actual) throw new Error("no encontrado");
      const actualizado = {
        ...actual,
        ...(data.roles !== undefined ? { roles: data.roles } : {}),
        ...(data.etiqueta !== undefined ? { etiqueta: data.etiqueta } : {}),
        ...(data.orden !== undefined ? { orden: data.orden } : {}),
        ...(data.horarioEspecial !== undefined ? { horarioEspecial: data.horarioEspecial } : {}),
        ...(data.trabajaFestivos !== undefined ? { trabajaFestivos: data.trabajaFestivos } : {}),
        ...(data.festivoHoraApertura !== undefined
          ? { festivoHoraApertura: data.festivoHoraApertura }
          : {}),
        ...(data.festivoHoraCierre !== undefined
          ? { festivoHoraCierre: data.festivoHoraCierre }
          : {}),
        ...(data.festivoDescansoInicio !== undefined
          ? { festivoDescansoInicio: data.festivoDescansoInicio }
          : {}),
        ...(data.festivoDescansoFin !== undefined
          ? { festivoDescansoFin: data.festivoDescansoFin }
          : {}),
        ...(data.descansoCompensatorio !== undefined
          ? { descansoCompensatorio: data.descansoCompensatorio }
          : {}),
        ...(data.diasDescansoCompensatorio !== undefined
          ? { diasDescansoCompensatorio: data.diasDescansoCompensatorio }
          : {}),
        ...(data.observaciones !== undefined ? { observaciones: data.observaciones } : {}),
        ...(data.activo !== undefined ? { activo: data.activo } : {}),
        ...(data.operarioId !== undefined ? { operarioId: data.operarioId } : {}),
      };
      necesidades.set(where.id, actualizado);
      if (data.horarios?.create) {
        horarios.set(
          where.id,
          data.horarios.create.map((h: any) => ({ necesidadId: where.id, ...h })),
        );
      }
      return proyectar(actualizado);
    }),
    delete: jest.fn(async ({ where }: any) => {
      necesidades.delete(where.id);
      horarios.delete(where.id);
    }),
  };

  const conjuntoNecesidadHorario = {
    deleteMany: jest.fn(async ({ where }: any) => {
      horarios.set(where.necesidadId, []);
    }),
    count: jest.fn(async ({ where }: any) => (horarios.get(where.necesidadId) ?? []).length),
  };

  const operario = {
    findUnique: jest.fn(async ({ where }: any) => {
      const op = operarios.get(where.id);
      if (!op) return null;
      const conjuntosDelOperario = Array.from(conjuntos.values()).filter((c) =>
        c.operariosIds.has(op.id),
      );
      return {
        id: op.id,
        funciones: op.funciones,
        conjuntos: conjuntosDelOperario.map((c) => ({ nit: c.nit })),
        necesidadesOcupadas: Array.from(necesidades.values())
          .filter((n) => n.operarioId === op.id && n.activo)
          .map((n) => ({ id: n.id, etiqueta: n.etiqueta })),
      };
    }),
    findMany: jest.fn(async ({ where }: any) => {
      const nit = where?.conjuntos?.some?.nit;
      return Array.from(operarios.values())
        .filter((op) => !nit || conjuntos.get(nit)?.operariosIds.has(op.id))
        .map((op) => ({ id: op.id, funciones: op.funciones }));
    }),
  };

  const conjunto = {
    findUnique: jest.fn(async ({ where }: any) => {
      const c = conjuntos.get(where.nit);
      return c ? { nit: c.nit } : null;
    }),
    update: jest.fn(async ({ where, data }: any) => {
      const c = conjuntos.get(where.nit);
      if (c && data.operarios?.connect) c.operariosIds.add(data.operarios.connect.id);
      return c;
    }),
  };

  const definiciones = new Map<
    number,
    {
      id: number;
      conjuntoId: string;
      descripcion: string;
      activo: boolean;
      operariosIds: string[];
      necesidadesIds: number[];
    }
  >();

  const definicionTareaPreventiva = {
    findMany: jest.fn(async ({ where }: any) => {
      let out = Array.from(definiciones.values()).filter(
        (d) => d.conjuntoId === where.conjuntoId,
      );
      if (where.activo != null) out = out.filter((d) => d.activo === where.activo);
      if (where.necesidades?.none) {
        out = out.filter((d) => d.necesidadesIds.length === 0);
      }
      if (where.operarios?.some) {
        out = out.filter((d) => d.operariosIds.length > 0);
      }
      return out.map((d) => ({
        id: d.id,
        descripcion: d.descripcion,
        operarios: d.operariosIds.map((id) => ({ id })),
      }));
    }),
    update: jest.fn(async ({ where, data }: any) => {
      const def = definiciones.get(where.id);
      if (!def) throw new Error("no encontrado");
      if (data.necesidades?.connect) {
        def.necesidadesIds = data.necesidades.connect.map((c: any) => c.id);
      }
      return def;
    }),
  };

  const prisma: any = {
    conjuntoNecesidadOperario,
    conjuntoNecesidadHorario,
    operario,
    conjunto,
    definicionTareaPreventiva,
    $transaction: async (fn: any) => fn(prisma),
  };

  return {
    prisma,
    seedConjunto: (nit: string) => conjuntos.set(nit, { nit, operariosIds: new Set() }),
    seedOperario: (id: string, funciones: TipoFuncion[], conjuntoId?: string) => {
      operarios.set(id, { id, funciones });
      if (conjuntoId) conjuntos.get(conjuntoId)?.operariosIds.add(id);
    },
    seedDefinicion: (params: {
      id: number;
      conjuntoId: string;
      descripcion: string;
      operariosIds: string[];
    }) =>
      definiciones.set(params.id, {
        ...params,
        activo: true,
        necesidadesIds: [],
      }),
    definicionesGuardadas: definiciones,
  };
}

describe("ConjuntoNecesidadService", () => {
  test("crea una plaza y rechaza etiquetas duplicadas en el mismo conjunto", async () => {
    const { prisma, seedConjunto } = makeFakePrisma();
    seedConjunto("C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const creada = await service.crear({ roles: ["TODERO"], etiqueta: "Todero #1" });
    expect(creada.etiqueta).toBe("Todero #1");

    await expect(service.crear({ roles: ["TODERO"], etiqueta: "Todero #1" })).rejects.toThrow(
      /Ya existe una necesidad/,
    );
  });

  test("no permite activar horario especial sin al menos un día configurado", async () => {
    const { prisma, seedConjunto } = makeFakePrisma();
    seedConjunto("C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    await expect(
      service.crear({ roles: ["SALVAVIDAS"], etiqueta: "Salvavidas #1", horarioEspecial: true }),
    ).rejects.toThrow(/horario especial/);

    const creada = await service.crear({
      roles: ["SALVAVIDAS"],
      etiqueta: "Salvavidas #1",
      horarioEspecial: true,
      horarios: [{ dia: DiaSemana.DOMINGO, horaApertura: "08:00", horaCierre: "17:00" }],
    });
    expect(creada.horarioEspecial).toBe(true);
    expect(creada.horarios).toHaveLength(1);
  });

  test("asignarOperario valida el rol, conecta al conjunto si hace falta, y mueve al operario si ya ocupaba otra plaza", async () => {
    const { prisma, seedConjunto, seedOperario } = makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("juan", [TipoFuncion.SALVAVIDAS]); // sin rol TODERO, aún no pertenece al conjunto
    seedOperario("pedro", [TipoFuncion.TODERO]);
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const t1 = await service.crear({ roles: ["TODERO"], etiqueta: "Todero #1" });
    const t2 = await service.crear({ roles: ["TODERO"], etiqueta: "Todero #2" });

    // Juan no tiene el rol TODERO.
    await expect(service.asignarOperario(t1.id, { operarioId: "juan" })).rejects.toThrow(
      /no tiene el rol/,
    );

    // Pedro sí lo tiene y no pertenecía aún al conjunto: debe conectarse solo.
    const asignado = await service.asignarOperario(t1.id, { operarioId: "pedro" });
    expect(asignado.operarioId).toBe("pedro");

    // Pedro ya ocupa Todero #1: asignarlo a Todero #2 lo MUEVE (libera #1
    // automáticamente, sin el paso manual de liberar primero).
    const movido = await service.asignarOperario(t2.id, { operarioId: "pedro" });
    expect(movido.operarioId).toBe("pedro");
    const listado = await service.listar();
    expect(listado.find((n) => n.id === t1.id)?.operarioId).toBeNull();
    expect(listado.find((n) => n.id === t2.id)?.operarioId).toBe("pedro");

    // Todero #2 ya está ocupado (por Pedro): no admite un segundo operario sin liberar antes.
    seedOperario("carlos", [TipoFuncion.TODERO], "C-1");
    await expect(service.asignarOperario(t2.id, { operarioId: "carlos" })).rejects.toThrow(
      /ya está ocupada/,
    );
  });

  test("liberar y reasignar una plaza no requiere tocar la definición que la referencia", async () => {
    const { prisma, seedConjunto, seedOperario } = makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("juan", [TipoFuncion.TODERO]);
    seedOperario("pedro", [TipoFuncion.TODERO]);
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const plaza = await service.crear({ roles: ["TODERO"], etiqueta: "Todero #1", operarioId: "juan" });
    expect(plaza.operarioId).toBe("juan");

    await service.liberarOperario(plaza.id);
    const reasignada = await service.asignarOperario(plaza.id, { operarioId: "pedro" });
    expect(reasignada.operarioId).toBe("pedro");
    // El id de la plaza (lo que referencia la definición/tarea) no cambió.
    expect(reasignada.id).toBe(plaza.id);
  });

  test("eliminar una plaza ocupada exige confirmación explícita", async () => {
    const { prisma, seedConjunto, seedOperario } = makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("juan", [TipoFuncion.TODERO]);
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const plaza = await service.crear({ roles: ["TODERO"], etiqueta: "Todero #1", operarioId: "juan" });

    const sinConfirmar = await service.eliminar(plaza.id);
    expect(sinConfirmar).toMatchObject({ ok: false, requiresConfirmation: true, motivo: "OCUPADA" });

    const confirmado = await service.eliminar(plaza.id, { confirmar: true });
    expect(confirmado).toEqual({ ok: true });
  });

  test("una plaza combinada (varios roles) exige que el operario tenga TODOS los roles", async () => {
    const { prisma, seedConjunto, seedOperario } = makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("juan", [TipoFuncion.TODERO]); // le falta SALVAVIDAS
    seedOperario("pedro", [TipoFuncion.TODERO, TipoFuncion.SALVAVIDAS]);
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const plaza = await service.crear({
      roles: ["TODERO", "SALVAVIDAS"],
      etiqueta: "Todero-Salvavidas #1",
    });

    // Juan solo cumple uno de los dos roles requeridos.
    await expect(service.asignarOperario(plaza.id, { operarioId: "juan" })).rejects.toThrow(
      /no tiene el rol Salvavidas/,
    );

    // Pedro cumple ambos.
    const asignado = await service.asignarOperario(plaza.id, { operarioId: "pedro" });
    expect(asignado.operarioId).toBe("pedro");
    expect(asignado.roles).toEqual(["TODERO", "SALVAVIDAS"]);
  });

  test("editar() rechaza quitar un rol combinado si el operario que la ocupa ya no lo cumpliría", async () => {
    const { prisma, seedConjunto, seedOperario } = makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("pedro", [TipoFuncion.TODERO, TipoFuncion.PISCINERO], "C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const plaza = await service.crear({
      roles: ["TODERO", "PISCINERO"],
      etiqueta: "Piscinero-Todero #1",
      operarioId: "pedro",
    });

    // Pedro no tiene SALVAVIDAS: ampliar los roles exigidos debe rechazarse.
    await expect(
      service.editar(plaza.id, { roles: ["TODERO", "PISCINERO", "SALVAVIDAS"] }),
    ).rejects.toThrow(/no tiene el rol Salvavidas/);

    // Reducir a un subconjunto que Pedro sí cumple está permitido.
    const editada = await service.editar(plaza.id, { roles: ["TODERO"] });
    expect(editada.roles).toEqual(["TODERO"]);
  });
});

describe("ConjuntoNecesidadService: vincularDefinicionesConNecesidades (migración paso 2)", () => {
  test("vincula una definición cuando todos sus operarios ya ocupan una plaza", async () => {
    const { prisma, seedConjunto, seedOperario, seedDefinicion } = makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("pedro", [TipoFuncion.TODERO], "C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const plaza = await service.crear({
      roles: ["TODERO"],
      etiqueta: "Todero #1",
      operarioId: "pedro",
    });
    seedDefinicion({
      id: 500,
      conjuntoId: "C-1",
      descripcion: "Ronda todero",
      operariosIds: ["pedro"],
    });

    const resultado = await service.vincularDefinicionesConNecesidades();

    expect(resultado.saltadas).toEqual([]);
    expect(resultado.vinculadas).toEqual([{ id: 500, descripcion: "Ronda todero" }]);
    expect(prisma.definicionTareaPreventiva.update).toHaveBeenCalledWith({
      where: { id: 500 },
      data: { necesidades: { connect: [{ id: plaza.id }] } },
    });
  });

  test("salta (sin tocar) una definición cuyo operario todavía no ocupa ninguna plaza", async () => {
    const { prisma, seedConjunto, seedOperario, seedDefinicion } = makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("juan", [TipoFuncion.TODERO], "C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    seedDefinicion({
      id: 501,
      conjuntoId: "C-1",
      descripcion: "Ronda sin plaza todavia",
      operariosIds: ["juan"],
    });

    const resultado = await service.vincularDefinicionesConNecesidades();

    expect(resultado.vinculadas).toEqual([]);
    expect(resultado.saltadas).toHaveLength(1);
    expect(resultado.saltadas[0]).toMatchObject({ id: 501 });
    expect(prisma.definicionTareaPreventiva.update).not.toHaveBeenCalled();
  });

  test("no vincula (ni cuenta) una definición que ya tiene necesidades vinculadas", async () => {
    const { prisma, seedConjunto, seedOperario, seedDefinicion, definicionesGuardadas } =
      makeFakePrisma();
    seedConjunto("C-1");
    seedOperario("pedro", [TipoFuncion.TODERO], "C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");

    const plaza = await service.crear({
      roles: ["TODERO"],
      etiqueta: "Todero #1",
      operarioId: "pedro",
    });
    seedDefinicion({
      id: 502,
      conjuntoId: "C-1",
      descripcion: "Ya vinculada antes",
      operariosIds: ["pedro"],
    });
    definicionesGuardadas.get(502)!.necesidadesIds = [plaza.id];

    const resultado = await service.vincularDefinicionesConNecesidades();

    expect(resultado.vinculadas).toEqual([]);
    expect(resultado.saltadas).toEqual([]);
  });
});

describe("CrearNecesidadDTO / EditarNecesidadDTO - festivos y descanso compensatorio", () => {
  const base = { roles: ["TODERO"], etiqueta: "Todero #1" };

  test("trabajaFestivos y descansoCompensatorio quedan en false por defecto", () => {
    const dto = CrearNecesidadDTO.parse(base);
    expect(dto.trabajaFestivos).toBe(false);
    expect(dto.horarioFestivo ?? null).toBeNull();
    expect(dto.descansoCompensatorio).toBe(false);
    expect(dto.diasDescansoCompensatorio).toBe(1);
  });

  test("trabajaFestivos=true sin horarioFestivo se rechaza", () => {
    expect(() => CrearNecesidadDTO.parse({ ...base, trabajaFestivos: true })).toThrow();
  });

  test("trabajaFestivos=true con horarioFestivo válido se acepta", () => {
    const dto = CrearNecesidadDTO.parse({
      ...base,
      trabajaFestivos: true,
      horarioFestivo: { horaApertura: "09:00", horaCierre: "15:00" },
      descansoCompensatorio: true,
      diasDescansoCompensatorio: 2,
    });
    expect(dto.horarioFestivo).toMatchObject({ horaApertura: "09:00", horaCierre: "15:00" });
    expect(dto.diasDescansoCompensatorio).toBe(2);
  });

  test("horarioFestivo con horaApertura >= horaCierre se rechaza (mismas reglas que el horario normal)", () => {
    expect(() =>
      CrearNecesidadDTO.parse({
        ...base,
        trabajaFestivos: true,
        horarioFestivo: { horaApertura: "15:00", horaCierre: "09:00" },
      }),
    ).toThrow();
  });

  test("diasDescansoCompensatorio fuera de 1-6 se rechaza", () => {
    expect(() =>
      CrearNecesidadDTO.parse({ ...base, diasDescansoCompensatorio: 0 }),
    ).toThrow();
    expect(() =>
      CrearNecesidadDTO.parse({ ...base, diasDescansoCompensatorio: 7 }),
    ).toThrow();
  });

  test("EditarNecesidadDTO: activar trabajaFestivos con horarioFestivo explícitamente null se rechaza", () => {
    expect(() =>
      EditarNecesidadDTO.parse({ trabajaFestivos: true, horarioFestivo: null }),
    ).toThrow();
  });

  test("EditarNecesidadDTO: activar trabajaFestivos sin mencionar horarioFestivo no se rechaza a nivel DTO (el servicio valida contra el estado en BD)", () => {
    expect(() => EditarNecesidadDTO.parse({ trabajaFestivos: true })).not.toThrow();
  });

  test("EditarNecesidadDTO: activar trabajaFestivos con horarioFestivo en el mismo payload se acepta", () => {
    const dto = EditarNecesidadDTO.parse({
      trabajaFestivos: true,
      horarioFestivo: { horaApertura: "08:00", horaCierre: "12:00" },
    });
    expect(dto.trabajaFestivos).toBe(true);
  });

  test("EditarNecesidadDTO: tocar otro campo sin mencionar trabajaFestivos no exige horarioFestivo (se valida contra BD en el servicio)", () => {
    expect(() => EditarNecesidadDTO.parse({ orden: 2 })).not.toThrow();
  });
});

describe("ConjuntoNecesidadService - invariante de festivos contra el estado en BD", () => {
  test("editar rechaza activar trabajaFestivos si la plaza no tiene horario festivo (ni en el payload ni en BD)", async () => {
    const { prisma, seedConjunto } = makeFakePrisma();
    seedConjunto("C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");
    const plaza = await service.crear({ roles: ["TODERO"], etiqueta: "Todero #1" });

    await expect(
      service.editar(plaza.id, { trabajaFestivos: true }),
    ).rejects.toThrow(/horario festivo/i);
  });

  test("editar acepta activar trabajaFestivos si la plaza ya tenía horario festivo guardado en BD", async () => {
    const { prisma, seedConjunto } = makeFakePrisma();
    seedConjunto("C-1");
    const service = new ConjuntoNecesidadService(prisma, "C-1");
    const plaza = await service.crear({
      roles: ["SALVAVIDAS"],
      etiqueta: "Salvavidas #1",
      trabajaFestivos: true,
      horarioFestivo: { horaApertura: "09:00", horaCierre: "15:00" },
    });

    // Se desactiva y se vuelve a activar sin repetir el horario en el payload.
    await service.editar(plaza.id, { trabajaFestivos: false });
    const reactivada = await service.editar(plaza.id, { trabajaFestivos: true });
    expect(reactivada.trabajaFestivos).toBe(true);
  });
});
