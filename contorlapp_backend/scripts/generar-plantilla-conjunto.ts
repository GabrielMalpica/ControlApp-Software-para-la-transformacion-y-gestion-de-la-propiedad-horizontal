import fs from "fs/promises";
import path from "path";

import { ConjuntoExcelTemplateService } from "../src/services/ConjuntoExcelTemplateService";

async function main() {
  const output = path.resolve(process.cwd(), "../docs/plantillas/plantilla_conjunto.xlsx");
  const buffer = await new ConjuntoExcelTemplateService().generar({
    insumos: [{ id: 1, nombre: "Insumo de ejemplo", unidad: "UNIDAD" }],
    herramientas: [{ id: 1, nombre: "Herramienta de ejemplo", unidad: "UNIDAD" }],
    supervisores: [{ id: "1000000000", nombre: "Supervisor de ejemplo" }],
  });
  await fs.writeFile(output, buffer);
}

void main();
