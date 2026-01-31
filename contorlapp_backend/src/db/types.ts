// src/db/types.ts
import type { Prisma, PrismaClient } from "../generated/prisma";

export type DbClient = PrismaClient | Prisma.TransactionClient;