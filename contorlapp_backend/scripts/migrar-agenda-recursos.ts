// Migra los datos existentes a la agenda de recursos (necesidad vs reserva).
// Ver docs/agenda-recursos.md.
//
// 1. Necesidades: crea NecesidadRecursoTarea para las tareas PUBLICADAS que
//    tienen maquinariaPlanJson / herramientasPlanJson (enum legado -> tipo de
//    catalogo de la empresa).
// 2. Prestamos vigentes de inventario (MaquinariaConjunto PRESTADA y
//    HerramientaItemConjunto en RESERVADA/ACTIVA) -> reservas PRESTAMO.
// 3. Reservas de maquinaria antiguas (UsoMaquinaria) -> ReservaRecurso por
//    CADA tarea del grupo que necesita ese tipo (antes la reserva quedaba solo
//    en la primera tarea del grupo). Tareas cerradas -> FINALIZADA; tareas no
//    completadas -> CANCELADA; el resto -> RESERVADA.
// 4. Reservas de herramientas por cantidad (UsoHerramienta sin unidad) no se
//    pueden convertir a una unidad fisica: la necesidad queda pendiente y se
//    listan en el reporte para asignarlas en la agenda.
//
// - Las filas UsoMaquinaria / UsoHerramienta NO se borran (son historico).
// - Lo que choca con una reserva ya existente no se fuerza: se reporta.
// - Es idempotente (marca cada reserva migrada con su origen).
//
// Uso (desde contorlapp_backend):
//   npx tsx scripts/migrar-agenda-recursos.ts            (simulación, no escribe)
//   npx tsx scripts/migrar-agenda-recursos.ts --apply    (aplica)
// Contra una base que no sea local exige además --permitir-remoto.
import "dotenv/config";
import { Prisma, PrismaClient } from "@prisma/client";

import {
  crearCalculadoraVentanas,
  maquinaAUnidad,
  maquinariaUnidadSelect,
  materializarNecesidadesDeTareas,
  resolverTipoLegado,
} from "../src/services/ReservaRecursoService";
import { esErrorExclusionReserva, normalizarUso } from "../src/utils/ventanaRecurso";

const prisma = new PrismaClient();
const APPLY = process.argv.includes("--apply");
const PERMITIR_REMOTO = process.argv.includes("--permitir-remoto");

const FINALIZAN = new Set(["COMPLETADA", "APROBADA", "PENDIENTE_APROBACION", "RECHAZADA"]);
const CANCELAN = new Set(["NO_COMPLETADA", "PENDIENTE_REPROGRAMACION"]);

