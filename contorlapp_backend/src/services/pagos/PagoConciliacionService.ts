import { EstadoCobro, type PagoCobro, type PrismaClient } from "@prisma/client";
import type { FactusCollection, FactusCollectionPage } from "./FactusPayClient";
import type { PagoService } from "./PagoService";

export type AnomaliaConciliacion = {
  tipo:
    | "SIN_COBRO_LOCAL"
    | "PAGADO_EN_FACTUS_NO_LOCAL"
    | "MONTO_DISTINTO"
    | "PAGADO_LOCAL_NO_EN_FACTUS"
    | "SINCRONIZACION_PENDIENTE";
  referenceCode: string;
  detalle: string;
  corregida?: boolean;
};

export type ReporteConciliacion = {
  ejecutadaEn: string;
  paginasRecorridas: number;
  /** false = se corto en el tope de paginas: no se hicieron las comprobaciones "local pagado que Factus no lista". */
  completo: boolean;
  remotosPagados: number;
  anomalias: AnomaliaConciliacion[];
};

// Referencias que crea este sistema (ver generarReferenceCode): un recaudo
// pagado con otro prefijo lo creo otro sistema de la misma cuenta de Factus.
const PREFIJOS_PROPIOS = ["CA-", "WC-"];
const ESTADOS_PENDIENTES_LOCALES: EstadoCobro[] = [EstadoCobro.CREADO, EstadoCobro.PENDIENTE, EstadoCobro.VENCIDO];
const ESTADOS_REABRIBLES: EstadoCobro[] = [EstadoCobro.ABANDONADO, EstadoCobro.FALLIDO, EstadoCobro.ERROR];

/**
 * Conciliacion: compara los recaudos que Factus lista como pagados con los
 * cobros locales y corrige lo que se pueda (un cobro que aqui quedo abandonado
 * pero Factus cobro). Factus no documenta filtro por fecha ni el orden del
 * listado, asi que recorre las paginas hasta `maxPaginas`.
 */
export class PagoConciliacionService {
  constructor(
    private prisma: PrismaClient,
    private pagos: Pick<PagoService, "verificarCobro" | "reabrirYVerificar">,
    private listar: (p: { status?: string; page?: number }) => Promise<FactusCollectionPage>,
    private alertar: (titulo: string, mensaje: string) => Promise<void>,
    private maxPaginas = Number(process.env.PAGOS_CONCILIACION_MAX_PAGINAS ?? 50),
  ) {}

  async ejecutar(): Promise<ReporteConciliacion> {
    const remotos: FactusCollection[] = [];
    let pagina = 1;
    let completo = false;
    for (; pagina <= this.maxPaginas; pagina++) {
      const res = await this.listar({ status: "paid", page: pagina });
      remotos.push(...res.items);
      if (res.page >= res.lastPage) {
        completo = true;
        break;
      }
    }
    const paginasRecorridas = Math.min(pagina, this.maxPaginas);

    const anomalias: AnomaliaConciliacion[] = [];
    const referenciasRemotas = new Set(remotos.map((r) => r.reference_code));

    for (const remoto of remotos) {
      const local = await this.prisma.pagoCobro.findUnique({ where: { referenceCode: remoto.reference_code } });
      if (!local) {
        if (PREFIJOS_PROPIOS.some((p) => remoto.reference_code.startsWith(p))) {
          anomalias.push({
            tipo: "SIN_COBRO_LOCAL",
            referenceCode: remoto.reference_code,
            detalle: `Factus reporta pagado un recaudo de ${remoto.amount} que no existe en el sistema`,
          });
        }
        continue;
      }
      if (ESTADOS_PENDIENTES_LOCALES.includes(local.estado) || ESTADOS_REABRIBLES.includes(local.estado)) {
        const antes = local.estado;
        const despues = await this.corregir(local);
        anomalias.push({
          tipo: "PAGADO_EN_FACTUS_NO_LOCAL",
          referenceCode: local.referenceCode,
          detalle: `Factus lo reporta pagado y aqui estaba ${antes}; ahora quedo ${despues}`,
          corregida: despues === EstadoCobro.PAGADO,
        });
      } else if (local.estado === EstadoCobro.PAGADO && Number(local.montoEsperado) !== Number(remoto.amount)) {
        anomalias.push({
          tipo: "MONTO_DISTINTO",
          referenceCode: local.referenceCode,
          detalle: `Esperado ${Number(local.montoEsperado)}, Factus ${remoto.amount}`,
        });
      }
    }

    if (completo) {
      const pagadosLocales = await this.prisma.pagoCobro.findMany({
        where: { estado: EstadoCobro.PAGADO },
        select: { referenceCode: true, montoEsperado: true },
      });
      for (const local of pagadosLocales) {
        if (!referenciasRemotas.has(local.referenceCode)) {
          anomalias.push({
            tipo: "PAGADO_LOCAL_NO_EN_FACTUS",
            referenceCode: local.referenceCode,
            detalle: "Aqui figura pagado pero Factus no lo lista como pagado",
          });
        }
      }
    }

    const sinSincronizar = await this.prisma.pagoCobro.findMany({
      where: {
        estado: EstadoCobro.PAGADO,
        pendienteSincronizarWoo: true,
        actualizadoEn: { lt: new Date(Date.now() - 60 * 60_000) },
      },
      select: { referenceCode: true },
    });
    for (const c of sinSincronizar) {
      anomalias.push({
        tipo: "SINCRONIZACION_PENDIENTE",
        referenceCode: c.referenceCode,
        detalle: "Pagado hace mas de una hora y la tienda aun no lo refleja",
      });
    }

    const reporte: ReporteConciliacion = {
      ejecutadaEn: new Date().toISOString(),
      paginasRecorridas,
      completo,
      remotosPagados: remotos.length,
      anomalias,
    };

    const sinCorregir = anomalias.filter((a) => !a.corregida);
    if (sinCorregir.length > 0) {
      try {
        await this.alertar(
          `Conciliacion de pagos: ${sinCorregir.length} para revisar`,
          sinCorregir
            .slice(0, 5)
            .map((a) => `${a.referenceCode}: ${a.detalle}`)
            .join(" | "),
        );
      } catch {
        // Best-effort: el reporte queda igual disponible.
      }
    }
    return reporte;
  }

  private async corregir(local: PagoCobro): Promise<EstadoCobro> {
    try {
      const actualizado = ESTADOS_REABRIBLES.includes(local.estado)
        ? await this.pagos.reabrirYVerificar(local.id)
        : await this.pagos.verificarCobro(local.id);
      return actualizado.estado;
    } catch {
      return local.estado;
    }
  }
}
