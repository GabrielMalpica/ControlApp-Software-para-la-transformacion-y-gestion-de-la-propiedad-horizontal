import { EstadoCobro, type PagoCobro, type PrismaClient } from "@prisma/client";
import { cacheGet, cacheSet } from "../RedisService";
import { siguienteEsperaMs, siguienteEsperaWebhookMs, VIGENCIA_QR_POR_DEFECTO_MS } from "./backoff";
import { webhookFactusConfigurado } from "./FactusWebhookService";
import { ESTADOS_ACTIVOS } from "./PagoService";
import { detalleErrorPagos } from "./errors";

/**
 * "polling": el worker consulta seguido (backoff de siempre). "webhook": el
 * webhook es la via principal y el worker solo hace unas pocas consultas de
 * respaldo por cobro.
 */
export type ModoConfirmacion = "polling" | "webhook";

const MINUTO = 60_000;
const HORA = 60 * MINUTO;
// Un pago que se confirmo por otra via (worker, "Ya pague", conciliacion)
// sin que llegara ningun aviso del webhook en este tiempo indica que el
// webhook no esta llegando (URL o llave mal en el panel, endpoint caido).
const GRACIA_SIN_WEBHOOK_MS = 15 * MINUTO;
// Mientras haya uno de esos pagos en las ultimas 24 h se usa el sondeo de
// siempre; al salir de la ventana se vuelve solo al modo webhook.
const VENTANA_SIN_WEBHOOK_MS = 24 * HORA;
const EVALUAR_CADA_MS = 5 * MINUTO;
// En el sondeo, un cobro de menos de 24 h se consulta al menos cada 5 min:
// uno agendado mas lejos viene del calendario del modo webhook.
const MAXIMA_ESPERA_SONDEO_MS = 5 * MINUTO;
const ESTADOS_CON_PAGO: EstadoCobro[] = [
  EstadoCobro.PAGADO,
  EstadoCobro.PAGADO_DUPLICADO,
  EstadoCobro.PAGADO_HUERFANO,
];

export function modoConfigurado(): ModoConfirmacion {
  const valor = String(process.env.PAGOS_MODO_CONFIRMACION ?? "polling").trim().toLowerCase();
  return valor === "webhook" ? "webhook" : "polling";
}

/**
 * Modo con el que de verdad se trabaja: el webhook solo reemplaza al sondeo
 * si asi esta configurado, si el endpoint tiene llave y si no hubo pagos que
 * se confirmaran sin su aviso en las ultimas 24 h (modo degradado).
 */
export function decidirModo(estado: {
  configurado: ModoConfirmacion;
  webhookConfigurado: boolean;
  pagosSinWebhook: number;
}): { modo: ModoConfirmacion; motivo: string | null } {
  if (estado.configurado === "polling") return { modo: "polling", motivo: null };
  if (!estado.webhookConfigurado) {
    return { modo: "polling", motivo: "La llave del webhook no esta configurada en el servidor" };
  }
  if (estado.pagosSinWebhook > 0) {
    return {
      modo: "polling",
      motivo:
        `${estado.pagosSinWebhook} pago(s) de las ultimas 24 h se confirmaron sin que llegara el aviso de ` +
        "Factus: se volvio a la verificacion frecuente",
    };
  }
  return { modo: "webhook", motivo: null };
}

/** Espera hasta la proxima consulta de un cobro pendiente, segun el modo. */
export function esperaSegunModo(
  modo: ModoConfirmacion,
  cobro: Pick<PagoCobro, "creadoEn" | "qrExpiraEn">,
  ahora: Date,
): number | null {
  const edadMs = ahora.getTime() - cobro.creadoEn.getTime();
  if (modo === "polling") return siguienteEsperaMs(edadMs);
  const vigenciaMs = cobro.qrExpiraEn
    ? cobro.qrExpiraEn.getTime() - cobro.creadoEn.getTime()
    : VIGENCIA_QR_POR_DEFECTO_MS;
  return siguienteEsperaWebhookMs(edadMs, vigenciaMs);
}

type Alertar = (titulo: string, mensaje: string) => Promise<void>;

/**
 * Salud del webhook de Factus y modo de confirmacion. Todo se deduce de la
 * base de datos (cobros pagados sin aviso), asi que varias instancias llegan
 * a la misma conclusion sin compartir estado.
 */
export class SaludPagosService {
  private modoActual: ModoConfirmacion = "polling";
  private evaluadoEn = 0;

  constructor(
    private prisma: PrismaClient,
    private alertar: Alertar,
  ) {}

  /** Lo usa el calendario de PagoService (sincrono): ultimo modo evaluado. */
  modoEfectivo(): ModoConfirmacion {
    return this.modoActual;
  }

  /** El worker lo llama en cada vuelta; solo recalcula cada 5 min. */
  async evaluarSiToca(ahora = new Date()) {
    if (ahora.getTime() - this.evaluadoEn < EVALUAR_CADA_MS) return;
    await this.evaluar(ahora);
  }

