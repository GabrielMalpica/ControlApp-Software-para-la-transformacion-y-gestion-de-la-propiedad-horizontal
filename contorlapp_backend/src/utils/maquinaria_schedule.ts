type DiaPermitido = 1 | 3 | 6; // Lunes=1, Miércoles=3, Sábado=6

function jsDayToISO(d: number): 1 | 2 | 3 | 4 | 5 | 6 | 7 {
  // JS: 0=domingo..6=sábado -> ISO: 1=lunes..7=domingo
  if (d === 0) return 7;
  return d as any;
}

function startOfDayLocal(d: Date) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
}
function endOfDayLocal(d: Date) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

function prevOrSameAllowedDay(date: Date, allowed: Set<DiaPermitido>) {
  const cur = startOfDayLocal(date);
  for (let i = 0; i < 10; i++) {
    const iso = jsDayToISO(cur.getDay());
    if (allowed.has(iso as DiaPermitido)) return cur;
    cur.setDate(cur.getDate() - 1);
  }
  return startOfDayLocal(date); // fallback
}

function nextOrSameAllowedDay(date: Date, allowed: Set<DiaPermitido>) {
  const cur = startOfDayLocal(date);
  for (let i = 0; i < 10; i++) {
    const iso = jsDayToISO(cur.getDay());
    if (allowed.has(iso as DiaPermitido)) return cur;
    cur.setDate(cur.getDate() + 1);
  }
  return startOfDayLocal(date); // fallback
}

function parseMaquinariaIds(maquinariaPlanJson: any): number[] {
  if (!maquinariaPlanJson) return [];
  if (!Array.isArray(maquinariaPlanJson)) return [];

  // soporta {maquinariaId} o {tipo} etc. Solo tomamos IDs numéricos
  return maquinariaPlanJson
    .map((x: any) => Number(x?.maquinariaId))
    .filter((n: number) => Number.isFinite(n) && n > 0);
}

function parseHerramientas(
  herramientasPlanJson: any,
): Array<{ herramientaId: number; cantidad: number }> {
  if (!herramientasPlanJson) return [];
  if (!Array.isArray(herramientasPlanJson)) return [];

  return herramientasPlanJson
    .map((x: any) => ({
      herramientaId: Number(x?.herramientaId),
      cantidad: Number(x?.cantidad ?? 1),
    }))
    .filter(
      (h) =>
        Number.isFinite(h.herramientaId) &&
        h.herramientaId > 0 &&
        Number.isFinite(h.cantidad) &&
        h.cantidad > 0,
    );
}
