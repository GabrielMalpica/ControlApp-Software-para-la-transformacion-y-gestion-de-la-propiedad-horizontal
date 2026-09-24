// Cola en memoria para generar los informes mensuales en segundo plano.
// El cliente pide el informe, recibe un jobId al instante y consulta el estado
// con peticiones cortas: ninguna conexion queda abierta esperando el PDF, asi
// que no hay timeout aunque la generacion tarde, y la cola limita cuantos PDF
// se arman a la vez para que varios usuarios no saturen el servidor.
import crypto from "crypto";
import fs from "fs";
import os from "os";
import path from "path";

export type EstadoJobInforme = "EN_COLA" | "GENERANDO" | "LISTO" | "ERROR";

export type JobInforme = {
  id: string;
  usuarioId: string;
  clave: string;
  estado: EstadoJobInforme;
  progreso: number;
  mensaje: string;
  error: string | null;
  archivo: string;
  nombreArchivo: string;
  creadoEn: number;
  terminadoEn: number | null;
};

export type ReportarProgreso = (porcentaje: number, mensaje: string) => void;

export type EjecutorInforme = (ctx: {
  archivoDestino: string;
  reportar: ReportarProgreso;
}) => Promise<{ nombreArchivo: string }>;

type HttpError = Error & { status: number };

function httpError(status: number, message: string): HttpError {
  const error = new Error(message) as HttpError;
  error.status = status;
  return error;
}

const MAX_SIMULTANEOS = Number(process.env.INFORME_PDF_MAX_SIMULTANEOS ?? 2);
const MAX_EN_COLA = 20;
const TTL_MS = 30 * 60 * 1000;
const LIMPIEZA_CADA_MS = 5 * 60 * 1000;
// Si una generacion se cuelga no debe bloquear al usuario ni un cupo de la cola.
const TIMEOUT_JOB_MS = 10 * 60 * 1000;

export class InformeMensualJobs {
  private jobs = new Map<string, JobInforme>();
  private ejecutores = new Map<string, EjecutorInforme>();
  private cola: string[] = [];
  private ejecutando = 0;
  private readonly carpeta: string;
  private temporizador: NodeJS.Timeout | null = null;

  constructor(carpeta = path.join(os.tmpdir(), "controlapp-informes")) {
    this.carpeta = carpeta;
  }

  private prepararCarpeta() {
    fs.mkdirSync(this.carpeta, { recursive: true });
    if (!this.temporizador) this.borrarHuerfanos();
    if (!this.temporizador) {
      this.temporizador = setInterval(() => this.limpiar(), LIMPIEZA_CADA_MS);
      // No debe mantener vivo el proceso (ni los tests).
      this.temporizador.unref();
    }
  }

  /** Restos de una ejecucion anterior del servidor (ya nadie los va a pedir). */
  private borrarHuerfanos() {
    try {
      for (const nombre of fs.readdirSync(this.carpeta)) {
        fs.unlink(path.join(this.carpeta, nombre), () => undefined);
      }
    } catch {
      // Best effort: la carpeta es temporal.
    }
  }

  private activoDelUsuario(usuarioId: string): JobInforme | undefined {
    for (const job of this.jobs.values()) {
      if (
        job.usuarioId === usuarioId &&
        (job.estado === "EN_COLA" || job.estado === "GENERANDO")
      ) {
        return job;
      }
    }
    return undefined;
  }

  /**
   * Encola un informe. Si el mismo usuario ya tiene uno igual en curso lo
   * reutiliza; si tiene otro distinto, pide esperar (un informe por usuario).
   */
  iniciar(params: {
    usuarioId: string;
    clave: string;
    ejecutar: EjecutorInforme;
  }): JobInforme {
    const activo = this.activoDelUsuario(params.usuarioId);
    if (activo) {
      if (activo.clave === params.clave) return activo;
      throw httpError(
        409,
        "Ya tienes un informe generándose. Espera a que termine para pedir otro.",
      );
    }
    if (this.cola.length >= MAX_EN_COLA) {
      throw httpError(
        429,
        "Hay muchos informes en proceso en este momento. Intenta de nuevo en unos minutos.",
      );
    }

    this.prepararCarpeta();
    const id = crypto.randomUUID();
    const job: JobInforme = {
      id,
      usuarioId: params.usuarioId,
      clave: params.clave,
      estado: "EN_COLA",
      progreso: 0,
      mensaje: "En cola",
      error: null,
      archivo: path.join(this.carpeta, `${id}.pdf`),
      nombreArchivo: "Informe_mensual.pdf",
      creadoEn: Date.now(),
      terminadoEn: null,
    };
    this.jobs.set(id, job);
    this.ejecutores.set(id, params.ejecutar);
    this.cola.push(id);
    this.avanzar();
    return job;
  }

  /** Devuelve el job solo si pertenece al usuario que lo consulta. */
  obtener(id: string, usuarioId: string): JobInforme | undefined {
    const job = this.jobs.get(id);
    if (!job || job.usuarioId !== usuarioId) return undefined;
    return job;
  }

  /** Posicion en la cola (1 = siguiente), o 0 si ya se esta generando. */
  posicionEnCola(id: string): number {
    const i = this.cola.indexOf(id);
    return i < 0 ? 0 : i + 1;
  }

  private avanzar() {
    while (this.ejecutando < MAX_SIMULTANEOS && this.cola.length > 0) {
      const id = this.cola.shift()!;
      const job = this.jobs.get(id);
      const ejecutor = this.ejecutores.get(id);
      if (!job || !ejecutor) continue;
      this.ejecutando += 1;
      void this.correr(job, ejecutor).finally(() => {
        this.ejecutando -= 1;
        this.ejecutores.delete(id);
        this.avanzar();
      });
    }
  }

  private async correr(job: JobInforme, ejecutor: EjecutorInforme) {
    job.estado = "GENERANDO";
    job.mensaje = "Preparando informe";
    job.progreso = 2;
    let corte: NodeJS.Timeout | undefined;
    try {
      const res = await Promise.race([
        ejecutor({
          archivoDestino: job.archivo,
          reportar: (porcentaje, mensaje) => {
            job.progreso = Math.max(
              job.progreso,
              Math.min(99, Math.round(porcentaje)),
            );
            job.mensaje = mensaje;
          },
        }),
        new Promise<never>((_, reject) => {
          corte = setTimeout(
            () => reject(new Error("Tiempo de generacion agotado")),
            TIMEOUT_JOB_MS,
          );
        }),
      ]);
      job.nombreArchivo = res.nombreArchivo;
      job.estado = "LISTO";
      job.progreso = 100;
      job.mensaje = "Informe listo";
    } catch (err) {
      console.error("[informe-mensual] error generando PDF:", err);
      job.estado = "ERROR";
      job.error =
        "No se pudo generar el informe. Intenta de nuevo en unos minutos.";
      job.mensaje = job.error;
      fs.promises.unlink(job.archivo).catch(() => undefined);
    } finally {
      if (corte) clearTimeout(corte);
      job.terminadoEn = Date.now();
    }
  }

  /** Borra jobs terminados hace mas del TTL junto con su archivo. */
  limpiar(ahora = Date.now()) {
    for (const [id, job] of this.jobs) {
      if (job.terminadoEn == null) continue;
      if (ahora - job.terminadoEn < TTL_MS) continue;
      this.jobs.delete(id);
      fs.promises.unlink(job.archivo).catch(() => undefined);
    }
  }
}

export const informeMensualJobs = new InformeMensualJobs();
