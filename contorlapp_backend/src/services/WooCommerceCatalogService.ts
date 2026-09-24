import { buildWooUrl, getWooBaseUrl, wooFetch } from "./wooFetch";
import { cached } from "./RedisService";

type ProductAudience = "todos" | "residente" | "conjunto" | "servicios";

type WooStoreCategory = {
  id?: number;
  name?: string;
  slug?: string;
  link?: string;
};

type WooStoreTag = {
  id?: number;
  name?: string;
  slug?: string;
};

type WooStoreImage = {
  id?: number;
  src?: string;
  thumbnail?: string;
  alt?: string;
};

type WooStorePriceBlock = {
  currency_code?: string;
  currency_symbol?: string;
  currency_minor_unit?: number;
  price?: string;
  regular_price?: string;
  sale_price?: string;
};

type WooStoreProduct = {
  id: number;
  name?: string;
  slug?: string;
  type?: string;
  sku?: string;
  short_description?: string;
  description?: string;
  permalink?: string;
  on_sale?: boolean;
  prices?: WooStorePriceBlock;
  is_in_stock?: boolean;
  is_on_backorder?: boolean;
  low_stock_remaining?: number | null;
  is_purchasable?: boolean;
  images?: WooStoreImage[];
  categories?: WooStoreCategory[];
  tags?: WooStoreTag[];
  average_rating?: string;
  review_count?: number;
  extensions?: {
    clx?: {
      clsr_config?: unknown;
    };
    clx_catalogo?: {
      only_conjunto?: boolean;
      only_public?: boolean;
      // Campos propios del plugin (formulario de producto en WordPress),
      // mismos 4 datos que pide el modal "Agregar insumo personalizado" de
      // ControlApp. Si se llenan, ControlApp puede crear/actualizar el
      // insumo correspondiente automaticamente -sin que nadie lo mapee a
      // mano la primera vez. Todos null/ausente = no declarado en Woo, en
      // cuyo caso se sigue usando el mapeo manual dentro de ControlApp.
      factor_inventario?: number | null;
      insumo_modo?: string | null;
      insumo_unidad?: string | null;
      insumo_contenido?: number | null;
      insumo_unidad_contenido?: string | null;
      insumo_categoria?: string | null;
      insumo_umbral?: number | null;
      // Producto variable por unidades: todas las variaciones suman al mismo insumo.
      insumo_compartido?: boolean;
    };
  };
};

type WooStoreProductsResponse = WooStoreProduct[];

// Woo REST v3 (no la Store API publica): unica forma de listar las
// variaciones reales (con su propio id, comprable via line_items.variation_id)
// de un producto variable. Requiere las credenciales de la tienda.
type WooRestVariation = {
  id: number;
  sku?: string;
  price?: string;
  regular_price?: string;
  sale_price?: string;
  on_sale?: boolean;
  purchasable?: boolean;
  stock_status?: string;
  attributes?: Array<{ name?: string; option?: string }>;
  image?: { src?: string } | null;
  // Inyectados por el plugin via woocommerce_rest_prepare_product_variation_object
  // (equivalente por-variacion de los 4 campos del producto padre; vacios =
  // se usan los del producto padre, ver normalizeVariation).
  clx_factor_inventario?: number | null;
  clx_insumo_modo?: string | null;
  clx_insumo_unidad?: string | null;
  clx_insumo_contenido?: number | null;
  clx_insumo_unidad_contenido?: string | null;
  clx_insumo_categoria?: string | null;
  clx_insumo_umbral?: number | null;
};

// Union deliberadamente amplia -en vez del enum de Prisma, para no acoplar
// este servicio (habla con WordPress) al cliente de Prisma- pero con los
// mismos 5 valores exactos que CategoriaInsumo. Validado/saneado en
// normalizeInsumoCategoria antes de usarse.
export type WooInsumoCategoria = "LIMPIEZA" | "JARDINERIA" | "PISCINA" | "FERRETERIA" | "OTROS";

function normalizeInsumoCategoria(raw: unknown): WooInsumoCategoria | null {
  const value = String(raw ?? "").trim().toUpperCase();
  const valid: WooInsumoCategoria[] = ["LIMPIEZA", "JARDINERIA", "PISCINA", "FERRETERIA", "OTROS"];
  return (valid as string[]).includes(value) ? (value as WooInsumoCategoria) : null;
}

