import ExcelJS from "exceljs";
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

import {
  HORARIOS_CONJUNTO_FALLBACK,
  PLANTILLA_COLUMNAS_REQUERIDAS,
  PLANTILLA_CONJUNTO_COLUMNAS,
  PLANTILLA_CONJUNTO_ETIQUETAS,
  type NombreHojaDatosConjunto,
} from "../model/ConjuntoExcel";

export type CatalogosPlantillaConjunto = {
  insumos: Array<{ id: number; nombre: string; unidad: string }>;
  herramientas: Array<{ id: number; nombre: string; unidad: string }>;
  supervisores: Array<{ id: string; nombre: string }>;
};

const HEADER_REQUIRED = "FF70AD47";
const HEADER_OPTIONAL = "FF92D050";
const HEADER_FONT = "FF17320B";
const INPUT_FILL = "FFF2F8EE";
const MAX_DATA_ROW = 1000;

function friendlyEnum(value: string): string {
  const explicit: Record<string, string> = {
    TERMINO_INDEFINIDO: "Indefinido",
    TERMINO_FIJO: "Fijo",
    OBRA_LABOR: "Obra labor",
    MEDIO_SEMANA_SABADO: "Medio día sábado completo",
    MEDIO_SEMANA_SABADO_TARDE: "Medio día tarde sábado completo",
    MEDIO_DIAS_INTERCALADOS: "Días intercalados",
    O_POSITIVO: "O+",
    O_NEGATIVO: "O-",
    A_POSITIVO: "A+",
    A_NEGATIVO: "A-",
    B_POSITIVO: "B+",
    B_NEGATIVO: "B-",
    AB_POSITIVO: "AB+",
    AB_NEGATIVO: "AB-",
    VIUDOA: "Viudo(a)",
    POR_MINUTO: "Por minuto",
    POR_HORA: "Por hora",
    RENDIMIENTO: "Por rendimiento",
    DURACION_FIJA: "Duración fija",
  };
  if (explicit[value]) return explicit[value];
  if (/^T_\d+$/.test(value)) return value.slice(2);
  return value
    .toLowerCase()
    .replace(/_/g, " ")
    .replace(/^./, (letter) => letter.toUpperCase());
}

function exampleRows(
  catalogos: CatalogosPlantillaConjunto,
): Partial<Record<NombreHojaDatosConjunto, unknown[][]>> {
  const supervisorId = catalogos.supervisores[0]?.id ?? "1000000000";
  return {
    Conjunto: [
      [
        "900123456-7",
        "Conjunto Mirador del Parque",
        "Carrera 10 # 20-30",
        "administracion@miradordelparque.com",
        new Date("2026-01-15T00:00:00.000Z"),
        "Aseo, Piscina, Mantenimientos locativos",
        8500000,
        "Control de acceso 24 horas, Reportar novedades",
        "Limpieza profunda mensual, Apoyo a eventos",
        "",
      ],
    ],
    Horarios: HORARIOS_CONJUNTO_FALLBACK.map((item) => [
      friendlyEnum(item.dia),
      item.horaApertura,
      item.horaCierre,
      item.descansoInicio ?? "",
      item.descansoFin ?? "",
    ]),
    Ubicaciones: [
      ["Zona húmeda", "Piscina", "Piscina principal"],
      ["Torre 1", "Zonas comunes", "Lobby"],
    ],
    Operarios: [
      [
        "1032456789",
        "Carlos Pérez",
        "carlos.perez@example.com",
        "3001234567",
        new Date("1992-06-15T00:00:00.000Z"),
        "Calle 10 # 20-30",
        "Soltero",
        0,
        "Sí",
        "O+",
        "Sura",
        "Porvenir",
        "M",
        "32",
        "40",
        "Indefinido",
        "Completa",
        "",
        "Sí",
        "Todero, Aseo",
        "No",
        "",
        "Sí",
        "",
        "Sí",
        "",
        new Date("2026-01-15T00:00:00.000Z"),
        "",
        "",
        "Operario creado desde la plantilla",
        "",
      ],
    ],
    "Disponibilidad operarios": [
      [
        "1032456789",
        new Date("2026-01-15T00:00:00.000Z"),
        "",
        "No",
        "",
        "Periodo inicial",
      ],
    ],
    Preventivas: [
      [
        "PREV-001",
        "Zona húmeda",
        "Piscina",
        "Piscina principal",
        "Revisar calidad del agua",
        "Semanal",
        "Lunes, Miércoles",
        "",
        "",
        1,
        "Duración fija",
        "",
        "",
        "",
        "",
        90,
        1,
        "",
        "",
        "1032456789",
        supervisorId,
        "Sí",
      ],
      [
        "PREV-002",
        "Zona húmeda",
        "Piscina",
        "Piscina principal",
        "Limpieza profunda del área",
        "Mensual",
        "",
        15,
        "",
        2,
        "Por rendimiento",
        "M2",
        500,
        20,
        "Por hora",
        "",
        2,
        "",
        "",
        "1032456789",
        supervisorId,
        "Sí",
      ],
    ],
    "Insumos preventivas": catalogos.insumos[0]
      ? [
          [
            "PREV-001",
            `${catalogos.insumos[0].id} | ${catalogos.insumos[0].nombre} | ${catalogos.insumos[0].unidad}`,
            catalogos.insumos[0].unidad,
            0.5,
          ],
        ]
      : [],
    "Maquinaria preventivas": [
      ["PREV-001", "Hidrolavadora eléctrica", 1],
    ],
    "Herramientas preventivas": catalogos.herramientas[0]
      ? [
          [
            "PREV-001",
            `${catalogos.herramientas[0].id} | ${catalogos.herramientas[0].nombre} | ${catalogos.herramientas[0].unidad}`,
            catalogos.herramientas[0].unidad,
            2,
          ],
        ]
      : [],
  };
}