  async evaluar(ahora = new Date()) {
    this.evaluadoEn = ahora.getTime();
    const webhookConfigurado = webhookFactusConfigurado();
    const pagosSinWebhook = webhookConfigurado ? await this.contarPagosSinWebhook(ahora) : 0;
    const configurado = modoConfigurado();
    const decision = decidirModo({ configurado, webhookConfigurado, pagosSinWebhook });
    this.modoActual = decision.modo;

    if (decision.modo === "polling") await this.adelantarConsultas(ahora);
    if (pagosSinWebhook > 0) await this.avisarPagosSinWebhook(pagosSinWebhook, configurado);
    return decision;
  }

  /** Resumen para el panel de pagos (Pagos > Salud). */
  async resumen(ahora = new Date()) {
    const hace24h = new Date(ahora.getTime() - 24 * HORA);
    const hace7d = new Date(ahora.getTime() - 7 * 24 * HORA);
    const webhookConfigurado = webhookFactusConfigurado();
    const [ultimo, avisos24h, sinProcesar, resultados, origenes, pagosSinWebhook, activos, activosViejos] =
      await Promise.all([
        this.prisma.pagoWebhookFactus.findFirst({ orderBy: { recibidoEn: "desc" }, select: { recibidoEn: true } }),
        this.prisma.pagoWebhookFactus.count({ where: { recibidoEn: { gte: hace24h } } }),
        this.prisma.pagoWebhookFactus.count({ where: { estado: "RECIBIDO" } }),
        this.prisma.pagoWebhookFactus.groupBy({
          by: ["resultado"],
          where: { recibidoEn: { gte: hace7d } },
          _count: { _all: true },
        }),
        this.prisma.pagoCobro.groupBy({
          by: ["origenConfirmacion"],
          where: { estado: EstadoCobro.PAGADO, pagadoDetectadoEn: { gte: hace7d } },
          _count: { _all: true },
        }),
        webhookConfigurado ? this.contarPagosSinWebhook(ahora) : Promise.resolve(0),
        this.prisma.pagoCobro.count({ where: { estado: { in: ESTADOS_ACTIVOS } } }),
        this.prisma.pagoCobro.count({ where: { estado: { in: ESTADOS_ACTIVOS }, creadoEn: { lt: hace24h } } }),
      ]);
    const configurado = modoConfigurado();
    const decision = decidirModo({ configurado, webhookConfigurado, pagosSinWebhook });
    const porOrigen = Object.fromEntries(
      origenes.map((fila) => [fila.origenConfirmacion ?? "SIN_DATO", fila._count._all]),
    );
    return {
      modoConfigurado: configurado,
      modoEfectivo: decision.modo,
      motivo: decision.motivo,
      webhookConfigurado,
      ultimoWebhookEn: ultimo?.recibidoEn ?? null,
      avisos24h,
      avisosSinProcesar: sinProcesar,
      resultadosAvisos7d: Object.fromEntries(resultados.map((fila) => [fila.resultado ?? "EN_PROCESO", fila._count._all])),
      confirmados7d: {
        total: Object.values(porOrigen).reduce((suma, n) => suma + n, 0),
        porOrigen,
      },
      pagosSinWebhook24h: pagosSinWebhook,
      cobrosPendientes: activos,
      cobrosPendientesMas24h: activosViejos,
      calculadoEn: ahora,
    };
  }

  private async contarPagosSinWebhook(ahora: Date) {
    return this.prisma.pagoCobro.count({
      where: {
        estado: { in: ESTADOS_CON_PAGO },
        webhookPrimeroEn: null,
        pagadoDetectadoEn: {
          gte: new Date(ahora.getTime() - VENTANA_SIN_WEBHOOK_MS),
          lt: new Date(ahora.getTime() - GRACIA_SIN_WEBHOOK_MS),
        },
      },
    });
  }

  /**
   * Al estar en sondeo, los cobros que quedaron agendados con el calendario
   * disperso del modo webhook (horas mas adelante) se consultan ya. Idempotente:
   * con el sondeo de siempre no hay cobros de menos de 24 h agendados a mas de 5 min.
   */
  private async adelantarConsultas(ahora: Date) {
    await this.prisma.pagoCobro.updateMany({
      where: {
        estado: { in: ESTADOS_ACTIVOS },
        creadoEn: { gt: new Date(ahora.getTime() - 24 * HORA) },
        proximaVerificacion: { gt: new Date(ahora.getTime() + MAXIMA_ESPERA_SONDEO_MS) },
      },
      data: { proximaVerificacion: ahora },
    });
  }

  private async avisarPagosSinWebhook(cantidad: number, configurado: ModoConfirmacion) {
    // Una alerta por dia aunque el problema siga (y aunque haya varias instancias).
    const clave = "pagos:salud:alerta-sin-webhook";
    try {
      if (await cacheGet<boolean>(clave)) return;
      await cacheSet(clave, true, 24 * 3600);
      await this.alertar(
        "Pagos: el aviso de Factus no esta llegando",
        `${cantidad} pago(s) de las ultimas 24 h se confirmaron sin que llegara el aviso del webhook de Factus. ` +
          "Revisa la URL y la llave del webhook en el panel de Factus." +
          (configurado === "webhook" ? " Mientras tanto los pagos se verifican con la consulta frecuente." : ""),
      );
    } catch (error) {
      console.error("[pagos] no se pudo avisar que el webhook no llega", detalleErrorPagos(error));
    }
  }
}
