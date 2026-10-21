import { Rol, TipoPedidoApp, type PrismaClient } from "@prisma/client";
import { CommerceAccessService } from "./CommerceAccessService";
import { PermissionService } from "./PermissionService";
import { cacheGet, cacheSet } from "./RedisService";

/**
 * Quién pide el archivo: `req.user` (id y rol del token) más la empresa ya
 * contrastada con `empresaIdAutenticada`.
 */
export type ActorEvidencia = { id: string; rol: string; empresaId: string };

/**
 * Entidades que guardan el enlace de Drive de un archivo. Solo datos que no
 * cambian (la tarea no cambia de conjunto, el pedido no cambia de dueño), para
 * poder guardarlos en caché; lo que sí cambia (administrador del conjunto,
 * operarios de la tarea, permisos) se consulta en cada petición.
 */
export type DuenosEvidencia = {
  tareas: Array<{ id: number; conjuntoId: string | null }>;
  diagnosticos: Array<{ id: number; conjuntoId: string }>;
  pedidos: Array<{
    id: number;
    tipo: TipoPedidoApp;
    usuarioId: string;
    conjuntoId: string | null;
  }>;
};

type Cache = {
  get: <T>(key: string) => Promise<T | null>;
  set: (key: string, value: unknown, ttlSeconds: number) => Promise<void>;
};

type Opciones = {
  /** Permisos efectivos del rol en la empresa (por defecto, PermissionService con su caché). */
  permisos?: (empresaId: string, rol: string) => Promise<ReadonlySet<string>>;
  commerce?: CommerceAccessService;
  cache?: Cache;
  /** Cuánto se espera para juntar en una sola consulta los archivos pedidos a la vez. */
  ventanaLoteMs?: number;
};

export const MENSAJE_EVIDENCIA_NO_DISPONIBLE = "No se pudo obtener la evidencia.";

// Las vistas que muestran evidencias de tareas: Tareas, cronograma, reportes.
// "tareas.veredicto" y "tareas.editar_cierre" ya dan "tareas.ver"
// (PERMISSIONS_THAT_GRANT_ACCESS), así que también cubren a quien aprueba o
// corrige un cierre.
const PERMISOS_VER_TAREAS = ["tareas.ver", "cronograma.ver", "reportes.ver"];
const PERMISOS_PLAN_ESPERANZA = ["plan_esperanza.acceso"];
const PERMISOS_PEDIDOS = ["comercio.pedidos.ver"];

// Lo que se encuentra para un archivo casi nunca cambia: solo se pierde si se
// quita la evidencia, y entonces quien la veía igual tenía acceso a la tarea.
const TTL_DUENOS_S = 10 * 60;
// Un archivo sin dueño se recuerda poco: evita repetir la búsqueda (recorre
// las evidencias de todas las tareas) con cada reintento de la imagen. No
// estorba a una evidencia nueva: la app solo conoce su id cuando la tarea ya
// quedó guardada.
const TTL_SIN_DUENO_S = 60;
const MAX_LOTE = 100;
// Un archivo pertenece a una tarea (o a pocas, si se copió); el tope solo
// evita traer de más si algo raro coincide.
const MAX_FILAS_POR_ARCHIVO = 20;

function noDisponible(): Error & { status: number } {
  const error = new Error(MENSAJE_EVIDENCIA_NO_DISPONIBLE) as Error & { status: number };
  error.status = 404;
  return error;
}

function claveCache(fileId: string) {
  return `evidencia:duenos:v1:${fileId}`;
}

const ID_DRIVE_SUELTO = /^[a-zA-Z0-9_-]{20,}$/;
// Las mismas formas que reconocen `extraerDriveId` y la app (evidence_utils):
// /file/d/ID, ?id=ID (enlaces viejos uc?id=) y la ruta del proxy.
const IDS_DRIVE_EN_TEXTO = [
  /\/d\/([a-zA-Z0-9_-]{20,})/g,
  /[?&]id=([a-zA-Z0-9_-]{20,})/g,
  /\/evidencias\/([a-zA-Z0-9_-]{10,})/g,
];

