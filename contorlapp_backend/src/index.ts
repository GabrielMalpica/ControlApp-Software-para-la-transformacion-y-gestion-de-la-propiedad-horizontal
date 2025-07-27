import express, { Request, Response } from 'express';
import { PrismaClient } from './generated/prisma';
import { GerenteService } from './services/GerenteServices';
import { Usuario } from './model/Usuario';
import { EmpresaService } from './services/EmpresaServices';

const app = express();
app.use(express.json());

const prisma = new PrismaClient();
const gerenteService = new GerenteService(prisma);
const empresaService = new EmpresaService(prisma, '901191875-4');

// ─── Crear gerente manualmente ─────────────────────────────
async function main() {
  try {
    const empresa = await prisma.empresa.findUnique({
      where: { nit: "901191875-4" },
    });

    console.log(empresa)

  } catch (error: any) {
    console.error('❌ Error:', error.message);
  } finally {
    await prisma.$disconnect();
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
