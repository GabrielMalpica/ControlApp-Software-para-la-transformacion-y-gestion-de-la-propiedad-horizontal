// src/utils/reservaMaquinaria.ts

/**
 * Dias en los que la empresa entrega y recoge maquinaria: lunes, miercoles y sabado.
 * Antes estaba duplicado en cinco archivos; esta es la unica fuente.
 */
export const DIAS_ENTREGA_RECOGIDA = new Set<number>([1, 3, 6]);

export type RangoReservaMaquinaria = {
  entregaDia: Date;
  recogidaDia: Date;
  iniReserva: Date;
  finReserva: Date;
};

function inicioDelDia(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
}

function finDelDia(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

function claveDia(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, "0");
  const dia = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${mes}-${dia}`;
}

function buscarDiaPermitido(
  fecha: Date,
  diasPermitidos: Set<number>,
  paso: 1 | -1,
  festivosSet?: Set<string>,
): Date {
  const cursor = inicioDelDia(fecha);
  cursor.setDate(cursor.getDate() + paso);

  for (let guard = 0; guard < 62; guard++) {
    const esFestivo = festivosSet?.has(claveDia(cursor)) ?? false;
    if (diasPermitidos.has(cursor.getDay()) && !esFestivo) return new Date(cursor);
    cursor.setDate(cursor.getDate() + paso);
  }

  return inicioDelDia(fecha);
}

export function buscarDiaEntrega(
  fecha: Date,
  diasPermitidos: Set<number> = DIAS_ENTREGA_RECOGIDA,
  festivosSet?: Set<string>,
): Date {
  return buscarDiaPermitido(fecha, diasPermitidos, -1, festivosSet);
}

export function buscarDiaRecogida(
  fecha: Date,
  diasPermitidos: Set<number> = DIAS_ENTREGA_RECOGIDA,
  festivosSet?: Set<string>,
): Date {
  return buscarDiaPermitido(fecha, diasPermitidos, 1, festivosSet);
}

/**
 * Ventana logistica de una reserva: la maquina sale el dia de entrega anterior
 * al uso y vuelve el dia de recogida posterior, saltando festivos.
 */
export function calcularRangoReserva(params: {
  fechaInicioUso: Date;
  fechaFinUso: Date;
  diasEntregaRecogida?: Set<number>;
  festivosSet?: Set<string>;
}): RangoReservaMaquinaria {
  const {
    fechaInicioUso,
    fechaFinUso,
    diasEntregaRecogida = DIAS_ENTREGA_RECOGIDA,
    festivosSet,
  } = params;

  if (!(fechaInicioUso instanceof Date) || Number.isNaN(+fechaInicioUso)) {
    throw new Error("fechaInicioUso inválida");
  }
  if (!(fechaFinUso instanceof Date) || Number.isNaN(+fechaFinUso)) {
    throw new Error("fechaFinUso inválida");
  }
  if (!diasEntregaRecogida.size) {
    throw new Error("diasEntregaRecogida vacío");
  }

  const iniUso = +fechaInicioUso <= +fechaFinUso ? fechaInicioUso : fechaFinUso;
  const finUso = +fechaInicioUso <= +fechaFinUso ? fechaFinUso : fechaInicioUso;

  const entregaDia = buscarDiaEntrega(
    inicioDelDia(iniUso),
    diasEntregaRecogida,
    festivosSet,
  );
  const recogidaDia = buscarDiaRecogida(
    inicioDelDia(finUso),
    diasEntregaRecogida,
    festivosSet,
  );

  const iniReserva = inicioDelDia(entregaDia);
  const finReserva = finDelDia(recogidaDia);

  if (+finReserva < +iniReserva) {
    throw new Error("Rango de reserva inválido (fin < inicio)");
  }

  return { entregaDia, recogidaDia, iniReserva, finReserva };
}
