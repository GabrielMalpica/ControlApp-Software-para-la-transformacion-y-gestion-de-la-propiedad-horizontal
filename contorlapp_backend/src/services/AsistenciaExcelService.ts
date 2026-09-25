import ExcelJS from "exceljs";
import type { PrismaClient } from "@prisma/client";

import { AsistenciaService } from "./AsistenciaService";

const DIA_SEMANA_LETRA = ["D", "L", "M", "M", "J", "V", "S"];

const MESES = [
  "ENERO",
  "FEBRERO",
  "MARZO",
  "ABRIL",
  "MAYO",
  "JUNIO",
  "JULIO",
  "AGOSTO",
  "SEPTIEMBRE",
  "OCTUBRE",
  "NOVIEMBRE",
  "DICIEMBRE",
];

const COLS_FIJAS = ["CLIENTE", "CARGO", "JORNADA", "TIPO CONTRATO", "NOMBRE", "CEDULA"];
const GAP_COLS = 2;

function friendlyEnum(value: string | null | undefined): string {
  if (!value) return "";
  return value
    .toLowerCase()
    .replace(/_/g, " ")
    .replace(/^./, (letter) => letter.toUpperCase());
}

function toYmd(d: Date): string {
  return `${d.getUTCFullYear().toString().padStart(4, "0")}-${(d.getUTCMonth() + 1)
    .toString()
    .padStart(2, "0")}-${d.getUTCDate().toString().padStart(2, "0")}`;
}

export class AsistenciaExcelService {
  private asistencia: AsistenciaService;

  constructor(private readonly prisma: PrismaClient) {
    this.asistencia = new AsistenciaService(prisma);
  }

  async exportar(input: {
    empresaId: string;
    conjuntoId?: string | null;
    anio: number;
    mes: number;
  }): Promise<Buffer> {
    const [grid, conceptos, turnosExtra] = await Promise.all([
      this.asistencia.getGrid(input),
      this.asistencia.listarConceptos(input.empresaId),
      this.asistencia.listarTurnosExtra({
        empresaId: input.empresaId,
        conjuntoId: input.conjuntoId,
        anio: input.anio,
        mes: input.mes,
      }),
    ]);

    const operarioIds = grid.operarios.map((o) => o.operarioId);
    const detalle = await this.prisma.operario.findMany({
      where: { id: { in: operarioIds } },
      select: {
        id: true,
        usuario: { select: { jornadaLaboral: true, tipoContrato: true } },
      },
    });
    const detalleMap = new Map(detalle.map((d) => [d.id, d]));

    const workbook = new ExcelJS.Workbook();
    workbook.creator = "ControlApp";
    workbook.created = new Date();

    this.armarHojaAsistencia(workbook, grid, conceptos, detalleMap, input);
    this.armarHojaTurnosExtra(workbook, turnosExtra, input);
    this.armarHojaConceptos(workbook, conceptos);

    const output = await workbook.xlsx.writeBuffer();
    return Buffer.from(output);
  }

