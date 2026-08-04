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

function ensureNoTrailingSlash(value: string) {
  return value.endsWith("/") ? value.slice(0, -1) : value;
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
  private readonly baseUrl = ensureNoTrailingSlash(
    process.env.WOOCOMMERCE_BASE_URL?.trim() || process.env.ECOMMERCE_BASE_URL?.trim() || "",
  );

  private readonly residenteSlugs = parseCsvSet(process.env.WOO_RESIDENTE_SLUGS);
  private readonly conjuntoSlugs = parseCsvSet(process.env.WOO_CONJUNTO_SLUGS);
  private readonly servicioSlugs = parseCsvSet(process.env.WOO_SERVICIO_SLUGS);
  private readonly includeDrafts = parseBoolean(process.env.WOO_INCLUDE_NON_PUBLISHED, false);

  private ensureConfigured() {
    if (!this.baseUrl) {
      throw new Error(
        "Falta WOOCOMMERCE_BASE_URL en el backend para consultar el catalogo comercial",
      );
    }
  }

  private buildStoreUrl(path: string, query: Record<string, string | number | boolean | undefined> = {}) {
    const url = new URL(`${this.baseUrl}/wp-json/wc/store/v1${path}`);
    for (const [key, value] of Object.entries(query)) {
      if (value == null || value === "") continue;
      url.searchParams.set(key, String(value));
    }
    return url.toString();
  }

  private async fetchJson<T>(url: string) {
    const response = await fetch(url, {
      headers: {
        Accept: "application/json",
      },
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(
        `WooCommerce respondio ${response.status}. ${body || "No se pudo consultar el catalogo comercial"}`,
      );
    }

    return response.json() as Promise<T>;
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
  }) {
    const slugs = new Set([
      ...product.categories.map((item) => normalizeSlug(item.slug)),
      ...product.tags.map((item) => normalizeSlug(item.slug)),
    ]);

    const hasResidentMatch = [...this.residenteSlugs].some((slug) => slugs.has(slug));
    const hasConjuntoMatch = [...this.conjuntoSlugs].some((slug) => slugs.has(slug));
    const hasServicioMatch = [...this.servicioSlugs].some((slug) => slugs.has(slug));

    const hasAnyConfiguredAudienceMatch = hasResidentMatch || hasConjuntoMatch || hasServicioMatch;

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

    const esServicio = hasAnyConfiguredAudienceMatch ? hasServicioMatch : inferredService;

    return {
      paraResidente: true,
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
    const flags = this.classifyProduct({
      name: String(product.name ?? "").trim(),
      categories,
      tags,
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
      baseUrl: this.baseUrl,
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
}
