import { DiaSemana, Frecuencia } from "@prisma/client";
import fs from "fs";
import path from "path";
import * as XLSX from "xlsx";

import {
  ConjuntoFilaDTO,
  HORARIOS_CONJUNTO_FALLBACK,
  OperarioFilaDTO,
  PLANTILLA_CONJUNTO_COLUMNAS,
  PreventivaFilaDTO,
  parseExcelList,
} from "../../src/model/ConjuntoExcel";
import { GerenteService } from "../../src/services/GerenteServices";
import { validarProgramacionFrecuencia } from "../../src/utils/preventivaProgramacion";

describe("Plantilla y parsing de carga masiva de conjuntos", () => {
  test("acepta coma y punto y coma como separadores de listas", () => {
    expect(parseExcelList("TODERO, ASEO; SALVAVIDAS,ASEO")).toEqual([
      "TODERO",
      "ASEO",
      "SALVAVIDAS",
    ]);
  });

  test("genera un XLSX válido con las cinco hojas y headers exactos", () => {
    const service = new GerenteService({} as any);
    const buffer = service.generarPlantillaConjunto();
    const workbook = XLSX.read(buffer, { type: "buffer" });

    expect(workbook.SheetNames).toEqual(Object.keys(PLANTILLA_CONJUNTO_COLUMNAS));
    for (const [name, expected] of Object.entries(PLANTILLA_CONJUNTO_COLUMNAS)) {
      const rows = XLSX.utils.sheet_to_json<unknown[]>(workbook.Sheets[name], {
        header: 1,
        raw: false,
      });
      expect(rows[0]).toEqual(expected);
    }
  });

  test("la plantilla versionada conserva el mismo contrato del endpoint", () => {
    const filePath = path.resolve(
      __dirname,
      "../../../docs/plantillas/plantilla_conjunto.xlsx",
    );
    const workbook = XLSX.read(fs.readFileSync(filePath), { type: "buffer" });
    expect(workbook.SheetNames).toEqual(Object.keys(PLANTILLA_CONJUNTO_COLUMNAS));
    for (const [name, expected] of Object.entries(PLANTILLA_CONJUNTO_COLUMNAS)) {
      const rows = XLSX.utils.sheet_to_json<unknown[]>(workbook.Sheets[name], {
        header: 1,
        raw: false,
      });
      expect(rows[0]).toEqual(expected);
      expect(rows.length).toBeGreaterThan(1);
    }
  });

  test("parsea datos de conjunto, listas, fechas y booleanos", () => {
    const conjunto = ConjuntoFilaDTO.parse({
      nit: "900-1",
      nombre: "Conjunto Uno",
      direccion: "Calle 1",
      correo: "ADMIN@TEST.COM",
      fechaInicioContrato: "2026-01-15",
      tipoServicio: "ASEO; PISCINA",
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
      funciones: "TODERO;ASEO",
      fechaIngreso: "2026-01-15",
      jornadaLaboral: "COMPLETA",
      patronJornada: "",
      cursoSalvamentoAcuatico: "NO",
      cursoAlturas: "SI",
      examenIngreso: "SI",
      trabajaDomingo: "NO",
      diaDescanso: "",
      contrasena: "",
    });

    expect(conjunto.correo).toBe("admin@test.com");
    expect(conjunto.tipoServicio).toEqual(["ASEO", "PISCINA"]);
    expect(operario.telefono).toBe("3001234567");
    expect(operario.cursoAlturas).toBe(true);
  });

  test("define el fallback L-V y sábado sin domingo", () => {
    expect(HORARIOS_CONJUNTO_FALLBACK).toHaveLength(6);
    expect(HORARIOS_CONJUNTO_FALLBACK[0]).toMatchObject({
      dia: DiaSemana.LUNES,
      horaApertura: "07:00",
      descansoInicio: "12:00",
    });
    expect(
      HORARIOS_CONJUNTO_FALLBACK[HORARIOS_CONJUNTO_FALLBACK.length - 1],
    ).toMatchObject({
      dia: DiaSemana.SABADO,
      horaApertura: "07:20",
      descansoInicio: null,
    });
  });

  test("rechaza QUINCENAL sin día de semana", () => {
    const row = PreventivaFilaDTO.parse({
      ubicacion: "Zona húmeda",
      zona: "Piscina",
      area: "Piscina principal",
      descripcion: "Limpiar filtros",
      frecuencia: "QUINCENAL",
      diaSemana: "",
      diaMes: "",
      fechasProgramadas: "",
      prioridad: "2",
      duracionMinutos: "90",
      operarioCedulas: "1032456789",
      supervisorCedula: "",
    });

    expect(() =>
      validarProgramacionFrecuencia({
        frecuencia: Frecuencia.QUINCENAL,
        diaSemanaProgramado: row.diaSemana,
      }),
    ).toThrow(/día de la semana/i);
  });
});
