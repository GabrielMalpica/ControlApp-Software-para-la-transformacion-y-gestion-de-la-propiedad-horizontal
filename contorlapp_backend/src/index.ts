import express, { Request, Response } from 'express';
import { Gerente } from './model/gerente';
import { TipoFuncion } from './model/enum/tipoFuncion';
import { TipoMaquinaria } from './model/enum/tipoMaquinaria';
import { Elemento } from './model/elemento';
import { Ubicacion } from './model/ubicacion';
import { Tarea } from './model/tarea';
import { Maquinaria } from './model/maquinaria';
import { EstadoMaquinaria } from './model/enum/estadoMaquinaria';

const app = express();
app.use(express.json());

const gerente = new Gerente(1, 'Frank Rojas', 'frank@control.com');

// 📦 Maquinaria general de la empresa
gerente.crearMaquinaria('Guadaña Stihl', 'Stihl', TipoMaquinaria.GUADANIA);
gerente.crearMaquinaria('Hidrolavadora Karcher', 'Karcher', TipoMaquinaria.HIDROLAVADORA_ELECTRICA);
gerente.crearMaquinaria('Cortasetos Bosch', 'Bosch', TipoMaquinaria.CORTASETOS_ALTURA);
gerente.crearMaquinaria('Pulidora Industrial', 'InduMax', TipoMaquinaria.OTRO);

const conjuntos = [];
const tareasGlobales = [];

for (let i = 1; i <= 3; i++) {
  const nombreConjunto = ['Altos del Llano', 'Torres del Sol', 'Villa Jardín'][i - 1];
  const admin = gerente.crearAdministrador(i + 100, `Admin_${i}`, `admin${i}@correo.com`);
  const conjunto = gerente.crearConjunto(
    i,
    nombreConjunto,
    `Cra ${i} #10-${i * 5}`,
    admin,
    `${nombreConjunto.replace(/ /g, '').toLowerCase()}@correo.com`
  );

  // Ubicaciones y elementos
  const piscina = new Ubicacion('Piscina');
  piscina.agregarElemento(new Elemento('Filtro principal'));
  piscina.agregarElemento(new Elemento('Escalera'));

  const salon = new Ubicacion('Salón comunal');
  salon.agregarElemento(new Elemento('Puerta norte'));
  salon.agregarElemento(new Elemento('Ventana lateral'));

  conjunto.agregarUbicacion(piscina);
  conjunto.agregarUbicacion(salon);

  // Inventario de insumos
  gerente.agregarInsumoAConjunto(conjunto, 'Jabón líquido', 5, 'L');
  gerente.agregarInsumoAConjunto(conjunto, 'Cloro', 10, 'L');

  // Operarios y tareas
  for (let k = 0; k < 2; k++) {
    const op = gerente.crearOperario(
      i * 10 + k + 1,
      `Operario_${i}_${k + 1}`,
      `op${i}${k + 1}@correo.com`,
      [TipoFuncion.ASEO, TipoFuncion.TODERO]
    );
    gerente.asignarOperarioAConjunto(op, conjunto);

    const ubicacion = conjunto.ubicaciones[k];
    const elemento = ubicacion.elementos[k];

    const tarea = new Tarea(
      i * 10 + k + 1,
      `Limpieza profunda de ${ubicacion.nombre}`,
      new Date('2025-07-05'),
      new Date('2025-07-06'),
      ubicacion,
      elemento,
      4,
      op
    );

    tareasGlobales.push(tarea);
  }

  // Asignar maquinaria del stock
  const maquinaDisponible = gerente.stockMaquinaria.find(m => m.disponible);
  if (maquinaDisponible) {
    gerente.entregarMaquinariaAConjunto(maquinaDisponible.nombre, conjunto);
  }

  conjuntos.push(conjunto);
}

// 🔍 Mostrar resultados
console.log('📦 Conjuntos:');
for (const c of conjuntos) {
  console.log(`- ${c.nombre}`);
  console.log(`  📍 Ubicaciones: ${c.ubicaciones.map(u => u.nombre).join(', ')}`);
  console.log(`  👷 Operarios: ${c.operarios.map(o => o.nombre).join(', ')}`);
  console.log(`  🧴 Insumos: ${c.inventario.listarInsumos().join(', ')}`);
  console.log(
    `  🛠️ Maquinaria prestada: ${c.maquinariaPrestada.map(m => `${m.nombre} (hasta ${m.fechaPrestamo?.toDateString()})`).join(', ') || 'Ninguna'}`
  );
}

console.log('\n📋 Tareas asignadas:');
tareasGlobales.forEach(t => console.log(t.resumen()));

console.log('\n🏭 Maquinaria disponible en empresa:');
gerente.listarMaquinariaDisponible().forEach(m => {
  console.log(`- ${m.nombre} (${m.tipo})`);
});

app.get('/', (_req: Request, res: Response) => {
  res.send('🚀 Backend funcionando. Verifica la consola para resultados.');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🟢 Servidor escuchando en http://localhost:${PORT}`);
});
