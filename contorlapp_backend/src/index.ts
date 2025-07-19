import express, { Request, Response } from 'express';
import { PrismaClient } from './generated/prisma';
import { GerenteService } from './services/GerenteServices';

const app = express();
app.use(express.json());

const prisma = new PrismaClient();
const servicioGerente = new GerenteService(prisma);

// ─── Crear gerente manualmente ─────────────────────────────
async function main() {
  try {
    const gerente = await servicioGerente.crearGerenteManual(
      123456789,                     // cédula
      "Carolina Gómez",              // nombre
      "carolina@example.com",        // correo
      "secreta123",                  // contraseña
      3115557788,                    // teléfono
      new Date("1985-06-15"),        // fecha nacimiento
      1                              // empresaId (opcional)
    );

    console.log("✅ Gerente creado:", gerente);
  } catch (err: any) {
    console.error("❌ Error:", err.message);
  } finally {
    await prisma.$disconnect(); // opcional si no vas a usar prisma luego
  }
}

// ─── Iniciar el servidor ──────────────────────────────────
app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend actualizado funcionando.');
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);

  // Llamamos la función de prueba para crear gerente
  main();
});
