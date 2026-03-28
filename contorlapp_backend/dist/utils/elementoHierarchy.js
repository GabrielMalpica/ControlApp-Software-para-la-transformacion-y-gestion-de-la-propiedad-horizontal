"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.elementoParentChainInclude = exports.elementoTreeInclude = void 0;
exports.normalizarArbolElementos = normalizarArbolElementos;
exports.aplanarElementosHoja = aplanarElementosHoja;
exports.construirRutaElemento = construirRutaElemento;
exports.elementoTreeInclude = {
    hijos: {
        include: {
            hijos: {
                include: {
                    hijos: true,
                },
            },
        },
    },
};
exports.elementoParentChainInclude = {
    padre: {
        include: {
            padre: {
                include: {
                    padre: true,
                },
            },
        },
    },
};
function normalizarArbolElementos(elementos) {
    return [...elementos].sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
}
function aplanarElementosHoja(elementos, parentPath = []) {
    const out = [];
    for (const item of elementos) {
        const path = [...parentPath, item.nombre];
        const hijos = item.hijos ?? [];
        if (!hijos.length) {
            out.push({ ...item, ruta: path.join(" > ") });
            continue;
        }
        out.push(...aplanarElementosHoja(hijos, path));
    }
    return out;
}
function construirRutaElemento(elemento) {
    if (!elemento)
        return null;
    const names = [];
    let current = elemento;
    while (current) {
        names.unshift(String(current.nombre));
        current = current.padre ?? null;
    }
    return names.join(" > ");
}
