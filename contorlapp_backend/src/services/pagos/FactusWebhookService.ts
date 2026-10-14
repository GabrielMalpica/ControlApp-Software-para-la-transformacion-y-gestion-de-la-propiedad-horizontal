import {
  EstadoCobro,
  OrigenVerificacionPago,
  Prisma,
  type PagoCobro,
  type PagoWebhookFactus,
  type PrismaClient,
} from "@prisma/client";
import crypto from "crypto";
import { z } from "zod";
import { contarEnVentana } from "../../middlewares/rate-limit.middleware";
import { cacheGet, cacheSet } from "../RedisService";
import { FactusPayerSchema, type FactusCollection } from "./FactusPayClient";
import { ESTADOS_ACTIVOS, ESTADOS_REABRIBLES, type PagoService } from "./PagoService";
import { pagadorSaneado } from "./datosRecaudo";
import { detalleErrorPagos } from "./errors";

// Referencias que crea este sistema (generarReferenceCode): CA- app, WC- tienda.
const PREFIJOS_PROPIOS = ["CA-", "WC-"];
// Factus aconseja una llave de 32 caracteres o mas (doc. de Webhooks, §1).
const LLAVE_MIN_CARACTERES = 32;
// Si Factus avisa "paid" pero su API todavia no lo confirma (o no responde),
// se vuelve a consultar a los 30 s, 2 min y 10 min; despues se alerta.
const ESPERAS_NO_CONFIRMADO_MS = [30_000, 120_000, 600_000];
// Errores inesperados (base de datos, etc.) antes de rendirse con una fila.
const MAX_INTENTOS_ERROR = 5;
const RECLAMO_FILA_MS = 60_000;
// Otra via (worker, otra entrega) esta consultando el mismo cobro.
const ESPERA_COBRO_OCUPADO_MS = 15_000;
// El barrido no toma filas recien llegadas: esas las procesa el propio
// request justo despues de responder.
const GRACIA_BARRIDO_MS = 10_000;
// Llaves invalidas por IP: a partir de aqui 429; al llegar a la mitad se alerta.
const VENTANA_15MIN_MS = 15 * 60_000;
const LIMITE_INVALIDOS = 20;
// Techo de avisos validos por IP (Factus manda uno por pago); si se supera,
// 429 y Factus reintenta mas tarde (doc. de Webhooks, §4).
const LIMITE_VALIDOS_15MIN = Number(process.env.FACTUS_PAY_WEBHOOK_LIMITE_15MIN ?? 1_200);
// Consultas a Factus por referencias desconocidas (no se sabe si el aviso es real).
const LIMITE_DESCONOCIDAS_HORA = 30;

const CuerpoWebhookSchema = z.object({
  data: z.object({
    reference_code: z.string().trim().min(1).max(100),
    amount: z.coerce.number().positive().max(1_000_000_000),
    status: z.string().trim().min(1).max(40),
    created_at: z.string().max(60).nullish(),
    qr_expires_at: z.string().max(60).nullish(),
    payer: FactusPayerSchema.nullish(),
  }),
});

export type RespuestaWebhook = { status: number; body: Record<string, unknown>; webhookId?: number };

type Consultar = (referenceCode: string) => Promise<FactusCollection | null>;
type Alertar = (titulo: string, mensaje: string) => Promise<void>;

function sha256(valor: string | Buffer) {
  return crypto.createHash("sha256").update(valor).digest();
}

function llavesConfiguradas(): string[] {
  return [process.env.FACTUS_PAY_WEBHOOK_KEY, process.env.FACTUS_PAY_WEBHOOK_KEY_ANTERIOR]
    .map((llave) => (llave ?? "").trim())
    .filter(Boolean);
}

/** El endpoint acepta avisos (hay llave y todas tienen el largo minimo). */
export function webhookFactusConfigurado(): boolean {
  const llaves = llavesConfiguradas();
  return llaves.length > 0 && llaves.every((llave) => llave.length >= LLAVE_MIN_CARACTERES);
}

/**
 * Compara la llave del query string con las configuradas (la vigente y, al
 * rotarla, la anterior) en tiempo constante: se comparan los SHA-256, que
 * tienen el mismo largo, asi no se filtra ni el largo de la llave.
 */
export function llaveWebhookValida(recibida: unknown, configuradas: string[]): boolean {
  if (typeof recibida !== "string" || !recibida || recibida.length > 512) return false;
  const digest = sha256(recibida);
  let valida = false;
  for (const llave of configuradas) {
    if (crypto.timingSafeEqual(digest, sha256(llave))) valida = true;
  }
  return valida;
}

