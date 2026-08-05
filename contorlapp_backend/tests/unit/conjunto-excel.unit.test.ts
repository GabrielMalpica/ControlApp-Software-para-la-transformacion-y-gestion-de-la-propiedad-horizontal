import { DiaSemana, Frecuencia } from "@prisma/client";
import ExcelJS from "exceljs";
import fs from "fs";
import path from "path";
import * as XLSX from "xlsx";

import {
  ConjuntoFilaDTO,
  DisponibilidadOperarioFilaDTO,
  HORARIOS_CONJUNTO_FALLBACK,
  OperarioFilaDTO,
  PLANTILLA_CONJUNTO_COLUMNAS,
  PLANTILLA_CONJUNTO_ETIQUETAS,
  PreventivaFilaDTO,
  resolverColumnaNormalizada,
  parseExcelList,
  parseExcelEnum,
} from "../../src/model/ConjuntoExcel";
import { ConjuntoExcelTemplateService } from "../../src/services/ConjuntoExcelTemplateService";
import { validarProgramacionFrecuencia } from "../../src/utils/preventivaProgramacion";

const catalogs = {
  insumos: [{ id: 1, nombre: "Cloro", unidad: "LITRO" }],
  herramientas: [{ id: 2, nombre: "Escoba", unidad: "UNIDAD" }],
  supervisores: [{ id: "1000000000", nombre: "Ana Supervisora" }],
};

