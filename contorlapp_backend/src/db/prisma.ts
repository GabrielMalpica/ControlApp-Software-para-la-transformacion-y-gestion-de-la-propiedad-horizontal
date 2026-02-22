// src/db/prisma.ts
import { PrismaClient } from "../generated/prisma";

declare global {
  var __prisma: PrismaClient | undefined;
}

export const prisma =
  global.__prisma ?? new PrismaClient({ log: ["error"] });

if (process.env.NODE_ENV !== "production") global.__prisma = prisma;
