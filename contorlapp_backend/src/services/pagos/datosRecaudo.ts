import type { z } from "zod";
import type { FactusPayerSchema } from "./FactusPayClient";

type FactusPayer = z.infer<typeof FactusPayerSchema>;

/** Fecha ISO de Factus (`qr_expires_at`, `created_at`) o null si no es valida. */
export function fechaFactus(valor: string | null | undefined): Date | null {
  if (!valor) return null;
  const fecha = new Date(valor);
  return Number.isNaN(fecha.getTime()) ? null : fecha;
}

/**
 * Ultimos 4 caracteres del documento del pagador: alcanzan para que soporte
 * lo identifique sin guardar el numero completo (dato personal). Documentos
 * muy cortos no se guardan: 4 caracteres serian casi todo el numero.
 */
export function recortarDocumento(documento: string | null | undefined): string | null {
  const limpio = (documento ?? "").replace(/\s+/g, "");
  return limpio.length > 6 ? limpio.slice(-4) : null;
}

/** Columnas del pagador en PagoCobro; vacio si Factus no lo informo. */
export function datosPagador(payer: FactusPayer | null | undefined) {
  const nombre = payer?.name?.trim();
  if (!nombre) return {};
  return {
    pagadorNombre: nombre.slice(0, 200),
    pagadorTipoDocumento: payer?.document_type?.trim().slice(0, 20) || null,
    pagadorDocumentoUltimos4: recortarDocumento(payer?.document_number),
  };
}

/** El pagador tal como se puede guardar o mostrar (sin el documento completo). */
export function pagadorSaneado(payer: FactusPayer | null | undefined) {
  if (!payer) return null;
  return {
    name: payer.name?.slice(0, 200) ?? null,
    document_type: payer.document_type?.slice(0, 20) ?? null,
    document_number_ultimos4: recortarDocumento(payer.document_number),
  };
}
