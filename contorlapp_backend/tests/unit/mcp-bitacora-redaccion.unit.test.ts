import { redactar } from "../../src/mcp/bitacora";

describe("redacción de parámetros MCP", () => {
  test("no conserva las imágenes adjuntas en los parámetros auditados", () => {
    const parametros = {
      conjuntoId: "C-1",
      fotoBase64: "contenido-de-imagen-privado",
      diagnosticoId: 42,
    };

    expect(redactar(parametros)).toEqual({
      conjuntoId: "C-1",
      fotoBase64: "[redactado]",
      diagnosticoId: 42,
    });
  });
});
