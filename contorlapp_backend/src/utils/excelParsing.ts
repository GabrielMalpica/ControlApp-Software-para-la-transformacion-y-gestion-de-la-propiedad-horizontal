export function normalizeHeader(value: string): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "")
    .trim();
}

export function normalizeCell(value: unknown): string {
  if (value == null) return "";
  return String(value).trim();
}

export function normalizeLocationPart(
  value: string | null | undefined,
): string {
  return String(value ?? "").trim().replace(/\s+/g, " ");
}

export function mapExcelRow(
  row: Record<string, unknown>,
): Record<string, unknown> {
  const mapped: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(row)) {
    mapped[normalizeHeader(key)] = value;
  }
  return mapped;
}

export function normalizedLocationKey(...parts: string[]): string {
  return parts.map((part) => normalizeHeader(normalizeLocationPart(part))).join("/");
}