/** La referencia de un cuerpo que no pasa el esquema (si se puede leer). */
function referenciaLaxa(cuerpo: unknown): string | null {
  const ref = (cuerpo as { data?: { reference_code?: unknown } } | null)?.data?.reference_code;
  return typeof ref === "string" && ref.trim() && ref.length <= 100 ? ref.trim() : null;
}

let avisoLlaveCorta = false;

/**
 * Webhook de Factus Pay (doc. oficial: https://pay-developers.factus.com.co/webhooks/).
 *
 * Factus solo autentica el aviso con una llave fija en el query string: sin
 * firma del cuerpo, sin timestamp, sin id de evento. Por eso el aviso NUNCA
 * confirma un pago por si solo: se guarda en la bandeja (PagoWebhookFactus),
 * se responde 200 rapido (Factus da 10 s) y despues se consulta el recaudo en
 * la API con nuestro token -la misma verificacion de siempre en PagoService-.
 * Un aviso falso, alterado o repetido a lo sumo provoca una consulta.
 */
export class FactusWebhookService {
  constructor(
    private prisma: PrismaClient,
    private pagos: Pick<
      PagoService,
      "verificarCobro" | "reabrirYVerificar" | "reclamarParaVerificar" | "liberarReclamo" | "registrarEvento"
    >,
    private consultar: Consultar,
    private alertar: Alertar,
    private esSandbox: () => boolean = () => false,
  ) {}

  /**
   * Primera mitad (dentro del request): valida la llave y guarda el aviso.
   * Solo responde 2xx si el aviso quedo guardado; si la base de datos falla
   * el error sube y el request responde 5xx, asi Factus lo reintenta.
   */
  async recibir(entrada: { key: unknown; body: unknown; rawBody?: Buffer; ip?: string }): Promise<RespuestaWebhook> {
    const llaves = llavesConfiguradas();
    if (llaves.some((llave) => llave.length < LLAVE_MIN_CARACTERES)) {
      if (!avisoLlaveCorta) {
        avisoLlaveCorta = true;
        console.error(`[pagos] la llave del webhook de Factus debe tener al menos ${LLAVE_MIN_CARACTERES} caracteres`);
      }
      return { status: 503, body: { message: "Webhook no configurado" } };
    }
    if (!llaves.length) return { status: 503, body: { message: "Webhook no configurado" } };

    const ip = (entrada.ip ?? "sin-ip").slice(0, 64);
    if (!llaveWebhookValida(entrada.key, llaves)) {
      return this.rechazarLlave(ip);
    }

    const validos = await contarEnVentana("pagos:webhook-factus:validos", ip, VENTANA_15MIN_MS);
    if (validos.count > LIMITE_VALIDOS_15MIN) {
      console.warn("[pagos] demasiados avisos de Factus desde la misma IP", { ip, avisos: validos.count });
      return { status: 429, body: { message: "Demasiadas solicitudes" } };
    }

    const parsed = CuerpoWebhookSchema.safeParse(entrada.body);
    const datos = parsed.success ? parsed.data.data : null;
    const referenceCode = datos?.reference_code ?? referenciaLaxa(entrada.body);
    const bodySha256 = sha256(entrada.rawBody ?? Buffer.from(JSON.stringify(entrada.body ?? null))).toString("hex");

    // Nunca se guarda el QR (pesado e inutil aqui) ni el documento completo del pagador.
    const payload: Prisma.InputJsonObject = datos
      ? {
          reference_code: datos.reference_code,
          amount: datos.amount,
          status: datos.status,
          created_at: datos.created_at ?? null,
          qr_expires_at: datos.qr_expires_at ?? null,
          payer: pagadorSaneado(datos.payer),
        }
      : {
          invalido: true,
          campos: parsed.success ? [] : parsed.error.issues.slice(0, 10).map((issue) => issue.path.join(".")),
        };
    if (!datos) {
      console.warn("[pagos] aviso de Factus con un formato inesperado", { referenceCode, bodySha256 });
    }

    const cobro = referenceCode
      ? await this.prisma.pagoCobro.findUnique({ where: { referenceCode } })
      : null;

    const fila = await this.prisma.$transaction(async (tx) => {
      const creada = await tx.pagoWebhookFactus.create({
        data: {
          referenceCode,
          cobroId: cobro?.id ?? null,
          bodySha256,
          payload,
          montoReportado: datos ? new Prisma.Decimal(datos.amount) : null,
          estadoReportado: datos?.status ?? null,
          ip,
          // Sin referencia no hay nada que verificar: queda solo como constancia.
          ...(referenceCode
            ? {}
            : {
                estado: "PROCESADO",
                resultado: "PAYLOAD_INVALIDO",
                detalle: "El aviso no trae una referencia legible",
                procesadoEn: new Date(),
              }),
        },
      });
      if (cobro) {
        await tx.pagoCobro.update({ where: { id: cobro.id }, data: { webhooksRecibidos: { increment: 1 } } });
        await tx.pagoCobro.updateMany({
          where: { id: cobro.id, webhookPrimeroEn: null },
          data: { webhookPrimeroEn: new Date() },
        });
        await this.pagos.registrarEvento(tx, cobro.id, "WEBHOOK_RECIBIDO", null, null, {
          webhookId: creada.id,
          estadoReportado: datos?.status ?? null,
          montoReportado: datos?.amount ?? null,
          bodySha256: bodySha256.slice(0, 16),
        });
      }
      return creada;
    });

    return {
      status: 200,
      body: { received: true },
      webhookId: fila.estado === "RECIBIDO" ? fila.id : undefined,
    };
  }

