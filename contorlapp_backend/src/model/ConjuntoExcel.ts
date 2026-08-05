import {
  DiaSemana,
  EPS,
  EstadoCivil,
  FondoPension,
  Frecuencia,
  JornadaLaboral,
  PatronJornada,
  TallaCalzado,
  TallaCamisa,
  TallaPantalon,
  TipoContrato,
  TipoFuncion,
  TipoMaquinaria,
  TipoSangre,
  TipoServicio,
  UnidadCalculo,
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
    "direccion",
    "estadoCivil",
    "numeroHijos",
    "padresVivos",
    "tipoSangre",
    "eps",
    "fondoPensiones",
    "tallaCamisa",
    "tallaPantalon",
    "tallaCalzado",
    "tipoContrato",
    "jornadaLaboral",
    "patronJornada",
    "activo",
    "funciones",
    "cursoSalvamentoAcuatico",
    "urlEvidenciaSalvamento",
    "cursoAlturas",
    "urlEvidenciaAlturas",
    "examenIngreso",
    "urlEvidenciaExamenIngreso",
    "fechaIngreso",
    "fechaSalida",
    "fechaUltimasVacaciones",
    "observaciones",
    "contrasena",
  ],
  "Disponibilidad operarios": [
    "operarioCedula",
    "fechaInicio",
    "fechaFin",
    "trabajaDomingo",
    "diaDescanso",
    "observaciones",
  ],
  Preventivas: [
    "codigo",
    "ubicacion",
    "zona",
    "area",
    "descripcion",
    "frecuencia",
    "diasSemana",
    "diaMes",
    "fechasProgramadas",
    "prioridad",
    "metodoDuracion",
    "unidadCalculo",
    "areaNumerica",
    "rendimientoBase",
    "rendimientoTiempoBase",
    "duracionMinutosFija",
    "diasParaCompletar",
    "insumoPrincipal",
    "consumoPrincipalPorUnidad",
    "operarioCedulas",
    "supervisorCedula",
    "activo",
  ],
  "Insumos preventivas": [
    "preventivaCodigo",
    "insumo",
    "unidad",
    "consumoPorUnidad",
  ],
  "Maquinaria preventivas": [
    "preventivaCodigo",
    "tipoMaquinaria",
    "cantidad",
  ],
  "Herramientas preventivas": [
    "preventivaCodigo",
    "herramienta",
    "unidad",
    "cantidad",
  ],
  Opciones: [],
} as const;

export type NombreHojaConjunto = keyof typeof PLANTILLA_CONJUNTO_COLUMNAS;
export type NombreHojaDatosConjunto = Exclude<NombreHojaConjunto, "Opciones">;

export const PLANTILLA_CONJUNTO_ETIQUETAS: Record<
  NombreHojaDatosConjunto,
  Record<string, string>
