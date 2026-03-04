"use strict";
function jsDayToISO(d) {
    // JS: 0=domingo..6=sábado -> ISO: 1=lunes..7=domingo
    if (d === 0)
        return 7;
    return d;
}
function startOfDayLocal(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
}
function endOfDayLocal(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}
function prevOrSameAllowedDay(date, allowed) {
    const cur = startOfDayLocal(date);
    for (let i = 0; i < 10; i++) {
        const iso = jsDayToISO(cur.getDay());
        if (allowed.has(iso))
            return cur;
        cur.setDate(cur.getDate() - 1);
    }
    return startOfDayLocal(date); // fallback
}
function nextOrSameAllowedDay(date, allowed) {
    const cur = startOfDayLocal(date);
    for (let i = 0; i < 10; i++) {
        const iso = jsDayToISO(cur.getDay());
        if (allowed.has(iso))
            return cur;
        cur.setDate(cur.getDate() + 1);
    }
    return startOfDayLocal(date); // fallback
}
function parseMaquinariaIds(maquinariaPlanJson) {
    if (!maquinariaPlanJson)
        return [];
    if (!Array.isArray(maquinariaPlanJson))
        return [];
    // soporta {maquinariaId} o {tipo} etc. Solo tomamos IDs numéricos
    return maquinariaPlanJson
        .map((x) => Number(x?.maquinariaId))
        .filter((n) => Number.isFinite(n) && n > 0);
}
function parseHerramientas(herramientasPlanJson) {
    if (!herramientasPlanJson)
        return [];
    if (!Array.isArray(herramientasPlanJson))
        return [];
    return herramientasPlanJson
        .map((x) => ({
        herramientaId: Number(x?.herramientaId),
        cantidad: Number(x?.cantidad ?? 1),
    }))
        .filter((h) => Number.isFinite(h.herramientaId) &&
        h.herramientaId > 0 &&
        Number.isFinite(h.cantidad) &&
        h.cantidad > 0);
}