/**
 * Todos los ids de Drive de un texto guardado. Un mismo texto puede traer
 * varios enlaces (la app también los separa), por eso no basta el primero.
 */
export function idsDriveEnTexto(raw: string | null | undefined): string[] {
  // Misma limpieza que normalizeEvidenceRaw de la app (JSON escapado, &amp;).
  const texto = String(raw ?? "")
    .trim()
    .replace(/^["']|["']$/g, "")
    .replace(/\\u003d/gi, "=")
    .replace(/\\u0026/gi, "&")
    .replace(/&amp;/g, "&")
    .replace(/\\\//g, "/");
  if (!texto) return [];
  if (ID_DRIVE_SUELTO.test(texto)) return [texto];
  const ids = new Set<string>();
  for (const patron of IDS_DRIVE_EN_TEXTO) {
    for (const m of texto.matchAll(patron)) ids.add(m[1]);
  }
  return [...ids];
}

/** Patrón LIKE que encuentra el id en cualquier parte del texto. */
function patronLike(fileId: string) {
  return `%${fileId.replace(/[\\%_]/g, "\\$&")}%`;
}

type Pendiente = {
  resolve: (duenos: DuenosEvidencia) => void;
  reject: (error: unknown) => void;
};

/**
 * Autoriza `GET /evidencias/:fileId`: el archivo se sirve solo si lo guarda
 * una entidad (tarea, diagnóstico del Plan Esperanza o comprobante de pago)
 * que el actor ya puede ver por su propia pantalla. Cualquier otro caso
 * -id desconocido, de otra entidad o documento de la página web, que tiene su
 * propia ruta con permiso- responde 404, sin confirmar que el archivo existe.
 */
export class EvidenciaAccesoService {
  private readonly permisos: (empresaId: string, rol: string) => Promise<ReadonlySet<string>>;
  private readonly commerce: CommerceAccessService;
  private readonly cache: Cache;
  private readonly ventanaLoteMs: number;

  private lote = new Map<string, Pendiente[]>();
  private temporizador: NodeJS.Timeout | null = null;

  constructor(
    private readonly prisma: PrismaClient,
    opciones: Opciones = {},
  ) {
    const permissionService = new PermissionService(prisma);
    this.permisos =
      opciones.permisos ??
      ((empresaId, rol) => permissionService.getEffectivePermissionsForRole(empresaId, rol));
    this.commerce = opciones.commerce ?? new CommerceAccessService(prisma);
    this.cache = opciones.cache ?? { get: cacheGet, set: cacheSet };
    this.ventanaLoteMs = opciones.ventanaLoteMs ?? 10;
  }

  /** Lanza 404 si el actor no puede ver el archivo. */
  async autorizar(fileId: string, actor: ActorEvidencia): Promise<void> {
    if (!actor.id || !actor.rol || !actor.empresaId) throw noDisponible();

    const duenos = await this.duenos(fileId);
    if (await this.puedeVerAlgunaTarea(duenos.tareas, actor)) return;
    if (await this.puedeVerAlgunDiagnostico(duenos.diagnosticos, actor)) return;
    if (await this.puedeVerAlgunPedido(duenos.pedidos, actor)) return;
    throw noDisponible();
  }

  /** Entidades que guardan el archivo (con caché compartida entre usuarios). */
  async duenos(fileId: string): Promise<DuenosEvidencia> {
    const clave = claveCache(fileId);
    const hit = await this.cache.get<DuenosEvidencia>(clave);
    if (hit) return hit;

    const encontrados = await this.buscarEnLote(fileId);
    const vacio =
      !encontrados.tareas.length &&
      !encontrados.diagnosticos.length &&
      !encontrados.pedidos.length;
    await this.cache.set(clave, encontrados, vacio ? TTL_SIN_DUENO_S : TTL_DUENOS_S);
    return encontrados;
  }

  // Una pantalla con muchas fotos pide todas casi a la vez. Buscar en las
  // evidencias de las tareas no tiene índice (recorre la tabla), así que los
  // archivos que llegan juntos se buscan en una sola consulta.
  private buscarEnLote(fileId: string): Promise<DuenosEvidencia> {
    return new Promise((resolve, reject) => {
      const esperando = this.lote.get(fileId);
      if (esperando) esperando.push({ resolve, reject });
      else this.lote.set(fileId, [{ resolve, reject }]);

      if (this.lote.size >= MAX_LOTE) {
        void this.procesarLote();
      } else if (!this.temporizador) {
        this.temporizador = setTimeout(() => void this.procesarLote(), this.ventanaLoteMs);
      }
    });
  }

  private async procesarLote() {
    if (this.temporizador) {
      clearTimeout(this.temporizador);
      this.temporizador = null;
    }
    const lote = this.lote;
    this.lote = new Map();
    if (!lote.size) return;

    try {
      const resultado = await this.buscarDuenos([...lote.keys()]);
      for (const [fileId, pendientes] of lote) {
        const duenos = resultado.get(fileId) ?? { tareas: [], diagnosticos: [], pedidos: [] };
        for (const p of pendientes) p.resolve(duenos);
      }
    } catch (error) {
      for (const pendientes of lote.values()) {
        for (const p of pendientes) p.reject(error);
      }
    }
  }

  /**
   * Busca los archivos en las tres entidades que guardan enlaces de Drive
   * servidos por `/evidencias/`. El filtro SQL solo preselecciona por texto;
   * la coincidencia exacta se comprueba con `idsDriveEnTexto`, así un id que
   * es parte de otro no cuenta.
   */
  private async buscarDuenos(fileIds: string[]): Promise<Map<string, DuenosEvidencia>> {
    const solicitados = new Set(fileIds);
    const resultado = new Map<string, DuenosEvidencia>();
    const de = (fileId: string) => {
      let d = resultado.get(fileId);
      if (!d) {
        d = { tareas: [], diagnosticos: [], pedidos: [] };
        resultado.set(fileId, d);
      }
      return d;
    };
    const limite = fileIds.length * MAX_FILAS_POR_ARCHIVO;

    const [tareas, diagnosticos, pedidos] = await Promise.all([
      this.prisma.$queryRaw<Array<{ id: number; conjuntoId: string | null; evidencias: string[] }>>`
        SELECT t."id", t."conjuntoId", t."evidencias"
        FROM "Tarea" t
        WHERE cardinality(t."evidencias") > 0
          AND array_to_string(t."evidencias", ' ') LIKE ANY (${fileIds.map(patronLike)}::text[])
        LIMIT ${limite}::int
      `,
      this.prisma.diagnosticoArea.findMany({
        where: { OR: fileIds.map((fileId) => ({ urlFoto: { contains: fileId } })) },
        select: { id: true, urlFoto: true, planEsperanza: { select: { conjuntoId: true } } },
        take: limite,
      }),
      this.prisma.pedidoApp.findMany({
        where: { OR: fileIds.map((fileId) => ({ comprobanteUrl: { contains: fileId } })) },
        select: { id: true, tipo: true, usuarioId: true, conjuntoId: true, comprobanteUrl: true },
        take: limite,
      }),
    ]);

    for (const t of tareas) {
      const ids = new Set((t.evidencias ?? []).flatMap((e) => idsDriveEnTexto(e)));
      for (const fileId of ids) {
        if (solicitados.has(fileId)) de(fileId).tareas.push({ id: t.id, conjuntoId: t.conjuntoId });
      }
    }
    for (const d of diagnosticos) {
      for (const fileId of idsDriveEnTexto(d.urlFoto)) {
        if (!solicitados.has(fileId)) continue;
        de(fileId).diagnosticos.push({ id: d.id, conjuntoId: d.planEsperanza.conjuntoId });
      }
    }
    for (const p of pedidos) {
      for (const fileId of idsDriveEnTexto(p.comprobanteUrl)) {
        if (!solicitados.has(fileId)) continue;
        de(fileId).pedidos.push({
          id: p.id,
          tipo: p.tipo,
          usuarioId: p.usuarioId,
          conjuntoId: p.conjuntoId,
        });
      }
    }
    return resultado;
  }

  private async tienePermiso(actor: ActorEvidencia, permisos: string[]) {
    const efectivos = await this.permisos(actor.empresaId, actor.rol);
    return PermissionService.hasAnyPermission(efectivos, permisos);
  }

  /**
   * Algún conjunto de la lista está en el alcance del actor: de su empresa y,
   * si es administrador, uno de los suyos (misma regla que requireConjuntoScope).
   */
  private async alcanzaConjunto(conjuntoIds: string[], actor: ActorEvidencia) {
    if (!conjuntoIds.length) return false;
    const conjunto = await this.prisma.conjunto.findFirst({
      where: {
        nit: { in: conjuntoIds },
        empresaId: actor.empresaId,
        ...(actor.rol === Rol.administrador ? { administradorId: actor.id } : {}),
      },
      select: { nit: true },
    });
    return Boolean(conjunto);
  }

  /**
   * Tareas: las mismas que el rol ya ve con sus evidencias.
   * - gerente, jefe de operaciones y supervisor: toda la empresa (el
   *   supervisor no tiene conjuntos asignados y el cronograma y los reportes
   *   le muestran todos los de la empresa);
   * - administrador: solo las de sus conjuntos;
   * - operario: solo las que tiene asignadas (su app no muestra otras);
   * - residente u otro rol: ninguna.
   */
  private async puedeVerAlgunaTarea(
    tareas: DuenosEvidencia["tareas"],
    actor: ActorEvidencia,
  ): Promise<boolean> {
    if (!tareas.length) return false;
    const permitidos: string[] = [
      Rol.gerente,
      Rol.jefe_operaciones,
      Rol.supervisor,
      Rol.administrador,
      Rol.operario,
    ];
    if (!permitidos.includes(actor.rol)) return false;
    if (!(await this.tienePermiso(actor, PERMISOS_VER_TAREAS))) return false;

    if (actor.rol === Rol.operario) {
      const asignada = await this.prisma.tarea.findFirst({
        where: {
          id: { in: tareas.map((t) => t.id) },
          conjunto: { empresaId: actor.empresaId },
          operarios: { some: { id: actor.id } },
        },
        select: { id: true },
      });
      return Boolean(asignada);
    }

    const conjuntos = tareas
      .map((t) => t.conjuntoId)
      .filter((nit): nit is string => !!nit);
    return this.alcanzaConjunto([...new Set(conjuntos)], actor);
  }

  /** Diagnósticos: el alcance del plan (permiso del Plan Esperanza + conjunto). */
  private async puedeVerAlgunDiagnostico(
    diagnosticos: DuenosEvidencia["diagnosticos"],
    actor: ActorEvidencia,
  ): Promise<boolean> {
    if (!diagnosticos.length || actor.rol === Rol.residente) return false;
    if (!(await this.tienePermiso(actor, PERMISOS_PLAN_ESPERANZA))) return false;
    return this.alcanzaConjunto([...new Set(diagnosticos.map((d) => d.conjuntoId))], actor);
  }

  /**
   * Comprobantes: la regla de `GET /commerce/pedidos/:id`. El residente solo
   * los de sus pedidos; administrador, gerente y jefe de operaciones con el
   * permiso de pedidos y acceso al conjunto (CommerceAccessService).
   */
  private async puedeVerAlgunPedido(
    pedidos: DuenosEvidencia["pedidos"],
    actor: ActorEvidencia,
  ): Promise<boolean> {
    if (!pedidos.length) return false;
    if (actor.rol !== Rol.residente && !(await this.tienePermiso(actor, PERMISOS_PEDIDOS))) {
      return false;
    }
    let commerceActor;
    try {
      commerceActor = await this.commerce.getActor(actor.id);
    } catch {
      return false;
    }
    for (const pedido of pedidos) {
      try {
        await this.commerce.assertPedidoAccess(commerceActor, pedido);
        return true;
      } catch {
        // Sin acceso a este pedido; se prueba el siguiente.
      }
    }
    return false;
  }
}