> = {
  Conjunto: {
    nit: "NIT",
    nombre: "Nombre",
    direccion: "Dirección",
    correo: "Correo",
    fechaInicioContrato: "Fecha inicio del contrato",
    tipoServicio: "Tipos de servicio",
    valorMensual: "Valor mensual",
    consignasEspeciales: "Consignas especiales",
    valorAgregado: "Valores agregados",
    administradorCedula: "Cédula del administrador",
  },
  Horarios: {
    dia: "Día",
    horaApertura: "Hora de apertura",
    horaCierre: "Hora de cierre",
    descansoInicio: "Inicio del descanso",
    descansoFin: "Fin del descanso",
  },
  Ubicaciones: {
    ubicacion: "Ubicación",
    zona: "Subzona",
    area: "Área final",
  },
  Operarios: {
    cedula: "Cédula",
    nombre: "Nombre",
    correo: "Correo",
    telefono: "Teléfono",
    fechaNacimiento: "Fecha de nacimiento",
    direccion: "Dirección",
    estadoCivil: "Estado civil",
    numeroHijos: "Número de hijos",
    padresVivos: "Padres vivos",
    tipoSangre: "Tipo de sangre",
    eps: "EPS",
    fondoPensiones: "Fondo de pensiones",
    tallaCamisa: "Talla de camisa",
    tallaPantalon: "Talla de pantalón",
    tallaCalzado: "Talla de calzado",
    tipoContrato: "Tipo de contrato",
    jornadaLaboral: "Jornada laboral",
    patronJornada: "Patrón de jornada",
    activo: "Usuario activo",
    funciones: "Funciones",
    cursoSalvamentoAcuatico: "Curso de salvamento acuático",
    urlEvidenciaSalvamento: "URL evidencia de salvamento",
    cursoAlturas: "Curso de alturas",
    urlEvidenciaAlturas: "URL evidencia de alturas",
    examenIngreso: "Examen de ingreso",
    urlEvidenciaExamenIngreso: "URL evidencia del examen",
    fechaIngreso: "Fecha de ingreso",
    fechaSalida: "Fecha de salida",
    fechaUltimasVacaciones: "Fecha de últimas vacaciones",
    observaciones: "Observaciones",
    contrasena: "Contraseña",
  },
  "Disponibilidad operarios": {
    operarioCedula: "Cédula del operario",
    fechaInicio: "Fecha de inicio",
    fechaFin: "Fecha de fin",
    trabajaDomingo: "Trabaja domingo",
    diaDescanso: "Día de descanso",
    observaciones: "Observaciones",
  },
  Preventivas: {
    codigo: "Código de preventiva",
    ubicacion: "Ubicación",
    zona: "Subzona",
    area: "Área final",
    descripcion: "Descripción",
    frecuencia: "Frecuencia",
    diasSemana: "Días de la semana",
    diaMes: "Día del mes",
    fechasProgramadas: "Fechas programadas",
    prioridad: "Prioridad",
    metodoDuracion: "Método de duración",
    unidadCalculo: "Unidad de cálculo",
    areaNumerica: "Cantidad o área",
    rendimientoBase: "Rendimiento",
    rendimientoTiempoBase: "Base del rendimiento",
    duracionMinutosFija: "Duración fija en minutos",
    diasParaCompletar: "Días para completar",
    insumoPrincipal: "Insumo principal",
    consumoPrincipalPorUnidad: "Consumo principal por unidad",
    operarioCedulas: "Cédulas de operarios",
    supervisorCedula: "Cédula del supervisor",
    activo: "Activa",
  },
  "Insumos preventivas": {
    preventivaCodigo: "Código de preventiva",
    insumo: "Insumo",
    unidad: "Unidad",
    consumoPorUnidad: "Consumo por unidad",
  },
  "Maquinaria preventivas": {
    preventivaCodigo: "Código de preventiva",
    tipoMaquinaria: "Tipo de maquinaria",
    cantidad: "Cantidad",
  },
  "Herramientas preventivas": {
    preventivaCodigo: "Código de preventiva",
    herramienta: "Herramienta",
    unidad: "Unidad",
    cantidad: "Cantidad",
  },
};

const ALIASES_COLUMNAS: Partial<
  Record<NombreHojaDatosConjunto, Record<string, string[]>>