  private async rechazarLlave(ip: string): Promise<RespuestaWebhook> {
    const intentos = await contarEnVentana("pagos:webhook-factus:invalidos", ip, VENTANA_15MIN_MS);
    // Nunca se registra la llave recibida ni la URL (la llave viaja en ella).
    console.warn("[pagos] aviso de Factus con llave invalida", { ip, intentos: intentos.count });
    if (intentos.count === Math.ceil(LIMITE_INVALIDOS / 2)) {
      await this.alertarSeguro(
        "Webhook de pagos: llaves invalidas",
        `Se recibieron ${intentos.count} avisos de pago con una llave invalida en 15 minutos (IP ${ip}). ` +
          "Si se cambio la llave en Factus, actualizala en el servidor; si no, alguien esta probando el endpoint.",
      );
    }
    if (intentos.count > LIMITE_INVALIDOS) {
      return { status: 429, body: { message: "Demasiadas solicitudes" } };
    }
    return { status: 401, body: { message: "Llave invalida" } };
  }

  /**
   * Segunda mitad (despues de responder, o desde el barrido del worker):
   * verifica por API el cobro del aviso. Nunca lanza.
   */
  async procesar(webhookId: number): Promise<void> {
    const ahora = new Date();
    const claim = await this.prisma.pagoWebhookFactus.updateMany({
      where: {
        id: webhookId,
        estado: "RECIBIDO",
        OR: [{ lockedUntil: null }, { lockedUntil: { lt: ahora } }],
      },
      data: { lockedUntil: new Date(ahora.getTime() + RECLAMO_FILA_MS), intentos: { increment: 1 } },
    });
    if (claim.count === 0) return;
    const fila = await this.prisma.pagoWebhookFactus.findUniqueOrThrow({ where: { id: webhookId } });

    try {
      await this.procesarFila(fila);
    } catch (error) {
      console.error("[pagos] fallo procesando un aviso de Factus", { webhookId, ...detalleErrorPagos(error) });
      if (fila.intentos >= MAX_INTENTOS_ERROR) {
        await this.cerrar(fila.id, "ERROR", "No se pudo procesar tras varios intentos");
        await this.alertarSeguro(
          "Webhook de pagos: aviso sin procesar",
          `No se pudo procesar el aviso de pago ${fila.referenceCode ?? `#${fila.id}`} tras ${fila.intentos} intentos. ` +
            "La verificacion periodica sigue revisando ese cobro.",
        );
      } else {
        await this.reprogramar(fila.id, 60_000 * fila.intentos, "Error inesperado; se reintenta");
      }
    }
  }

  /** Retoma los avisos que quedaron sin procesar (caida del proceso, cobro
   * ocupado, Factus sin confirmar todavia). Lo llama el worker en cada vuelta. */
  async barrerPendientes(limite = 20): Promise<void> {
    const ahora = new Date();
    const filas = await this.prisma.pagoWebhookFactus.findMany({
      where: {
        estado: "RECIBIDO",
        recibidoEn: { lt: new Date(ahora.getTime() - GRACIA_BARRIDO_MS) },
        OR: [{ lockedUntil: null }, { lockedUntil: { lt: ahora } }],
      },
      orderBy: { recibidoEn: "asc" },
      take: limite,
      select: { id: true },
    });
    for (const fila of filas) {
      await this.procesar(fila.id);
    }
  }