// Igual que el modal "Agregar insumo personalizado" de la app:
//  - "unidad": se cuenta en piezas (escobas, pares, kits).
//  - "empaque": se cuenta en empaques (tarro, caja) que traen un contenido
//    medible (1,8 L, 500 g), que el inventario muestra como total.
export type WooInsumoModo = "unidad" | "empaque";

function normalizeInsumoModo(raw: unknown): WooInsumoModo | null {
  const value = String(raw ?? "").trim().toLowerCase();
  return value === "unidad" || value === "empaque" ? value : null;
}

function positiveNumber(raw: unknown): number | null {
  return typeof raw === "number" && Number.isFinite(raw) && raw > 0 ? raw : null;
}

export type WooInsumoConfig = {
  // null = no declarado en Woo (o producto de antes del selector de modo: se
  // interpreta como "unidad" si trae unidad, ver modoEfectivo).
  modo: WooInsumoModo | null;
  // Unidad de conteo ("unidad", "par") o nombre del empaque ("tarro", "caja").
  unidad: string | null;
  // Solo modo empaque: cuanto trae cada empaque y en que se mide.
  contenido: number | null;
  unidadContenido: string | null;
  categoria: WooInsumoCategoria | null;
  umbralBajo: number | null;
  // Cuantas unidades (o empaques) de inventario trae CADA unidad vendida en Woo.
  factorConversion: number | null;
  // Producto variable contado por unidades: todas las variaciones (ej. Sanitabs
  // de 30, 60 y 120 pastillas) suman al MISMO insumo, con el nombre del
  // producto y no el de cada variacion; cada variacion aporta su propio factor.
  // Las variaciones lo heredan del producto.
  compartido: boolean;
};

/** Modo con el que se creara el insumo: el declarado o, si solo hay unidad, "unidad". */
export function modoEfectivo(config: Pick<WooInsumoConfig, "modo" | "unidad">): WooInsumoModo | null {
  if (config.modo) return config.modo;
  return config.unidad ? "unidad" : null;
}

/**
 * ¿Woo declaro lo suficiente para crear el insumo sin que nadie lo mapee?
 * Por unidades basta la unidad; por empaques hacen falta ademas el contenido
 * (mayor a 0) y su unidad de medida.
 */
export function insumoDeclaradoCompleto(config: WooInsumoConfig): boolean {
  const modo = modoEfectivo(config);
  if (!modo || !config.unidad) return false;
  if (modo === "empaque") return config.contenido != null && config.contenido > 0 && !!config.unidadContenido;
  return true;
}

function normalizeSlug(value: string | null | undefined) {
  return String(value ?? "").trim().toLowerCase();
}

function parseCsvSet(raw: string | undefined) {
  return new Set(
    String(raw ?? "")
      .split(",")
      .map((item) => normalizeSlug(item))
      .filter(Boolean),
  );
}

function parseBoolean(raw: string | undefined, fallback: boolean) {
  if (raw == null || raw.trim() === "") return fallback;
  const normalized = raw.trim().toLowerCase();
  return ["1", "true", "si", "yes"].includes(normalized);
}

