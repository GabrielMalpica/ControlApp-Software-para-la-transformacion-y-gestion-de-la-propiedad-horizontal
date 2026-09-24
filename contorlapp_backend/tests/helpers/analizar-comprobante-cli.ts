// Ejecuta analizarComprobante fuera de Jest. pdf.js (usado por pdf-parse)
// necesita import() dinamico, que Jest bloquea sin --experimental-vm-modules;
// en un proceso Node normal -como en produccion- funciona sin ajustes.
// Entrada: JSON por stdin { base64, mimeType, contexto }. Salida: JSON.
import { analizarComprobante, apagarWorkerOcr } from "../../src/services/ComprobanteOcrService";

async function main() {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  const entrada = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const contexto = { ...entrada.contexto, creadoEn: new Date(entrada.contexto.creadoEn), ahora: new Date(entrada.contexto.ahora) };
  const resultado = await analizarComprobante({
    buffer: Buffer.from(entrada.base64, "base64"),
    mimeType: entrada.mimeType,
    contexto,
  });
  await apagarWorkerOcr();
  process.stdout.write(`\n@@RESULTADO@@${JSON.stringify(resultado)}\n`);
}

void main();
