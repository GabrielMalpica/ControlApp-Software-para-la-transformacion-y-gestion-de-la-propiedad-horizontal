import { PrismaClient } from "@prisma/client";
import { prisma } from "../db/prisma";
import { uploadPlanEsperanzaFoto } from "../utils/drive_plan_esperanza";

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
  creadoEn: Date;
};

type TimelineEntry = {
  planId: number;
  fechaInicio: Date;
  urlFoto: string | null;
  valoracion: number | null;
  observaciones: string | null;
};

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

  async obtenerConfig(conjuntoId: string) {
    let config = await this.prisma.planEsperanzaConfig.findUnique({
      where: { conjuntoId },
    });
    if (!config) {
      config = await this.prisma.planEsperanzaConfig.create({
        data: { conjuntoId },
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
        });
      }
    } else {
      for (const hoja of hojas) {
        diagnosticosData.push({
          planEsperanzaId: plan.id,
          elementoId: hoja.id,
        });
      }
    }

    if (diagnosticosData.length > 0) {
      await this.prisma.diagnosticoArea.createMany({ data: diagnosticosData });
    }

    return this.obtenerPlanActivo(conjuntoId);
  }

  async obtenerPlanActivo(conjuntoId: string) {
    const plan = await this.prisma.planEsperanza.findFirst({
      where: { conjuntoId, completado: false },
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
      where: { conjuntoId },
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
    };
  }

  async guardarDiagnostico(
    diagnosticoId: number,
    data: {
      valoracion?: number | null;
      observaciones?: string | null;
      filePath?: string | null;
      fileName?: string | null;
      mimeType?: string | null;
      conjuntoNombre?: string | null;
    }
  ) {
    const updateData: {
      valoracion?: number | null;
      observaciones?: string | null;
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

    if (data.filePath && data.fileName && data.mimeType && data.conjuntoNombre) {
      const url = await uploadPlanEsperanzaFoto({
        filePath: data.filePath,
        fileName: data.fileName,
        mimeType: data.mimeType,
        conjuntoNombre: data.conjuntoNombre,
      });
      updateData.urlFoto = url;
    }

    await this.prisma.diagnosticoArea.update({
      where: { id: diagnosticoId },
      data: updateData,
    });

    return this.obtenerDiagnostico(diagnosticoId);
  }

  async finalizarPlan(planId: number) {
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

  async obtenerHistorico(conjuntoId: string) {
    const hojas = await obtenerElementosHoja(this.prisma, conjuntoId);

    const planes = await this.prisma.planEsperanza.findMany({
      where: { conjuntoId },
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
          fechaInicio: plan.fechaInicio,
          urlFoto: d.urlFoto,
          valoracion: d.valoracion,
          observaciones: d.observaciones,
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
      where: { conjuntoId, completado: false },
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
      where: { conjuntoId, completado: false },
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
    }));
  }
}