function stripHtml(value: string | null | undefined) {
  return String(value ?? "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function moneyToNumber(raw: string | undefined, minorUnit: number | undefined) {
  const clean = String(raw ?? "").trim();
  if (!clean) return 0;
  const parsed = Number(clean);
  if (Number.isNaN(parsed)) return 0;
  const safeMinorUnit = Number.isFinite(minorUnit) ? Number(minorUnit) : 0;
  const divisor = safeMinorUnit > 0 ? 10 ** safeMinorUnit : 1;
  return parsed / divisor;
}

// La REST v3 (variaciones) devuelve el precio como decimal "normal" (ej.
// "95400" o "10.50"), a diferencia de la Store API que lo entrega en unidad
// menor (centavos) + currency_minor_unit. Por eso no reutiliza moneyToNumber.
function restMoneyToNumber(raw: string | undefined) {
  const parsed = Number(String(raw ?? "").trim());
  return Number.isFinite(parsed) ? parsed : 0;
}

export type CommerceServiceSlot = { id: string; label: string; capacity: number };
export type CommerceAddonOption = { id: number; label: string; price: number };
export type CommerceAddonGroup = {
  id: string;
  label: string;
  type: "radio" | "checkbox";
  required: boolean;
  group: CommerceAddonOption[];
};
export type CommerceServiceConfig = {
  enabled: boolean;
  depositPct: number;
  allowFull: boolean;
  minDays: number;
  daysAllowed: number[];
  maxPerDay: number;
  slots: CommerceServiceSlot[];
  showRange: boolean;
  range: { min: number; max: number };
  addons: CommerceAddonGroup[];
};

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function safeNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function normalizeWooServiceConfig(raw: unknown): CommerceServiceConfig | null {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) return null;
  const value = asRecord(raw);
  const slots = (Array.isArray(value.slots) ? value.slots : [])
    .map((entry) => {
      const slot = asRecord(entry);
      return {
        id: normalizeSlug(String(slot.id ?? "")),
        label: String(slot.label ?? "").trim(),
        capacity: Math.max(1, Math.trunc(safeNumber(slot.capacity, 1))),
      };
    })
    .filter((slot) => slot.id !== "" && slot.label !== "");

  const addons = (Array.isArray(value.addons) ? value.addons : [])
    .map((entry) => {
      const addon = asRecord(entry);
      const optionsRaw = Array.isArray(addon.group)
        ? addon.group
        : Array.isArray(addon.options)
          ? addon.options
          : [];
      const group = optionsRaw
        .map((optionEntry, index) => {
          const option = asRecord(optionEntry);
          return {
            id: Math.trunc(safeNumber(option.id, index)),
            label: String(option.label ?? "").trim(),
            price: Math.max(0, safeNumber(option.price)),
          };
        })
        .filter((option) => option.label !== "");
      return {
        id: normalizeSlug(String(addon.id ?? addon.group_id ?? "")),
        label: String(addon.label ?? addon.title ?? "").trim(),
        type: addon.type === "checkbox" ? ("checkbox" as const) : ("radio" as const),
        required: addon.required === true,
        group,
      };
    })
    .filter((addon) => addon.id !== "" && addon.label !== "" && addon.group.length > 0);

  const range = asRecord(value.range);
  const daysAllowed = (Array.isArray(value.daysAllowed)
    ? value.daysAllowed
    : String(value.daysAllowed ?? "1,2,3,4,5,6,7").split(","))
    .map((day) => Math.trunc(safeNumber(day)))
    .filter((day) => day >= 1 && day <= 7);

  return {
    enabled: value.enabled === true,
    depositPct: Math.min(100, Math.max(1, safeNumber(value.depositPct, 50))),
    allowFull: value.allowFull === true,
    minDays: Math.max(0, Math.trunc(safeNumber(value.minDays))),
    daysAllowed: daysAllowed.length > 0 ? [...new Set(daysAllowed)] : [1, 2, 3, 4, 5, 6, 7],
    maxPerDay: Math.max(1, Math.trunc(safeNumber(value.maxPerDay, 1))),
    slots,
    showRange: value.showRange === true,
    range: {
      min: Math.max(0, safeNumber(range.min ?? value.rangeMin)),
      max: Math.max(0, safeNumber(range.max ?? value.rangeMax)),
    },
    addons,
  };
}

function buildSearchableText(product: {
  name: string;
  sku: string;
  categories: Array<{ name: string; slug: string }>;
  tags: Array<{ name: string; slug: string }>;
  shortDescription: string;
}) {
  return [
    product.name,
    product.sku,
    product.shortDescription,
    ...product.categories.flatMap((item) => [item.name, item.slug]),
    ...product.tags.flatMap((item) => [item.name, item.slug]),
  ]
    .join(" ")
    .toLowerCase();
}

export class WooCommerceCatalogService {
  private readonly residenteSlugs = parseCsvSet(process.env.WOO_RESIDENTE_SLUGS);
  private readonly conjuntoSlugs = parseCsvSet(process.env.WOO_CONJUNTO_SLUGS);
  private readonly servicioSlugs = parseCsvSet(process.env.WOO_SERVICIO_SLUGS);
  private readonly includeDrafts = parseBoolean(process.env.WOO_INCLUDE_NON_PUBLISHED, false);

