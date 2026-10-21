// Salvaguardas del catalogo MCP (docs/mcp/MCP_INTEGRATION_GUIDELINES.md):
// fallan si alguien agrega una herramienta prohibida, sin scope valido, con
// entrada abierta a campos extra, que llame a Prisma o services directamente,
// o un modulo nuevo sin decision MCP.
import { readdirSync, readFileSync } from "fs";
import { join } from "path";

jest.mock("../../src/db/prisma", () => ({ prisma: {} }));

import { DECISIONES_POR_MODULO, HERRAMIENTAS, PATRONES_PROHIBIDOS } from "../../src/mcp/catalogo";
import { OPERACIONES_CONFIRMABLES } from "../../src/mcp/operaciones";
import { esScopeValido } from "../../src/mcp/scopes";
import { PermissionService } from "../../src/services/PermissionService";

describe("catalogo de herramientas MCP", () => {
  test("nombres unicos en snake_case y ninguno prohibido", () => {
    const nombres = HERRAMIENTAS.map((h) => h.nombre);
    expect(new Set(nombres).size).toBe(nombres.length);
    for (const nombre of nombres) {
      expect(nombre).toMatch(/^[a-z]+(_[a-z0-9]+)*$/);
      for (const patron of PATRONES_PROHIBIDOS) {
        expect({ nombre, prohibido: patron.test(nombre) }).toEqual({ nombre, prohibido: false });
      }
    }
  });

  test("cada herramienta declara scope valido, riesgo y version", () => {
    for (const h of HERRAMIENTAS) {
      if (h.scope !== "") expect({ h: h.nombre, valido: esScopeValido(h.scope) }).toEqual({ h: h.nombre, valido: true });
      expect(["LECTURA", "ESCRITURA", "ALTO_RIESGO"]).toContain(h.riesgo);
      expect(h.version).toBeGreaterThanOrEqual(1);
      expect(h.descripcion.length).toBeGreaterThan(20);
    }
  });

  test("las herramientas con scope vacio son solo las de confirmaciones", () => {
    expect(HERRAMIENTAS.filter((h) => h.scope === "").map((h) => h.nombre).sort()).toEqual([
      "confirmar_operacion",
      "estado_confirmacion",
    ]);
  });

  test("toda entrada es un objeto estricto (rechaza campos no declarados)", () => {
    for (const h of HERRAMIENTAS) {
      const tipo = (h.entrada as any)._zod.def.catchall?._zod?.def?.type;
      expect({ h: h.nombre, estricto: tipo }).toEqual({ h: h.nombre, estricto: "never" });
    }
  });

  test("lo que no es lectura nunca se marca como solo lectura salvo las previsualizaciones", () => {
    for (const h of HERRAMIENTAS) {
      if (h.riesgo !== "LECTURA" && !h.nombre.startsWith("previsualizar_")) {
        expect({ h: h.nombre, lectura: false }).toEqual({ h: h.nombre, lectura: false });
      }
    }
    expect(HERRAMIENTAS.find((h) => h.nombre === "confirmar_operacion")?.destructiva).toBe(true);
  });

  test("las herramientas solo llaman casos de uso (sin Prisma ni services)", () => {
    const carpeta = join(__dirname, "../../src/mcp/herramientas");
    for (const archivo of readdirSync(carpeta).filter((f) => f.endsWith(".ts"))) {
      const fuente = readFileSync(join(carpeta, archivo), "utf8");
      expect({ archivo, prisma: /from "\.\.\/\.\.\/db\/prisma"/.test(fuente) }).toEqual({ archivo, prisma: false });
      expect({ archivo, services: /from "\.\.\/\.\.\/services\//.test(fuente) }).toEqual({ archivo, services: false });
      expect({ archivo, prismaCliente: /prisma\.\w+\.(find|create|update|delete)/.test(fuente) }).toEqual({
        archivo,
        prismaCliente: false,
      });
    }
  });

  test("cada operacion confirmable tiene scope valido y su previsualizacion", () => {
    for (const op of OPERACIONES_CONFIRMABLES.values()) {
      expect(esScopeValido(op.scope)).toBe(true);
    }
    expect(OPERACIONES_CONFIRMABLES.get("publicar_cronograma")?.requiereAprobacionHumana({} as never)).toBe(true);
  });

  test("todo modulo de permisos de la app tiene una decision MCP", () => {
    const modulos = new Set(PermissionService.catalog().map((p) => p.module));
    for (const modulo of modulos) {
      expect({ modulo, decidido: modulo in DECISIONES_POR_MODULO }).toEqual({ modulo, decidido: true });
    }
  });

  test("catalogo publicado (cambiarlo exige actualizar la guia)", () => {
    expect(HERRAMIENTAS.map((h) => `${h.nombre}|${h.scope || "-"}|${h.riesgo}`)).toMatchInlineSnapshot(`
[
  "listar_conjuntos|conjuntos:read|LECTURA",
  "obtener_conjunto|conjuntos:read|LECTURA",
  "listar_personal|personal:read|LECTURA",
  "consultar_plazas|personal:read|LECTURA",
  "listar_conceptos_asistencia|asistencia:read|LECTURA",
  "consultar_asistencia_dia|asistencia:read|LECTURA",
  "consultar_asistencia_mes|asistencia:read|LECTURA",
  "listar_tareas|tareas:read|LECTURA",
  "obtener_tarea|tareas:read|LECTURA",
  "consultar_inventario|inventario:read|LECTURA",
  "listar_insumos_bajos|inventario:read|LECTURA",
  "listar_maquinaria|recursos:read|LECTURA",
  "listar_solicitudes_insumos|solicitudes:read|LECTURA",
  "indicadores_tareas|reportes:read|LECTURA",
  "listar_compromisos|compromisos:read|LECTURA",
  "estado_cronograma|cronograma:read|LECTURA",
  "registrar_novedad_asistencia|asistencia:write|ESCRITURA",
  "registrar_movimiento_insumo|inventario:write|ESCRITURA",
  "crear_compromiso|compromisos:write|ESCRITURA",
  "previsualizar_traslado_operario|personal:write|ESCRITURA",
  "previsualizar_asignacion_plaza|personal:write|ESCRITURA",
  "previsualizar_liberar_plaza|personal:write|ESCRITURA",
  "previsualizar_crear_operarios|personal:write|ESCRITURA",
  "previsualizar_crear_conjunto|conjuntos:write|ESCRITURA",
  "previsualizar_publicar_cronograma|cronograma:publicar|ALTO_RIESGO",
  "confirmar_operacion|-|ESCRITURA",
  "estado_confirmacion|-|LECTURA",
]
`);
  });
});
