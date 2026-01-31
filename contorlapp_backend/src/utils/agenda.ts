export type Intervalo = { i: number; f: number };

export type Bloqueo = { startMin: number; endMin: number; motivo?: string };

export type HorarioDia = {
  startMin: number;
  endMin: number;
  descansoStartMin?: number;
  descansoEndMin?: number;
};


export const validarMaquinariaDisponible = async (
  tx: any,
  maquinariaIds: number[],
  ini: Date,
  fin: Date
) => {
  if (!maquinariaIds?.length) return;

  for (const mid of maquinariaIds) {
    const choque = await tx.usoMaquinaria.findFirst({
      where: {
        maquinariaId: mid,
        // solape: [ini, fin] cruza con [fechaInicio, fechaFin]
        fechaInicio: { lt: fin },
        OR: [
          { fechaFin: { gt: ini } },     // rango cerrado
          { fechaFin: null },            // aún prestada (sin devolver)
        ],
      },
      select: {
        id: true,
        tareaId: true,
        fechaInicio: true,
        fechaFin: true,
      },
    });

    if (choque) {
      throw new Error(
        `La maquinaria ${mid} está ocupada y se cruza con el horario solicitado.`
      );
    }
  }
};


export const crearUsoMaquinaria = async (
  tx: any,
  tareaId: number,
  maquinariaIds: number[],
  ini: Date,
  fin: Date
) => {
  if (!maquinariaIds?.length) return;

  for (const mid of maquinariaIds) {
    await tx.usoMaquinaria.create({
      data: {
        tarea: { connect: { id: tareaId } },
        maquinaria: { connect: { id: mid } },
        fechaInicio: ini,
        fechaFin: fin, // 🔥 aquí la reservas por ese bloque
        observacion: `Reservada al crear tarea #${tareaId}`,
      },
    });
  }
};
