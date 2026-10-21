// src/mcp/oauth/vistas.ts
//
// Pantallas del servidor de autorizacion: inicio de sesion con la cuenta de
// ControlApp y consentimiento. HTML sin JavaScript, con CSP estricta (ver
// cabecerasPagina en servidorAutorizacion.ts). Todo texto variable pasa por
// escaparHtml.
import { CATALOGO_SCOPES, type DefinicionScope } from "../scopes";

export function escaparHtml(valor: unknown): string {
  return String(valor ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const ESTILOS = `
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         background: #eef2f7; color: #1d2733; }
  main { max-width: 460px; margin: 40px auto; padding: 0 16px; }
  .tarjeta { background: #fff; border-radius: 14px; padding: 28px;
             box-shadow: 0 8px 24px rgba(15, 35, 60, 0.12); }
  h1 { font-size: 1.35rem; margin: 0 0 6px; }
  p { line-height: 1.45; }
  .sub { color: #52606d; margin: 0 0 18px; }
  label { display: block; font-weight: 600; margin: 14px 0 6px; }
  input[type=email], input[type=password] { width: 100%; padding: 11px 12px; border-radius: 9px;
         border: 1px solid #c3ccd6; font-size: 1rem; }
  .boton { display: inline-block; width: 100%; margin-top: 18px; padding: 12px; border: 0;
           border-radius: 9px; font-size: 1rem; font-weight: 600; cursor: pointer; }
  .primario { background: #1f6feb; color: #fff; }
  .secundario { background: #e3e8ee; color: #1d2733; }
  .error { background: #fde8e8; color: #9b1c1c; padding: 10px 12px; border-radius: 9px; }
  .aviso { background: #fff7e0; color: #6b4a00; padding: 10px 12px; border-radius: 9px; font-size: .92rem; }
  .cliente { font-weight: 700; }
  .host { font-family: ui-monospace, Consolas, monospace; background: #eef2f7; padding: 1px 6px; border-radius: 6px; }
  fieldset { border: 1px solid #d5dce4; border-radius: 10px; margin: 14px 0 0; padding: 6px 12px 12px; }
  legend { font-weight: 700; padding: 0 6px; }
  .permiso { display: flex; gap: 10px; align-items: flex-start; margin-top: 10px; font-weight: 400; }
  .permiso small { display: block; color: #52606d; }
  .riesgo { color: #9b1c1c; font-weight: 700; }
  footer { text-align: center; color: #7b8794; font-size: .85rem; margin-top: 16px; }
`;

function pagina(titulo: string, nonce: string, cuerpo: string): string {
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${escaparHtml(titulo)} · ControlApp</title>
<style nonce="${escaparHtml(nonce)}">${ESTILOS}</style>
</head>
<body><main><div class="tarjeta">${cuerpo}</div>
<footer>ControlApp · Integraciones de IA</footer></main></body>
</html>`;
}

export function vistaError(nonce: string, mensaje: string): string {
  return pagina(
    "No se pudo conectar",
    nonce,
    `<h1>No se pudo conectar</h1><p class="error">${escaparHtml(mensaje)}</p>
     <p class="sub">Puedes cerrar esta ventana y volver a intentarlo desde tu asistente de IA.</p>`,
  );
}

export function vistaLogin(params: {
  nonce: string;
  solicitudId: string;
  csrf: string;
  clienteNombre: string;
  redirectHost: string;
  correo?: string;
  error?: string;
}): string {
  return pagina(
    "Conectar con ControlApp",
    params.nonce,
    `<h1>Conectar con ControlApp</h1>
     <p class="sub"><span class="cliente">${escaparHtml(params.clienteNombre)}</span> quiere acceder a
       ControlApp en tu nombre. Volverá a <span class="host">${escaparHtml(params.redirectHost)}</span>.</p>
     <p class="aviso">Escribe tu contraseña solo aquí, en esta página de ControlApp. Nunca se la des al
       asistente de IA. Solo los gerentes habilitados pueden conectar una IA.</p>
     ${params.error ? `<p class="error">${escaparHtml(params.error)}</p>` : ""}
     <form method="post" action="/oauth/login" autocomplete="on">
       <input type="hidden" name="solicitud" value="${escaparHtml(params.solicitudId)}">
       <input type="hidden" name="csrf" value="${escaparHtml(params.csrf)}">
       <label for="correo">Correo</label>
       <input id="correo" name="correo" type="email" required autocomplete="username"
              value="${escaparHtml(params.correo ?? "")}">
       <label for="contrasena">Contraseña</label>
       <input id="contrasena" name="contrasena" type="password" required autocomplete="current-password">
       <button class="boton primario" type="submit">Iniciar sesión</button>
     </form>`,
  );
}

function filaPermiso(def: DefinicionScope, marcado: boolean): string {
  const riesgo =
    def.nivel === "alto_riesgo"
      ? ` <span class="riesgo">(alto riesgo)</span>`
      : def.nivel === "escritura"
        ? ` <span class="riesgo">(modifica datos)</span>`
        : "";
  return `<label class="permiso"><input type="checkbox" name="scope" value="${escaparHtml(def.scope)}"${
    marcado ? " checked" : ""
  }><span>${escaparHtml(def.titulo)}${riesgo}<small>${escaparHtml(def.descripcion)}</small></span></label>`;
}

export function vistaConsentimiento(params: {
  nonce: string;
  solicitudId: string;
  csrf: string;
  clienteNombre: string;
  redirectHost: string;
  nombreGerente: string;
  scopesSolicitados: string[];
}): string {
  const solicitados = new Set(params.scopesSolicitados);
  const grupos: Array<{ titulo: string; items: DefinicionScope[] }> = [
    { titulo: "Consultar", items: CATALOGO_SCOPES.filter((s) => s.nivel === "lectura") },
    { titulo: "Modificar", items: CATALOGO_SCOPES.filter((s) => s.nivel !== "lectura") },
  ];
  const secciones = grupos
    .map(
      (grupo) =>
        `<fieldset><legend>${escaparHtml(grupo.titulo)}</legend>${grupo.items
          .map((def) =>
            // Las lecturas pedidas vienen marcadas; lo que modifica datos solo
            // si el cliente lo pidio, y aun asi el gerente decide.
            filaPermiso(def, solicitados.has(def.scope)),
          )
          .join("")}</fieldset>`,
    )
    .join("");
  return pagina(
    "Autorizar acceso",
    params.nonce,
    `<h1>Autorizar a ${escaparHtml(params.clienteNombre)}</h1>
     <p class="sub">Hola, ${escaparHtml(params.nombreGerente)}. Elige qué podrá hacer en tu nombre. Podrás
       revocarlo cuando quieras en ControlApp → Configuración → Integraciones IA.</p>
     <p class="aviso">La IA nunca podrá eliminar información, cambiar permisos, ni ver cédulas, datos de salud,
       pagos o documentos. Las operaciones que cambian datos te pedirán confirmación, y las de alto riesgo
       también tu aprobación dentro de ControlApp.</p>
     <form method="post" action="/oauth/consentir">
       <input type="hidden" name="solicitud" value="${escaparHtml(params.solicitudId)}">
       <input type="hidden" name="csrf" value="${escaparHtml(params.csrf)}">
       ${secciones}
       <p class="sub">Volverá a <span class="host">${escaparHtml(params.redirectHost)}</span>.</p>
       <button class="boton primario" type="submit" name="decision" value="aprobar">Autorizar</button>
       <button class="boton secundario" type="submit" name="decision" value="rechazar">Cancelar</button>
     </form>`,
  );
}
