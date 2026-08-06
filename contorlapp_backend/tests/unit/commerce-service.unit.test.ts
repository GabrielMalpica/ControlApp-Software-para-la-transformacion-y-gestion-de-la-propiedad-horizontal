import {
  normalizeWooServiceConfig,
  type CommerceServiceConfig,
} from "../../src/services/WooCommerceCatalogService";
import {
  roundUpServicePayNow,
  validateAndPriceServiceSelection,
} from "../../src/services/CommerceOrderService";

const config: CommerceServiceConfig = {
  enabled: true,
  depositPct: 50,
  allowFull: true,
  minDays: 2,
  daysAllowed: [1, 2, 3, 4, 5],
  maxPerDay: 1,
  slots: [{ id: "am", label: "Medio dia (manana)", capacity: 2 }],
  showRange: false,
  range: { min: 0, max: 0 },
  addons: [
    {
      id: "tipo",
      label: "Tipo de servicio",
      type: "radio",
      required: true,
      group: [
        { id: 0, label: "Basico", price: 0 },
        { id: 1, label: "Profundo", price: 33500 },
      ],
    },
  ],
};

describe("configuracion de servicios de WooCommerce", () => {
  test("normaliza extensions.clx.clsr_config", () => {
    const parsed = normalizeWooServiceConfig({
      enabled: true,
      depositPct: 40,
      allowFull: false,
      minDays: 1,
      daysAllowed: [1, 6],
      maxPerDay: 3,
      slots: [{ id: "pm", label: "Tarde", capacity: 2 }],
      range: { min: 100000, max: 180000 },
      addons: [
        {
          id: "extras",
          label: "Extras",
          type: "checkbox",
          required: false,
          group: [{ id: 4, label: "Canaleta", price: 15000 }],
        },
      ],
    });

    expect(parsed).toEqual(
      expect.objectContaining({
        enabled: true,
        depositPct: 40,
        daysAllowed: [1, 6],
        slots: [{ id: "pm", label: "Tarde", capacity: 2 }],
      }),
    );
    expect(parsed?.addons[0].group[0].price).toBe(15000);
  });

  test("recalcula addons y redondea el anticipo hacia arriba a 1000", () => {
    const result = validateAndPriceServiceSelection(
      config,
      {
        date: "2026-08-10",
        slot: "am",
        payChoice: "deposit",
        addons: { tipo: [1] },
      },
      100000,
      1,
      "2026-08-05",
    );

    expect(result.unitPrice).toBe(133500);
    expect(result.service.addonsTotal).toBe(33500);
    expect(result.service.payNow).toBe(67000);
    expect(roundUpServicePayNow(66001)).toBe(67000);
  });

  test("rechaza fecha sin anticipacion, dia no permitido y addon obligatorio faltante", () => {
    expect(() =>
      validateAndPriceServiceSelection(
        config,
        {
          date: "2026-08-06",
          slot: "am",
          payChoice: "deposit",
          addons: { tipo: [0] },
        },
        100000,
        1,
        "2026-08-05",
      ),
    ).toThrow("anticipacion");

    expect(() =>
      validateAndPriceServiceSelection(
        config,
        {
          date: "2026-08-09",
          slot: "am",
          payChoice: "deposit",
          addons: { tipo: [0] },
        },
        100000,
        1,
        "2026-08-05",
      ),
    ).toThrow("dia de la semana");

    expect(() =>
      validateAndPriceServiceSelection(
        config,
        {
          date: "2026-08-10",
          slot: "am",
          payChoice: "deposit",
          addons: {},
        },
        100000,
        1,
        "2026-08-05",
      ),
    ).toThrow("Debes seleccionar");
  });
});
