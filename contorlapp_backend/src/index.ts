import express, { Request, Response } from 'express';
import { PrismaClient } from './generated/prisma';

const app = express();
app.use(express.json());
const prisma = new PrismaClient();




// ─── Ruta de prueba ───────────────────────────────────
app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend actualizado funcionando.');
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
