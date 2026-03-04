"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.prisma = void 0;
// src/db/prisma.ts
const client_1 = require("@prisma/client");
exports.prisma = global.__prisma ?? new client_1.PrismaClient({ log: ["error"] });
if (process.env.NODE_ENV !== "production")
    global.__prisma = exports.prisma;