  private ensureConfigured() {
    getWooBaseUrl();
  }

  private buildStoreUrl(path: string, query: Record<string, string | number | boolean | undefined> = {}) {
    return buildWooUrl("store", path, query);
  }

  private async fetchJson<T>(url: string) {
    return wooFetch<T>(url, {}, {
      failureMessage: "No se pudo consultar el catalogo comercial. Intenta nuevamente",
    });
  }

  private async fetchAllProducts() {
    return cached("commerce:catalogo:productos:v1", 60, async () => {
      const all: WooStoreProduct[] = [];
      let page = 1;
      const perPage = 100;

      while (true) {
        const url = this.buildStoreUrl("/products", {
          page,
          per_page: perPage,
        });
        const chunk = await this.fetchJson<WooStoreProductsResponse>(url);
        all.push(...chunk);
        if (chunk.length < perPage) break;
        page += 1;
        if (page > 50) break;
      }

      return all;
    });
  }

  private classifyProduct(product: {
    name: string;
    categories: Array<{ slug: string; name: string; link: string }>;
    tags: Array<{ slug: string }>;
    service: CommerceServiceConfig | null;
    onlyConjunto: boolean;
    onlyPublic: boolean;
  }) {
    const slugs = new Set([
      ...product.categories.map((item) => normalizeSlug(item.slug)),
      ...product.tags.map((item) => normalizeSlug(item.slug)),
    ]);

    const hasResidentMatch = [...this.residenteSlugs].some((slug) => slugs.has(slug));
    const hasConjuntoMatch = [...this.conjuntoSlugs].some((slug) => slugs.has(slug));
    const hasServicioMatch = [...this.servicioSlugs].some((slug) => slugs.has(slug));

    const hasAnyConfiguredAudienceMatch = hasResidentMatch || hasConjuntoMatch;

    const inferredService =
      product.name.trim().toLowerCase().startsWith("servicio") ||
      product.categories.some((item) => {
        const categoryName = item.name.trim().toLowerCase();
        const categoryLink = item.link.trim().toLowerCase();
        return (
          categoryName.includes("servicio") ||
          categoryLink.includes("/servicios/") ||
          categoryLink.includes("categoria-producto/servicios")
        );
      });

    // "service.enabled" indica si el producto usa el widget de RESERVA (fecha
    // + turno), no si es o no un servicio. Un servicio "de cotizar" (sin
    // calendario) trae service.enabled=false explicito, y con "??" ese false
    // saltaba el respaldo por categoria/nombre (?? solo cae en null/undefined,
    // no en false), clasificandolo como si fuera un insumo. Por eso solo se
    // usa como override cuando es true; en cualquier otro caso manda la
    // categoria/nombre.
    const esServicio =
      product.service?.enabled === true || hasServicioMatch || inferredService;

    // El checkbox "Solo Conjuntos" / "Solo Público" del plugin de WooCommerce
    // es la forma en que el equipo realmente clasifica los productos desde el
    // admin. Cuando esta presente manda sobre las categorias/tags, que quedan
    // como respaldo para productos que nunca se marcaron con el checkbox.
    if (product.onlyConjunto) {
      return { paraResidente: false, paraConjunto: true, esServicio };
    }
    if (product.onlyPublic) {
      return { paraResidente: true, paraConjunto: false, esServicio };
    }

    return {
      paraResidente: hasAnyConfiguredAudienceMatch ? hasResidentMatch : true,
      paraConjunto: hasAnyConfiguredAudienceMatch ? hasConjuntoMatch : !esServicio,
      esServicio,
    };
  }

