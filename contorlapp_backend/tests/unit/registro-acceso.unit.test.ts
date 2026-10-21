import { rutaParaLog } from "../../src/middlewares/access-log.middleware";

describe("registro de acceso", () => {
  test("enmascara cedulas, NIT, ids y quita la query", () => {
    expect(rutaParaLog({ originalUrl: "/gerente/operarios/1022334455/trasladar" })).toBe(
      "/gerente/operarios/:id/trasladar",
    );
    expect(rutaParaLog({ originalUrl: "/conjunto/conjuntos/900123456-7/necesidades/42" })).toBe(
      "/conjunto/conjuntos/:id/necesidades/42",
    );
    expect(
      rutaParaLog({ originalUrl: "/commerce/webhooks/factus-pay?key=llave-secreta" }),
    ).toBe("/commerce/webhooks/factus-pay");
    expect(rutaParaLog({ originalUrl: "/evidencias/1AbCdEfGhIjKlMnOpQrStUvWxYz012" })).toBe(
      "/evidencias/:id",
    );
  });

  test("enmascara ids largos de Drive aunque no tengan tres digitos seguidos", () => {
    expect(rutaParaLog({ originalUrl: "/evidencias/1AbCdEfGhIjKlMnOpQrStUvWxYz" })).toBe(
      "/evidencias/:id",
    );
  });

  test("conserva los segmentos de texto de la ruta", () => {
    expect(rutaParaLog({ originalUrl: "/auth/cambiar-contrasena-inicial" })).toBe(
      "/auth/cambiar-contrasena-inicial",
    );
    expect(rutaParaLog({ originalUrl: "/cronograma/conjuntos/x/excluidas-standby-detalle" })).toBe(
      "/cronograma/conjuntos/x/excluidas-standby-detalle",
    );
  });
});