> = {
  Conjunto: {
    tipoServicio: ["tipo servicio", "tipos servicio"],
    valorAgregado: ["valor agregado"],
    administradorCedula: ["administrador cedula"],
  },
  Ubicaciones: {
    zona: ["zona"],
    area: ["area"],
  },
  Operarios: {
    cedula: ["documento", "numero documento"],
    patronJornada: ["patron jornada"],
    contrasena: ["password", "clave"],
    fechaInicioDisponibilidad: ["fecha inicio jornada"],
    fechaFinDisponibilidad: ["fecha fin jornada", "fecha fin jornada opcional"],
  },
  "Disponibilidad operarios": {
    operarioCedula: ["cedula operario", "operario cedula"],
  },
  Preventivas: {
    codigo: ["codigo", "id preventiva"],
    zona: ["zona"],
    area: ["area"],
    diasSemana: ["dia semana", "dias semana", "diaSemana"],
    diaMes: ["dia mes"],
    duracionMinutosFija: ["duracion minutos", "duracionMinutos"],
    operarioCedulas: [
      "cedulas operarios",
      "operarios cedulas",
      "operario cedulas",
    ],
    supervisorCedula: ["cedula supervisor", "supervisor cedula"],
  },
  "Insumos preventivas": {
    preventivaCodigo: ["codigo preventiva"],
  },
  "Maquinaria preventivas": {
    preventivaCodigo: ["codigo preventiva"],
  },
  "Herramientas preventivas": {
    preventivaCodigo: ["codigo preventiva"],
  },
};

export const PLANTILLA_COLUMNAS_REQUERIDAS: Record<
  NombreHojaDatosConjunto,
  readonly string[]
> = {
  Conjunto: ["nit", "nombre", "direccion", "correo", "tipoServicio"],
  Horarios: ["dia", "horaApertura", "horaCierre"],
  Ubicaciones: ["ubicacion", "zona", "area"],
  Operarios: [
    "cedula",
    "nombre",
    "correo",
    "telefono",
    "fechaNacimiento",
    "funciones",
    "fechaIngreso",
  ],
  "Disponibilidad operarios": [
    "operarioCedula",
    "fechaInicio",
    "trabajaDomingo",
  ],
  Preventivas: [
    "ubicacion",
    "zona",
    "area",
    "descripcion",
    "frecuencia",
    "operarioCedulas",
    "supervisorCedula",
  ],
  "Insumos preventivas": [
    "preventivaCodigo",
    "insumo",
    "consumoPorUnidad",
  ],
  "Maquinaria preventivas": [
    "preventivaCodigo",
    "tipoMaquinaria",
    "cantidad",
  ],
  "Herramientas preventivas": [
    "preventivaCodigo",
    "herramienta",
    "cantidad",
  ],
};

export const PLANTILLA_HOJAS_OPCIONALES = new Set<NombreHojaConjunto>([
  "Horarios",
  "Disponibilidad operarios",
  "Insumos preventivas",
  "Maquinaria preventivas",
  "Herramientas preventivas",
  "Opciones",
]);

const CAMPOS_LEGACY: Partial<Record<NombreHojaDatosConjunto, string[]>> = {
  Operarios: [
    "fechaInicioDisponibilidad",
    "fechaFinDisponibilidad",
    "trabajaDomingo",
    "diaDescanso",
  ],
};

export function columnasCargaHoja(nombre: NombreHojaDatosConjunto): string[] {
  return [
    ...PLANTILLA_CONJUNTO_COLUMNAS[nombre],
    ...(CAMPOS_LEGACY[nombre] ?? []),
  ];
}

export function aliasesColumna(
  nombre: NombreHojaDatosConjunto,
  columna: string,
): string[] {
  const etiqueta = PLANTILLA_CONJUNTO_ETIQUETAS[nombre][columna];
  return [
    columna,
    ...(etiqueta ? [etiqueta] : []),
    ...(ALIASES_COLUMNAS[nombre]?.[columna] ?? []),
  ];
}

export function resolverColumnaNormalizada(
  nombre: NombreHojaDatosConjunto,
  columna: string,
  normalizedRow: Record<string, unknown>,
): unknown {
  for (const alias of aliasesColumna(nombre, columna)) {
    const key = normalizeHeader(alias);
    if (Object.prototype.hasOwnProperty.call(normalizedRow, key)) {
      return normalizedRow[key];
    }
  }
  return "";
}

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
  throw new Error("El valor debe ser SÍ o NO");
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

