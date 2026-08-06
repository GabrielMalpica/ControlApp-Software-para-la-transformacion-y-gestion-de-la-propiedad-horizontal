import { buildWooUrl, getWooBaseUrl, wooFetch } from "./wooFetch";

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
  stock_status?: string;
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
  };
};

type WooStoreProductsResponse = WooStoreProduct[];

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
  }

  private classifyProduct(product: {
    name: string;
    categories: Array<{ slug: string; name: string; link: string }>;
    tags: Array<{ slug: string }>;
    service: CommerceServiceConfig | null;
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

    const esServicio = product.service?.enabled ?? (hasServicioMatch || inferredService);

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
      purchasable: product.is_purchasable !== false,
      stockStatus: String(product.stock_status ?? "unknown").trim(),
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

    const categoriesUrl = this.buildStoreUrl("/products/categories", {
      per_page: 100,
    });

    const [productsRaw, categoriesRaw] = await Promise.all([
      this.fetchAllProducts(),
      this.fetchJson<Array<{ id?: number; name?: string; slug?: string }>>(categoriesUrl),
    ]);

    const normalized = productsRaw.map((item) => this.normalizeProduct(item));
    const filtered = this.applyFilters(normalized, filters);
    const total = filtered.length;
    const totalPages = Math.max(1, Math.ceil(total / perPage));
    const start = (page - 1) * perPage;
    const items = filtered.slice(start, start + perPage);

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
  }

  async getProduct(productId: number) {
    this.ensureConfigured();
    const url = this.buildStoreUrl(`/products/${productId}`);
    const product = await this.fetchJson<WooStoreProduct>(url);
    return this.normalizeProduct(product);
  }

  async getServiceAvailability(productId: number, date: string, slot?: string) {
    const url = buildWooUrl("plugin", `/services/${productId}/availability`, {
      date,
      slot,
    });
    return wooFetch<{
      date: string;
      slot: string | null;
      capacity: number;
      booked: number;
      remaining: number;
      available: boolean;
    }>(url, {}, {
      failureMessage: "No se pudo consultar la disponibilidad del servicio",
      mapConflict: true,
    });
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
