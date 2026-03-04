"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.decToNumber = exports.toDec = void 0;
const client_1 = require("@prisma/client");
const toDec = (n) => new client_1.Prisma.Decimal(n);
exports.toDec = toDec;
const decToNumber = (d) => {
    if (d && typeof d === "object" && typeof d.toNumber === "function")
        return d.toNumber();
    return Number(d);
};
exports.decToNumber = decToNumber;