  private normalizeProduct(product: WooStoreProduct) {
    const categories = (product.categories ?? []).map((item) => ({
      id: Number(item.id ?? 0),
      name: String(item.name ?? "").trim(),
      slug: normalizeSlug(item.slug),
      link: String(item.link ?? "").trim(),
    }));
    const tags = (product.tags ?? []).map((item) => ({
      id: Number(item.id ?? 0),
      name: String(item.name ?? "").trim(),
      slug: normalizeSlug(item.slug),
    }));
    const shortDescription = stripHtml(product.short_description);
    const description = stripHtml(product.description);
    const service = normalizeWooServiceConfig(product.extensions?.clx?.clsr_config);
    const flags = this.classifyProduct({
      name: String(product.name ?? "").trim(),
      categories,
      tags,
      service,
      onlyConjunto: product.extensions?.clx_catalogo?.only_conjunto === true,
      onlyPublic: product.extensions?.clx_catalogo?.only_public === true,
    });

    return {
      id: product.id,
      name: String(product.name ?? "").trim(),
      slug: normalizeSlug(product.slug),
      type: String(product.type ?? "simple").trim(),
      sku: String(product.sku ?? "").trim(),
      shortDescription,
      description,
      permalink: String(product.permalink ?? "").trim(),
      onSale: product.on_sale === true,
      // La Store API de Woo no expone "stock_status" (ese campo es de la REST
      // API v3); expone is_in_stock/is_on_backorder. Ademas "is_purchasable"
      // refleja restricciones de la vitrina publica (p.ej. modo catalogo o
      // "solicitar cotizacion") que no aplican a esta app: los pedidos se
      // crean por REST v3 con credenciales propias, no por el carrito publico.
      // Por eso la disponibilidad se calcula solo a partir del stock real.
      purchasable: product.is_on_backorder === true || product.is_in_stock !== false,
      stockStatus:
        product.is_on_backorder === true
          ? "onbackorder"
          : product.is_in_stock === false
            ? "outofstock"
            : "instock",
      lowStockRemaining:
        typeof product.low_stock_remaining === "number" ? product.low_stock_remaining : null,
      price: {
        currencyCode: String(product.prices?.currency_code ?? "COP").trim(),
        currencySymbol: String(product.prices?.currency_symbol ?? "$"),
        current: moneyToNumber(product.prices?.price, product.prices?.currency_minor_unit as number | undefined),
        regular: moneyToNumber(product.prices?.regular_price, product.prices?.currency_minor_unit as number | undefined),
        sale: moneyToNumber(product.prices?.sale_price, product.prices?.currency_minor_unit as number | undefined),
      },
      images: (product.images ?? []).map((image) => ({
        id: Number(image.id ?? 0),
        src: String(image.src ?? "").trim(),
        thumbnail: String(image.thumbnail ?? image.src ?? "").trim(),
        alt: String(image.alt ?? "").trim(),
      })),
      categories,
      tags,
      averageRating: Number(product.average_rating ?? 0),
      reviewCount: Number(product.review_count ?? 0),
      audience: flags,
      service,
      searchableText: "",
      source: "woo_store_api",
      insumoConfig: {
        modo: normalizeInsumoModo(product.extensions?.clx_catalogo?.insumo_modo),
        unidad: product.extensions?.clx_catalogo?.insumo_unidad?.trim() || null,
        contenido: positiveNumber(product.extensions?.clx_catalogo?.insumo_contenido),
        unidadContenido: product.extensions?.clx_catalogo?.insumo_unidad_contenido?.trim() || null,
        categoria: normalizeInsumoCategoria(product.extensions?.clx_catalogo?.insumo_categoria),
        compartido: product.extensions?.clx_catalogo?.insumo_compartido === true,
        umbralBajo:
          typeof product.extensions?.clx_catalogo?.insumo_umbral === "number"
            ? product.extensions.clx_catalogo.insumo_umbral
            : null,
        factorConversion:
          typeof product.extensions?.clx_catalogo?.factor_inventario === "number"
            ? product.extensions.clx_catalogo.factor_inventario
            : null,
      } satisfies WooInsumoConfig,
    };
  }

  private applyFilters(
    products: ReturnType<WooCommerceCatalogService["normalizeProduct"]>[],
    filters: {
      q?: string;
      target?: ProductAudience;
      category?: string;
    },
  ) {
    const q = String(filters.q ?? "").trim().toLowerCase();
    const category = normalizeSlug(filters.category);
    const target = filters.target ?? "todos";

    return products.filter((product) => {
      if (target === "residente" && !product.audience.paraResidente) return false;
      if (target === "conjunto" && !product.audience.paraConjunto) return false;
      if (target === "servicios" && !product.audience.esServicio) return false;
      if (category && !product.categories.some((item) => item.slug === category)) return false;
      if (q) {
        const searchableText = buildSearchableText(product);
        if (!searchableText.includes(q)) return false;
      }
      return true;
    });
  }

