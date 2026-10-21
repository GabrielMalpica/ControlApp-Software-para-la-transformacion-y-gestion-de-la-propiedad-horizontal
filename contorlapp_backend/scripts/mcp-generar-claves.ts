// Genera los secretos del servicio MCP. Imprime las lineas para pegar en las
// variables de Railway del servicio controlapp-mcp (no se guardan en disco).
//   npm --prefix contorlapp_backend run mcp:claves
// Rotar la clave JWT invalida todos los access tokens (desconexion inmediata
// de los clientes de IA en cuanto venzan los que tengan en uso, <=10 min).
import { generateKeyPairSync, randomBytes } from "crypto";

const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString().trim();

console.log("# Variables del servicio controlapp-mcp (secretas, no las subas a git):");
console.log(`MCP_JWT_PRIVATE_KEY=${pem.replace(/\n/g, "\\n")}`);
console.log(`MCP_REF_KEY=${randomBytes(32).toString("base64")}`);