export class ConjuntoExcelTemplateService {
  async generar(catalogos: CatalogosPlantillaConjunto): Promise<Buffer> {
    const workbook = new ExcelJS.Workbook();
    workbook.creator = "ControlApp";
    workbook.created = new Date();
    workbook.modified = new Date();

    const examples = exampleRows(catalogos);
    for (const nombre of Object.keys(
      PLANTILLA_CONJUNTO_COLUMNAS,
    ) as Array<keyof typeof PLANTILLA_CONJUNTO_COLUMNAS>) {
      if (nombre === "Opciones") continue;
      const sheet = workbook.addWorksheet(nombre, {
        views: [{ state: "frozen", ySplit: 1 }],
      });
      const keys: string[] = [...PLANTILLA_CONJUNTO_COLUMNAS[nombre]];
      const labels = keys.map(
        (key) => PLANTILLA_CONJUNTO_ETIQUETAS[nombre][key] ?? key,
      );
      sheet.addRow(labels);
      for (const row of examples[nombre] ?? []) sheet.addRow(row);
      this.formatearHoja(sheet, nombre, keys);
    }

    const opciones = workbook.addWorksheet("Opciones", {
      views: [{ state: "frozen", ySplit: 1 }],
    });
    const optionColumns = this.crearOpciones(catalogos);
    const optionNames = Object.keys(optionColumns);
    opciones.addRow(optionNames);
    const maxLength = Math.max(...Object.values(optionColumns).map((v) => v.length));
    for (let index = 0; index < maxLength; index += 1) {
      opciones.addRow(optionNames.map((name) => optionColumns[name][index] ?? ""));
    }
    opciones.getRow(1).font = { bold: true, color: { argb: "FFFFFFFF" } };
    opciones.getRow(1).fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: HEADER_REQUIRED },
    };
    opciones.autoFilter = {
      from: { row: 1, column: 1 },
      to: { row: 1, column: optionNames.length },
    };
    opciones.columns.forEach((column, index) => {
      const values = optionColumns[optionNames[index]];
      column.width = Math.min(
        42,
        Math.max(14, optionNames[index].length + 2, ...values.map((v) => v.length + 2)),
      );
    });
    opciones.getCell("A1").note =
      "Hoja auxiliar para listas desplegables. No cambies sus encabezados.";

    this.aplicarValidaciones(workbook, optionColumns);
    const output = await workbook.xlsx.writeBuffer();
    return Buffer.from(output);
  }

  private formatearHoja(
    sheet: ExcelJS.Worksheet,
    nombre: NombreHojaDatosConjunto,
    keys: string[],
  ): void {
    const required = new Set(PLANTILLA_COLUMNAS_REQUERIDAS[nombre]);
    const header = sheet.getRow(1);
    header.height = 34;
    header.alignment = { vertical: "middle", horizontal: "center", wrapText: true };
    header.font = { bold: true, color: { argb: HEADER_FONT } };
    keys.forEach((key, index) => {
      const cell = header.getCell(index + 1);
      cell.fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: required.has(key) ? HEADER_REQUIRED : HEADER_OPTIONAL },
      };
      cell.border = {
        bottom: { style: "thin", color: { argb: "FF548235" } },
      };
      sheet.getColumn(index + 1).width = Math.min(
        34,
        Math.max(14, String(cell.value ?? "").length + 3),
      );
    });
    sheet.autoFilter = {
      from: { row: 1, column: 1 },
      to: { row: 1, column: keys.length },
    };
    for (let row = 2; row <= Math.max(sheet.rowCount, 25); row += 1) {
      for (let column = 1; column <= keys.length; column += 1) {
        sheet.getCell(row, column).fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: INPUT_FILL },
        };
      }
    }
    keys.forEach((key, index) => {
      if (/fecha/i.test(key)) {
        sheet.getColumn(index + 1).numFmt = "yyyy-mm-dd";
      }
      if (/hora/i.test(key)) {
        sheet.getColumn(index + 1).numFmt = "hh:mm";
      }
    });
  }

  private crearOpciones(
    catalogos: CatalogosPlantillaConjunto,
  ): Record<string, string[]> {
    return {
      "Tipo servicio": Object.values(TipoServicio).map(friendlyEnum),
      Frecuencia: Object.values(Frecuencia).map(friendlyEnum),
      Booleano: ["Sí", "No"],
      Prioridad: ["1", "2", "3"],
      "Día semana": Object.values(DiaSemana).map(friendlyEnum),
      "Día mes": Array.from({ length: 31 }, (_, index) => String(index + 1)),
      Función: Object.values(TipoFuncion).map(friendlyEnum),
      "Estado civil": Object.values(EstadoCivil).map(friendlyEnum),
      "Tipo sangre": Object.values(TipoSangre).map(friendlyEnum),
      EPS: Object.values(EPS).map(friendlyEnum),
      "Fondo pensiones": Object.values(FondoPension).map(friendlyEnum),
      "Talla camisa": Object.values(TallaCamisa).map(friendlyEnum),
      "Talla pantalón": Object.values(TallaPantalon).map(friendlyEnum),
      "Talla calzado": Object.values(TallaCalzado).map(friendlyEnum),
      "Tipo contrato": Object.values(TipoContrato).map(friendlyEnum),
      Jornada: Object.values(JornadaLaboral).map(friendlyEnum),
      "Patrón jornada": Object.values(PatronJornada).map(friendlyEnum),
      "Unidad cálculo": Object.values(UnidadCalculo).map(friendlyEnum),
      "Base rendimiento": ["Por minuto", "Por hora"],
      "Método duración": ["Por rendimiento", "Duración fija"],
      "Tipo maquinaria": Object.values(TipoMaquinaria).map(friendlyEnum),
      Insumo: catalogos.insumos.map(
        (item) => `${item.id} | ${item.nombre} | ${item.unidad}`,
      ),
      Herramienta: catalogos.herramientas.map(
        (item) => `${item.id} | ${item.nombre} | ${item.unidad}`,
      ),
      Supervisor: catalogos.supervisores.map(
        (item) => `${item.id} | ${item.nombre}`,
      ),
    };
  }

  private aplicarValidaciones(
    workbook: ExcelJS.Workbook,
    options: Record<string, string[]>,
  ): void {
    const optionNames = Object.keys(options);
    const optionColumn = (name: string): string => {
      const index = optionNames.indexOf(name) + 1;
      return workbook.getWorksheet("Opciones")!.getColumn(index).letter;
    };
    const listFormula = (name: string): string => {
      const length = Math.max(2, options[name].length + 1);
      const letter = optionColumn(name);
      return `'Opciones'!$${letter}$2:$${letter}$${length}`;
    };
    const applyList = (
      sheetName: NombreHojaDatosConjunto,
      key: string,
      optionName: string,
    ) => {
      const sheet = workbook.getWorksheet(sheetName)!;
      const keys: string[] = [...PLANTILLA_CONJUNTO_COLUMNAS[sheetName]];
      const column = keys.indexOf(key) + 1;
      if (!column || options[optionName].length === 0) return;
      for (let row = 2; row <= MAX_DATA_ROW; row += 1) {
        sheet.getCell(row, column).dataValidation = {
          type: "list",
          allowBlank: true,
          formulae: [listFormula(optionName)],
          showErrorMessage: true,
          errorTitle: "Valor no permitido",
          error: "Selecciona un valor de la lista.",
        };
      }
    };
    const applyWhole = (
      sheetName: NombreHojaDatosConjunto,
      key: string,
      min: number,
      max?: number,
    ) => {
      const sheet = workbook.getWorksheet(sheetName)!;
      const keys: string[] = [...PLANTILLA_CONJUNTO_COLUMNAS[sheetName]];
      const column = keys.indexOf(key) + 1;
      for (let row = 2; row <= MAX_DATA_ROW; row += 1) {
        sheet.getCell(row, column).dataValidation = {
          type: "whole",
          operator: max == null ? "greaterThanOrEqual" : "between",
          allowBlank: true,
          formulae: max == null ? [min] : [min, max],
          showErrorMessage: true,
          errorTitle: "Número inválido",
          error: max == null ? `Usa un número igual o mayor a ${min}.` : `Usa un número entre ${min} y ${max}.`,
        };
      }
    };

    applyList("Horarios", "dia", "Día semana");
    applyList("Operarios", "estadoCivil", "Estado civil");
    applyList("Operarios", "padresVivos", "Booleano");
    applyList("Operarios", "tipoSangre", "Tipo sangre");
    applyList("Operarios", "eps", "EPS");
    applyList("Operarios", "fondoPensiones", "Fondo pensiones");
    applyList("Operarios", "tallaCamisa", "Talla camisa");
    applyList("Operarios", "tallaPantalon", "Talla pantalón");
    applyList("Operarios", "tallaCalzado", "Talla calzado");
    applyList("Operarios", "tipoContrato", "Tipo contrato");
    applyList("Operarios", "jornadaLaboral", "Jornada");
    applyList("Operarios", "patronJornada", "Patrón jornada");
    applyList("Operarios", "activo", "Booleano");
    applyList("Operarios", "cursoSalvamentoAcuatico", "Booleano");
    applyList("Operarios", "cursoAlturas", "Booleano");
    applyList("Operarios", "examenIngreso", "Booleano");
    applyWhole("Operarios", "numeroHijos", 0);
    applyList("Disponibilidad operarios", "trabajaDomingo", "Booleano");
    applyList("Disponibilidad operarios", "diaDescanso", "Día semana");
    applyList("Preventivas", "frecuencia", "Frecuencia");
    applyList("Preventivas", "prioridad", "Prioridad");
    applyList("Preventivas", "diaMes", "Día mes");
    applyList("Preventivas", "metodoDuracion", "Método duración");
    applyList("Preventivas", "unidadCalculo", "Unidad cálculo");
    applyList("Preventivas", "rendimientoTiempoBase", "Base rendimiento");
    applyList("Preventivas", "insumoPrincipal", "Insumo");
    applyList("Preventivas", "supervisorCedula", "Supervisor");
    applyList("Preventivas", "activo", "Booleano");
    applyWhole("Preventivas", "duracionMinutosFija", 1);
    applyWhole("Preventivas", "diasParaCompletar", 1, 31);
    applyList("Insumos preventivas", "insumo", "Insumo");
    applyList("Maquinaria preventivas", "tipoMaquinaria", "Tipo maquinaria");
    applyWhole("Maquinaria preventivas", "cantidad", 1);
    applyList("Herramientas preventivas", "herramienta", "Herramienta");

    workbook.getWorksheet("Conjunto")!.getCell("F1").note =
      "Admite varios servicios separados por coma o punto y coma. Consulta la hoja Opciones.";
    workbook.getWorksheet("Operarios")!.getCell("T1").note =
      "Admite varias funciones separadas por coma o punto y coma.";
    workbook.getWorksheet("Preventivas")!.getCell("G1").note =
      "SEMANAL admite varios días separados por coma o punto y coma. QUINCENAL admite uno.";
    workbook.getWorksheet("Preventivas")!.getCell("I1").note =
      "Solo para BIMESTRAL, TRIMESTRAL, SEMESTRAL y ANUAL. Usa fechas yyyy-mm-dd separadas por coma o punto y coma.";
    workbook.getWorksheet("Preventivas")!.getCell("T1").note =
      "Admite varias cédulas separadas por coma o punto y coma.";
  }
}