describe("Plantilla y parsing de carga masiva de conjuntos", () => {
  test("acepta coma y punto y coma como separadores de listas", () => {
    expect(parseExcelList("TODERO, ASEO; SALVAVIDAS,ASEO")).toEqual([
      "TODERO",
      "ASEO",
      "SALVAVIDAS",
    ]);
  });

  test("acepta valores amigables para enums de formulario", () => {
    expect(parseExcelEnum("Indefinido", ["TERMINO_INDEFINIDO"])).toBe(
      "TERMINO_INDEFINIDO",
    );
    expect(parseExcelEnum("O-", ["O_POSITIVO", "O_NEGATIVO"])).toBe(
      "O_NEGATIVO",
    );
    expect(
      parseExcelEnum("Medio día sábado completo", ["MEDIO_SEMANA_SABADO"]),
    ).toBe("MEDIO_SEMANA_SABADO");
  });

  test("mapea encabezados amigables y conserva aliases camelCase", () => {
    expect(
      resolverColumnaNormalizada("Ubicaciones", "zona", {
        subzona: "Piscina",
      }),
    ).toBe("Piscina");
    expect(
      resolverColumnaNormalizada("Preventivas", "operarioCedulas", {
        operariocedulas: "100, 200",
      }),
    ).toBe("100, 200");
  });

  test("genera las diez hojas con encabezados amigables y validaciones", async () => {
    const buffer = await new ConjuntoExcelTemplateService().generar(catalogs);
    const workbook = XLSX.read(buffer, { type: "buffer" });
    expect(workbook.SheetNames).toEqual(Object.keys(PLANTILLA_CONJUNTO_COLUMNAS));
    for (const name of Object.keys(PLANTILLA_CONJUNTO_ETIQUETAS) as Array<
      keyof typeof PLANTILLA_CONJUNTO_ETIQUETAS
    >) {
      const rows = XLSX.utils.sheet_to_json<unknown[]>(workbook.Sheets[name], {
        header: 1,
        raw: false,
      });
      expect(rows[0]).toEqual(
        PLANTILLA_CONJUNTO_COLUMNAS[name].map(
          (key) => PLANTILLA_CONJUNTO_ETIQUETAS[name][key],
        ),
      );
    }

    const excel = new ExcelJS.Workbook();
    await excel.xlsx.load(buffer);
    expect(excel.getWorksheet("Preventivas")!.getCell("F2").dataValidation.type).toBe(
      "list",
    );
    expect(excel.getWorksheet("Operarios")!.getCell("I2").dataValidation.type).toBe(
      "list",
    );
    expect(excel.getWorksheet("Preventivas")!.getCell("I1").note).toBeTruthy();
  });

  test("la plantilla versionada conserva contrato, estilos y listas", async () => {
    const filePath = path.resolve(
      __dirname,
      "../../../docs/plantillas/plantilla_conjunto.xlsx",
    );
    const fileBuffer = fs.readFileSync(filePath);
    const workbook = XLSX.read(fileBuffer, { type: "buffer" });
    expect(workbook.SheetNames).toEqual(Object.keys(PLANTILLA_CONJUNTO_COLUMNAS));
    expect(
      XLSX.utils.sheet_to_json<unknown[]>(workbook.Sheets.Operarios, {
        header: 1,
      })[0],
    ).toEqual(
      PLANTILLA_CONJUNTO_COLUMNAS.Operarios.map(
        (key) => PLANTILLA_CONJUNTO_ETIQUETAS.Operarios[key],
      ),
    );

    const excel = new ExcelJS.Workbook();
    await excel.xlsx.load(fileBuffer);
    expect(excel.getWorksheet("Preventivas")!.getCell("F2").dataValidation.type).toBe(
      "list",
    );
    expect(excel.getWorksheet("Operarios")!.getCell("A1").fill).toMatchObject({
      type: "pattern",
      pattern: "solid",
    });
  });

  test("parsea todos los datos personales y laborales del operario", () => {
    const conjunto = ConjuntoFilaDTO.parse({
      nit: "900-1",
      nombre: "Conjunto Uno",
      direccion: "Calle 1",
      correo: "ADMIN@TEST.COM",
      fechaInicioContrato: "2026-01-15",
      tipoServicio: "Aseo, Piscina",
      valorMensual: "1500000",
      consignasEspeciales: "Una;Dos",
      valorAgregado: "",
      administradorCedula: "",
    });
    const operario = OperarioFilaDTO.parse({
      cedula: "1032456789",
      nombre: "Carlos Pérez",
      correo: "CARLOS@TEST.COM",
      telefono: "300 123 4567",
      fechaNacimiento: "1992-06-15",
      direccion: "Calle 2",
      estadoCivil: "Unión libre",
      numeroHijos: "2",
      padresVivos: "Sí",
      tipoSangre: "O-",
      eps: "Sura",
      fondoPensiones: "Porvenir",
      tallaCamisa: "M",
      tallaPantalon: "32",
      tallaCalzado: "40",
      tipoContrato: "Indefinido",
      jornadaLaboral: "Medio tiempo",
      patronJornada: "Medio día sábado completo",
      activo: "Sí",
      funciones: "Todero, Aseo",
      cursoSalvamentoAcuatico: "No",
      cursoAlturas: "Sí",
      examenIngreso: "Sí",
      fechaIngreso: "2026-01-15",
      observaciones: "Ingreso masivo",
      contrasena: "",
    });

    expect(conjunto.tipoServicio).toEqual(["ASEO", "PISCINA"]);
    expect(operario.telefono).toBe("3001234567");
    expect(operario.estadoCivil).toBe("UNION_LIBRE");
    expect(operario.tipoSangre).toBe("O_NEGATIVO");
    expect(operario.tipoContrato).toBe("TERMINO_INDEFINIDO");
    expect(operario.patronJornada).toBe("MEDIO_SEMANA_SABADO");
  });

  test("valida disponibilidad y periodos de domingo", () => {
    expect(() =>
      DisponibilidadOperarioFilaDTO.parse({
        operarioCedula: "1032456789",
        fechaInicio: "2026-01-15",
        fechaFin: "2026-01-01",
        trabajaDomingo: "Sí",
        diaDescanso: "Domingo",
      }),
    ).toThrow();
  });

  test("define el fallback L-V y sábado sin domingo", () => {
    expect(HORARIOS_CONJUNTO_FALLBACK).toHaveLength(6);
    expect(HORARIOS_CONJUNTO_FALLBACK[0].dia).toBe(DiaSemana.LUNES);
    expect(HORARIOS_CONJUNTO_FALLBACK[HORARIOS_CONJUNTO_FALLBACK.length - 1]).toMatchObject({
      dia: DiaSemana.SABADO,
      descansoInicio: null,
    });
  });

  test("parsea semanal multidía y rechaza QUINCENAL sin día", () => {
    const weekly = PreventivaFilaDTO.parse({
      codigo: "PREV-1",
      ubicacion: "Zona húmeda",
      zona: "Piscina",
      area: "Piscina principal",
      descripcion: "Limpiar filtros",
      frecuencia: "Semanal",
      diasSemana: "Lunes, Miércoles",
      prioridad: "2",
      metodoDuracion: "Duración fija",
      duracionMinutosFija: "90",
      operarioCedulas: "1032456789",
      supervisorCedula: "1000000000",
    });
    expect(weekly.diasSemana).toEqual([DiaSemana.LUNES, DiaSemana.MIERCOLES]);

    expect(() =>
      validarProgramacionFrecuencia({
        frecuencia: Frecuencia.QUINCENAL,
        diaSemanaProgramado: null,
      }),
    ).toThrow(/día de la semana/i);
  });
});
