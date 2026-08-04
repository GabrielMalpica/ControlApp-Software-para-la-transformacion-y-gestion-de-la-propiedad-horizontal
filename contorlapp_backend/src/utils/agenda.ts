export type Intervalo = { i: number; f: number };

export type Bloqueo = { startMin: number; endMin: number; motivo?: string };

export type HorarioDia = {
  startMin: number;
  endMin: number;
  descansoStartMin?: number;
  descansoEndMin?: number;
};