  async listCatalog(filters: {
    q?: string;
    target?: ProductAudience;
    category?: string;
    page?: number;
    perPage?: number;
  }) {
    this.ensureConfigured();

    const page = Math.max(1, Number(filters.page ?? 1));
    const perPage = Math.min(100, Math.max(1, Number(filters.perPage ?? 24)));
    const cacheKey = `commerce:catalogo:listado:v1:${encodeURIComponent(
      JSON.stringify({
        q: String(filters.q ?? "").trim().toLowerCase(),
        target: filters.target ?? "todos",
        category: normalizeSlug(filters.category),
        page,
        perPage,
      }),
    )}`;

    return cached(cacheKey, 60, async () => {

    const categoriesUrl = this.buildStoreUrl("/products/categories", {
      per_page: 100,
    });

    const [productsRaw, categoriesRaw] = await Promise.all([
      this.fetchAllProducts(),
      cached("commerce:catalogo:categorias:v1", 60, () =>
        this.fetchJson<Array<{ id?: number; name?: string; slug?: string }>>(categoriesUrl),
      ),
    ]);

    const normalized = productsRaw.map((item) => this.normalizeProduct(item));
    const filtered = this.applyFilters(normalized, filters);
    // A los conjuntos se les quiere vender insumos antes que servicios: los
    // insumos van primero. Woo devuelve todo por fecha de creacion, y como
    // los servicios se cargaron despues, sin este orden explicito quedaban
    // todos antes que los insumos (y estos ni siquiera entraban en la
    // primera pagina del catalogo). Sort estable: no altera el orden dentro
    // de cada grupo.
    const sorted = [...filtered].sort(
      (a, b) => Number(a.audience.esServicio) - Number(b.audience.esServicio),
    );
    const total = sorted.length;
    const totalPages = Math.max(1, Math.ceil(total / perPage));
    const start = (page - 1) * perPage;
    const items = sorted.slice(start, start + perPage);

    const categoryMap = new Map<string, { id: number; name: string; slug: string }>();
    for (const raw of categoriesRaw) {
      const slug = normalizeSlug(raw.slug);
      if (!slug) continue;
      categoryMap.set(slug, {
        id: Number(raw.id ?? 0),
        name: String(raw.name ?? "").trim(),
        slug,
      });
    }

    return {
      source: "woo_store_api",
      baseUrl: getWooBaseUrl(),
      target: filters.target ?? "todos",
      pagination: {
        page,
        perPage,
        total,
        totalPages,
      },
      filters: {
        q: String(filters.q ?? "").trim(),
        category: normalizeSlug(filters.category),
      },
      categories: [...categoryMap.values()].sort((a, b) => a.name.localeCompare(b.name)),
      items,
    };
    });
  }

  private normalizeVariation(variation: WooRestVariation, currencyCode: string) {
    const optionLabel = (variation.attributes ?? [])
      .map((attr) => String(attr.option ?? "").trim())
      .filter(Boolean)
      .join(" / ");
    const regular = restMoneyToNumber(variation.regular_price ?? variation.price);
    const current = restMoneyToNumber(variation.price);
    return {
      id: variation.id,
      label: optionLabel || `#${variation.id}`,
      sku: String(variation.sku ?? "").trim(),
      purchasable: variation.purchasable !== false && variation.stock_status !== "outofstock",
      stockStatus: variation.stock_status ?? "instock",
      price: {
        currencyCode,
        current,
        regular,
        sale: variation.on_sale ? restMoneyToNumber(variation.sale_price) : current,
      },
      image: variation.image?.src ? String(variation.image.src).trim() : "",
      // Sin fallback al producto padre todavia -eso pasa en getProduct(),
      // que es quien tiene ambos objetos disponibles para mezclarlos.
      insumoConfig: {
        modo: normalizeInsumoModo(variation.clx_insumo_modo),
        unidad: variation.clx_insumo_unidad?.trim() || null,
        contenido: positiveNumber(variation.clx_insumo_contenido),
        unidadContenido: variation.clx_insumo_unidad_contenido?.trim() || null,
        categoria: normalizeInsumoCategoria(variation.clx_insumo_categoria),
        compartido: false, // se hereda del producto en getProduct()
        umbralBajo: typeof variation.clx_insumo_umbral === "number" ? variation.clx_insumo_umbral : null,
        factorConversion:
          typeof variation.clx_factor_inventario === "number" ? variation.clx_factor_inventario : null,
      } satisfies WooInsumoConfig,
    };
  }