const VALUE_ALIASES: Record<string, string> = {
  indefinido: "TERMINO_INDEFINIDO",
  terminofijo: "TERMINO_FIJO",
  fijo: "TERMINO_FIJO",
  obralabor: "OBRA_LABOR",
  mediodiasabadocompleto: "MEDIO_SEMANA_SABADO",
  mediodiatardesabadocompleto: "MEDIO_SEMANA_SABADO_TARDE",
  intercaladosabadocompleto: "MEDIO_DIAS_INTERCALADOS",
  diasintercalados: "MEDIO_DIAS_INTERCALADOS",
  viudo: "VIUDOA",
  viuda: "VIUDOA",
  o: "O_POSITIVO",
  onegativo: "O_NEGATIVO",
  a: "A_POSITIVO",
  anegativo: "A_NEGATIVO",
  b: "B_POSITIVO",
  bnegativo: "B_NEGATIVO",
  ab: "AB_POSITIVO",
  abnegativo: "AB_NEGATIVO",
  porrendimiento: "RENDIMIENTO",
  duracionfija: "DURACION_FIJA",
};

export function parseExcelEnum<T extends string>(
  value: unknown,
  values: readonly T[],
): T {
  const raw = normalizeCell(value);
  const signedAlias: Record<string, string> = {
    "O+": "O_POSITIVO",
    "O-": "O_NEGATIVO",
    "A+": "A_POSITIVO",
    "A-": "A_NEGATIVO",
    "B+": "B_POSITIVO",
    "B-": "B_NEGATIVO",
    "AB+": "AB_POSITIVO",
    "AB-": "AB_NEGATIVO",
  };
  const signed = signedAlias[raw.toUpperCase().replace(/\s/g, "")];
  const normalized = normalizeHeader(raw);
  const aliased = signed ?? VALUE_ALIASES[normalized];
  const found = values.find((item) => {
    const key = normalizeHeader(item);
    return (
      key === normalized ||
      item === aliased ||
      (/^T_\d+$/.test(item) && normalizeHeader(item.slice(2)) === normalized)
    );
  });
  if (!found) throw new Error(`Valor no permitido: ${raw}`);
  return found;
}

function optionalEnumValue<T extends string>(
  value: unknown,
  values: readonly T[],
): T | undefined {
  return normalizeCell(value) ? parseExcelEnum(value, values) : undefined;
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

function parseMinutes(value: string): number {
  const [hour, minute] = value.split(":").map(Number);
  return hour * 60 + minute;
}

function optionalBoolean(value: unknown, defaultValue: boolean): boolean {
  return normalizeCell(value) ? parseExcelBoolean(value) : defaultValue;
}

function optionalNumber(value: unknown): number | undefined {
  return normalizeCell(value) ? Number(value) : undefined;
}

const requiredText = z.preprocess(
  (value) => normalizeCell(value),
  z.string().min(1, "El valor es obligatorio"),
);
const optionalText = z.preprocess(blankToUndefined, z.string().optional());
const optionalUrl = z.preprocess(
  blankToUndefined,
  z.string().url("La URL no es válida").optional(),
);
const excelDate = z.preprocess((value) => parseExcelDate(value), z.date());
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
        parseExcelEnum(item, Object.values(TipoServicio)),
      ),
    z.array(z.nativeEnum(TipoServicio)).min(1, "Indica al menos un servicio"),
  ),
  valorMensual: z.preprocess(optionalNumber, z.number().positive().optional()),
  consignasEspeciales: z.preprocess(parseExcelList, z.array(z.string())),
  valorAgregado: z.preprocess(parseExcelList, z.array(z.string())),
  administradorCedula: optionalText,
});