function destino(): { host: string; base: string } {
  try {
    const u = new URL(process.env.DATABASE_URL ?? "");
    return { host: u.hostname, base: u.pathname.replace(/^\//, "") };
  } catch {
    return { host: "?", base: "?" };
  }
}

const reporte = {
  necesidadesCreadas: 0,
  necesidadesDescartadas: [] as Array<{ tareaId: number; motivo: string }>,
  prestamosMigrados: 0,
  prestamosOmitidos: [] as Array<{ origen: string; id: number; motivo: string }>,
  reservasMigradas: 0,
  reservasOmitidas: [] as Array<{ usoMaquinariaId: number; tareaId: number; motivo: string }>,
  herramientasPorCantidadPendientes: [] as Array<{
    usoHerramientaId: number;
    tareaId: number;
    herramientaId: number;
    cantidad: number;
  }>,
};

/** Simulación: todo corre dentro de una transacción que se deshace al final. */
class Simulacion extends Error {}

async function paso1Necesidades(tx: Prisma.TransactionClient) {
  const tareas = await tx.tarea.findMany({
    where: {
      borrador: false,
      conjuntoId: { not: null },
      OR: [
        { maquinariaPlanJson: { not: Prisma.DbNull } },
        { herramientasPlanJson: { not: Prisma.DbNull } },
      ],
    },
    select: { id: true },
    orderBy: { id: "asc" },
  });
  for (let i = 0; i < tareas.length; i += 500) {
    const lote = tareas.slice(i, i + 500).map((t) => t.id);
    const res = await materializarNecesidadesDeTareas(tx, lote);
    reporte.necesidadesCreadas += res.creadas;
    reporte.necesidadesDescartadas.push(...res.descartadas);
  }
}

async function crearReservaSegura(
  tx: Prisma.TransactionClient,
  data: Prisma.ReservaRecursoUncheckedCreateInput,
): Promise<string | null> {
  // SAVEPOINT: un choque no aborta toda la migración.
  await tx.$executeRawUnsafe("SAVEPOINT migrar_reserva");
  try {
    await tx.reservaRecurso.create({ data });
    await tx.$executeRawUnsafe("RELEASE SAVEPOINT migrar_reserva");
    return null;
  } catch (err) {
    await tx.$executeRawUnsafe("ROLLBACK TO SAVEPOINT migrar_reserva");
    if (esErrorExclusionReserva(err)) return "Choca con otra reserva de la misma unidad (dato heredado en conflicto).";
    return `Error: ${String((err as any)?.message ?? err).slice(0, 200)}`;
  }
}

async function paso2Prestamos(tx: Prisma.TransactionClient) {
  const anio = 365 * 86_400_000;

  const maq = await tx.maquinariaConjunto.findMany({
    where: { estado: { in: ["RESERVADA", "ACTIVA"] }, tipoTenencia: "PRESTADA" },
    select: {
      id: true,
      conjuntoId: true,
      fechaInicio: true,
      fechaDevolucionEstimada: true,
      conjunto: { select: { nombre: true, empresaId: true } },
      maquinaria: { select: maquinariaUnidadSelect },
    },
  });
  for (const p of maq) {
    const ya = await tx.reservaRecurso.count({ where: { prestamoMaquinariaId: p.id } });
    if (ya) continue;
    const empresaId = p.conjunto.empresaId;
    if (!empresaId) {
      reporte.prestamosOmitidos.push({ origen: "MaquinariaConjunto", id: p.id, motivo: "Conjunto sin empresa." });
      continue;
    }
    if (p.maquinaria.propietarioTipo !== "EMPRESA") continue;
    const unidad = maquinaAUnidad(p.maquinaria);
    const { usoInicio, usoFin } = normalizarUso(
      p.fechaInicio,
      p.fechaDevolucionEstimada ?? new Date(+p.fechaInicio + anio),
    );
    const motivo = await crearReservaSegura(tx, {
      empresaId,
      clase: "MAQUINARIA",
      maquinariaId: unidad.id,
      tipo: "PRESTAMO",
      estado: "RESERVADA",
      origen: "EMPRESA",
      conjuntoId: p.conjuntoId,
      usoInicio,
      usoFin,
      bloqueoInicio: usoInicio,
      bloqueoFin: usoFin,
      recursoEtiqueta: unidad.etiqueta,
      conjuntoNombre: p.conjunto.nombre,
      prestamoMaquinariaId: p.id,
      observacion: p.fechaDevolucionEstimada
        ? "[migración] Préstamo de inventario."
        : "[migración] Préstamo de inventario sin fecha de devolución (se asumió 1 año).",
    });
    if (motivo) reporte.prestamosOmitidos.push({ origen: "MaquinariaConjunto", id: p.id, motivo });
    else reporte.prestamosMigrados += 1;
  }

  const herr = await tx.herramientaItemConjunto.findMany({
    where: { estado: { in: ["RESERVADA", "ACTIVA"] } },
    select: {
      id: true,
      conjuntoId: true,
      fechaInicio: true,
      fechaDevolucionEstimada: true,
      conjunto: { select: { nombre: true, empresaId: true } },
      herramientaItem: {
        select: {
          id: true,
          codigoInterno: true,
          alias: true,
          propietarioTipo: true,
          herramienta: { select: { nombre: true } },
        },
      },
    },
  });
  for (const p of herr) {
    const ya = await tx.reservaRecurso.count({ where: { prestamoHerramientaId: p.id } });
    if (ya) continue;
    const empresaId = p.conjunto.empresaId;
    if (!empresaId || p.herramientaItem.propietarioTipo !== "EMPRESA") continue;
    const { usoInicio, usoFin } = normalizarUso(
      p.fechaInicio,
      p.fechaDevolucionEstimada ?? new Date(+p.fechaInicio + anio),
    );
    const etiqueta = `${(p.herramientaItem.alias ?? "").trim() || p.herramientaItem.herramienta.nombre} · ${p.herramientaItem.codigoInterno}`;
    const motivo = await crearReservaSegura(tx, {
      empresaId,
      clase: "HERRAMIENTA",
      herramientaItemId: p.herramientaItem.id,
      tipo: "PRESTAMO",
      estado: "RESERVADA",
      origen: "EMPRESA",
      conjuntoId: p.conjuntoId,
      usoInicio,
      usoFin,
      bloqueoInicio: usoInicio,
      bloqueoFin: usoFin,
      recursoEtiqueta: etiqueta,
      conjuntoNombre: p.conjunto.nombre,
      prestamoHerramientaId: p.id,
      observacion: "[migración] Préstamo de inventario.",
    });
    if (motivo) reporte.prestamosOmitidos.push({ origen: "HerramientaItemConjunto", id: p.id, motivo });
    else reporte.prestamosMigrados += 1;
  }
}

async function paso3UsosMaquinaria(tx: Prisma.TransactionClient) {
  const usos = await tx.usoMaquinaria.findMany({
    where: { tarea: { borrador: false, conjuntoId: { not: null } } },
    select: {
      id: true,
      fechaInicio: true,
      fechaFin: true,
      maquinaria: { select: maquinariaUnidadSelect },
      tarea: {
        select: {
          id: true,
          descripcion: true,
          estado: true,
          fechaInicio: true,
          fechaFin: true,
          grupoPlanId: true,
          conjuntoId: true,
          conjunto: { select: { nombre: true, empresaId: true } },
        },
      },
    },
    orderBy: { id: "asc" },
  });

  const calculadoras = new Map<string, Awaited<ReturnType<typeof crearCalculadoraVentanas>>>();

  for (const uso of usos) {
    const t = uso.tarea;
    const empresaId = t.conjunto?.empresaId;
    if (!empresaId || !t.conjuntoId) continue;

    const unidad = maquinaAUnidad(uso.maquinaria);
    let tipoId = unidad.tipoId;
    if (tipoId == null) {
      tipoId = await resolverTipoLegado(tx, empresaId, uso.maquinaria.tipo);
      await tx.maquinaria.update({ where: { id: unidad.id }, data: { tipoCatalogoId: tipoId } });
    }

    // Tareas que cubria esta reserva: la propia y, si era un grupo de bloques,
    // las del mismo grupo dentro de la ventana que necesitan ese tipo.
    const cubiertas = t.grupoPlanId
      ? await tx.tarea.findMany({
          where: {
            grupoPlanId: t.grupoPlanId,
            conjuntoId: t.conjuntoId,
            borrador: false,
            fechaInicio: { gte: uso.fechaInicio, lte: uso.fechaFin ?? uso.fechaInicio },
            necesidadesRecurso: { some: { tipoMaquinariaId: tipoId } },
          },
          select: { id: true, descripcion: true, estado: true, fechaInicio: true, fechaFin: true },
        })
      : [];
    if (!cubiertas.some((c) => c.id === t.id)) cubiertas.unshift(t);

    for (const c of cubiertas) {
      const marca = `[migración:UsoMaquinaria:${uso.id}]`;
      const ya = await tx.reservaRecurso.count({
        where: { tareaId: c.id, maquinariaId: unidad.id },
      });
      if (ya) continue;

      const necesidad = await tx.necesidadRecursoTarea.findFirst({
        where: { tareaId: c.id, tipoMaquinariaId: tipoId },
        select: { id: true },
      });

      const origen =
        unidad.propietarioTipo === "CONJUNTO" && unidad.conjuntoPropietarioId === t.conjuntoId
          ? "CONJUNTO"
          : "EMPRESA";
      let calc = calculadoras.get(empresaId);
      if (!calc) {
        calc = await crearCalculadoraVentanas({
          db: tx,
          empresaId,
          desde: new Date(2020, 0, 1),
          hasta: new Date(new Date().getFullYear() + 2, 0, 1),
        });
        calculadoras.set(empresaId, calc);
      }
      const ventana = calc.ventana(origen, c.fechaInicio, c.fechaFin);
      const estado = FINALIZAN.has(c.estado) ? "FINALIZADA" : CANCELAN.has(c.estado) ? "CANCELADA" : "RESERVADA";

      const motivo = await crearReservaSegura(tx, {
        empresaId,
        clase: "MAQUINARIA",
        maquinariaId: unidad.id,
        tipo: "TAREA",
        estado,
        origen,
        conjuntoId: t.conjuntoId,
        tareaId: c.id,
        necesidadId: necesidad?.id ?? null,
        ...ventana,
        recursoEtiqueta: unidad.etiqueta,
        tareaDescripcion: c.descripcion,
        conjuntoNombre: t.conjunto?.nombre ?? null,
        observacion: marca,
        ...(estado === "FINALIZADA" ? { finalizadaEn: c.fechaFin } : {}),
        ...(estado === "CANCELADA"
          ? { canceladoEn: new Date(), motivoCancelacion: "[migración] La tarea no se ejecutó." }
          : {}),
      });
      if (motivo) reporte.reservasOmitidas.push({ usoMaquinariaId: uso.id, tareaId: c.id, motivo });
      else reporte.reservasMigradas += 1;
    }
  }
}

async function paso4HerramientasPorCantidad(tx: Prisma.TransactionClient) {
  const usos = await tx.usoHerramienta.findMany({
    where: {
      herramientaItemId: null,
      estado: { in: ["RESERVADA", "EN_USO"] },
      OR: [{ fechaFin: null }, { fechaFin: { gt: new Date() } }],
      tarea: { borrador: false },
    },
    select: { id: true, tareaId: true, herramientaId: true, cantidad: true },
  });
  for (const u of usos) {
    reporte.herramientasPorCantidadPendientes.push({
      usoHerramientaId: u.id,
      tareaId: u.tareaId,
      herramientaId: u.herramientaId,
      cantidad: Number(u.cantidad),
    });
  }
}

async function main() {
  const { host, base } = destino();
  console.log(`Base: ${base} @ ${host} · modo: ${APPLY ? "APLICAR" : "simulación"}`);
  const local = ["localhost", "127.0.0.1", "::1"].includes(host);
  if (!local && !PERMITIR_REMOTO) {
    console.error("La base no es local. Para correrlo aquí agrega --permitir-remoto (con respaldo previo).");
    process.exit(1);
  }

  try {
    await prisma.$transaction(
      async (tx) => {
        await paso1Necesidades(tx);
        await paso2Prestamos(tx);
        await paso3UsosMaquinaria(tx);
        await paso4HerramientasPorCantidad(tx);
        if (!APPLY) throw new Simulacion();
      },
      { timeout: 10 * 60_000, maxWait: 30_000 },
    );
  } catch (err) {
    if (!(err instanceof Simulacion)) throw err;
  }

  console.log(JSON.stringify(reporte, null, 2));
  console.log(
    APPLY
      ? "Migración aplicada."
      : "Simulación: no se escribió nada. Ejecuta con --apply para aplicar.",
  );
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
