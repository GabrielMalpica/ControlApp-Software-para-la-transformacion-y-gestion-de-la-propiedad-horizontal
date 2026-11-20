import { Prisma, PrismaClient } from "@prisma/client";
import fs from "fs";
import { prisma } from "../db/prisma";
import { uploadPlanEsperanzaFoto } from "../utils/drive_plan_esperanza";
import {
  construirRangosContrato,
  inicioMesEnBogota,
  programarFasesPlanEsperanza,
  sumarAnnosContrato,
} from "../utils/planEsperanzaCronologia";

type ChecklistItem = {
  texto: string;
  completado: boolean;
};

type ElementoHoja = {
  id: number;
  nombre: string;
  ubicacionId: number;
  ubicacionNombre: string;
  padreId: number | null;
  padreNombre: string | null;
};

type DiagnosticoInfo = {
  id: number;
  elementoId: number;
  elementoNombre: string;
  ubicacionId: number;
  ubicacionNombre: string;
  subzonaNombre: string | null;
  urlFoto: string | null;
  valoracion: number | null;
  observaciones: string | null;
  checklist: ChecklistItem[];
  creadoEn: Date;
};

type TimelineEntry = {
  planId: number;
  fecha: Date;
  urlFoto: string | null;
  valoracion: number | null;
  observaciones: string | null;
  checklist: ChecklistItem[];
};

function normalizeChecklistItem(item: unknown): ChecklistItem | null {
  if (!item || typeof item !== "object") return null;
  const rawTexto = (item as { texto?: unknown }).texto;
  const texto = typeof rawTexto === "string" ? rawTexto.trim() : "";
  if (!texto) return null;
  return {
    texto,
    completado: Boolean((item as { completado?: unknown }).completado),
  };
}

function parseChecklist(value: Prisma.JsonValue | null | undefined): ChecklistItem[] {
  if (!Array.isArray(value)) return [];
  return value.map(normalizeChecklistItem).filter((item): item is ChecklistItem => item != null);
}

function diagnosticoTieneContenido(diagnostico: {
  valoracion: number | null;
  observaciones: string | null;
  urlFoto: string | null;
  checklist: ChecklistItem[];
}) {
  return diagnostico.valoracion != null ||
    !!diagnostico.observaciones?.trim() ||
    !!diagnostico.urlFoto ||
    diagnostico.checklist.length > 0;
}

function obtenerElementosHoja(prisma: PrismaClient, conjuntoId: string) {
  return prisma.$queryRaw<ElementoHoja[]>`
    SELECT
      e.id,
      e.nombre,
      e."ubicacionId",
      u.nombre AS "ubicacionNombre",
      e."padreId",
      p.nombre AS "padreNombre"
    FROM "Elemento" e
    JOIN "Ubicacion" u ON u.id = e."ubicacionId"
    LEFT JOIN "Elemento" p ON p.id = e."padreId"
    WHERE u."conjuntoId" = ${conjuntoId}
      AND e.id NOT IN (
        SELECT DISTINCT h."padreId" FROM "Elemento" h WHERE h."padreId" IS NOT NULL
      )
    ORDER BY u.nombre, COALESCE(p.nombre, ''), e.nombre
  `;
}

export class PlanEsperanzaService {
  private prisma: PrismaClient;

  constructor(client?: PrismaClient) {
    this.prisma = client ?? prisma;
  }

