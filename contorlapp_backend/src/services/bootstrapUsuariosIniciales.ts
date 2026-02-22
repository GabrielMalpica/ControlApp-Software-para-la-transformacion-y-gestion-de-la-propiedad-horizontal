import bcrypt from "bcrypt";
import type { PrismaClient } from "../generated/prisma";

type SeedGerente = {
  id: string;
  nombre: string;
  correo: string;
  telefono: string;
  fechaNacimiento: string;
};

const GERENTES_INICIALES: SeedGerente[] = [
  {
    id: "1019043425",
    nombre: "Frank Rojas",
    correo: "stevenrojascruz@gmail.com",
    telefono: "3192578670",
    fechaNacimiento: "1990-01-01",
  },
  {
    id: "1121851393",
    nombre: "Jaivert Mathias",
    correo: "Jathmati@hotmail.com",
    telefono: "318 7140247",
    // Fecha no suministrada por negocio: dejamos la misma por defecto
    fechaNacimiento: "1990-01-01",
  },
];

function normalizarTelefono(raw: string): bigint {
  const digits = raw.replace(/\D+/g, "");
  if (!digits) {
    throw new Error(`Telefono invalido: "${raw}"`);
  }
  return BigInt(digits);
}

function normalizarCorreo(raw: string): string {
  return raw.trim().toLowerCase();
}

export async function bootstrapUsuariosIniciales(db: PrismaClient) {
  const empresa = await db.empresa.findFirst({
    select: { nit: true },
    orderBy: { id: "asc" },
  });
  const empresaId = empresa?.nit ?? null;

  for (const g of GERENTES_INICIALES) {
    const correo = normalizarCorreo(g.correo);
    const telefono = normalizarTelefono(g.telefono);
    const fechaNacimiento = new Date(`${g.fechaNacimiento}T00:00:00.000Z`);

    const usuarioConCorreo = await db.usuario.findUnique({
      where: { correo },
      select: { id: true },
    });

    if (usuarioConCorreo && usuarioConCorreo.id !== g.id) {
      console.warn(
        `[bootstrapUsuariosIniciales] No se crea ${g.id}: el correo ${correo} ya pertenece a ${usuarioConCorreo.id}.`,
      );
      continue;
    }

    const usuarioPorId = await db.usuario.findUnique({
      where: { id: g.id },
      select: { id: true },
    });

    if (!usuarioPorId) {
      const hash = await bcrypt.hash(g.id, 10); // clave inicial = cedula
      await db.usuario.create({
        data: {
          id: g.id,
          nombre: g.nombre,
          correo,
          contrasena: hash,
          rol: "gerente",
          activo: true,
          telefono,
          fechaNacimiento,
        },
      });
    } else {
      await db.usuario.update({
        where: { id: g.id },
        data: {
          nombre: g.nombre,
          correo,
          rol: "gerente",
          activo: true,
          telefono,
          fechaNacimiento,
        },
      });
    }

    await db.gerente.upsert({
      where: { id: g.id },
      update: { empresaId },
      create: {
        id: g.id,
        empresaId,
      },
    });
  }
}