export const HorarioFilaDTO = z
  .object({
    dia: z.preprocess(
      (value) => parseExcelEnum(value, Object.values(DiaSemana)),
      z.nativeEnum(DiaSemana),
    ),
    horaApertura: z.preprocess(
      parseTime,
      z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Hora inválida"),
    ),
    horaCierre: z.preprocess(
      parseTime,
      z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Hora inválida"),
    ),
    descansoInicio: z.preprocess(
      (value) => (normalizeCell(value) ? parseTime(value) : null),
      z.string().nullable(),
    ),
    descansoFin: z.preprocess(
      (value) => (normalizeCell(value) ? parseTime(value) : null),
      z.string().nullable(),
    ),
  })
  .superRefine((row, ctx) => {
    const apertura = parseMinutes(row.horaApertura);
    const cierre = parseMinutes(row.horaCierre);
    if (cierre <= apertura) {
      ctx.addIssue({
        code: "custom",
        path: ["horaCierre"],
        message: "La hora de cierre debe ser posterior a la apertura",
      });
    }
    if (!!row.descansoInicio !== !!row.descansoFin) {
      ctx.addIssue({
        code: "custom",
        path: ["descansoInicio"],
        message: "Debes indicar inicio y fin del descanso",
      });
    } else if (row.descansoInicio && row.descansoFin) {
      const inicio = parseMinutes(row.descansoInicio);
      const fin = parseMinutes(row.descansoFin);
      if (inicio < apertura || fin > cierre || fin <= inicio) {
        ctx.addIssue({
          code: "custom",
          path: ["descansoFin"],
          message: "El descanso debe estar dentro del horario y tener fin posterior",
        });
      }
    }
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
    direccion: optionalText,
    estadoCivil: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(EstadoCivil)),
      z.nativeEnum(EstadoCivil).optional(),
    ),
    numeroHijos: z.preprocess(
      optionalNumber,
      z.number().int().min(0).optional(),
    ),
    padresVivos: z.preprocess(
      (value) => optionalBoolean(value, true),
      z.boolean(),
    ),
    tipoSangre: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(TipoSangre)),
      z.nativeEnum(TipoSangre).optional(),
    ),
    eps: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(EPS)),
      z.nativeEnum(EPS).optional(),
    ),
    fondoPensiones: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(FondoPension)),
      z.nativeEnum(FondoPension).optional(),
    ),
    tallaCamisa: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(TallaCamisa)),
      z.nativeEnum(TallaCamisa).optional(),
    ),
    tallaPantalon: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(TallaPantalon)),
      z.nativeEnum(TallaPantalon).optional(),
    ),
    tallaCalzado: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(TallaCalzado)),
      z.nativeEnum(TallaCalzado).optional(),
    ),
    tipoContrato: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(TipoContrato)),
      z.nativeEnum(TipoContrato).optional(),
    ),
    jornadaLaboral: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(JornadaLaboral)),
      z.nativeEnum(JornadaLaboral).optional(),
    ),
    patronJornada: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(PatronJornada)),
      z.nativeEnum(PatronJornada).optional(),
    ),
    activo: z.preprocess((value) => optionalBoolean(value, true), z.boolean()),
    funciones: z.preprocess(
      (value) =>
        parseExcelList(value).map((item) =>
          parseExcelEnum(item, Object.values(TipoFuncion)),
        ),
      z.array(z.nativeEnum(TipoFuncion)).min(1, "Indica al menos una función"),
    ),
    cursoSalvamentoAcuatico: z.preprocess(
      (value) => optionalBoolean(value, false),
      z.boolean(),
    ),
    urlEvidenciaSalvamento: optionalUrl,
    cursoAlturas: z.preprocess(
      (value) => optionalBoolean(value, false),
      z.boolean(),
    ),
    urlEvidenciaAlturas: optionalUrl,
    examenIngreso: z.preprocess(
      (value) => optionalBoolean(value, false),
      z.boolean(),
    ),
    urlEvidenciaExamenIngreso: optionalUrl,
    fechaIngreso: excelDate,
    fechaSalida: optionalExcelDate,
    fechaUltimasVacaciones: optionalExcelDate,
    observaciones: optionalText,
    contrasena: optionalText,
    fechaInicioDisponibilidad: optionalExcelDate,
    fechaFinDisponibilidad: optionalExcelDate,
    trabajaDomingo: z.preprocess(
      (value) => optionalBoolean(value, false),
      z.boolean(),
    ),
    diaDescanso: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(DiaSemana)),
      z.nativeEnum(DiaSemana).optional(),
    ),
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
    if (row.fechaSalida && row.fechaSalida < row.fechaIngreso) {
      ctx.addIssue({
        code: "custom",
        path: ["fechaSalida"],
        message: "La fecha de salida no puede ser anterior al ingreso",
      });
    }
    if (
      row.fechaInicioDisponibilidad &&
      row.fechaFinDisponibilidad &&
      row.fechaFinDisponibilidad < row.fechaInicioDisponibilidad
    ) {
      ctx.addIssue({
        code: "custom",
        path: ["fechaFinDisponibilidad"],
        message: "La fecha fin de jornada no puede ser anterior al inicio",
      });
    }
  });

