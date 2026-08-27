import { isTaskClosingRequest } from "../../src/middlewares/task-closing-rate-limit.middleware";

describe("rate limit dedicado al cierre de tareas", () => {
  test.each([
    "/supervisor/tareas/123/cerrar",
    "/supervisor/tareas/123/cerrar/",
    "/operario/operarios/45/tareas/123/cerrar",
  ])("identifica el endpoint de cierre %s", (path) => {
    expect(isTaskClosingRequest({ method: "POST", path })).toBe(true);
  });

  test.each([
    ["GET", "/supervisor/tareas/123/cerrar"],
    ["POST", "/supervisor/tareas/cerrar"],
    ["POST", "/supervisor/tareas/123/veredicto"],
    ["POST", "/operario/operarios/45/tareas/123/iniciar"],
    ["POST", "/commerce/pedidos"],
  ])("no excluye otros flujos: %s %s", (method, path) => {
    expect(isTaskClosingRequest({ method, path })).toBe(false);
  });
});
