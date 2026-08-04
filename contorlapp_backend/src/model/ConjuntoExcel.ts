import {
  DiaSemana,
  Frecuencia,
  JornadaLaboral,
  PatronJornada,
  TipoFuncion,
  TipoServicio,
} from "@prisma/client";
import { z } from "zod";

import { normalizeCell, normalizeHeader } from "../utils/excelParsing";

export const PLANTILLA_CONJUNTO_COLUMNAS = {
  Conjunto: [
    "nit",
    "nombre",
    "direccion",
    "correo",
    "fechaInicioContrato",
    "tipoServicio",
    "valorMensual",
    "consignasEspeciales",
    "valorAgregado",
    "administradorCedula",
  ],
  Horarios: [
    "dia",
    "horaApertura",
    "horaCierre",
    "descansoInicio",
    "descansoFin",
  ],
  Ubicaciones: ["ubicacion", "zona", "area"],
  Operarios: [
    "cedula",
    "nombre",
    "correo",
    "telefono",
    "fechaNacimiento",
    "funciones",
    "fechaIngreso",
    "jornadaLaboral",
    "patronJornada",
    "cursoSalvamentoAcuatico",
    "cursoAlturas",
    "examenIngreso",
    "trabajaDomingo",
    "diaDescanso",
    "contrasena",
  ],
  Preventivas: [
    "ubicacion",
    "zona",
    "area",
    "descripcion",
    "frecuencia",
    "diaSemana",
    "diaMes",
    "fechasProgramadas",
    "prioridad",
    "duracionMinutos",
    "operarioCedulas",
    "supervisorCedula",
  ],
} as const;

export type NombreHojaConjunto = keyof typeof PLANTILLA_CONJUNTO_COLUMNAS;

export const HORARIOS_CONJUNTO_FALLBACK = [
  ...[
    DiaSemana.LUNES,
    DiaSemana.MARTES,
    DiaSemana.MIERCOLES,
    DiaSemana.JUEVES,
    DiaSemana.VIERNES,
  ].map((dia) => ({
    dia,
    horaApertura: "07:00",
    horaCierre: "15:40",
    descansoInicio: "12:00",
    descansoFin: "13:00",
  })),
  {
    dia: DiaSemana.SABADO,
    horaApertura: "07:20",
    horaCierre: "11:00",
    descansoInicio: null,
    descansoFin: null,
  },
] as const;

export const PLANTILLA_CONJUNTO_EJEMPLOS: Record<
  NombreHojaConjunto,
  Array<Array<string | number | Date | null>>
> = {
  Conjunto: [
    [
      "900123456-7",
      "Conjunto Mirador del Parque",
      "Carrera 10 # 20-30",
      "administracion@miradordelparque.com",
      new Date("2026-01-15T00:00:00.000Z"),
      "ASEO;PISCINA;MANTENIMIENTOS_LOCATIVOS",
      8500000,
      "Control de acceso 24 horas;Reportar novedades al administrador",
      "Limpieza profunda mensual;Apoyo a eventos",
      null,
    ],
  ],
  Horarios: [
    ["LUNES", "07:00", "15:40", "12:00", "13:00"],
    ["MARTES", "07:00", "15:40", "12:00", "13:00"],
    ["MIERCOLES", "07:00", "15:40", "12:00", "13:00"],
    ["JUEVES", "07:00", "15:40", "12:00", "13:00"],
    ["VIERNES", "07:00", "15:40", "12:00", "13:00"],
    ["SABADO", "07:20", "11:00", null, null],
  ],
  Ubicaciones: [
    ["Torre 1", "Zonas comunes", "Lobby"],
    ["Torre 1", "Zonas comunes", "Escaleras"],
    ["Zona húmeda", "Piscina", "Piscina principal"],
    ["Zona húmeda", "Piscina", "Cuarto de máquinas"],
  ],
  Operarios: [
    [
      "1032456789",
      "Carlos Pérez",
      "carlos.perez@example.com",
      "3001234567",
      new Date("1992-06-15T00:00:00.000Z"),
      "TODERO;ASEO",
      new Date("2026-01-15T00:00:00.000Z"),
      "COMPLETA",
      null,
      "NO",
      "SI",
      "SI",
      "NO",
      null,
      null,
    ],
  ],
  Preventivas: [
    [
      "Zona húmeda",
      "Piscina",
      "Piscina principal",
      "Revisar calidad del agua",
      "SEMANAL",
      "LUNES",
      null,
      null,
      1,
      90,
      "1032456789",
      null,
    ],
    [
      "Zona húmeda",
      "Piscina",
      "Piscina principal",
      "Limpiar filtros de piscina",
      "QUINCENAL",
      "MIERCOLES",
      null,
      null,
      2,
      120,
      "1032456789",
      null,
    ],
    [
      "Zona húmeda",
      "Piscina",
      "Piscina principal",
      "Inspección general de equipos",
      "MENSUAL",
      null,
      15,
      null,
      2,
      180,
      "1032456789",
      null,
    ],
  ],
};

