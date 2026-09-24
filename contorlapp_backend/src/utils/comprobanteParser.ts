// Lectura del texto de un comprobante de transferencia (Nequi o Bre-B) y
// comparacion contra el pedido. Son funciones puras: el OCR/PDF que produce el
// texto vive en ComprobanteOcrService.
//
// El resultado ayuda al revisor, NO confirma el pago: una captura se puede
// falsificar, asi que nunca se usa para pasar un pedido a PAGADO por si sola.

export type MetodoPagoManual = "nequi" | "bre_b";

export type VeredictoComprobante = "COINCIDE" | "REVISAR" | "DUPLICADO" | "ILEGIBLE";

export interface ComprobanteExtraido {
  metodos: MetodoPagoManual[];
  monto: number | null;
  referencia: string | null;
  fecha: Date | null;
}

export interface CheckComprobante {
  clave: "monto" | "metodo" | "destino" | "fecha" | "referencia" | "duplicado";
  // null = no se pudo evaluar (p. ej. el destino no esta configurado).
  ok: boolean | null;
  detalle: string;
}

export interface VerificacionComprobante {
  veredicto: VeredictoComprobante;
  metodoDetectado: MetodoPagoManual | null;
  montoDetectado: number | null;
  montosEsperados: number[];
  referencia: string | null;
  fechaDetectada: string | null;
  checks: CheckComprobante[];
  motor: "ocr" | "pdf-texto" | "ninguno";
  analizadoEn: string;
}

const PALABRAS_A_IGNORAR_EN_MONTO = /disponible|saldo|comisi[oó]n|iva|gmf|4\s?x\s?1000|costo/i;

const MESES: Record<string, number> = {
  enero: 0, ene: 0,
  febrero: 1, feb: 1,
  marzo: 2, mar: 2,
  abril: 3, abr: 3,
  mayo: 4, may: 4,
  junio: 5, jun: 5,
  julio: 6, jul: 6,
  agosto: 7, ago: 7,
  septiembre: 8, setiembre: 8, sep: 8, sept: 8,
  octubre: 9, oct: 9,
  noviembre: 10, nov: 10,
  diciembre: 11, dic: 11,
};

