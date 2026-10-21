// src/mcp/referencias.ts
//
// Referencias opacas para personas. El id de un usuario en ControlApp es su
// cedula: por MCP nunca sale. Cada herramienta devuelve `op_...`/`sup_...`,
// cifrado (AES-256-GCM) y ligado a la conexion: una referencia copiada de
// otra conexion, alterada o inventada no resuelve.
//
// El IV se deriva del contenido con HMAC (estilo SIV): la misma persona da
// siempre la misma referencia dentro de una conexion, y personas distintas
// nunca comparten IV.
import { createCipheriv, createDecipheriv, createHmac } from "crypto";

export type TipoReferencia = "op" | "sup";

export class ErrorReferencia extends Error {
  status = 400;
  code = "REFERENCIA_INVALIDA";
}

export class Referencias {
  constructor(
    private readonly clave: Buffer,
    private readonly conexionId: string,
  ) {
    if (clave.length !== 32) throw new Error("La clave de referencias debe tener 32 bytes.");
  }

  private aad(tipo: TipoReferencia): Buffer {
    return Buffer.from(`${this.conexionId}|${tipo}`);
  }

  crear(tipo: TipoReferencia, id: string): string {
    const iv = createHmac("sha256", this.clave).update(`${this.conexionId}|${tipo}|${id}`).digest().subarray(0, 12);
    const cipher = createCipheriv("aes-256-gcm", this.clave, iv);
    cipher.setAAD(this.aad(tipo));
    const cifrado = Buffer.concat([cipher.update(id, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return `${tipo}_${Buffer.concat([iv, cifrado, tag]).toString("base64url")}`;
  }

  resolver(referencia: string, tipo: TipoReferencia): string {
    const prefijo = `${tipo}_`;
    if (typeof referencia !== "string" || !referencia.startsWith(prefijo)) {
      throw new ErrorReferencia(
        `Referencia inválida: se esperaba una referencia "${prefijo}..." obtenida de otra herramienta de ControlApp.`,
      );
    }
    const datos = Buffer.from(referencia.slice(prefijo.length), "base64url");
    if (datos.length < 12 + 1 + 16) throw new ErrorReferencia("Referencia inválida.");
    const iv = datos.subarray(0, 12);
    const tag = datos.subarray(datos.length - 16);
    const cifrado = datos.subarray(12, datos.length - 16);
    try {
      const decipher = createDecipheriv("aes-256-gcm", this.clave, iv);
      decipher.setAAD(this.aad(tipo));
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(cifrado), decipher.final()]).toString("utf8");
    } catch {
      throw new ErrorReferencia("Referencia inválida o de otra conexión.");
    }
  }
}
