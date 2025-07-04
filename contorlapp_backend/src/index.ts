import express, { Request, Response } from 'express';
import { Gerente } from './model/gerente';
import { TipoFuncion } from './model/enum/tipoFuncion';
import { TipoMaquinaria } from './model/enum/tipoMaquinaria';

const app = express();
app.use(express.json());

const gerente = new Gerente(1, 'Frank Rojas', 'frank@control.com');

// Crear un administrador y conjunto
const admin = gerente.crearAdministrador(2, 'Diana', 'diana@admin.com');
const conjunto = gerente.crearConjunto(100, 'Altos del Llano', 'Cra 10 #123', admin, 'correo@correo.com');

// Crear operario y asignarlo
const operario = gerente.crearOperario(10, 'Luis', 'luis@operario.com', [TipoFuncion.ASEO, TipoFuncion.TODERO]);
gerente.asignarOperarioAConjunto(operario, conjunto);

// Agregar insumo
gerente.agregarInsumoAConjunto(conjunto, 'Jabón industrial', 10, 'litros');

// Crear y asignar maquinaria
gerente.crearMaquinaria('Guadaña Honda', 'Honda', TipoMaquinaria.GUADANIA);
const disponible1 = gerente.maquinariaDisponible(1);
console.log(disponible1);
gerente.entregarMaquinariaAConjunto('Guadaña Honda', conjunto);
gerente.maquinariaDisponible(1);
const disponible2 = gerente.maquinariaDisponible(1);
console.log(disponible2);

// Ver en consola
console.log('📦 Inventario del conjunto:', conjunto.inventario.listarInsumos());
console.log('👷‍♂️ Operarios en el conjunto:', conjunto.operarios.map(o => o.nombre));
console.log('🛠️ Maquinaria prestada:', conjunto.maquinariaPrestada.map(m => m.nombre));
console.log('🏭 Stock de maquinaria disponible:', gerente.listarMaquinariaDisponible().map(m => m.nombre));

app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend funcionando. Verifica la consola para resultados.');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
