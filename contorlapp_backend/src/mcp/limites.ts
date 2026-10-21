// src/mcp/limites.ts
//
// Una IA puede llamar herramientas mucho mas rapido que una persona. Topes
// por conexion segun el riesgo, y uno diario por gerente para las
// escrituras (sume las conexiones que sume). Redis si esta configurado.
import { contarEnVentana } from "../middlewares/rate-limit.middleware";
import type { NivelRiesgo } from "./herramientas/tipos";

type Tope = { nombre: string; ventanaMs: number; maximo: number; descripcion: string };

const MINUTO = 60_000;
const DIA = 24 * 60 * MINUTO;

export const TOPES_POR_RIESGO: Record<NivelRiesgo, Tope[]> = {
  LECTURA: [{ nombre: "lecturas-min", ventanaMs: MINUTO, maximo: 120, descripcion: "120 consultas por minuto" }],
  ESCRITURA: [
    { nombre: "escrituras-min", ventanaMs: MINUTO, maximo: 20, descripcion: "20 cambios por minuto" },
    { nombre: "escrituras-dia", ventanaMs: DIA, maximo: 200, descripcion: "200 cambios por día" },
  ],
  ALTO_RIESGO: [{ nombre: "alto-riesgo-dia", ventanaMs: DIA, maximo: 20, descripcion: "20 operaciones de alto riesgo por día" }],
};

const TOPE_ESCRITURAS_GERENTE_DIA = 300;

export class ErrorLimite extends Error {
  status = 429;
  code = "LIMITE";
}

export async function verificarLimites(params: {
  riesgo: NivelRiesgo;
  conexionId: string;
  usuarioId: string;
}): Promise<void> {
  for (const tope of TOPES_POR_RIESGO[params.riesgo]) {
    const { count } = await contarEnVentana(`mcp:${tope.nombre}`, params.conexionId, tope.ventanaMs);
    if (count > tope.maximo) {
      throw new ErrorLimite(`Límite alcanzado (${tope.descripcion}). Espera un momento antes de seguir.`);
    }
  }
  if (params.riesgo !== "LECTURA") {
    const { count } = await contarEnVentana("mcp:escrituras-gerente-dia", params.usuarioId, DIA);
    if (count > TOPE_ESCRITURAS_GERENTE_DIA) {
      throw new ErrorLimite("Límite diario de cambios por IA alcanzado para tu cuenta. Continúa desde ControlApp.");
    }
  }
}