  private async procesarFila(fila: PagoWebhookFactus): Promise<void> {
    if (!fila.referenceCode) {
      await this.cerrar(fila.id, "PAYLOAD_INVALIDO", "El aviso no trae una referencia legible");
      return;
    }
    const cobro = fila.cobroId
      ? await this.prisma.pagoCobro.findUnique({ where: { id: fila.cobroId } })
      : await this.prisma.pagoCobro.findUnique({ where: { referenceCode: fila.referenceCode } });
    if (!cobro) {
      await this.referenciaDesconocida(fila);
      return;
    }

    let resultado: PagoCobro;
    if (ESTADOS_REABRIBLES.includes(cobro.estado)) {
      // Fallido/abandonado aqui: solo se reabre si la API dice "paid".
      resultado = await this.pagos.reabrirYVerificar(cobro.id, OrigenVerificacionPago.WEBHOOK);
    } else if (!ESTADOS_ACTIVOS.includes(cobro.estado)) {
      await this.cerrar(fila.id, "YA_PROCESADO", `El cobro ya estaba ${cobro.estado}`);
      return;
    } else if (!(await this.pagos.reclamarParaVerificar(cobro.id))) {
      // Otra via lo esta consultando ahora mismo: se reintenta en unos
      // segundos sin gastar uno de los intentos de la fila.
      await this.prisma.pagoWebhookFactus.update({
        where: { id: fila.id },
        data: {
          lockedUntil: new Date(Date.now() + ESPERA_COBRO_OCUPADO_MS),
          intentos: { decrement: 1 },
        },
      });
      return;
    } else {
      try {
        resultado = await this.pagos.verificarCobro(cobro.id, OrigenVerificacionPago.WEBHOOK);
      } catch (error) {
        await this.pagos.liberarReclamo(cobro.id).catch(() => undefined);
        throw error;
      }
    }

    await this.resolver(fila, resultado);
  }