function blankToUndefined(value: unknown): unknown {
  const text = normalizeCell(value);
  return text ? text : undefined;
}

export function parseExcelList(value: unknown): string[] {
  const seen = new Set<string>();
  return normalizeCell(value)
    .split(/[;,]/)
    .map((item) => item.trim())
    .filter((item) => {
      if (!item) return false;
      const key = normalizeHeader(item);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

export function parseExcelBoolean(value: unknown): boolean {
  const normalized = normalizeHeader(normalizeCell(value));
  if (["si", "s", "true", "1"].includes(normalized)) return true;
  if (["no", "n", "false", "0"].includes(normalized)) return false;
  throw new Error("El valor debe ser SI o NO");
}

export function parseExcelDate(value: unknown): Date {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return new Date(
      Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate()),
    );
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    const date = new Date(Date.UTC(1899, 11, 30) + Math.round(value) * 86400000);
    if (!Number.isNaN(date.getTime())) return date;
  }

  const text = normalizeCell(value);
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (iso) {
    const date = new Date(`${text}T00:00:00.000Z`);
    if (!Number.isNaN(date.getTime())) return date;
  }

  const date = new Date(text);
  if (!text || Number.isNaN(date.getTime())) {
    throw new Error("La fecha no es válida; usa yyyy-mm-dd");
  }
  return new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
}

function enumValue<T extends string>(value: unknown, values: readonly T[]): T {
  const normalized = normalizeHeader(normalizeCell(value));
  const found = values.find((item) => normalizeHeader(item) === normalized);
  if (!found) throw new Error(`Valor no permitido: ${normalizeCell(value)}`);
  return found;
}

function optionalEnumValue<T extends string>(
  value: unknown,
  values: readonly T[],
): T | undefined {
  return normalizeCell(value) ? enumValue(value, values) : undefined;
}

function parseTime(value: unknown): string {
  if (typeof value === "number" && value >= 0 && value < 1) {
    const totalMinutes = Math.round(value * 24 * 60) % (24 * 60);
    return `${String(Math.floor(totalMinutes / 60)).padStart(2, "0")}:${String(totalMinutes % 60).padStart(2, "0")}`;
  }
  const text = normalizeCell(value);
  const match = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(text);
  if (!match) return text;
  return `${match[1].padStart(2, "0")}:${match[2]}`;
}

const requiredText = z.preprocess(
  (value) => normalizeCell(value),
  z.string().min(1, "El valor es obligatorio"),
);
const optionalText = z.preprocess(blankToUndefined, z.string().optional());
const excelDate = z.preprocess(
  (value) => parseExcelDate(value),
  z.date(),
);
const optionalExcelDate = z.preprocess(
  (value) => (normalizeCell(value) ? parseExcelDate(value) : undefined),
  z.date().optional(),
);

export const ConjuntoFilaDTO = z.object({
  nit: requiredText,
  nombre: requiredText,
  direccion: requiredText,
  correo: z.preprocess(
    (value) => normalizeCell(value).toLowerCase(),
    z.string().email("El correo no es válido"),
  ),
  fechaInicioContrato: optionalExcelDate,
  tipoServicio: z.preprocess(
    (value) =>
      parseExcelList(value).map((item) =>
        enumValue(item, Object.values(TipoServicio)),
      ),
    z.array(z.nativeEnum(TipoServicio)).min(1, "Indica al menos un servicio"),
  ),
  valorMensual: z.preprocess(
    (value) => (normalizeCell(value) ? Number(value) : undefined),
    z.number().positive().optional(),
  ),
  consignasEspeciales: z.preprocess(
    parseExcelList,
    z.array(z.string()),
  ),
  valorAgregado: z.preprocess(parseExcelList, z.array(z.string())),
  administradorCedula: optionalText,
});

export const HorarioFilaDTO = z.object({
  dia: z.preprocess(
    (value) => enumValue(value, Object.values(DiaSemana)),
    z.nativeEnum(DiaSemana),
  ),
  horaApertura: z.preprocess(parseTime, z.string()),
  horaCierre: z.preprocess(parseTime, z.string()),
  descansoInicio: z.preprocess(
    (value) => (normalizeCell(value) ? parseTime(value) : null),
    z.string().nullable(),
  ),
  descansoFin: z.preprocess(
    (value) => (normalizeCell(value) ? parseTime(value) : null),
    z.string().nullable(),
  ),
});

export const UbicacionFilaDTO = z.object({
  ubicacion: requiredText,
  zona: requiredText,
  area: requiredText,
});

export const OperarioFilaDTO = z
  .object({
    cedula: z.preprocess(
      (value) => normalizeCell(value),
      z.string().min(5, "La cédula debe tener al menos 5 caracteres"),
    ),
    nombre: requiredText,
    correo: z.preprocess(
      (value) => normalizeCell(value).toLowerCase(),
      z.string().email("El correo no es válido"),
    ),
    telefono: z.preprocess(
      (value) => normalizeCell(value).replace(/\D/g, ""),
      z.string().regex(/^\d+$/, "El teléfono debe contener dígitos"),
    ),
    fechaNacimiento: excelDate,
    funciones: z.preprocess(
      (value) =>
        parseExcelList(value).map((item) =>
          enumValue(item, Object.values(TipoFuncion)),
        ),
      z.array(z.nativeEnum(TipoFuncion)).min(1, "Indica al menos una función"),
    ),
    fechaIngreso: excelDate,
    jornadaLaboral: z.preprocess(
      (value) => enumValue(value, Object.values(JornadaLaboral)),
      z.nativeEnum(JornadaLaboral),
    ),
    patronJornada: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(PatronJornada)),
      z.nativeEnum(PatronJornada).optional(),
    ),
    cursoSalvamentoAcuatico: z.preprocess(parseExcelBoolean, z.boolean()),
    cursoAlturas: z.preprocess(parseExcelBoolean, z.boolean()),
    examenIngreso: z.preprocess(parseExcelBoolean, z.boolean()),
    trabajaDomingo: z.preprocess(parseExcelBoolean, z.boolean()),
    diaDescanso: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(DiaSemana)),
      z.nativeEnum(DiaSemana).optional(),
    ),
    contrasena: optionalText,
  })
  .superRefine((row, ctx) => {
    if (
      row.jornadaLaboral === JornadaLaboral.MEDIO_TIEMPO &&
      !row.patronJornada
    ) {
      ctx.addIssue({
        code: "custom",
        path: ["patronJornada"],
        message: "El patrón de jornada es obligatorio para medio tiempo",
      });
    }
    if (
      row.trabajaDomingo &&
      (!row.diaDescanso || row.diaDescanso === DiaSemana.DOMINGO)
    ) {
      ctx.addIssue({
        code: "custom",
        path: ["diaDescanso"],
        message:
          "Si trabaja domingo debe indicar un día de descanso entre semana",
      });
    }
  });

