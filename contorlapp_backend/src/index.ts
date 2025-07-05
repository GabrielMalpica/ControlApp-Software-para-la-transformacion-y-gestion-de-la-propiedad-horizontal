import express, { Request, Response } from 'express';

const app = express();
app.use(express.json());


app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend funcionando. Verifica la consola para resultados.');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
