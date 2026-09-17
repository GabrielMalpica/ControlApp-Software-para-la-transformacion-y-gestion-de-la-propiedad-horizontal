import { DiaSemana, TipoFuncion } from "@prisma/client";
import { ConjuntoNecesidadService } from "../../src/services/ConjuntoNecesidadService";

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

  const prisma: any = {
    conjuntoNecesidadOperario,
    conjuntoNecesidadHorario,
    operario,
    conjunto,
    $transaction: async (fn: any) => fn(prisma),
  };

  return {
    prisma,
    seedConjunto: (nit: string) => conjuntos.set(nit, { nit, operariosIds: new Set() }),
    seedOperario: (id: string, funciones: TipoFuncion[], conjuntoId?: string) => {
      operarios.set(id, { id, funciones });
      if (conjuntoId) conjuntos.get(conjuntoId)?.operariosIds.add(id);
    },
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
