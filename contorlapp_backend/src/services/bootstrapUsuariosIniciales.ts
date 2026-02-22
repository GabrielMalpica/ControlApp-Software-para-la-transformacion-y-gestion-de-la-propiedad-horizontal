import bcrypt from "bcrypt";
import type { PrismaClient } from "@prisma/client";

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

    // Si el correo ya existe con otro id, se toma ese usuario y se fuerza contraseña.
    const usuarioConCorreo = await db.usuario.findUnique({
      where: { correo },
      select: { id: true },
    });
    const usuarioPorId = await db.usuario.findUnique({
      where: { id: g.id },
      select: { id: true },
    });

    const targetUserId = usuarioConCorreo?.id ?? usuarioPorId?.id ?? g.id;
    const hash = await bcrypt.hash(g.id, 10); // forzar clave temporal = cédula del seed

    if (!usuarioConCorreo && !usuarioPorId) {
      await db.usuario.create({
        data: {
          id: targetUserId,
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
        where: { id: targetUserId },
        data: {
          nombre: g.nombre,
          correo,
          contrasena: hash,
          rol: "gerente",
          activo: true,
          telefono,
          fechaNacimiento,
        },
      });
    }

    await db.gerente.upsert({
      where: { id: targetUserId },
      update: { empresaId },
      create: {
        id: targetUserId,
        empresaId,
      },
    });
  }
}