export const DisponibilidadOperarioFilaDTO = z
  .object({
    operarioCedula: requiredText,
    fechaInicio: excelDate,
    fechaFin: optionalExcelDate,
    trabajaDomingo: z.preprocess(
      (value) => optionalBoolean(value, false),
      z.boolean(),
    ),
    diaDescanso: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(DiaSemana)),
      z.nativeEnum(DiaSemana).optional(),
    ),
    observaciones: optionalText,
  })
  .superRefine((row, ctx) => {
    if (row.fechaFin && row.fechaFin < row.fechaInicio) {
      ctx.addIssue({
        code: "custom",
        path: ["fechaFin"],
        message: "La fecha de fin no puede ser anterior al inicio",
      });
    }
    if (
      row.trabajaDomingo &&
      (!row.diaDescanso || row.diaDescanso === DiaSemana.DOMINGO)
    ) {
      ctx.addIssue({
        code: "custom",
        path: ["diaDescanso"],
        message: "Si trabaja domingo debe indicar un descanso entre semana",
      });
    }
  });

const MetodoDuracionDTO = z.enum(["RENDIMIENTO", "DURACION_FIJA"]);

export const PreventivaFilaDTO = z
  .object({
    codigo: optionalText,
    ubicacion: requiredText,
    zona: requiredText,
    area: requiredText,
    descripcion: z.preprocess(
      (value) => normalizeCell(value),
      z.string().min(3, "La descripción debe tener al menos 3 caracteres"),
    ),
    frecuencia: z.preprocess(
      (value) => parseExcelEnum(value, Object.values(Frecuencia)),
      z.nativeEnum(Frecuencia),
    ),
    diasSemana: z.preprocess(
      (value) =>
        parseExcelList(value).map((item) =>
          parseExcelEnum(item, Object.values(DiaSemana)),
        ),
      z.array(z.nativeEnum(DiaSemana)),
    ),
    diaMes: z.preprocess(
      optionalNumber,
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
    metodoDuracion: z.preprocess(
      (value) =>
        normalizeCell(value)
          ? parseExcelEnum(value, ["RENDIMIENTO", "DURACION_FIJA"] as const)
          : undefined,
      MetodoDuracionDTO.optional(),
    ),
    unidadCalculo: z.preprocess(
      (value) => optionalEnumValue(value, Object.values(UnidadCalculo)),
      z.nativeEnum(UnidadCalculo).optional(),
    ),
    areaNumerica: z.preprocess(optionalNumber, z.number().positive().optional()),
    rendimientoBase: z.preprocess(optionalNumber, z.number().positive().optional()),
    rendimientoTiempoBase: z.preprocess(
      (value) =>
        optionalEnumValue(value, ["POR_MINUTO", "POR_HORA"] as const),
      z.enum(["POR_MINUTO", "POR_HORA"]).optional(),
    ),
    duracionMinutosFija: z.preprocess(
      optionalNumber,
      z.number().int().positive().optional(),
    ),
    diasParaCompletar: z.preprocess(
      optionalNumber,
      z.number().int().min(1).max(31).optional(),
    ),
    insumoPrincipal: optionalText,
    consumoPrincipalPorUnidad: z.preprocess(
      optionalNumber,
      z.number().min(0).optional(),
    ),
    operarioCedulas: z.preprocess(
      parseExcelList,
      z.array(z.string()).min(1, "Indica al menos un operario"),
    ),
    supervisorCedula: requiredText,
    activo: z.preprocess((value) => optionalBoolean(value, true), z.boolean()),
  })
  .superRefine((row, ctx) => {
    const tieneRendimiento =
      row.unidadCalculo != null &&
      row.areaNumerica != null &&
      row.rendimientoBase != null;
    const tieneDuracion = row.duracionMinutosFija != null;
    const metodo =
      row.metodoDuracion ?? (tieneRendimiento ? "RENDIMIENTO" : "DURACION_FIJA");
    if (metodo === "RENDIMIENTO" && !tieneRendimiento) {
      ctx.addIssue({
        code: "custom",
        path: ["unidadCalculo"],
        message: "Completa unidad, cantidad y rendimiento",
      });
    }
    if (metodo === "DURACION_FIJA" && !tieneDuracion) {
      ctx.addIssue({
        code: "custom",
        path: ["duracionMinutosFija"],
        message: "Indica la duración fija en minutos",
      });
    }
    if (tieneRendimiento && tieneDuracion) {
      ctx.addIssue({
        code: "custom",
        path: ["metodoDuracion"],
        message: "Usa rendimiento o duración fija, no ambos",
      });
    }
    if (row.insumoPrincipal && row.consumoPrincipalPorUnidad == null) {
      ctx.addIssue({
        code: "custom",
        path: ["consumoPrincipalPorUnidad"],
        message: "Indica el consumo del insumo principal",
      });
    }
    if (!row.insumoPrincipal && row.consumoPrincipalPorUnidad != null) {
      ctx.addIssue({
        code: "custom",
        path: ["insumoPrincipal"],
        message: "Indica el insumo principal",
      });
    }
  });

export const InsumoPreventivaFilaDTO = z.object({
  preventivaCodigo: requiredText,
  insumo: requiredText,
  unidad: optionalText,
  consumoPorUnidad: z.preprocess(
    (value) => Number(value),
    z.number().positive(),
  ),
});

export const MaquinariaPreventivaFilaDTO = z.object({
  preventivaCodigo: requiredText,
  tipoMaquinaria: z.preprocess(
    (value) => parseExcelEnum(value, Object.values(TipoMaquinaria)),
    z.nativeEnum(TipoMaquinaria),
  ),
  cantidad: z.preprocess((value) => Number(value), z.number().int().positive()),
});

export const HerramientaPreventivaFilaDTO = z.object({
  preventivaCodigo: requiredText,
  herramienta: requiredText,
  unidad: optionalText,
  cantidad: z.preprocess((value) => Number(value), z.number().positive()),
});

export type ConjuntoFila = z.infer<typeof ConjuntoFilaDTO>;
export type HorarioFila = z.infer<typeof HorarioFilaDTO>;
export type UbicacionFila = z.infer<typeof UbicacionFilaDTO>;
export type OperarioFila = z.infer<typeof OperarioFilaDTO>;
export type DisponibilidadOperarioFila = z.infer<
  typeof DisponibilidadOperarioFilaDTO
>;
export type PreventivaFila = z.infer<typeof PreventivaFilaDTO>;
export type InsumoPreventivaFila = z.infer<typeof InsumoPreventivaFilaDTO>;
export type MaquinariaPreventivaFila = z.infer<
  typeof MaquinariaPreventivaFilaDTO
>;
export type HerramientaPreventivaFila = z.infer<
  typeof HerramientaPreventivaFilaDTO
>;
