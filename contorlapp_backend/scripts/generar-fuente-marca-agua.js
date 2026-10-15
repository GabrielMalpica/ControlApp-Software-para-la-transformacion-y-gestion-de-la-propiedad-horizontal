#!/usr/bin/env node
// Regenera src/utils/fuente_roboto_bold.ts a partir de assets/fonts/Roboto-Bold.ttf.
// La marca de agua de las evidencias usa la fuente desde ese módulo (en base64)
// para no depender de que el despliegue copie la carpeta assets.
//
// Uso, desde contorlapp_backend: node scripts/generar-fuente-marca-agua.js

const fs = require("fs");
const path = require("path");

const raiz = path.resolve(__dirname, "..");
const origen = path.join(raiz, "assets/fonts/Roboto-Bold.ttf");
const destino = path.join(raiz, "src/utils/fuente_roboto_bold.ts");

const base64 = fs.readFileSync(origen).toString("base64");
const lineas = base64.match(/.{1,100}/g).join("\n");

const contenido = `// Fuente Roboto Bold (Google, licencia Apache 2.0) de la marca de agua de las
// evidencias, en base64 dentro del código: así viaja en dist/ con cualquier
// forma de desplegar. Cuando se leía de assets/fonts, el Dockerfile no copiaba
// esa carpeta y producción subió las fotos sin marca (sin fecha ni dirección).
//
// Archivo generado: no editar a mano. Para regenerarlo desde
// assets/fonts/Roboto-Bold.ttf: node scripts/generar-fuente-marca-agua.js
//
// Los saltos de línea no estorban: Buffer.from(..., "base64") los ignora.
export const ROBOTO_BOLD_TTF_BASE64 = \`
${lineas}
\`;
`;

fs.writeFileSync(destino, contenido);
console.log(`[fuente-marca-agua] ${path.relative(raiz, destino)} (${base64.length} caracteres)`);