export const PreventivaFilaDTO = z.object({
  ubicacion: requiredText,
  zona: requiredText,
  area: requiredText,
  descripcion: z.preprocess(
    (value) => normalizeCell(value),
    z.string().min(3, "La descripción debe tener al menos 3 caracteres"),
  ),
  frecuencia: z.preprocess(
    (value) => enumValue(value, Object.values(Frecuencia)),
    z.nativeEnum(Frecuencia),
  ),
  diaSemana: z.preprocess(
    (value) => optionalEnumValue(value, Object.values(DiaSemana)),
    z.nativeEnum(DiaSemana).optional(),
  ),
  diaMes: z.preprocess(
    (value) => (normalizeCell(value) ? Number(value) : undefined),
    z.number().int().min(1).max(31).optional(),
  ),
  fechasProgramadas: z.preprocess(
    (value) =>
      parseExcelList(value).map((item) =>
        parseExcelDate(item).toISOString().slice(0, 10),
      ),
    z.array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)),
  ),
  prioridad: z.preprocess(
    (value) => (normalizeCell(value) ? Number(value) : 2),
    z.number().int().min(1).max(3),
  ),
  duracionMinutos: z.preprocess(
    (value) => Number(value),
    z.number().int().positive(),
  ),
  operarioCedulas: z.preprocess(
    parseExcelList,
    z.array(z.string()).min(1, "Indica al menos un operario"),
  ),
  supervisorCedula: optionalText,
});

export type ConjuntoFila = z.infer<typeof ConjuntoFilaDTO>;
export type HorarioFila = z.infer<typeof HorarioFilaDTO>;
export type UbicacionFila = z.infer<typeof UbicacionFilaDTO>;
export type OperarioFila = z.infer<typeof OperarioFilaDTO>;
export type PreventivaFila = z.infer<typeof PreventivaFilaDTO>;
