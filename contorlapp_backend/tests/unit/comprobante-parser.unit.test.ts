import {
  coincideDestino,
  evaluarComprobante,
  extraerDatosComprobante,
  parseMontoCop,
  resumenVerificacion,
} from "../../src/utils/comprobanteParser";

// Textos con la forma que entrega el OCR de una captura de cada app.
const NEQUI = `Nequi
¡Listo! Tu envío quedó

Para

JUAN CARLOS PEREZ

Cuánto

$ 374.500

Fecha

24 de septiembre de 2026 a las 10:15 a. m.
Referencia

M4839201

Disponible $ 1.250.000`;

const NEQUI_UNA_LINEA = `Nequi
Enviaste $ 18.900 a MARIA LOPEZ
Fecha: 24 de septiembre de 2026 a las 03:45 p. m.
Referencia: M7788123
Disponible: $ 2.000.000`;

const BREB = `Transferencia exitosa
Bre-B
Valor: $374.500,00
Llave destino: 3001234567
Fecha: 24/09/2026 10:20 AM
Código de la transacción: 2026092410204512`;

const contexto = (overrides: Record<string, unknown> = {}) => ({
  metodoPago: "nequi",
  montosEsperados: [374500],
  creadoEn: new Date("2026-09-24T14:00:00Z"),
  ahora: new Date("2026-09-24T16:00:00Z"),
  destinosConfigurados: [] as string[],
  ...overrides,
});

describe("parseMontoCop", () => {
  test.each([
    ["50.000", 50000],
    ["$ 374.500", 374500],
    ["1.250.000", 1250000],
    ["$374.500,00", 374500],
    ["374,500.00", 374500],
    ["50000", 50000],
    ["18.900", 18900],
    ["12,50", 12.5],
  ])("%s -> %d", (entrada, esperado) => {
    expect(parseMontoCop(entrada)).toBe(esperado);
  });

  test("sin digitos devuelve null", () => {
    expect(parseMontoCop("abc")).toBeNull();
  });
});

describe("extraerDatosComprobante", () => {
  test("Nequi con etiquetas y valores en lineas separadas", () => {
    const r = extraerDatosComprobante(NEQUI);
    expect(r.monto).toBe(374500);
    expect(r.referencia).toBe("M4839201");
    expect(r.metodos).toEqual(["nequi"]);
    // 10:15 a. m. en Colombia (UTC-5) = 15:15 UTC.
    expect(r.fecha?.toISOString()).toBe("2026-09-24T15:15:00.000Z");
  });

  test("Nequi en una sola linea ignora el saldo disponible", () => {
    const r = extraerDatosComprobante(NEQUI_UNA_LINEA);
    expect(r.monto).toBe(18900);
    expect(r.referencia).toBe("M7788123");
    // 03:45 p. m. = 15:45 Bogota = 20:45 UTC.
    expect(r.fecha?.toISOString()).toBe("2026-09-24T20:45:00.000Z");
  });

  test("Bre-B: valor con decimales, codigo de transaccion y fecha dd/mm/aaaa", () => {
    const r = extraerDatosComprobante(BREB);
    expect(r.monto).toBe(374500);
    expect(r.referencia).toBe("2026092410204512");
    expect(r.metodos).toContain("bre_b");
    expect(r.fecha?.toISOString()).toBe("2026-09-24T15:20:00.000Z");
  });

  test.each([
    ["Número de aprobación: 884433221", "884433221"],
    ["ID de la transacción 55TT66YY77", "55TT66YY77"],
    ["Ref. 99887766", "99887766"],
  ])("referencia con etiqueta %s", (texto, esperado) => {
    expect(extraerDatosComprobante(texto).referencia).toBe(esperado);
  });

  test("una palabra sin digitos no cuenta como referencia", () => {
    expect(extraerDatosComprobante("Referencia: Transferencia").referencia).toBeNull();
  });

  test.each([
    ["Fecha: 5 sep 2026 8:05 pm", "2026-09-06T01:05:00.000Z"],
    ["2026-09-24 09:00", "2026-09-24T14:00:00.000Z"],
    ["Fecha 24 de septiembre de 2026", "2026-09-24T17:00:00.000Z"],
  ])("fecha %s", (texto, iso) => {
    expect(extraerDatosComprobante(texto).fecha?.toISOString()).toBe(iso);
  });

  test("texto sin datos no inventa nada", () => {
    const r = extraerDatosComprobante("hola mundo sin comprobante");
    expect(r).toEqual({ metodos: [], monto: null, referencia: null, fecha: null });
  });
});

describe("coincideDestino", () => {
  test("null cuando no hay destinos configurados", () => {
    expect(coincideDestino(BREB, [])).toBeNull();
  });

  test("celular completo, con espacios o enmascarado", () => {
    expect(coincideDestino("Para: 300 123 4567", ["3001234567"])).toBe(true);
    expect(coincideDestino("Para: *** *** 4567", ["3001234567"])).toBe(true);
    expect(coincideDestino("Para: 310 999 0000", ["3001234567"])).toBe(false);
  });

  test("llave alfanumerica", () => {
    expect(coincideDestino("Llave: @ControlSAS", ["@controlsas"])).toBe(true);
    expect(coincideDestino("Llave: @otro", ["@controlsas"])).toBe(false);
  });
});

