import { prisma } from "../../db/prisma";
import { CommerceLifecycleService } from "../CommerceLifecycleService";
import { cacheGet, cacheSet } from "../RedisService";
import { listarCobrosFactus } from "./FactusPayClient";
import { PagoConciliacionService, type ReporteConciliacion } from "./PagoConciliacionService";
import { pagoService } from "./pagoServiceInstance";

const lifecycle = new CommerceLifecycleService(prisma);
const CLAVE_ULTIMO = "pagos:conciliacion:ultimo";

export const pagoConciliacion = new PagoConciliacionService(
  prisma,
  pagoService,
  listarCobrosFactus,
  (titulo, mensaje) => lifecycle.alertarConciliacion(titulo, mensaje),
);

/** Corre la conciliacion y guarda el reporte (7 dias) para consultarlo despues. */
export async function ejecutarConciliacion(): Promise<ReporteConciliacion> {
  const reporte = await pagoConciliacion.ejecutar();
  await cacheSet(CLAVE_ULTIMO, reporte, 7 * 24 * 3600);
  return reporte;
}

export async function ultimoReporteConciliacion(): Promise<ReporteConciliacion | null> {
  return cacheGet<ReporteConciliacion>(CLAVE_ULTIMO);
}

export async function fechaUltimaConciliacion(): Promise<Date | null> {
  const ultimo = await ultimoReporteConciliacion();
  return ultimo ? new Date(ultimo.ejecutadaEn) : null;
}
