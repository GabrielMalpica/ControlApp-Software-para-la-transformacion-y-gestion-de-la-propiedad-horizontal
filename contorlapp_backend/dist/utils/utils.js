"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.calcularDuracionMeses = calcularDuracionMeses;
function calcularDuracionMeses(inicio, fin) {
    if (!inicio || !fin)
        return null;
    const y = fin.getFullYear() - inicio.getFullYear();
    const m = fin.getMonth() - inicio.getMonth();
    const d = fin.getDate() - inicio.getDate();
    const total = y * 12 + m + (d >= 0 ? 0 : -1);
    return Math.max(total, 0);
}
