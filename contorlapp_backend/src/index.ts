import express, { Request, Response } from 'express';
import { PrismaClient, Rol, TipoFuncion } from './generated/prisma';
import { GerenteService } from './services/GerenteServices';
import { Usuario } from './model/Usuario';
import { EmpresaService } from './services/EmpresaServices';
import { ConjuntoService } from './services/ConjuntoServices';
import { AdministradorService } from './services/AdministradorServices';
import { OperarioService } from './services/OperarioServices';

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

    const gerente = await prisma.gerente.findUnique({
      where: { id: 1019043425 },
      include: { usuario: true }
    });

    const alborada = await prisma.conjunto.findUnique({
      where: { nit: '123456' },
    });
    const alboradaServices = new ConjuntoService(prisma, '123456');

    const gabriel = await prisma.administrador.findUnique({
      where: { id: 1122921051 },
      include: { usuario: true, conjuntos: true }
    });
    const gabrielServices = new AdministradorService(prisma, 1122921051);

    const jaime = await prisma.operario.findUnique({
      where: { id: 987654321 },
      include: { usuario: true, conjuntos: true }
    });
    const jaimeServices = new OperarioService(prisma, 987654321);
    console.log(jaime)


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
