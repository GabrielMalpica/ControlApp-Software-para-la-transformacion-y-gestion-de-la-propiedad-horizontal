// Planificación pura (sin Prisma) de la migración "operarios directos -> plazas":
// qué plazas faltan por crear y qué preventivas se pueden vincular. La usa el
// script `scripts/vincular-preventivas-a-plazas.ts` para la simulación; la
// ejecución real reutiliza ConjuntoNecesidadService (migrarDesdeOperariosActuales
// y vincularDefinicionesConNecesidades), que son idempotentes.

export type OperarioConjunto = { id: string; funciones: readonly string[] };
export type PlazaExistente = { operarioId: string | null };
export type DefinicionDirecta = {
  id: number;
  descripcion: string;
  operariosIds: readonly string[];
};

export type PlanMigracionPlazas = {
  /** Operarios del conjunto sin plaza (se les crea una con sus funciones como roles). */
  plazasACrear: Array<{ operarioId: string; roles: string[] }>;
  /** Preventivas cuyos operarios quedarán todos con plaza. */
  defsVincular: number[];
  defsSaltadas: Array<{ id: number; descripcion: string; motivo: string }>;
};

export function planificarMigracionPlazas(params: {
  operarios: readonly OperarioConjunto[];
  plazas: readonly PlazaExistente[];
  defs: readonly DefinicionDirecta[];
}): PlanMigracionPlazas {
  const conPlaza = new Set(
    params.plazas.map((p) => p.operarioId).filter((id): id is string => id != null),
  );
  const plazasACrear: PlanMigracionPlazas["plazasACrear"] = [];
  const delConjunto = new Set<string>();
  for (const operario of params.operarios) {
    delConjunto.add(operario.id);
    if (conPlaza.has(operario.id)) continue;
    // Sin funciones no hay de dónde inferir la plaza (igual que el servicio).
    if (!operario.funciones.length) continue;
    plazasACrear.push({ operarioId: operario.id, roles: [...operario.funciones] });
    conPlaza.add(operario.id);
  }

  const sinFunciones = new Set(
    params.operarios.filter((o) => !o.funciones.length).map((o) => o.id),
  );
  const defsVincular: number[] = [];
  const defsSaltadas: PlanMigracionPlazas["defsSaltadas"] = [];
  for (const def of params.defs) {
    const faltante = def.operariosIds.find((id) => !conPlaza.has(id));
    if (faltante == null) {
      defsVincular.push(def.id);
      continue;
    }
    defsSaltadas.push({
      id: def.id,
      descripcion: def.descripcion,
      motivo: !delConjunto.has(faltante)
        ? `El operario ${faltante} no pertenece al conjunto: agrégalo al conjunto o cámbialo en la preventiva.`
        : sinFunciones.has(faltante)
          ? `El operario ${faltante} no tiene funciones (roles) configuradas: no se puede crear su plaza.`
          : `El operario ${faltante} todavía no ocupa una plaza.`,
    });
  }
  return { plazasACrear, defsVincular, defsSaltadas };
}