describe("evaluarComprobante", () => {
  const evaluar = (texto: string, ctx = contexto(), motor: "ocr" | "pdf-texto" = "ocr") =>
    evaluarComprobante(texto, extraerDatosComprobante(texto), ctx, motor);

  test("Nequi correcto -> COINCIDE", () => {
    const v = evaluar(NEQUI);
    expect(v.veredicto).toBe("COINCIDE");
    expect(v.montoDetectado).toBe(374500);
    expect(v.referencia).toBe("M4839201");
  });

  test("Bre-B correcto con destino configurado -> COINCIDE", () => {
    const v = evaluar(
      BREB,
      contexto({ metodoPago: "bre_b", destinosConfigurados: ["3001234567"] }),
    );
    expect(v.veredicto).toBe("COINCIDE");
    expect(v.checks.find((c) => c.clave === "destino")?.ok).toBe(true);
  });

  test("monto distinto -> REVISAR con el detalle del desfase", () => {
    const v = evaluar(NEQUI, contexto({ montosEsperados: [400000] }));
    expect(v.veredicto).toBe("REVISAR");
    expect(v.checks.find((c) => c.clave === "monto")?.detalle).toContain("$400.000");
  });

  test("acepta cualquiera de los montos esperados (p. ej. total con descuento)", () => {
    const v = evaluar(NEQUI, contexto({ montosEsperados: [0, 400000, 374500] }));
    expect(v.veredicto).toBe("COINCIDE");
  });

  test("metodo declarado distinto al del comprobante -> REVISAR", () => {
    const v = evaluar(NEQUI, contexto({ metodoPago: "bre_b" }));
    expect(v.veredicto).toBe("REVISAR");
    expect(v.checks.find((c) => c.clave === "metodo")?.ok).toBe(false);
  });

  test("sin logo ni nombre de la app: el metodo queda sin evaluar, no en contra", () => {
    const v = evaluar(NEQUI.replace("Nequi\n", ""), contexto());
    expect(v.checks.find((c) => c.clave === "metodo")?.ok).toBeNull();
    expect(v.veredicto).toBe("COINCIDE");
  });

  test("destino visible pero distinto al del negocio -> REVISAR", () => {
    const v = evaluar(
      BREB,
      contexto({ metodoPago: "bre_b", destinosConfigurados: ["3109990000"] }),
    );
    expect(v.veredicto).toBe("REVISAR");
  });

  test("destino configurado pero el comprobante no muestra numero -> no penaliza", () => {
    const v = evaluar(NEQUI, contexto({ destinosConfigurados: ["3001234567"] }));
    expect(v.checks.find((c) => c.clave === "destino")?.ok).toBeNull();
    expect(v.veredicto).toBe("COINCIDE");
  });

  test("fecha muy anterior al pedido (comprobante viejo reutilizado) -> REVISAR", () => {
    const v = evaluar(
      NEQUI.replace("24 de septiembre", "2 de septiembre"),
      contexto(),
    );
    expect(v.veredicto).toBe("REVISAR");
    expect(v.checks.find((c) => c.clave === "fecha")?.ok).toBe(false);
  });

  test("fecha futura -> REVISAR", () => {
    const v = evaluar(NEQUI.replace("24 de septiembre", "30 de septiembre"), contexto());
    expect(v.checks.find((c) => c.clave === "fecha")?.ok).toBe(false);
  });

  test("pago hecho minutos antes de crear el pedido es valido", () => {
    const v = evaluar(
      NEQUI,
      contexto({ creadoEn: new Date("2026-09-24T15:30:00Z") }),
    );
    expect(v.checks.find((c) => c.clave === "fecha")?.ok).toBe(true);
  });

  test("referencia o archivo ya usados en otro pedido -> DUPLICADO", () => {
    const v = evaluar(NEQUI, contexto({ duplicadoDe: { pedidoId: 9, motivo: "referencia" } }));
    expect(v.veredicto).toBe("DUPLICADO");
    expect(v.checks.find((c) => c.clave === "duplicado")?.detalle).toContain("#9");
  });

  test("sin monto ni referencia -> ILEGIBLE", () => {
    const v = evaluar("imagen borrosa sin datos");
    expect(v.veredicto).toBe("ILEGIBLE");
  });

  test("sin referencia legible -> REVISAR aunque el valor coincida", () => {
    const v = evaluar("Nequi\nCuánto $ 374.500\nFecha 24/09/2026 10:15 AM");
    expect(v.veredicto).toBe("REVISAR");
  });

  test("el resumen para WooCommerce advierte que hay que confirmar contra la cuenta", () => {
    const texto = resumenVerificacion(evaluar(NEQUI));
    expect(texto).toContain("COINCIDE");
    expect(texto).toContain("M4839201");
    expect(texto).toContain("confirma el pago contra tu cuenta");
  });
});
