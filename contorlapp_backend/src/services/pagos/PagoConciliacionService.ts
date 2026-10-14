import { EstadoCobro, OrigenVerificacionPago, type PagoCobro, type PrismaClient } from "@prisma/client";
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
  /** Cobros pagados de los ultimos 3 dias confirmados de nuevo con Factus (uno por uno). */
  verificadosRecientes?: number;
  /** Cobros pendientes con el QR vencido que se cerraron (sin pago en Factus). */
  cerradosPorVencimiento?: number;
  anomalias: AnomaliaConciliacion[];
};

export type OpcionesConciliacion = {
  /**
   * Consulta un recaudo por referencia. Con ella la conciliacion tambien
   * (1) vuelve a confirmar con Factus, uno por uno, los cobros pagados de los
   * ultimos 3 dias -no depende de recorrer todo el listado, que con el tiempo
   * pasa del tope- y (2) cierra los pendientes cuyo QR ya vencio sin pago.
   */
  consultar?: (referenceCode: string) => Promise<FactusCollection | null>;
};

const HORA = 3_600_000;
// Ventana de la doble verificacion de pagados y tope por corrida.
const VENTANA_PAGADOS_RECIENTES_MS = 72 * HORA;
const MAX_PAGADOS_RECIENTES = 200;
// Un QR vencido hace mas de esto ya no se puede pagar: se cierra el cobro.
const MARGEN_VENCIDO_MS = HORA;
// Vigencia del QR si Factus no informo qr_expires_at (FAQ de Factus: 24 h).
const VIGENCIA_QR_MS = 24 * HORA;
const MAX_VENCIDOS_POR_CORRIDA = 200;

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
    private pagos: Pick<PagoService, "verificarCobro" | "reabrirYVerificar" | "cerrarVencido">,
    private listar: (p: { status?: string; page?: number }) => Promise<FactusCollectionPage>,
    private alertar: (titulo: string, mensaje: string) => Promise<void>,
    private maxPaginas = Number(process.env.PAGOS_CONCILIACION_MAX_PAGINAS ?? 50),
    /**
     * En el sandbox de Factus un recaudo pagado sin cobro aqui no es dinero
     * perdido: es una prueba hecha desde otro entorno (p. ej. local) con la
     * misma cuenta. Ahi no se reporta.
     */
    private esSandbox: () => boolean = () => false,
    private opciones: OpcionesConciliacion = {},
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
        if (!this.esSandbox() && PREFIJOS_PROPIOS.some((p) => remoto.reference_code.startsWith(p))) {
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

    const verificadosRecientes = await this.verificarPagadosRecientes(referenciasRemotas, anomalias);
    const cerradosPorVencimiento = await this.cerrarVencidos(anomalias);

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
      ...(this.opciones.consultar ? { verificadosRecientes, cerradosPorVencimiento } : {}),
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

  /**
   * Doble verificacion: los cobros que aqui quedaron pagados en los ultimos
   * 3 dias se confirman de nuevo con Factus, uno por uno. Si Factus no los
   * da por pagados es grave (se entrego algo sin dinero): anomalia sin
   * correccion automatica. Si la consulta falla no se concluye nada.
   */
  private async verificarPagadosRecientes(listados: Set<string>, anomalias: AnomaliaConciliacion[]) {
    const consultar = this.opciones.consultar;
    if (!consultar) return 0;
    const yaReportados = new Set(
      anomalias.filter((a) => a.tipo === "PAGADO_LOCAL_NO_EN_FACTUS").map((a) => a.referenceCode),
    );
    const recientes = await this.prisma.pagoCobro.findMany({
      where: {
        estado: EstadoCobro.PAGADO,
        pagadoDetectadoEn: { gte: new Date(Date.now() - VENTANA_PAGADOS_RECIENTES_MS) },
      },
      orderBy: { pagadoDetectadoEn: "desc" },
      take: MAX_PAGADOS_RECIENTES,
      select: { referenceCode: true },
    });
    let verificados = 0;
    for (const { referenceCode } of recientes) {
      if (yaReportados.has(referenceCode)) continue;
      if (listados.has(referenceCode)) {
        verificados++;
        continue;
      }
      let remoto: FactusCollection | null;
      try {
        remoto = await consultar(referenceCode);
      } catch {
        continue;
      }
      verificados++;
      if (remoto?.status !== "paid") {
        anomalias.push({
          tipo: "PAGADO_LOCAL_NO_EN_FACTUS",
          referenceCode,
          detalle: `Aqui figura pagado pero Factus responde ${remoto ? `"${remoto.status}"` : "que no existe"}`,
        });
      }
    }
    return verificados;
  }

  /**
   * Cobros pendientes cuyo QR vencio hace mas de una hora: una ultima consulta
   * y, si Factus no lo cobro, se cierran. Si lo cobro, se confirma por el
   * camino normal. Un pago que llegara despues igual lo reabren el webhook o
   * esta conciliacion (reabrirYVerificar).
   */
  private async cerrarVencidos(anomalias: AnomaliaConciliacion[]) {
    const consultar = this.opciones.consultar;
    if (!consultar) return 0;
    const limite = Date.now() - MARGEN_VENCIDO_MS;
    const vencidos = await this.prisma.pagoCobro.findMany({
      where: {
        estado: { in: ESTADOS_PENDIENTES_LOCALES },
        OR: [
          { qrExpiraEn: { lt: new Date(limite) } },
          { qrExpiraEn: null, creadoEn: { lt: new Date(limite - VIGENCIA_QR_MS) } },
        ],
      },
      orderBy: { creadoEn: "asc" },
      take: MAX_VENCIDOS_POR_CORRIDA,
      select: { id: true, referenceCode: true },
    });
    let cerrados = 0;
    for (const cobro of vencidos) {
      try {
        const remoto = await consultar(cobro.referenceCode);
        if (remoto?.status === "paid") {
          const actualizado = await this.pagos.verificarCobro(cobro.id, OrigenVerificacionPago.CONCILIACION);
          anomalias.push({
            tipo: "PAGADO_EN_FACTUS_NO_LOCAL",
            referenceCode: cobro.referenceCode,
            detalle: `Factus lo reporta pagado con el QR ya vencido; ahora quedo ${actualizado.estado}`,
            corregida: actualizado.estado === EstadoCobro.PAGADO,
          });
        } else if (await this.pagos.cerrarVencido(cobro.id, "conciliacion: el QR vencio sin pago")) {
          cerrados++;
        }
      } catch {
        // Factus no respondio: se intenta en la siguiente corrida.
      }
    }
    return cerrados;
  }

  private async corregir(local: PagoCobro): Promise<EstadoCobro> {
    try {
      const actualizado = ESTADOS_REABRIBLES.includes(local.estado)
        ? await this.pagos.reabrirYVerificar(local.id, OrigenVerificacionPago.CONCILIACION)
        : await this.pagos.verificarCobro(local.id, OrigenVerificacionPago.CONCILIACION);
      return actualizado.estado;
    } catch {
      return local.estado;
    }
  }
}