  private async resolver(fila: PagoWebhookFactus, cobro: PagoCobro) {
    const notas: string[] = [];
    if (fila.montoReportado && !new Prisma.Decimal(fila.montoReportado).equals(cobro.montoEsperado)) {
      // La API es la que decide; esto solo queda anotado.
      notas.push(`el aviso dice ${fila.montoReportado.toString()} y el cobro es por ${cobro.montoEsperado.toString()}`);
      console.warn("[pagos] el monto del aviso de Factus no coincide con el cobro", {
        webhookId: fila.id,
        cobroId: cobro.id,
      });
    }
    if (fila.estadoReportado && fila.estadoReportado !== "paid") {
      notas.push(`el aviso trae status "${fila.estadoReportado}"`);
    }
    const sufijo = notas.length ? ` (${notas.join("; ")})` : "";

    switch (cobro.estado) {
      case EstadoCobro.PAGADO:
        await this.completarPagador(fila, cobro);
        await this.cerrar(
          fila.id,
          // Si lo confirmo otra via mientras tanto (worker, "Ya pague"), este
          // aviso no fue el que lo confirmo.
          cobro.origenConfirmacion === OrigenVerificacionPago.WEBHOOK ? "CONFIRMADO" : "YA_PROCESADO",
          `Factus confirmo el pago por API${sufijo}`,
        );
        return;
      case EstadoCobro.DISCREPANCIA:
      case EstadoCobro.PAGADO_DUPLICADO:
      case EstadoCobro.PAGADO_HUERFANO:
        // PagoService ya genero la alerta de revision manual.
        await this.cerrar(fila.id, cobro.estado, `Requiere revision manual${sufijo}`);
        return;
      case EstadoCobro.DEVUELTO:
      case EstadoCobro.RESUELTO:
        await this.cerrar(fila.id, "YA_PROCESADO", `El cobro ya estaba ${cobro.estado}${sufijo}`);
        return;
      default: {
        // Factus aviso el pago pero su API no lo confirma (todavia, o no
        // respondio). Se reintenta unas veces; si sigue igual, alguien debe
        // mirarlo: puede ser un aviso falso con la llave filtrada.
        const espera = ESPERAS_NO_CONFIRMADO_MS[fila.intentos - 1];
        if (espera != null) {
          await this.reprogramar(fila.id, espera, `Factus aun no confirma el pago por API${sufijo}`);
          return;
        }
        await this.cerrar(fila.id, "NO_CONFIRMADO_POR_API", `Factus no confirmo el pago por API${sufijo}`);
        await this.alertarSeguro(
          "Webhook de pagos: aviso no confirmado",
          `Llego un aviso de pago para ${cobro.referenceCode}${cobro.pedidoAppId ? ` (pedido #${cobro.pedidoAppId})` : ""} ` +
            "pero la API de Factus no lo confirma tras varias consultas. Si Factus no esta caido, revisa si la llave del webhook se filtro.",
        );
      }
    }
  }

  /** El pagador que trajo el aviso, si la API no lo informo (solo tras confirmar el pago). */
  private async completarPagador(fila: PagoWebhookFactus, cobro: PagoCobro) {
    if (cobro.pagadorNombre) return;
    const payer = (fila.payload as { payer?: Record<string, unknown> | null } | null)?.payer;
    const nombre = typeof payer?.name === "string" ? payer.name.trim() : "";
    if (!nombre) return;
    await this.prisma.pagoCobro.updateMany({
      where: { id: cobro.id, pagadorNombre: null },
      data: {
        pagadorNombre: nombre.slice(0, 200),
        pagadorTipoDocumento: typeof payer?.document_type === "string" ? payer.document_type : null,
        pagadorDocumentoUltimos4:
          typeof payer?.document_number_ultimos4 === "string" ? payer.document_number_ultimos4 : null,
      },
    });
  }

  /**
   * Aviso con una referencia que no existe aqui. Si no es de este sistema
   * (otro prefijo) o es el sandbox -compartido por todos los entornos- solo
   * queda constancia. Si es nuestra en produccion, se pregunta a la API: un
   * pago real sin cobro local es dinero recibido que nadie va a aplicar.
   */
  private async referenciaDesconocida(fila: PagoWebhookFactus) {
    const ref = fila.referenceCode ?? "";
    const propia = PREFIJOS_PROPIOS.some((prefijo) => ref.startsWith(prefijo));
    if (!propia || this.esSandbox()) {
      await this.cerrar(
        fila.id,
        "REFERENCIA_DESCONOCIDA",
        propia ? "Sandbox: pago de prueba de otro entorno" : "Referencia de otro sistema",
      );
      return;
    }

    const consultas = await contarEnVentana("pagos:webhook-factus:desconocidas", "global", 3_600_000);
    if (consultas.count > LIMITE_DESCONOCIDAS_HORA) {
      await this.cerrar(fila.id, "REFERENCIA_DESCONOCIDA", "Sin consultar a Factus: limite de consultas por hora");
      return;
    }
    const remoto = await this.consultar(ref);
    if (remoto?.status !== "paid") {
      await this.cerrar(fila.id, "REFERENCIA_DESCONOCIDA", "Factus no la confirma pagada (aviso no verificable)");
      console.warn("[pagos] aviso de Factus para una referencia que no existe ni esta pagada", { webhookId: fila.id });
      return;
    }

    await this.cerrar(fila.id, "REFERENCIA_DESCONOCIDA", `Factus confirma un pago de ${remoto.amount} sin cobro local`);
    const clave = `pagos:webhook-factus:alerta-desconocida:${ref}`;
    if (await cacheGet<boolean>(clave)) return;
    await cacheSet(clave, true, 24 * 3600);
    await this.alertarSeguro(
      "Pago recibido sin cobro en el sistema",
      `Factus confirma un pago de $${remoto.amount} con la referencia ${ref}, que no existe en ControlApp. Revisalo en el panel de Factus.`,
    );
  }

  private async cerrar(id: number, resultado: string, detalle: string) {
    await this.prisma.pagoWebhookFactus.update({
      where: { id },
      data: {
        estado: "PROCESADO",
        resultado,
        detalle: detalle.slice(0, 500),
        procesadoEn: new Date(),
        lockedUntil: null,
      },
    });
  }

  private async reprogramar(id: number, esperaMs: number, detalle: string) {
    await this.prisma.pagoWebhookFactus.update({
      where: { id },
      data: { lockedUntil: new Date(Date.now() + esperaMs), detalle: detalle.slice(0, 500) },
    });
  }

  private async alertarSeguro(titulo: string, mensaje: string) {
    try {
      await this.alertar(titulo, mensaje);
    } catch (error) {
      console.error("[pagos] no se pudo enviar una alerta del webhook", detalleErrorPagos(error));
    }
  }
}
