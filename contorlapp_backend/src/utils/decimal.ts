import { Prisma } from "../generated/prisma";

export const toDec = (n: number | string) => new Prisma.Decimal(n);

export const decToNumber = (d: any) => {
  if (d && typeof d === "object" && typeof d.toNumber === "function") return d.toNumber();
  return Number(d);
};