  private armarHojaAsistencia(
    workbook: ExcelJS.Workbook,
    grid: Awaited<ReturnType<AsistenciaService["getGrid"]>>,
    conceptos: Awaited<ReturnType<AsistenciaService["listarConceptos"]>>,
    detalleMap: Map<string, { usuario: { jornadaLaboral: string | null; tipoContrato: string | null } | null }>,
    input: { conjuntoId?: string | null; anio: number; mes: number },
  ): void {
    const nombreMes = MESES[input.mes - 1] ?? "";
    const sheet = workbook.addWorksheet(`${nombreMes} ${input.anio}`.trim(), {
      views: [{ state: "frozen", xSplit: COLS_FIJAS.length, ySplit: 2 }],
    });

    const totalDias = grid.totalDias;
    const firstDayCol = COLS_FIJAS.length + 1;
    // Dos columnas de resumen (dominicales/festivos trabajados) justo
    // después de los días, antes del hueco que separa la leyenda.
    const domingosCol = firstDayCol + totalDias;
    const festivosCol = domingosCol + 1;

    // Fila 1: titulo + letra de dia de semana por cada dia
    sheet.getCell(1, 1).value = `NOVEDADES CONTROL ${nombreMes}`;
    sheet.getCell(1, 1).font = { bold: true };
    for (let dia = 1; dia <= totalDias; dia += 1) {
      const fecha = new Date(Date.UTC(input.anio, input.mes - 1, dia));
      sheet.getCell(1, firstDayCol + dia - 1).value = DIA_SEMANA_LETRA[fecha.getUTCDay()];
    }

    // Fila 2: encabezados fijos + numero de dia
    COLS_FIJAS.forEach((label, index) => {
      sheet.getCell(2, index + 1).value = label;
    });
    for (let dia = 1; dia <= totalDias; dia += 1) {
      sheet.getCell(2, firstDayCol + dia - 1).value = dia;
    }
    sheet.getCell(2, domingosCol).value = "DOMINICALES";
    sheet.getCell(2, festivosCol).value = "FESTIVOS";

    const headerRow1 = sheet.getRow(1);
    const headerRow2 = sheet.getRow(2);
    [headerRow1, headerRow2].forEach((row) => {
      row.font = { bold: true };
      row.eachCell((cell) => {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEFEFEF" } };
        cell.alignment = { horizontal: "center", vertical: "middle" };
      });
    });

    // Días festivos: encabezado resaltado en ambas filas, para que se note
    // a simple vista cuál día es festivo (igual que el grid en la app).
    const primeraFilaOperario = grid.operarios[0];
    for (let dia = 1; dia <= totalDias; dia += 1) {
      const esFestivo = primeraFilaOperario?.dias[dia - 1]?.esFestivo;
      if (!esFestivo) continue;
      const col = firstDayCol + dia - 1;
      [sheet.getCell(1, col), sheet.getCell(2, col)].forEach((cell) => {
        cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFD9B3" } };
      });
    }

    // Leyenda a la derecha
    const legendCol = festivosCol + GAP_COLS;
    sheet.getCell(2, legendCol).value = "CODIGO";
    sheet.getCell(2, legendCol + 1).value = "CONCEPTO";
    sheet.getRow(2).getCell(legendCol).font = { bold: true };
    sheet.getRow(2).getCell(legendCol + 1).font = { bold: true };
    conceptos
      .filter((c) => c.activo)
      .forEach((c, index) => {
        const row = 3 + index;
        sheet.getCell(row, legendCol).value = c.codigo;
        sheet.getCell(row, legendCol + 1).value = c.nombre;
        const cell = sheet.getCell(row, legendCol);
        cell.fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: `FF${c.colorHex.replace("#", "")}` },
        };
      });

    // Filas de datos: una por operario
    grid.operarios.forEach((fila, index) => {
      const row = 3 + index;
      const detalle = detalleMap.get(fila.operarioId);
      const cliente = fila.conjuntos.map((c: { nombre: string }) => c.nombre).join(", ");

      sheet.getCell(row, 1).value = cliente;
      sheet.getCell(row, 2).value = fila.cargo;
      sheet.getCell(row, 3).value = friendlyEnum(detalle?.usuario?.jornadaLaboral);
      sheet.getCell(row, 4).value = friendlyEnum(detalle?.usuario?.tipoContrato);
      sheet.getCell(row, 5).value = fila.nombre;
      sheet.getCell(row, 6).value = fila.cedula;

      const CODIGOS_TRABAJADO = new Set(["A", "DFC", "DFP"]);
      let dominicales = 0;
      let festivos = 0;

      fila.dias.forEach((dia) => {
        const cell = sheet.getCell(row, firstDayCol + dia.dia - 1);
        if (dia.registro && CODIGOS_TRABAJADO.has(dia.registro.conceptoCodigo)) {
          if (dia.esFestivo) festivos += 1;
          else if (dia.diaSemana === 0) dominicales += 1;
        }
        if (!dia.registro) return;
        cell.value = dia.registro.conceptoCodigo;
        cell.fill = {
          type: "pattern",
          pattern: "solid",
          fgColor: { argb: `FF${dia.registro.colorHex.replace("#", "")}` },
        };
        cell.alignment = { horizontal: "center" };
        if (dia.registro.observacion) {
          cell.note = dia.registro.observacion;
        }
      });

      sheet.getCell(row, domingosCol).value = dominicales;
      sheet.getCell(row, festivosCol).value = festivos;
      sheet.getCell(row, domingosCol).alignment = { horizontal: "center" };
      sheet.getCell(row, festivosCol).alignment = { horizontal: "center" };
    });

    sheet.getColumn(1).width = 22;
    sheet.getColumn(2).width = 18;
    sheet.getColumn(3).width = 16;
    sheet.getColumn(4).width = 16;
    sheet.getColumn(5).width = 26;
    sheet.getColumn(6).width = 14;
    for (let dia = 1; dia <= totalDias; dia += 1) {
      sheet.getColumn(firstDayCol + dia - 1).width = 4;
    }
    sheet.getColumn(domingosCol).width = 12;
    sheet.getColumn(festivosCol).width = 10;
    sheet.getColumn(legendCol).width = 8;
    sheet.getColumn(legendCol + 1).width = 40;
  }

  private armarHojaTurnosExtra(
    workbook: ExcelJS.Workbook,
    turnosExtra: Awaited<ReturnType<AsistenciaService["listarTurnosExtra"]>>,
    input: { anio: number; mes: number },
  ): void {
    const nombreMes = MESES[input.mes - 1] ?? "";
    const sheet = workbook.addWorksheet("Turnos extra", {
      views: [{ state: "frozen", ySplit: 1 }],
    });

    const headers = [
      "ITEM",
      "MES",
      "FECHA",
      "NOMBRES Y APELLIDOS",
      "CEDULA",
      "TIPO",
      "REEMPLAZO DE",
      "CLIENTE",
      "MOTIVO",
      "VALOR NEGOCIADO",
      "TURNOS ORDINARIOS",
      "TURNOS DOMINICALES",
      "ESTADO",
    ];
    sheet.addRow(headers);
    sheet.getRow(1).font = { bold: true };
    sheet.getRow(1).eachCell((cell) => {
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEFEFEF" } };
    });

    turnosExtra.forEach((t, index) => {
      const reemplazo = !t.esReemplazo
        ? "NO"
        : `SI (${t.operarioReemplazado?.usuario?.nombre ?? t.reemplazadoNombreLibre ?? "?"})`;

      sheet.addRow([
        index + 1,
        nombreMes,
        toYmd(t.fecha),
        t.operario.usuario?.nombre ?? "",
        t.operarioId,
        t.tipo,
        reemplazo,
        t.conjunto?.nombre ?? "",
        t.motivo ?? "",
        t.valorNegociado ? Number(t.valorNegociado) : "",
        t.turnosOrdinarios,
        t.turnosDominicales,
        t.estado,
      ]);
    });

    sheet.columns.forEach((column) => {
      column.width = 18;
    });
    sheet.getColumn(4).width = 26;
    sheet.getColumn(9).width = 28;
  }

  private armarHojaConceptos(
    workbook: ExcelJS.Workbook,
    conceptos: Awaited<ReturnType<AsistenciaService["listarConceptos"]>>,
  ): void {
    const sheet = workbook.addWorksheet("Conceptos", {
      views: [{ state: "frozen", ySplit: 1 }],
    });

    sheet.addRow(["CODIGO", "CONCEPTO", "CUENTA COMO DIA PAGADO"]);
    sheet.getRow(1).font = { bold: true };
    sheet.getRow(1).eachCell((cell) => {
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEFEFEF" } };
    });

    conceptos.forEach((c) => {
      sheet.addRow([c.codigo, c.nombre, c.cuentaComoTrabajado ? "Si" : "No"]);
    });

    sheet.getColumn(1).width = 10;
    sheet.getColumn(2).width = 45;
    sheet.getColumn(3).width = 20;
  }
}