  /**
   * Variaciones reales de un producto variable (Woo REST v3, autenticado).
   * Cada una tiene su propio id, comprable via line_items.variation_id -no
   * confundir con los atributos que trae la Store API publica, que solo
   * listan las opciones, no las combinaciones vendibles ni sus precios.
   */
  async getProductVariations(productId: number, currencyCode = "COP") {
    this.ensureConfigured();
    const url = buildWooUrl("rest", `/products/${productId}/variations`, { per_page: 100 });
    return cached(`commerce:catalogo:variaciones:v1:${productId}`, 60, async () => {
      const raw = await wooFetch<WooRestVariation[]>(
        url,
        {},
        {
          requireAuth: true,
          failureMessage: "No se pudieron consultar las variaciones de este producto",
        },
      );
      return raw.map((variation) => this.normalizeVariation(variation, currencyCode));
    });
  }

  async getProduct(productId: number) {
    this.ensureConfigured();
    const url = this.buildStoreUrl(`/products/${productId}`);
    return cached(`commerce:catalogo:producto:v1:${productId}`, 60, async () => {
      const product = await this.fetchJson<WooStoreProduct>(url);
      const normalized = this.normalizeProduct(product);
      if (normalized.type === "simple") {
        return { ...normalized, variations: [] as ReturnType<WooCommerceCatalogService["normalizeVariation"]>[] };
      }
      const rawVariations = await this.getProductVariations(productId, normalized.price.currencyCode);
      // Cada campo vacio en la variacion cae al del producto padre (ej. si
      // solo el padre declaro "categoria", todas las variaciones la heredan
      // salvo que alguna la sobrescriba puntualmente).
      const variations = rawVariations.map((variation) => ({
        ...variation,
        insumoConfig: {
          compartido: normalized.insumoConfig.compartido,
          modo: variation.insumoConfig.modo ?? normalized.insumoConfig.modo,
          contenido: variation.insumoConfig.contenido ?? normalized.insumoConfig.contenido,
          unidadContenido: variation.insumoConfig.unidadContenido ?? normalized.insumoConfig.unidadContenido,
          unidad: variation.insumoConfig.unidad ?? normalized.insumoConfig.unidad,
          categoria: variation.insumoConfig.categoria ?? normalized.insumoConfig.categoria,
          umbralBajo: variation.insumoConfig.umbralBajo ?? normalized.insumoConfig.umbralBajo,
          factorConversion: variation.insumoConfig.factorConversion ?? normalized.insumoConfig.factorConversion,
        } satisfies WooInsumoConfig,
      }));
      return { ...normalized, variations };
    });
  }

  async getServiceAvailability(productId: number, date: string, slot?: string) {
    const url = buildWooUrl("plugin", `/services/${productId}/availability`, {
      date,
      slot,
    });
    return cached(`commerce:disponibilidad:v1:${productId}:${date}:${slot ?? "todos"}`, 30, () => wooFetch<{
      date: string;
      slot: string | null;
      capacity: number;
      booked: number;
      remaining: number;
      available: boolean;
    }>(url, {}, {
      failureMessage: "No se pudo consultar la disponibilidad del servicio",
      mapConflict: true,
    }));
  }

  async claimServiceAvailability(
    productId: number,
    selection: { date: string; slot: string; quantity: number },
  ) {
    const url = buildWooUrl("plugin", `/services/${productId}/claim`);
    return wooFetch<{
      token: string;
      date: string;
      slot: string;
      capacity: number;
      booked: number;
      remaining: number;
      available: boolean;
      expiresAt: string;
    }>(
      url,
      {
        method: "POST",
        body: JSON.stringify(selection),
      },
      {
        requireAuth: true,
        mapConflict: true,
        failureMessage: "No se pudo reservar el cupo del servicio. Intenta nuevamente",
      },
    );
  }
}