/** Quita tildes y pasa a minusculas, para comparar sin depender del OCR. */
function plano(texto: string) {
  return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

/**
 * "50.000", "$ 50.000,00", "50,000.00" y "50000" -> 50000. En pesos
 * colombianos un solo separador con 3 digitos detras es de miles; con 1-2 es
 * decimal.
 */
export function parseMontoCop(raw: string): number | null {
  const s = raw.replace(/[^\d.,]/g, "");
  if (!/\d/.test(s)) return null;

  const lastDot = s.lastIndexOf(".");
  const lastComma = s.lastIndexOf(",");
  let decimalSep: "." | "," | null = null;
  if (lastDot >= 0 && lastComma >= 0) {
    decimalSep = lastDot > lastComma ? "." : ",";
  } else {
    const sep = lastDot >= 0 ? "." : lastComma >= 0 ? "," : null;
    if (sep) {
      const partes = s.split(sep);
      if (partes.length === 2 && partes[1].length <= 2) decimalSep = sep;
    }
  }

  let entero = s;
  let decimal = "";
  if (decimalSep) {
    const idx = s.lastIndexOf(decimalSep);
    entero = s.slice(0, idx);
    decimal = s.slice(idx + 1);
  }
  entero = entero.replace(/[.,]/g, "");
  const n = Number(`${entero || "0"}${decimal ? `.${decimal}` : ""}`);
  return Number.isFinite(n) && n > 0 ? n : null;
}

const NUMERO_MONEDA = String.raw`(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)`;

function extraerMonto(texto: string): number | null {
  const lineas = texto.split(/\r?\n/);

  // 1) Un monto etiquetado ("Cuanto", "Valor", "Enviaste"...) en la misma linea.
  const etiquetado = new RegExp(
    String.raw`(?:cu[aá]nto|valor(?:\s+(?:enviado|transferido|de la transferencia|pagado|total))?|monto(?:\s+transferido)?|enviaste|pagaste|transferiste|total)\s*[:\-]?\s*[$S§]?\s*${NUMERO_MONEDA}`,
    "i",
  );
  for (const linea of lineas) {
    if (PALABRAS_A_IGNORAR_EN_MONTO.test(linea)) continue;
    const m = linea.match(etiquetado);
    const monto = m ? parseMontoCop(m[1]) : null;
    if (monto) return monto;
  }

  // 2) Etiqueta en una linea y valor con "$" en la siguiente (asi salen las
  //    tarjetas de Nequi cuando el OCR separa las columnas).
  for (let i = 0; i < lineas.length - 1; i++) {
    if (!/^\s*(cu[aá]nto|valor|monto|total)\s*:?\s*$/i.test(lineas[i])) continue;
    const m = lineas[i + 1].match(new RegExp(String.raw`[$S§]?\s*${NUMERO_MONEDA}`));
    const monto = m ? parseMontoCop(m[1]) : null;
    if (monto) return monto;
  }

  // 3) Ultimo recurso: el primer "$ 12.345" que no sea saldo ni comision.
  const conSigno = new RegExp(String.raw`\$\s*${NUMERO_MONEDA}`);
  for (const linea of lineas) {
    if (PALABRAS_A_IGNORAR_EN_MONTO.test(linea)) continue;
    const m = linea.match(conSigno);
    const monto = m ? parseMontoCop(m[1]) : null;
    if (monto) return monto;
  }
  return null;
}

function extraerReferencia(texto: string): string | null {
  const etiqueta = String.raw`(?:referencia(?:\s+de\s+(?:pago|transferencia))?|ref\.?|n[uú]mero\s+de\s+(?:aprobaci[oó]n|transacci[oó]n|comprobante|referencia|autorizaci[oó]n)|n[uú]m\.?\s+de\s+(?:aprobaci[oó]n|transacci[oó]n)|c[oó]digo(?:\s+de)?(?:\s+la)?(?:\s+(?:referencia|transacci[oó]n|aprobaci[oó]n|autorizaci[oó]n))?|id(?:\s+de(?:\s+la)?)?\s+transacci[oó]n|comprobante(?:\s+n[oº°])?|cus|consecutivo)`;
  const re = new RegExp(
    String.raw`${etiqueta}[ \t]*(?:[:#\-]?[ \t]*|\s+)([A-Za-z0-9][A-Za-z0-9\-]{5,29})`,
    "gi",
  );
  for (const m of texto.matchAll(re)) {
    const candidato = m[1].toUpperCase();
    // Un codigo real trae al menos un digito; descarta palabras sueltas.
    if (/\d/.test(candidato)) return candidato;
  }
  return null;
}

function extraerFecha(texto: string): Date | null {
  const t = plano(texto);
  const hora = String.raw`(?:[\s,\-]*(?:a\s+las\s+)?(\d{1,2}):(\d{2})\s*(a\.?\s?m\.?|p\.?\s?m\.?)?)?`;

  const construir = (
    anio: number,
    mes: number,
    dia: number,
    h?: string,
    min?: string,
    meridiano?: string,
  ) => {
    if (mes < 0 || mes > 11 || dia < 1 || dia > 31 || anio < 2020 || anio > 2100) return null;
    let horas = h ? Number(h) : 12;
    const minutos = min ? Number(min) : 0;
    if (meridiano) {
      const pm = meridiano.replace(/[^a-z]/g, "").startsWith("p");
      if (pm && horas < 12) horas += 12;
      if (!pm && horas === 12) horas = 0;
    }
    // Colombia es UTC-5 todo el anio.
    return new Date(Date.UTC(anio, mes, dia, horas + 5, minutos));
  };

  let m = t.match(new RegExp(String.raw`(\d{1,2})\s+de\s+([a-z]+)\s+(?:de\s+)?(\d{4})${hora}`));
  if (m && MESES[m[2]] !== undefined) {
    return construir(Number(m[3]), MESES[m[2]], Number(m[1]), m[4], m[5], m[6]);
  }

  m = t.match(new RegExp(String.raw`(\d{1,2})\s+([a-z]{3,10})\.?,?\s+(\d{4})${hora}`));
  if (m && MESES[m[2]] !== undefined) {
    return construir(Number(m[3]), MESES[m[2]], Number(m[1]), m[4], m[5], m[6]);
  }

  m = t.match(new RegExp(String.raw`(\d{4})-(\d{2})-(\d{2})${hora}`));
  if (m) return construir(Number(m[1]), Number(m[2]) - 1, Number(m[3]), m[4], m[5], m[6]);

  m = t.match(new RegExp(String.raw`(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})${hora}`));
  if (m) return construir(Number(m[3]), Number(m[2]) - 1, Number(m[1]), m[4], m[5], m[6]);

  return null;
}

function extraerMetodos(texto: string): MetodoPagoManual[] {
  const t = plano(texto);
  const metodos: MetodoPagoManual[] = [];
  if (/nequi/.test(t)) metodos.push("nequi");
  if (/bre[\s\-]?b\b|\bbreb\b|llave/.test(t)) metodos.push("bre_b");
  return metodos;
}

export function extraerDatosComprobante(texto: string): ComprobanteExtraido {
  return {
    metodos: extraerMetodos(texto),
    monto: extraerMonto(texto),
    referencia: extraerReferencia(texto),
    fecha: extraerFecha(texto),
  };
}

/**
 * ¿El comprobante muestra alguno de los destinos configurados (celular Nequi o
 * llave Bre-B del negocio)? Los bancos suelen enmascarar el numero
 * ("*** 4567"), asi que basta que coincidan los ultimos digitos. null = no hay
 * destinos configurados, no se puede evaluar.
 */
export function coincideDestino(texto: string, destinos: string[]): boolean | null {
  const configurados = destinos.map((d) => d.trim()).filter(Boolean);
  if (configurados.length === 0) return null;

  const t = plano(texto);
  const soloDigitos = t.replace(/[^\d]/g, "");

  return configurados.some((destino) => {
    const d = plano(destino);
    const digitos = d.replace(/[^\d]/g, "");
    if (digitos.length >= 7 && digitos.length === d.replace(/\s/g, "").length) {
      if (soloDigitos.includes(digitos)) return true;
      const ultimos = digitos.slice(-4);
      return new RegExp(String.raw`[*•x·]{2,}\s*${ultimos}\b`).test(t);
    }
    // Llave alfanumerica o alias: se busca tal cual, ignorando espacios.
    return t.replace(/\s/g, "").includes(d.replace(/\s/g, ""));
  });
}

/** ¿El texto trae algun celular (completo o enmascarado) que pueda ser el destinatario? */
function muestraNumeroDestino(texto: string): boolean {
  return (
    /(?<!\d)3\d{2}[\s-]?\d{3}[\s-]?\d{4}(?!\d)/.test(texto) ||
    /[*•x·]{2,}\s*\d{3,4}(?!\d)/i.test(texto)
  );
}

export interface ContextoPedido {
  metodoPago: string | null;
  montosEsperados: number[];
  creadoEn: Date;
  ahora?: Date;
  destinosConfigurados?: string[];
  duplicadoDe?: { pedidoId: number; motivo: "referencia" | "archivo" } | null;
}

const MARGEN_PAGO_ANTES_DEL_PEDIDO_MS = 24 * 60 * 60 * 1000;
const MARGEN_RELOJ_MS = 15 * 60 * 1000;

export function evaluarComprobante(
  texto: string,
  extraido: ComprobanteExtraido,
  contexto: ContextoPedido,
  motor: VerificacionComprobante["motor"],
): VerificacionComprobante {
  const ahora = contexto.ahora ?? new Date();
  const checks: CheckComprobante[] = [];

  // Monto
  const montosEsperados = [...new Set(contexto.montosEsperados.filter((m) => m > 0))];
  if (extraido.monto == null) {
    checks.push({ clave: "monto", ok: false, detalle: "No se pudo leer el valor del comprobante" });
  } else {
    const ok = montosEsperados.some((esperado) => Math.abs(esperado - extraido.monto!) < 1);
    checks.push({
      clave: "monto",
      ok,
      detalle: ok
        ? `El valor (${formatoCop(extraido.monto)}) coincide con el pedido`
        : `El comprobante dice ${formatoCop(extraido.monto)} y el pedido espera ${montosEsperados.map(formatoCop).join(" o ")}`,
    });
  }

  // Metodo
  const declarado = contexto.metodoPago as MetodoPagoManual | null;
  if (extraido.metodos.length === 0) {
    checks.push({ clave: "metodo", ok: null, detalle: "No se reconoce si es Nequi o Bre-B" });
  } else if (declarado && !extraido.metodos.includes(declarado)) {
    checks.push({
      clave: "metodo",
      ok: false,
      detalle: `El comprobante parece de ${etiquetaMetodo(extraido.metodos[0])} y el pedido dice ${etiquetaMetodo(declarado)}`,
    });
  } else {
    checks.push({
      clave: "metodo",
      ok: true,
      detalle: `Comprobante de ${etiquetaMetodo(declarado ?? extraido.metodos[0])}`,
    });
  }

  // Destino: solo cuenta en contra si el comprobante muestra OTRO numero; si
  // no muestra ninguno (p. ej. solo el nombre del destinatario) no se puede
  // afirmar nada.
  const destinos = contexto.destinosConfigurados ?? [];
  const destino = coincideDestino(texto, destinos);
  const destinoOk = destino === false && !muestraNumeroDestino(texto) ? null : destino;
  checks.push({
    clave: "destino",
    ok: destinoOk,
    detalle:
      destino == null
        ? "El destino del negocio no esta configurado, no se pudo verificar"
        : destino
          ? "El destinatario coincide con la cuenta del negocio"
          : destinoOk === null
            ? "El comprobante no muestra el numero o llave del destinatario"
            : "El destinatario del comprobante no es la cuenta del negocio",
  });

  // Fecha
  if (!extraido.fecha) {
    checks.push({ clave: "fecha", ok: null, detalle: "No se pudo leer la fecha" });
  } else {
    const desde = contexto.creadoEn.getTime() - MARGEN_PAGO_ANTES_DEL_PEDIDO_MS;
    const hasta = ahora.getTime() + MARGEN_RELOJ_MS;
    const ok = extraido.fecha.getTime() >= desde && extraido.fecha.getTime() <= hasta;
    checks.push({
      clave: "fecha",
      ok,
      detalle: ok
        ? "La fecha es coherente con el pedido"
        : "La fecha del comprobante no corresponde a este pedido (muy anterior o futura)",
    });
  }

  // Referencia
  checks.push({
    clave: "referencia",
    ok: extraido.referencia != null,
    detalle: extraido.referencia
      ? `Referencia ${extraido.referencia}`
      : "No se pudo leer la referencia de la transaccion",
  });

  // Duplicado
  if (contexto.duplicadoDe) {
    checks.push({
      clave: "duplicado",
      ok: false,
      detalle:
        contexto.duplicadoDe.motivo === "referencia"
          ? `La misma referencia ya se uso en el pedido #${contexto.duplicadoDe.pedidoId}`
          : `El mismo archivo ya se subio en el pedido #${contexto.duplicadoDe.pedidoId}`,
    });
  }

  let veredicto: VeredictoComprobante;
  if (contexto.duplicadoDe) {
    veredicto = "DUPLICADO";
  } else if (extraido.monto == null && extraido.referencia == null) {
    veredicto = "ILEGIBLE";
  } else if (checks.every((c) => c.ok !== false)) {
    veredicto = "COINCIDE";
  } else {
    veredicto = "REVISAR";
  }

  return {
    veredicto,
    metodoDetectado: extraido.metodos[0] ?? null,
    montoDetectado: extraido.monto,
    montosEsperados,
    referencia: extraido.referencia,
    fechaDetectada: extraido.fecha ? extraido.fecha.toISOString() : null,
    checks,
    motor,
    analizadoEn: ahora.toISOString(),
  };
}

export function verificacionIlegible(motivo: string, ahora = new Date()): VerificacionComprobante {
  return {
    veredicto: "ILEGIBLE",
    metodoDetectado: null,
    montoDetectado: null,
    montosEsperados: [],
    referencia: null,
    fechaDetectada: null,
    checks: [{ clave: "monto", ok: false, detalle: motivo }],
    motor: "ninguno",
    analizadoEn: ahora.toISOString(),
  };
}

function etiquetaMetodo(metodo: MetodoPagoManual) {
  return metodo === "nequi" ? "Nequi" : "Bre-B";
}

function formatoCop(valor: number) {
  return `$${Math.round(valor).toLocaleString("es-CO")}`;
}

/** Resumen de una linea para la nota interna del pedido en WooCommerce. */
export function resumenVerificacion(v: VerificacionComprobante): string {
  const etiqueta: Record<VeredictoComprobante, string> = {
    COINCIDE: "COINCIDE con el pedido",
    REVISAR: "REVISAR manualmente",
    DUPLICADO: "POSIBLE DUPLICADO",
    ILEGIBLE: "NO SE PUDO LEER",
  };
  const problemas = v.checks.filter((c) => c.ok === false).map((c) => c.detalle);
  return [
    `Verificacion automatica del comprobante: ${etiqueta[v.veredicto]}.`,
    v.montoDetectado != null ? `Valor leido: ${formatoCop(v.montoDetectado)}.` : "",
    v.referencia ? `Referencia: ${v.referencia}.` : "",
    problemas.length ? `Alertas: ${problemas.join("; ")}.` : "",
    "Es una lectura automatica de la imagen: confirma el pago contra tu cuenta antes de aceptarlo.",
  ]
    .filter(Boolean)
    .join(" ");
}