  async obtenerCronologia(conjuntoId: string, hoy = new Date()) {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: {
        nit: true,
        nombre: true,
        fechaInicioContrato: true,
        fechaFinContrato: true,
      },
    });
    if (!conjunto) throw Object.assign(new Error("Conjunto no encontrado."), { status: 404 });
    if (!conjunto.fechaInicioContrato) {
      throw Object.assign(new Error("Registre la fecha de inicio del contrato para crear el Plan Esperanza."), {
        status: 409,
        code: "FECHA_CONTRATO_REQUERIDA",
      });
    }

    const inicioContrato = conjunto.fechaInicioContrato;
    if (conjunto.fechaFinContrato && conjunto.fechaFinContrato < inicioContrato) {
      throw Object.assign(new Error("La fecha de fin del contrato es anterior a la fecha de inicio."), {
        status: 409,
        code: "FECHAS_CONTRATO_INVALIDAS",
      });
    }
    const finContrato = conjunto.fechaFinContrato ?? new Date(
      sumarAnnosContrato(inicioContrato, 1).getTime() - 24 * 60 * 60 * 1000,
    );
    const rangos = construirRangosContrato(inicioContrato, conjunto.fechaFinContrato, hoy);
    const hoyMes = inicioMesEnBogota(hoy);

    for (const rango of rangos) {
      const ciclo = await this.prisma.planEsperanzaCiclo.upsert({
        where: { conjuntoId_fechaInicio: { conjuntoId, fechaInicio: rango.inicio } },
        update: {},
        create: {
          conjuntoId,
          fechaInicioContrato: rango.inicio,
          fechaFinContrato: rango.fin,
          fechaInicio: rango.inicio,
          fechaFin: rango.fin,
        },
      });
      const fases = programarFasesPlanEsperanza(rango.inicio, rango.fin);
      const hojas = await obtenerElementosHoja(this.prisma, conjuntoId);
      for (const fase of fases) {
        const plan = await this.prisma.planEsperanza.upsert({
          where: { cicloId_faseClave: { cicloId: ciclo.id, faseClave: fase.clave } },
          update: {},
          create: {
            conjuntoId,
            cicloId: ciclo.id,
            faseClave: fase.clave,
            mesObjetivo: fase.mesObjetivo,
            fechaProgramada: fase.fechaProgramada,
            fechaInicio: fase.fechaProgramada,
            completado: false,
          },
        });
        if (hojas.length) {
          await this.prisma.diagnosticoArea.createMany({
            data: hojas.map((hoja) => ({ planEsperanzaId: plan.id, elementoId: hoja.id })),
            skipDuplicates: true,
          });
        }
      }
    }

    await this.adaptarPlanesAnteriores(conjuntoId, rangos);

    const ciclos = await this.prisma.planEsperanzaCiclo.findMany({
      where: { conjuntoId },
      include: {
        fases: {
          orderBy: { id: "asc" },
          include: {
            _count: { select: { diagnosticos: true } },
            diagnosticos: {
              include: {
                elemento: { include: { padre: true, ubicacion: true } },
              },
              orderBy: [
                { elemento: { ubicacion: { nombre: "asc" } } },
                { elemento: { padre: { nombre: "asc" } } },
                { elemento: { nombre: "asc" } },
              ],
            },
          },
        },
      },
      orderBy: { fechaInicio: "desc" },
    });

    return {
      conjuntoId,
      conjuntoNombre: conjunto.nombre,
      fechaInicioContrato: inicioContrato,
      fechaFinContrato: conjunto.fechaFinContrato ?? finContrato,
      ciclos: ciclos.map((ciclo) => ({
        id: ciclo.id,
        fechaInicio: ciclo.fechaInicio,
        fechaFin: ciclo.fechaFin,
        fases: ciclo.fases.map((fase) => {
          const diagnosticos = fase.diagnosticos.map((d) => ({
            id: d.id,
            elementoId: d.elementoId,
            elementoNombre: d.elemento.nombre,
            ubicacionId: d.elemento.ubicacionId,
            ubicacionNombre: d.elemento.ubicacion.nombre,
            subzonaNombre: d.elemento.padre?.nombre ?? null,
            urlFoto: d.urlFoto,
            valoracion: d.valoracion,
            observaciones: d.observaciones,
            checklist: parseChecklist(d.checklist),
            creadoEn: d.creadoEn,
          }));
          const disponible = !!fase.fechaProgramada && fase.fechaProgramada <= hoyMes;
          const evaluadas = diagnosticos.filter((d) => diagnosticoTieneContenido(d)).length;
          return {
            id: fase.id,
            clave: fase.faseClave,
            mesObjetivo: fase.mesObjetivo,
            fechaProgramada: fase.fechaProgramada,
            fechaInicio: fase.fechaInicio,
            fechaFin: fase.fechaFin,
            completado: fase.completado,
            disponible,
            estado: fase.completado
              ? "COMPLETADA"
              : !disponible
                ? "BLOQUEADA"
                : fase.fechaProgramada && fase.fechaProgramada < hoyMes
                  ? "ATRASADA"
                  : evaluadas > 0
                    ? "EN_PROGRESO"
                    : "PENDIENTE",
            totalAreas: fase._count.diagnosticos,
            areasEvaluadas: evaluadas,
            diagnosticos,
          };
        }),
      })),
    };
  }

  async obtenerInformeFases(cicloId: number, desde?: number, hasta?: number, conjuntoId?: string) {
    const ciclo = await this.prisma.planEsperanzaCiclo.findUnique({
      where: { id: cicloId, ...(conjuntoId ? { conjuntoId } : {}) },
      include: {
        conjunto: { select: { nombre: true, nit: true } },
        fases: {
          include: {
            diagnosticos: {
              include: { elemento: { include: { padre: true, ubicacion: true } } },
            },
          },
          orderBy: { id: "asc" },
        },
      },
    });
    if (!ciclo) return null;
    const fasesOrdenadas = [...ciclo.fases].sort((a, b) => (a.mesObjetivo ?? 0) - (b.mesObjetivo ?? 0));
    const fases = fasesOrdenadas.slice(Math.max(0, (desde ?? 1) - 1), hasta ?? fasesOrdenadas.length);
    return {
      cicloId: ciclo.id,
      conjuntoNombre: ciclo.conjunto.nombre,
      conjuntoNit: ciclo.conjunto.nit,
      fechaInicio: ciclo.fechaInicio,
      fechaFin: ciclo.fechaFin,
      fases: fases.map((fase) => ({
        id: fase.id,
        clave: fase.faseClave,
        mesObjetivo: fase.mesObjetivo,
        fechaProgramada: fase.fechaProgramada,
        fechaFin: fase.fechaFin,
        completado: fase.completado,
        totalAreas: fase.diagnosticos.length,
        areasEvaluadas: fase.diagnosticos.filter((d) => diagnosticoTieneContenido({
          valoracion: d.valoracion,
          observaciones: d.observaciones,
          urlFoto: d.urlFoto,
          checklist: parseChecklist(d.checklist),
        })).length,
        diagnosticos: fase.diagnosticos.map((d) => ({
          elementoId: d.elementoId,
          elementoNombre: d.elemento.nombre,
          ubicacionNombre: d.elemento.ubicacion.nombre,
          subzonaNombre: d.elemento.padre?.nombre ?? null,
          urlFoto: d.urlFoto,
          valoracion: d.valoracion,
          observaciones: d.observaciones,
          checklist: parseChecklist(d.checklist),
        })),
      })),
    };
  }

  async obtenerConfig(conjuntoId: string) {
    let config = await this.prisma.planEsperanzaConfig.findUnique({
      where: { conjuntoId },
    });
    if (!config) {
      config = await this.prisma.planEsperanzaConfig.create({
        data: { conjuntoId, intervaloMeses: 3 },
      });
    }
    return config;
  }

  async actualizarConfig(conjuntoId: string, intervaloMeses: number) {
    return this.prisma.planEsperanzaConfig.upsert({
      where: { conjuntoId },
      update: { intervaloMeses },
      create: { conjuntoId, intervaloMeses },
    });
  }

  async iniciarPlan(
    conjuntoId: string,
    mantenerEvidencias?: boolean,
    planAnteriorId?: number
  ) {
    const conjunto = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoId },
      select: { fechaInicioContrato: true },
    });
    if (conjunto?.fechaInicioContrato) {
      const cronologia = await this.obtenerCronologia(conjuntoId);
      const fases = cronologia.ciclos
        .slice()
        .sort((a, b) => a.fechaInicio.getTime() - b.fechaInicio.getTime())
        .flatMap((ciclo) => ciclo.fases);
      const fase = fases.find((item) => item.disponible && !item.completado) ?? fases[0];
      if (!fase) {
        throw Object.assign(new Error("No fue posible generar las fases del contrato."), {
          status: 409,
          code: "PLAN_CONTRATO_SIN_FASES",
        });
      }
      // Compatibilidad con clientes anteriores que aún llaman a /iniciar.
      // El plan se crea desde el contrato y nunca desde la fecha de este clic.
      return fase;
    }
    const hojas = await obtenerElementosHoja(this.prisma, conjuntoId);

    const plan = await this.prisma.planEsperanza.create({
      data: {
        conjuntoId,
        completado: false,
      },
    });

    const diagnosticosData: {
      planEsperanzaId: number;
      elementoId: number;
      urlFoto?: string | null;
      valoracion?: number | null;
      observaciones?: string | null;
      checklist?: Prisma.InputJsonValue | typeof Prisma.JsonNull;
    }[] = [];

    if (mantenerEvidencias && planAnteriorId) {
      const anteriores = await this.prisma.diagnosticoArea.findMany({
        where: { planEsperanzaId: planAnteriorId },
      });
      const mapAnteriores = new Map(
        anteriores.map((d) => [d.elementoId, d])
      );

      for (const hoja of hojas) {
        const anterior = mapAnteriores.get(hoja.id);
        diagnosticosData.push({
          planEsperanzaId: plan.id,
          elementoId: hoja.id,
          urlFoto: anterior?.urlFoto ?? null,
          valoracion: anterior?.valoracion ?? null,
          observaciones: anterior?.observaciones ?? null,
          checklist: anterior?.checklist ?? Prisma.JsonNull,
        });
      }
    } else {
      const ultimoPlanFinalizado = await this.prisma.planEsperanza.findFirst({
        where: { conjuntoId, completado: true },
        orderBy: { fechaInicio: "desc" },
        include: { diagnosticos: true },
      });
      const checklistAnterior = new Map(
        (ultimoPlanFinalizado?.diagnosticos ?? []).map((d) => [d.elementoId, d.checklist])
      );
      for (const hoja of hojas) {
        diagnosticosData.push({
          planEsperanzaId: plan.id,
          elementoId: hoja.id,
          checklist: checklistAnterior.get(hoja.id) ?? Prisma.JsonNull,
        });
      }
    }

    if (diagnosticosData.length > 0) {
      await this.prisma.diagnosticoArea.createMany({ data: diagnosticosData });
    }

    return this.obtenerPlanActivo(conjuntoId);
  }

  private async adaptarPlanesAnteriores(
    conjuntoId: string,
    rangos: Array<{ inicio: Date; fin: Date }>,
  ) {
    if (!rangos.length) return;
    const anteriores = await this.prisma.planEsperanza.findMany({
      where: { conjuntoId, cicloId: null },
      include: { diagnosticos: true },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    for (const anterior of anteriores) {
      const rango = rangos.find(
        (item) => anterior.fechaInicio >= item.inicio && anterior.fechaInicio <= item.fin,
      ) ?? (anterior.fechaInicio < rangos[0].inicio ? rangos[0] : rangos[rangos.length - 1]);
      const hitos = programarFasesPlanEsperanza(rango.inicio, rango.fin);
      const hito = hitos.reduce((mejor, actual) =>
        Math.abs(actual.fechaProgramada.getTime() - anterior.fechaInicio.getTime()) <
          Math.abs(mejor.fechaProgramada.getTime() - anterior.fechaInicio.getTime())
          ? actual
          : mejor,
      );
      const ciclo = await this.prisma.planEsperanzaCiclo.findUnique({
        where: { conjuntoId_fechaInicio: { conjuntoId, fechaInicio: rango.inicio } },
      });
      if (!ciclo) continue;
      const destino = await this.prisma.planEsperanza.findUnique({
        where: { cicloId_faseClave: { cicloId: ciclo.id, faseClave: hito.clave } },
      });
      if (!destino) continue;

      await this.prisma.$transaction(async (tx) => {
        const planActual = await tx.planEsperanza.findUnique({
          where: { id: anterior.id },
          include: { diagnosticos: true },
        });
        if (!planActual) return;
        for (const diagnostico of planActual.diagnosticos) {
          const existente = await tx.diagnosticoArea.findUnique({
            where: {
              planEsperanzaId_elementoId: {
                planEsperanzaId: destino.id,
                elementoId: diagnostico.elementoId,
              },
            },
          });
          if (!existente) {
            await tx.diagnosticoArea.create({
              data: {
                planEsperanzaId: destino.id,
                elementoId: diagnostico.elementoId,
                urlFoto: diagnostico.urlFoto,
                valoracion: diagnostico.valoracion,
                observaciones: diagnostico.observaciones,
                checklist: diagnostico.checklist ?? Prisma.JsonNull,
                creadoEn: diagnostico.creadoEn,
              },
            });
            continue;
          }
          const data: Prisma.DiagnosticoAreaUpdateInput = {};
          if (existente.urlFoto == null && diagnostico.urlFoto != null) data.urlFoto = diagnostico.urlFoto;
          if (existente.valoracion == null && diagnostico.valoracion != null) data.valoracion = diagnostico.valoracion;
          if (existente.observaciones == null && diagnostico.observaciones != null) data.observaciones = diagnostico.observaciones;
          if (existente.checklist == null && diagnostico.checklist != null) data.checklist = diagnostico.checklist;
          if (Object.keys(data).length) {
            await tx.diagnosticoArea.update({ where: { id: existente.id }, data });
          }
        }
        if (planActual.completado && !destino.completado) {
          await tx.planEsperanza.update({
            where: { id: destino.id },
            data: { completado: true, fechaFin: planActual.fechaFin },
          });
        }
        await tx.planEsperanza.delete({ where: { id: planActual.id } });
      });
    }
  }

  async obtenerPlanActivo(conjuntoId: string) {
    const plan = await this.prisma.planEsperanza.findFirst({
      where: { conjuntoId, cicloId: null, completado: false },
      orderBy: { fechaInicio: "desc" },
      include: {
        diagnosticos: {
          include: {
            elemento: {
              include: {
                padre: true,
                ubicacion: true,
              },
            },
          },
          orderBy: [
            { elemento: { ubicacion: { nombre: "asc" } } },
            { elemento: { padre: { nombre: "asc" } } },
            { elemento: { nombre: "asc" } },
          ],
        },
      },
    });

    if (!plan) return null;

    const diagnosticosMap = plan.diagnosticos.map((d) => ({
      id: d.id,
      elementoId: d.elementoId,
      elementoNombre: d.elemento.nombre,
      ubicacionId: d.elemento.ubicacionId,
      ubicacionNombre: d.elemento.ubicacion.nombre,
      subzonaNombre: d.elemento.padre?.nombre ?? null,
      urlFoto: d.urlFoto,
      valoracion: d.valoracion,
      observaciones: d.observaciones,
      checklist: parseChecklist(d.checklist),
      creadoEn: d.creadoEn,
    }));

    return {
      id: plan.id,
      conjuntoId: plan.conjuntoId,
      fechaInicio: plan.fechaInicio,
      fechaFin: plan.fechaFin,
      completado: plan.completado,
      diagnosticos: diagnosticosMap,
    };
  }

  async listarPlanes(conjuntoId: string) {
    const planes = await this.prisma.planEsperanza.findMany({
      where: { conjuntoId, cicloId: null },
      orderBy: { fechaInicio: "desc" },
      include: {
        _count: { select: { diagnosticos: true } },
      },
    });

    return planes.map((p) => ({
      id: p.id,
      fechaInicio: p.fechaInicio,
      fechaFin: p.fechaFin,
      completado: p.completado,
      totalAreas: p._count.diagnosticos,
    }));
  }

  async obtenerDiagnostico(diagnosticoId: number) {
    const d = await this.prisma.diagnosticoArea.findUnique({
      where: { id: diagnosticoId },
      include: {
        elemento: {
          include: {
            padre: true,
            ubicacion: true,
          },
        },
        planEsperanza: true,
      },
    });
    if (!d) return null;
    return {
      id: d.id,
      planId: d.planEsperanzaId,
      conjuntoId: d.planEsperanza.conjuntoId,
      elementoId: d.elementoId,
      elementoNombre: d.elemento.nombre,
      subzonaNombre: d.elemento.padre?.nombre ?? null,
      ubicacionNombre: d.elemento.ubicacion.nombre,
      urlFoto: d.urlFoto,
      valoracion: d.valoracion,
      observaciones: d.observaciones,
      checklist: parseChecklist(d.checklist),
    };
  }

  async guardarDiagnostico(
    diagnosticoId: number,
    data: {
      valoracion?: number | null;
      observaciones?: string | null;
      checklist?: ChecklistItem[] | null;
      filePath?: string | null;
      fileName?: string | null;
      mimeType?: string | null;
      conjuntoNombre?: string | null;
    }
  ) {
    const actual = await this.prisma.diagnosticoArea.findUnique({
      where: { id: diagnosticoId },
      include: { planEsperanza: { select: { fechaProgramada: true, cicloId: true } } },
    });
    if (actual?.planEsperanza.cicloId && actual.planEsperanza.fechaProgramada) {
      const hoy = new Date();
      const hoyMes = inicioMesEnBogota(hoy);
      if (actual.planEsperanza.fechaProgramada > hoyMes) {
        throw Object.assign(new Error("Esta fase se habilita en el mes programado."), {
          status: 409,
          code: "FASE_BLOQUEADA",
        });
      }
    }
    const updateData: {
      valoracion?: number | null;
      observaciones?: string | null;
      checklist?: Prisma.InputJsonValue | typeof Prisma.JsonNull;
      urlFoto?: string | null;
    } = {};

    if (data.valoracion !== undefined) {
      const v = Number(data.valoracion);
      if (v < 0 || v > 5) {
        throw Object.assign(new Error("La valoracion debe estar entre 0 y 5."), {
          status: 400,
        });
      }
      updateData.valoracion = v;
    }

    if (data.observaciones !== undefined) {
      updateData.observaciones = data.observaciones;
    }

    if (data.checklist !== undefined) {
      updateData.checklist = !data.checklist || data.checklist.length == 0
        ? Prisma.JsonNull
        : (data.checklist as Prisma.InputJsonValue);
    }

    if (data.filePath && data.fileName && data.mimeType && data.conjuntoNombre) {
      try {
        const url = await uploadPlanEsperanzaFoto({
          filePath: data.filePath,
          fileName: data.fileName,
          mimeType: data.mimeType,
          conjuntoNombre: data.conjuntoNombre,
        });
        updateData.urlFoto = url;
      } finally {
        try {
          if (fs.existsSync(data.filePath)) fs.unlinkSync(data.filePath);
        } catch {
          // La limpieza del temporal es best-effort y no oculta el resultado del upload.
        }
      }
    }

    await this.prisma.diagnosticoArea.update({
      where: { id: diagnosticoId },
      data: updateData,
    });

    return this.obtenerDiagnostico(diagnosticoId);
  }

  async finalizarPlan(planId: number) {
    const existente = await this.prisma.planEsperanza.findUnique({
      where: { id: planId },
      select: { fechaProgramada: true, cicloId: true },
    });
    if (existente?.cicloId && existente.fechaProgramada) {
      const hoy = new Date();
      const hoyMes = inicioMesEnBogota(hoy);
      if (existente.fechaProgramada > hoyMes) {
        throw Object.assign(new Error("Esta fase se habilita en el mes programado."), {
          status: 409,
          code: "FASE_BLOQUEADA",
        });
      }
    }
    if (existente?.cicloId) {
      const diagnosticos = await this.prisma.diagnosticoArea.findMany({
        where: { planEsperanzaId: planId },
        select: { valoracion: true, observaciones: true, urlFoto: true, checklist: true },
      });
      const pendientes = diagnosticos.filter((d) => !diagnosticoTieneContenido({
        valoracion: d.valoracion,
        observaciones: d.observaciones,
        urlFoto: d.urlFoto,
        checklist: parseChecklist(d.checklist),
      })).length;
      if (pendientes) {
        throw Object.assign(new Error(`Faltan ${pendientes} área(s) por evaluar. Guarda los avances y completa la fase más tarde.`), {
          status: 409,
          code: "FASE_INCOMPLETA",
        });
      }
    }
    return this.prisma.planEsperanza.update({
      where: { id: planId },
      data: {
        completado: true,
        fechaFin: new Date(),
      },
    });
  }

  async obtenerInforme(planId: number) {
    const plan = await this.prisma.planEsperanza.findUnique({
      where: { id: planId },
      include: {
        conjunto: { select: { nombre: true, nit: true } },
        diagnosticos: {
          include: {
            elemento: {
              include: {
                padre: true,
                ubicacion: true,
              },
            },
          },
          orderBy: [
            { elemento: { ubicacion: { nombre: "asc" } } },
            { elemento: { padre: { nombre: "asc" } } },
            { elemento: { nombre: "asc" } },
          ],
        },
      },
    });

    if (!plan) return null;

    const agrupado: Record<
      number,
      {
        ubicacionNombre: string;
        subzonas: Record<
          string,
          {
            subzonaNombre: string;
            areas: Array<{
              elementoId: number;
              elementoNombre: string;
              urlFoto: string | null;
              valoracion: number | null;
              observaciones: string | null;
              checklist: ChecklistItem[];
            }>;
          }
        >;
      }
    > = {};

    for (const d of plan.diagnosticos) {
      const ubicId = d.elemento.ubicacionId;
      const uNombre = d.elemento.ubicacion.nombre;
      const sNombre = d.elemento.padre?.nombre ?? "Sin subzona";

      if (!agrupado[ubicId]) {
        agrupado[ubicId] = { ubicacionNombre: uNombre, subzonas: {} };
      }
      if (!agrupado[ubicId].subzonas[sNombre]) {
        agrupado[ubicId].subzonas[sNombre] = {
          subzonaNombre: sNombre,
          areas: [],
        };
      }
      agrupado[ubicId].subzonas[sNombre].areas.push({
        elementoId: d.elementoId,
        elementoNombre: d.elemento.nombre,
        urlFoto: d.urlFoto,
        valoracion: d.valoracion,
        observaciones: d.observaciones,
        checklist: parseChecklist(d.checklist),
      });
    }

    return {
      planId: plan.id,
      conjuntoNombre: plan.conjunto.nombre,
      conjuntoNit: plan.conjunto.nit,
      fechaInicio: plan.fechaInicio,
      fechaFin: plan.fechaFin,
      completado: plan.completado,
      ubicaciones: Object.values(agrupado).map((u) => ({
        ubicacionNombre: u.ubicacionNombre,
        subzonas: Object.values(u.subzonas).map((s) => ({
          subzonaNombre: s.subzonaNombre,
          areas: s.areas,
        })),
      })),
    };
  }

  async obtenerHistorico(conjuntoId: string, planIds?: number[]) {
    const hojas = await obtenerElementosHoja(this.prisma, conjuntoId);

    const planes = await this.prisma.planEsperanza.findMany({
      where: {
        conjuntoId,
        cicloId: null,
        ...(planIds?.length ? { id: { in: planIds } } : {}),
      },
      orderBy: { fechaInicio: "asc" },
      include: {
        diagnosticos: {
          include: {
            elemento: {
              include: {
                padre: true,
                ubicacion: true,
              },
            },
          },
        },
      },
    });

    type AreaRow = {
      elementoId: number;
      elementoNombre: string;
      ubicacionId: number;
      ubicacionNombre: string;
      subzonaNombre: string | null;
      entradas: TimelineEntry[];
    };

    const areasMap = new Map<number, AreaRow>();

    for (const plan of planes) {
      for (const d of plan.diagnosticos) {
        if (!areasMap.has(d.elementoId)) {
          areasMap.set(d.elementoId, {
            elementoId: d.elementoId,
            elementoNombre: d.elemento.nombre,
            ubicacionId: d.elemento.ubicacionId,
            ubicacionNombre: d.elemento.ubicacion.nombre,
            subzonaNombre: d.elemento.padre?.nombre ?? null,
            entradas: [],
          });
        }
        areasMap.get(d.elementoId)!.entradas.push({
          planId: plan.id,
          fecha: plan.fechaInicio,
          urlFoto: d.urlFoto,
          valoracion: d.valoracion,
          observaciones: d.observaciones,
          checklist: parseChecklist(d.checklist),
        });
      }
    }

    const agrupado: Record<
      number,
      {
        ubicacionNombre: string;
        subzonas: Record<
          string,
          {
            subzonaNombre: string;
            areas: AreaRow[];
          }
        >;
      }
    > = {};

    for (const area of areasMap.values()) {
      const uNombre = area.ubicacionNombre;
      const sNombre = area.subzonaNombre ?? "Sin subzona";
      if (!agrupado[area.ubicacionId]) {
        agrupado[area.ubicacionId] = { ubicacionNombre: uNombre, subzonas: {} };
      }
      if (!agrupado[area.ubicacionId].subzonas[sNombre]) {
        agrupado[area.ubicacionId].subzonas[sNombre] = {
          subzonaNombre: sNombre,
          areas: [],
        };
      }
      agrupado[area.ubicacionId].subzonas[sNombre].areas.push(area);
    }

    const planesResumen = planes.map((p) => ({
      id: p.id,
      fechaInicio: p.fechaInicio,
      fechaFin: p.fechaFin,
      completado: p.completado,
    }));

    return {
      planes: planesResumen,
      ubicaciones: Object.values(agrupado).map((u) => ({
        ubicacionNombre: u.ubicacionNombre,
        subzonas: Object.values(u.subzonas).map((s) => ({
          subzonaNombre: s.subzonaNombre,
          areas: s.areas.map((a) => ({
            elementoId: a.elementoId,
            elementoNombre: a.elementoNombre,
            entradas: a.entradas,
          })),
        })),
      })),
    };
  }

  async reiniciarPlan(
    conjuntoId: string,
    mantenerEvidencias: boolean
  ) {
    const planActivo = await this.prisma.planEsperanza.findFirst({
      where: { conjuntoId, cicloId: null, completado: false },
      orderBy: { fechaInicio: "desc" },
    });

    const planAnteriorId = mantenerEvidencias ? planActivo?.id : undefined;

    if (planActivo) {
      await this.prisma.diagnosticoArea.deleteMany({
        where: { planEsperanzaId: planActivo.id },
      });
      await this.prisma.planEsperanza.delete({
        where: { id: planActivo.id },
      });
    }

    return this.iniciarPlan(conjuntoId, mantenerEvidencias, planAnteriorId);
  }

  async verificarZonasNuevas(conjuntoId: string) {
    const planActivo = await this.prisma.planEsperanza.findFirst({
      where: { conjuntoId, cicloId: null, completado: false },
      orderBy: { fechaInicio: "desc" },
    });

    if (!planActivo) return { hayZonasNuevas: false, zonasExistentes: 0, zonasActuales: 0 };

    const hojas = await obtenerElementosHoja(this.prisma, conjuntoId);
    const totalActual = hojas.length;
    const diagnosticadas = await this.prisma.diagnosticoArea.count({
      where: { planEsperanzaId: planActivo.id },
    });

    return {
      hayZonasNuevas: totalActual > diagnosticadas,
      zonasExistentes: diagnosticadas,
      zonasActuales: totalActual,
    };
  }

  async obtenerLineaTiempoElemento(elementoId: number) {
    const diagnosticos = await this.prisma.diagnosticoArea.findMany({
      where: { elementoId },
      include: {
        planEsperanza: { select: { fechaInicio: true, conjuntoId: true } },
      },
      orderBy: { planEsperanza: { fechaInicio: "asc" } },
    });

    return diagnosticos.map((d) => ({
      planId: d.planEsperanzaId,
      fecha: d.planEsperanza.fechaInicio,
      urlFoto: d.urlFoto,
      valoracion: d.valoracion,
      observaciones: d.observaciones,
      checklist: parseChecklist(d.checklist),
    }));
  }
}
