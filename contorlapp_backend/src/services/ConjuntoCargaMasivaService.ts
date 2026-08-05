import {
  DiaSemana,
  Frecuencia,
  JornadaLaboral,
  Prisma,
  Rol,
  type PrismaClient,
} from "@prisma/client";
import bcrypt from "bcrypt";
import * as XLSX from "xlsx";
import { z } from "zod";

import {
  ConjuntoFilaDTO,
  DisponibilidadOperarioFilaDTO,
  HerramientaPreventivaFilaDTO,
  HorarioFilaDTO,
  HORARIOS_CONJUNTO_FALLBACK,
  InsumoPreventivaFilaDTO,
  MaquinariaPreventivaFilaDTO,
  OperarioFilaDTO,
  PLANTILLA_COLUMNAS_REQUERIDAS,
  PLANTILLA_CONJUNTO_COLUMNAS,
  PreventivaFilaDTO,
  UbicacionFilaDTO,
  aliasesColumna,
  columnasCargaHoja,
  resolverColumnaNormalizada,
  type DisponibilidadOperarioFila,
  type HerramientaPreventivaFila,
  type InsumoPreventivaFila,
  type MaquinariaPreventivaFila,
  type NombreHojaConjunto,
  type NombreHojaDatosConjunto,
  type OperarioFila,
  type PreventivaFila,
  type UbicacionFila,
} from "../model/ConjuntoExcel";
import { CrearConjuntoDTO, HorarioDTO } from "../model/Conjunto";
import { CrearOperarioDTO } from "../model/Operario";
import { CrearUsuarioDTO } from "../model/Usuario";
import {
  mapExcelRow,
  normalizedLocationKey,
  normalizeHeader,
  normalizeLocationPart,
} from "../utils/excelParsing";
import { validarProgramacionFrecuencia } from "../utils/preventivaProgramacion";
import { DefinicionTareaPreventivaService } from "./DefinicionTareaPreventivaService";

type PrismaWriteClient = PrismaClient | Prisma.TransactionClient;

type CrearConjuntoConEstructura = (
  client: PrismaWriteClient,
  dto: z.infer<typeof CrearConjuntoDTO>,
  empresaId: string,
  administradorId: string | null,
) => Promise<unknown>;

type CargaError = {
  fila: number;
  seccion: NombreHojaConjunto;
  motivo: string;
  codigo?: string;
};

type OperarioPlan = {
  fila: number;
  row: OperarioFila;
  disponibilidad: DisponibilidadOperarioFila[];
  mode: "CREATE_USER" | "CREATE_PROFILE" | "REUSE";
  passwordHash?: string;
};

type PreventivaPlan = {
  fila: number;
  codigo: string;
  row: PreventivaFila;
  operariosIds: string[];
  supervisorId: string;
  insumoPrincipalId: number | null;
  insumosPlan: Array<{ insumoId: number; consumoPorUnidad: number }>;
  maquinariaPlan: Array<{
    tipo: MaquinariaPreventivaFila["tipoMaquinaria"];
    cantidad: number;
  }>;
  herramientasPlan: Array<{ herramientaId: number; cantidad: number }>;
};

type CatalogItem = { id: number; nombre: string; unidad: string };

export class ConjuntoCargaMasivaService {
  constructor(
    private prisma: PrismaClient,
    private crearConjuntoConEstructura: CrearConjuntoConEstructura,
  ) {}

  async cargar(
    empresaId: string,
    file: Express.Multer.File | undefined,
  ) {
    if (!file?.buffer?.length) {
      throw new Error("Debes adjuntar la plantilla Excel del conjunto.");
    }
    if (!file.originalname.toLowerCase().endsWith(".xlsx")) {
      throw new Error("La carga masiva de conjuntos solo admite archivos .xlsx.");
    }

    const workbook = XLSX.read(file.buffer, { type: "buffer", cellDates: true });
    const conjuntoRows = this.leerFilas(workbook, "Conjunto");
    const horarioRows = this.leerFilas(workbook, "Horarios", false);
    const ubicacionRows = this.leerFilas(workbook, "Ubicaciones");
    const operarioRows = this.leerFilas(workbook, "Operarios");
    const disponibilidadRows = this.leerFilas(
      workbook,
      "Disponibilidad operarios",
      false,
    );
    const preventivaRows = this.leerFilas(workbook, "Preventivas");
    const insumoRows = this.leerFilas(workbook, "Insumos preventivas", false);
    const maquinariaRows = this.leerFilas(
      workbook,
      "Maquinaria preventivas",
      false,
    );
    const herramientaRows = this.leerFilas(
      workbook,
      "Herramientas preventivas",
      false,
    );

    if (conjuntoRows.length !== 1) {
      throw new Error("La hoja Conjunto debe contener exactamente una fila de datos.");
    }
    if (!ubicacionRows.length) {
      throw new Error("La hoja Ubicaciones debe contener al menos una fila.");
    }
    if (!operarioRows.length) {
      throw new Error("La hoja Operarios debe contener al menos una fila.");
    }
    if (!preventivaRows.length) {
      throw new Error("La hoja Preventivas debe contener al menos una fila.");
    }

    const conjuntoRow = ConjuntoFilaDTO.parse(
      this.canonicalizar("Conjunto", conjuntoRows[0]),
    );
    const duplicate = await this.prisma.conjunto.findUnique({
      where: { nit: conjuntoRow.nit },
      select: { nit: true },
    });
    if (duplicate) throw new Error("Ya existe un conjunto con ese NIT.");

    let administradorId: string | null = null;
    if (conjuntoRow.administradorCedula) {
      const administrador = await this.prisma.administrador.findUnique({
        where: { id: this.idReferencia(conjuntoRow.administradorCedula) },
        select: { id: true },
      });
      if (!administrador) throw new Error("El administrador indicado no existe.");
      administradorId = administrador.id;
    }

    const erroresEstrictos: CargaError[] = [];
    const erroresPreventivas: CargaError[] = [];
    const horarios = this.procesarHorarios(horarioRows, erroresEstrictos);
    const ubicacionesParsed = this.procesarUbicaciones(
      ubicacionRows,
      erroresEstrictos,
    );
    const ubicaciones = this.construirArbolUbicaciones(ubicacionesParsed);
    const locationKeys = new Set(
      ubicacionesParsed.map((row) =>
        normalizedLocationKey(row.ubicacion, row.zona, row.area),
      ),
    );

    const operariosParsed = this.procesarOperarios(
      operarioRows,
      erroresEstrictos,
    );
    const disponibilidadPorCedula = this.procesarDisponibilidad(
      disponibilidadRows,
      new Set(operariosParsed.map((item) => item.row.cedula)),
      erroresEstrictos,
    );
    const operarioPlans = await this.planearOperarios(
      empresaId,
      operariosParsed,
      disponibilidadPorCedula,
      erroresEstrictos,
    );

    const [insumosCatalogo, herramientasCatalogo] = await Promise.all([
      this.prisma.insumo.findMany({
        where: { empresaId },
        select: { id: true, nombre: true, unidad: true },
      }),
      this.prisma.herramienta.findMany({
        where: { empresaId },
        select: { id: true, nombre: true, unidad: true },
      }),
    ]);

    const recursos = this.procesarRecursos(
      { insumoRows, maquinariaRows, herramientaRows },
      { insumosCatalogo, herramientasCatalogo },
      erroresPreventivas,
    );
    const preventivaPlans = await this.planearPreventivas({
      empresaId,
      rows: preventivaRows,
      locationKeys,
      operarioPlans,
      recursos,
      insumosCatalogo,
      errores: erroresPreventivas,
    });

    const baseResult = {
      conjunto: { nit: conjuntoRow.nit, nombre: conjuntoRow.nombre },
      columnasEsperadas: PLANTILLA_CONJUNTO_COLUMNAS,
    };
    if (erroresEstrictos.length) {
      return {
        creado: false as const,
        ...baseResult,
        resumen: this.resumenVacio(preventivaRows.length),
        errores: [...erroresEstrictos, ...erroresPreventivas],
      };
    }

    await Promise.all(
      operarioPlans.map(async (plan) => {
        if (plan.mode === "CREATE_USER") {
          plan.passwordHash = await bcrypt.hash(
            plan.row.contrasena || plan.row.cedula,
            10,
          );
        }
      }),
    );

    const conjuntoDto = CrearConjuntoDTO.parse({
      nit: conjuntoRow.nit,
      nombre: conjuntoRow.nombre,
      direccion: conjuntoRow.direccion,
      correo: conjuntoRow.correo,
      administradorId,
      fechaInicioContrato: conjuntoRow.fechaInicioContrato,
      activo: true,
      tipoServicio: conjuntoRow.tipoServicio,
      valorMensual: conjuntoRow.valorMensual,
      consignasEspeciales: conjuntoRow.consignasEspeciales,
      valorAgregado: conjuntoRow.valorAgregado,
      horarios,
      ubicaciones,
    });
    const referencedExisting = new Set(
      preventivaPlans
        .flatMap((item) => item.operariosIds)
        .filter(
          (id) => !operarioPlans.some((operator) => operator.row.cedula === id),
        ),
    );
    const allOperarios = new Set([
      ...operarioPlans.map((item) => item.row.cedula),
      ...referencedExisting,
    ]);

    await this.prisma.$transaction(async (tx) => {
      for (const plan of operarioPlans) {
        await this.crearOperarioPlan(tx, empresaId, plan);
      }
      await this.crearConjuntoConEstructura(
        tx,
        conjuntoDto,
        empresaId,
        administradorId,
      );
      if (allOperarios.size) {
        await tx.conjunto.update({
          where: { nit: conjuntoRow.nit },
          data: {
            operarios: {
              connect: [...allOperarios].map((id) => ({ id })),
            },
          },
        });
      }
    });

    const paths = await this.resolverRutasCreadas(conjuntoRow.nit);
    let preventivasCreadas = 0;
    let definicionesCreadas = 0;
    let insumosCreados = 0;
    let maquinariaCreada = 0;
    let herramientasCreadas = 0;

    for (const plan of preventivaPlans) {
      try {
        const ids = paths.get(
          normalizedLocationKey(plan.row.ubicacion, plan.row.zona, plan.row.area),
        );
        if (!ids) throw new Error("No se pudo resolver la ruta creada");
        const dias =
          plan.row.frecuencia === Frecuencia.SEMANAL
            ? plan.row.diasSemana
            : [plan.row.diasSemana[0] ?? null];
        await this.prisma.$transaction(async (tx) => {
          const service = new DefinicionTareaPreventivaService(this.prisma);
          for (const dia of dias) {
            await service.crearEnTransaccion(tx, {
              conjuntoId: conjuntoRow.nit,
              ...ids,
              descripcion: plan.row.descripcion,
              frecuencia: plan.row.frecuencia,
              prioridad: plan.row.prioridad,
              diaSemanaProgramado: dia,
              diaMesProgramado: plan.row.diaMes ?? null,
              fechasProgramadasJson: plan.row.fechasProgramadas,
              unidadCalculo: plan.row.unidadCalculo,
              areaNumerica: plan.row.areaNumerica,
              rendimientoBase: plan.row.rendimientoBase,
              rendimientoTiempoBase: plan.row.rendimientoTiempoBase,
              duracionMinutosFija: plan.row.duracionMinutosFija,
              diasParaCompletar: plan.row.diasParaCompletar,
              insumoPrincipalId: plan.insumoPrincipalId ?? undefined,
              consumoPrincipalPorUnidad: plan.row.consumoPrincipalPorUnidad,
              insumosPlanJson: plan.insumosPlan,
              maquinariaPlanJson: plan.maquinariaPlan,
              herramientasPlanJson: plan.herramientasPlan,
              operariosIds: plan.operariosIds,
              supervisorId: plan.supervisorId,
              activo: plan.row.activo,
            });
          }
        });
        preventivasCreadas += 1;
        definicionesCreadas += dias.length;
        insumosCreados += plan.insumosPlan.length;
        maquinariaCreada += plan.maquinariaPlan.length;
        herramientasCreadas += plan.herramientasPlan.length;
      } catch (error) {
        erroresPreventivas.push({
          fila: plan.fila,
          seccion: "Preventivas",
          codigo: plan.codigo,
          motivo: this.motivoError(error),
        });
      }
    }

    return {
      creado: true as const,
      ...baseResult,
      resumen: {
        horarios: horarios.length,
        ubicaciones: ubicaciones.length,
        operariosCreados: operarioPlans.filter((item) => item.mode !== "REUSE")
          .length,
        operariosReutilizados:
          operarioPlans.filter((item) => item.mode === "REUSE").length +
          referencedExisting.size,
        preventivasTotal: preventivaRows.length,
        preventivasCreadas,
        preventivasFallidas: preventivaRows.length - preventivasCreadas,
        definicionesCreadas,
        insumosPreventivas: insumosCreados,
        maquinariaPreventivas: maquinariaCreada,
        herramientasPreventivas: herramientasCreadas,
      },
      errores: erroresPreventivas,
    };
  }

  private obtenerHoja(
    workbook: XLSX.WorkBook,
    nombre: NombreHojaDatosConjunto,
    required: boolean,
  ): XLSX.WorkSheet | null {
    const actual = workbook.SheetNames.find(
      (item) => normalizeHeader(item) === normalizeHeader(nombre),
    );
    if (!actual) {
      if (required) throw new Error(`El archivo no contiene la hoja ${nombre}.`);
      return null;
    }
    return workbook.Sheets[actual] ?? null;
  }

  private leerFilas(
    workbook: XLSX.WorkBook,
    nombre: NombreHojaDatosConjunto,
    required = true,
  ): Array<Record<string, unknown>> {
    const sheet = this.obtenerHoja(workbook, nombre, required);
    if (!sheet) return [];
    const matrix = XLSX.utils.sheet_to_json<unknown[]>(sheet, {
      header: 1,
      defval: "",
      raw: true,
    });
    const header = (matrix[0] ?? []).map((item) => normalizeHeader(String(item)));
    const missing = PLANTILLA_COLUMNAS_REQUERIDAS[nombre].filter((column) =>
      aliasesColumna(nombre, column).every(
        (alias) => !header.includes(normalizeHeader(alias)),
      ),
    );
    if (missing.length) {
      throw new Error(
        `La hoja ${nombre} no contiene las columnas: ${missing.join(", ")}.`,
      );
    }
    return XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, {
      defval: "",
      raw: true,
    });
  }

  private canonicalizar(
    nombre: NombreHojaDatosConjunto,
    row: Record<string, unknown>,
  ): Record<string, unknown> {
    const normalized = mapExcelRow(row);
    return Object.fromEntries(
      columnasCargaHoja(nombre).map((column) => [
        column,
        resolverColumnaNormalizada(nombre, column, normalized),
      ]),
    );
  }

  private motivoError(error: unknown): string {
    if (error instanceof z.ZodError) {
      return error.issues
        .map((issue) => {
          const field = issue.path.length ? `${issue.path.join(".")}: ` : "";
          return `${field}${issue.message}`;
        })
        .join("; ");
    }
    return error instanceof Error ? error.message : "No se pudo procesar la fila";
  }

  private procesarHorarios(
    rows: Array<Record<string, unknown>>,
    errores: CargaError[],
  ): Array<z.infer<typeof HorarioDTO>> {
    if (!rows.length) {
      return HORARIOS_CONJUNTO_FALLBACK.map((item) => ({ ...item }));
    }
    const result: Array<z.infer<typeof HorarioDTO>> = [];
    const dias = new Set<DiaSemana>();
    rows.forEach((raw, index) => {
      try {
        const row = HorarioFilaDTO.parse(this.canonicalizar("Horarios", raw));
        if (dias.has(row.dia)) throw new Error(`El día ${row.dia} está repetido`);
        dias.add(row.dia);
        result.push(HorarioDTO.parse(row));
      } catch (error) {
        errores.push({
          fila: index + 2,
          seccion: "Horarios",
          motivo: this.motivoError(error),
        });
      }
    });
    return result;
  }

  private procesarUbicaciones(
    rows: Array<Record<string, unknown>>,
    errores: CargaError[],
  ): UbicacionFila[] {
    const result: UbicacionFila[] = [];
    rows.forEach((raw, index) => {
      try {
        result.push(UbicacionFilaDTO.parse(this.canonicalizar("Ubicaciones", raw)));
      } catch (error) {
        errores.push({
          fila: index + 2,
          seccion: "Ubicaciones",
          motivo: this.motivoError(error),
        });
      }
    });
    return result;
  }

  private procesarOperarios(
    rows: Array<Record<string, unknown>>,
    errores: CargaError[],
  ): Array<{ fila: number; row: OperarioFila }> {
    const result: Array<{ fila: number; row: OperarioFila }> = [];
    const cedulas = new Set<string>();
    const correos = new Set<string>();
    rows.forEach((raw, index) => {
      const fila = index + 2;
      try {
        const row = OperarioFilaDTO.parse(this.canonicalizar("Operarios", raw));
        if (cedulas.has(row.cedula)) {
          throw new Error("La cédula está repetida en la hoja Operarios");
        }
        if (correos.has(row.correo)) {
          throw new Error("El correo está repetido en la hoja Operarios");
        }
        cedulas.add(row.cedula);
        correos.add(row.correo);
        result.push({ fila, row });
      } catch (error) {
        errores.push({
          fila,
          seccion: "Operarios",
          motivo: this.motivoError(error),
        });
      }
    });
    return result;
  }

  private procesarDisponibilidad(
    rows: Array<Record<string, unknown>>,
    cedulasHoja: Set<string>,
    errores: CargaError[],
  ): Map<string, DisponibilidadOperarioFila[]> {
    const result = new Map<string, DisponibilidadOperarioFila[]>();
    rows.forEach((raw, index) => {
      const fila = index + 2;
      try {
        const row = DisponibilidadOperarioFilaDTO.parse(
          this.canonicalizar("Disponibilidad operarios", raw),
        );
        if (!cedulasHoja.has(row.operarioCedula)) {
          throw new Error("La cédula no aparece en la hoja Operarios");
        }
        const current = result.get(row.operarioCedula) ?? [];
        current.push(row);
        result.set(row.operarioCedula, current);
      } catch (error) {
        errores.push({
          fila,
          seccion: "Disponibilidad operarios",
          motivo: this.motivoError(error),
        });
      }
    });
    for (const [cedula, periodos] of result) {
      const sorted = [...periodos].sort(
        (a, b) => a.fechaInicio.getTime() - b.fechaInicio.getTime(),
      );
      for (let index = 1; index < sorted.length; index += 1) {
        const previous = sorted[index - 1];
        if (!previous.fechaFin || sorted[index].fechaInicio <= previous.fechaFin) {
          errores.push({
            fila: 0,
            seccion: "Disponibilidad operarios",
            motivo: `Los periodos del operario ${cedula} se solapan`,
          });
          break;
        }
      }
    }
    return result;
  }

  private async planearOperarios(
    empresaId: string,
    parsed: Array<{ fila: number; row: OperarioFila }>,
    disponibilidad: Map<string, DisponibilidadOperarioFila[]>,
    errores: CargaError[],
  ): Promise<OperarioPlan[]> {
    const plans: OperarioPlan[] = [];
    for (const item of parsed) {
      const [usuario, correoOwner] = await Promise.all([
        this.prisma.usuario.findUnique({
          where: { id: item.row.cedula },
          include: { operario: { select: { id: true, empresaId: true } } },
        }),
        this.prisma.usuario.findUnique({
          where: { correo: item.row.correo },
          select: { id: true },
        }),
      ]);
      if (correoOwner && correoOwner.id !== item.row.cedula) {
        errores.push({
          fila: item.fila,
          seccion: "Operarios",
          motivo: "Ya existe otro usuario con ese correo",
        });
        continue;
      }
      if (usuario && usuario.rol !== Rol.operario) {
        errores.push({
          fila: item.fila,
          seccion: "Operarios",
          motivo: "La cédula ya existe con un rol diferente de operario",
        });
        continue;
      }
      if (usuario?.operario && usuario.operario.empresaId !== empresaId) {
        errores.push({
          fila: item.fila,
          seccion: "Operarios",
          motivo: "El operario pertenece a otra empresa",
        });
        continue;
      }
      const periodos = disponibilidad.get(item.row.cedula) ?? [
        {
          operarioCedula: item.row.cedula,
          fechaInicio:
            item.row.fechaInicioDisponibilidad ?? item.row.fechaIngreso,
          fechaFin: item.row.fechaFinDisponibilidad,
          trabajaDomingo: item.row.trabajaDomingo,
          diaDescanso: item.row.diaDescanso,
        },
      ];
      if (usuario?.operario && disponibilidad.has(item.row.cedula)) {
        errores.push({
          fila: item.fila,
          seccion: "Operarios",
          motivo:
            "No se puede reemplazar la disponibilidad de un operario reutilizado desde esta carga",
        });
        continue;
      }
      try {
        CrearUsuarioDTO.parse({
          id: item.row.cedula,
          nombre: item.row.nombre,
          correo: item.row.correo,
          contrasena: item.row.contrasena || item.row.cedula,
          rol: Rol.operario,
          telefono: item.row.telefono,
          fechaNacimiento: item.row.fechaNacimiento,
          direccion: item.row.direccion,
          estadoCivil: item.row.estadoCivil,
          numeroHijos: item.row.numeroHijos,
          padresVivos: item.row.padresVivos,
          tipoSangre: item.row.tipoSangre,
          eps: item.row.eps,
          fondoPensiones: item.row.fondoPensiones,
          tallaCamisa: item.row.tallaCamisa,
          tallaPantalon: item.row.tallaPantalon,
          tallaCalzado: item.row.tallaCalzado,
          tipoContrato: item.row.tipoContrato,
          jornadaLaboral: item.row.jornadaLaboral,
          patronJornada: item.row.patronJornada,
          activo: item.row.activo,
        });
        CrearOperarioDTO.parse({
          Id: item.row.cedula,
          funciones: item.row.funciones,
          cursoSalvamentoAcuatico: item.row.cursoSalvamentoAcuatico,
          urlEvidenciaSalvamento: item.row.urlEvidenciaSalvamento,
          cursoAlturas: item.row.cursoAlturas,
          urlEvidenciaAlturas: item.row.urlEvidenciaAlturas,
          examenIngreso: item.row.examenIngreso,
          urlEvidenciaExamenIngreso: item.row.urlEvidenciaExamenIngreso,
          fechaIngreso: item.row.fechaIngreso,
          fechaSalida: item.row.fechaSalida,
          fechaUltimasVacaciones: item.row.fechaUltimasVacaciones,
          observaciones: item.row.observaciones,
          disponibilidadPeriodos: periodos,
        });
      } catch (error) {
        errores.push({
          fila: item.fila,
          seccion: "Operarios",
          motivo: this.motivoError(error),
        });
        continue;
      }
      plans.push({
        ...item,
        disponibilidad: periodos,
        mode: !usuario
          ? "CREATE_USER"
          : usuario.operario
            ? "REUSE"
            : "CREATE_PROFILE",
      });
    }
    return plans;
  }

  private procesarRecursos(
    rows: {
      insumoRows: Array<Record<string, unknown>>;
      maquinariaRows: Array<Record<string, unknown>>;
      herramientaRows: Array<Record<string, unknown>>;
    },
    catalogos: {
      insumosCatalogo: CatalogItem[];
      herramientasCatalogo: CatalogItem[];
    },
    errores: CargaError[],
  ) {
    const insumos = new Map<string, Array<{ fila: number; row: InsumoPreventivaFila; id: number }>>();
    const maquinaria = new Map<string, Array<{ fila: number; row: MaquinariaPreventivaFila }>>();
    const herramientas = new Map<string, Array<{ fila: number; row: HerramientaPreventivaFila; id: number }>>();
    const invalidCodes = new Set<string>();

    rows.insumoRows.forEach((raw, index) => {
      const fila = index + 2;
      let codigo = "";
      try {
        const canonical = this.canonicalizar("Insumos preventivas", raw);
        codigo = normalizeHeader(String(canonical.preventivaCodigo ?? ""));
        const row = InsumoPreventivaFilaDTO.parse(canonical);
        codigo = normalizeHeader(row.preventivaCodigo);
        const item = this.resolverCatalogo(
          row.insumo,
          row.unidad,
          catalogos.insumosCatalogo,
          "insumo",
        );
        const current = insumos.get(codigo) ?? [];
        if (current.some((entry) => entry.id === item.id)) {
          throw new Error("El insumo está repetido para la preventiva");
        }
        current.push({ fila, row, id: item.id });
        insumos.set(codigo, current);
      } catch (error) {
        if (codigo) invalidCodes.add(codigo);
        errores.push({
          fila,
          seccion: "Insumos preventivas",
          codigo: codigo || undefined,
          motivo: this.motivoError(error),
        });
      }
    });
    rows.maquinariaRows.forEach((raw, index) => {
      const fila = index + 2;
      let codigo = "";
      try {
        const canonical = this.canonicalizar("Maquinaria preventivas", raw);
        codigo = normalizeHeader(String(canonical.preventivaCodigo ?? ""));
        const row = MaquinariaPreventivaFilaDTO.parse(canonical);
        codigo = normalizeHeader(row.preventivaCodigo);
        const current = maquinaria.get(codigo) ?? [];
        if (current.some((entry) => entry.row.tipoMaquinaria === row.tipoMaquinaria)) {
          throw new Error("El tipo de maquinaria está repetido para la preventiva");
        }
        current.push({ fila, row });
        maquinaria.set(codigo, current);
      } catch (error) {
        if (codigo) invalidCodes.add(codigo);
        errores.push({
          fila,
          seccion: "Maquinaria preventivas",
          codigo: codigo || undefined,
          motivo: this.motivoError(error),
        });
      }
    });
    rows.herramientaRows.forEach((raw, index) => {
      const fila = index + 2;
      let codigo = "";
      try {
        const canonical = this.canonicalizar("Herramientas preventivas", raw);
        codigo = normalizeHeader(String(canonical.preventivaCodigo ?? ""));
        const row = HerramientaPreventivaFilaDTO.parse(canonical);
        codigo = normalizeHeader(row.preventivaCodigo);
        const item = this.resolverCatalogo(
          row.herramienta,
          row.unidad,
          catalogos.herramientasCatalogo,
          "herramienta",
        );
        const current = herramientas.get(codigo) ?? [];
        if (current.some((entry) => entry.id === item.id)) {
          throw new Error("La herramienta está repetida para la preventiva");
        }
        current.push({ fila, row, id: item.id });
        herramientas.set(codigo, current);
      } catch (error) {
        if (codigo) invalidCodes.add(codigo);
        errores.push({
          fila,
          seccion: "Herramientas preventivas",
          codigo: codigo || undefined,
          motivo: this.motivoError(error),
        });
      }
    });
    return { insumos, maquinaria, herramientas, invalidCodes };
  }

  private async planearPreventivas(params: {
    empresaId: string;
    rows: Array<Record<string, unknown>>;
    locationKeys: Set<string>;
    operarioPlans: OperarioPlan[];
    recursos: ReturnType<ConjuntoCargaMasivaService["procesarRecursos"]>;
    insumosCatalogo: CatalogItem[];
    errores: CargaError[];
  }): Promise<PreventivaPlan[]> {
    const parsed: Array<{ fila: number; codigo: string; row: PreventivaFila }> = [];
    const codeCount = new Map<string, number>();
    const hasResources =
      params.recursos.insumos.size > 0 ||
      params.recursos.maquinaria.size > 0 ||
      params.recursos.herramientas.size > 0;
    params.rows.forEach((raw, index) => {
      const fila = index + 2;
      try {
        const row = PreventivaFilaDTO.parse(this.canonicalizar("Preventivas", raw));
        if (hasResources && !row.codigo) {
          throw new Error("El código es obligatorio cuando existen hojas de recursos");
        }
        const codigo = normalizeHeader(row.codigo || `FILA-${fila}`);
        codeCount.set(codigo, (codeCount.get(codigo) ?? 0) + 1);
        parsed.push({ fila, codigo, row });
      } catch (error) {
        params.errores.push({
          fila,
          seccion: "Preventivas",
          motivo: this.motivoError(error),
        });
      }
    });
    for (const [codigo, count] of codeCount) {
      if (count > 1) params.recursos.invalidCodes.add(codigo);
    }

    const availableFromSheet = new Set(
      params.operarioPlans.map((item) => item.row.cedula),
    );
    const plans: PreventivaPlan[] = [];
    for (const item of parsed) {
      try {
        if ((codeCount.get(item.codigo) ?? 0) > 1) {
          throw new Error("El código de preventiva está repetido");
        }
        if (params.recursos.invalidCodes.has(item.codigo)) {
          throw new Error("La preventiva contiene recursos inválidos");
        }
        this.validarProgramacion(item.row);
        if (
          !params.locationKeys.has(
            normalizedLocationKey(
              item.row.ubicacion,
              item.row.zona,
              item.row.area,
            ),
          )
        ) {
          throw new Error("La ruta de ubicación no existe en la hoja Ubicaciones");
        }
        const operariosIds: string[] = [];
        for (const rawId of item.row.operarioCedulas) {
          const id = this.idReferencia(rawId);
          if (!availableFromSheet.has(id)) {
            const existing = await this.prisma.operario.findUnique({
              where: { id },
              select: { id: true, empresaId: true },
            });
            if (!existing || existing.empresaId !== params.empresaId) {
              throw new Error(`El operario ${id} no existe en la empresa`);
            }
          }
          operariosIds.push(id);
        }
        const supervisorId = this.idReferencia(item.row.supervisorCedula);
        const supervisor = await this.prisma.supervisor.findUnique({
          where: { id: supervisorId },
          select: { id: true, empresaId: true },
        });
        if (!supervisor || supervisor.empresaId !== params.empresaId) {
          throw new Error("El supervisor indicado no existe en la empresa");
        }
        let insumoPrincipalId: number | null = null;
        if (item.row.insumoPrincipal) {
          insumoPrincipalId = this.resolverCatalogo(
            item.row.insumoPrincipal,
            undefined,
            params.insumosCatalogo,
            "insumo principal",
          ).id;
        }
        const insumosPlan = (params.recursos.insumos.get(item.codigo) ?? []).map(
          (entry) => ({
            insumoId: entry.id,
            consumoPorUnidad: entry.row.consumoPorUnidad,
          }),
        );
        if (
          insumoPrincipalId != null &&
          insumosPlan.some((entry) => entry.insumoId === insumoPrincipalId)
        ) {
          throw new Error("El insumo principal no debe repetirse como adicional");
        }
        plans.push({
          ...item,
          operariosIds: [...new Set(operariosIds)],
          supervisorId,
          insumoPrincipalId,
          insumosPlan,
          maquinariaPlan: (params.recursos.maquinaria.get(item.codigo) ?? []).map(
            (entry) => ({
              tipo: entry.row.tipoMaquinaria,
              cantidad: entry.row.cantidad,
            }),
          ),
          herramientasPlan: (
            params.recursos.herramientas.get(item.codigo) ?? []
          ).map((entry) => ({
            herramientaId: entry.id,
            cantidad: entry.row.cantidad,
          })),
        });
      } catch (error) {
        params.errores.push({
          fila: item.fila,
          seccion: "Preventivas",
          codigo: item.row.codigo,
          motivo: this.motivoError(error),
        });
      }
    }

    const knownCodes = new Set(parsed.map((item) => item.codigo));
    for (const [codigo, entries] of [
      ...params.recursos.insumos,
      ...params.recursos.maquinaria,
      ...params.recursos.herramientas,
    ]) {
      if (!knownCodes.has(codigo)) {
        params.errores.push({
          fila: entries[0]?.fila ?? 0,
          seccion: "Preventivas",
          codigo,
          motivo: "El código de recurso no existe en la hoja Preventivas",
        });
      }
    }
    return plans;
  }

  private validarProgramacion(row: PreventivaFila): void {
    if (row.frecuencia === Frecuencia.SEMANAL && row.diasSemana.length < 1) {
      throw new Error("La frecuencia semanal requiere al menos un día");
    }
    if (row.frecuencia === Frecuencia.QUINCENAL && row.diasSemana.length !== 1) {
      throw new Error("La frecuencia quincenal requiere exactamente un día");
    }
    if (
      row.frecuencia !== Frecuencia.SEMANAL &&
      row.frecuencia !== Frecuencia.QUINCENAL &&
      row.diasSemana.length
    ) {
      throw new Error("Los días de la semana no aplican para esta frecuencia");
    }
    if (row.frecuencia !== Frecuencia.MENSUAL && row.diaMes != null) {
      throw new Error("El día del mes solo aplica para la frecuencia mensual");
    }
    const usaFechasExplicitas = [
      Frecuencia.BIMESTRAL,
      Frecuencia.TRIMESTRAL,
      Frecuencia.SEMESTRAL,
      Frecuencia.ANUAL,
    ].some((frecuencia) => frecuencia === row.frecuencia);
    if (!usaFechasExplicitas && row.fechasProgramadas.length) {
      throw new Error("Las fechas programadas no aplican para esta frecuencia");
    }
    validarProgramacionFrecuencia({
      frecuencia: row.frecuencia,
      diaSemanaProgramado: row.diasSemana[0] ?? null,
      diaMesProgramado: row.diaMes ?? null,
      fechasProgramadasJson: row.fechasProgramadas,
    });
    const totalMinutos = row.duracionMinutosFija ?? this.calcularMinutos(row);
    if (
      row.diasParaCompletar != null &&
      totalMinutos != null &&
      row.diasParaCompletar > totalMinutos
    ) {
      throw new Error(
        "Los días para completar no pueden superar los minutos estimados",
      );
    }
  }

  private calcularMinutos(row: PreventivaFila): number | null {
    if (row.areaNumerica == null || row.rendimientoBase == null) return null;
    const base = row.rendimientoTiempoBase ?? "POR_MINUTO";
    const minutes = row.areaNumerica / row.rendimientoBase;
    return Math.max(1, Math.round(base === "POR_HORA" ? minutes * 60 : minutes));
  }

  private resolverCatalogo(
    reference: string,
    unit: string | undefined,
    catalog: CatalogItem[],
    type: string,
  ): CatalogItem {
    const parts = reference.split("|").map((part) => part.trim());
    const id = /^\d+$/.test(parts[0]) ? Number(parts[0]) : null;
    if (id != null) {
      const found = catalog.find((item) => item.id === id);
      if (!found) throw new Error(`El ${type} ${id} no existe en la empresa`);
      return found;
    }
    const name = parts.length >= 2 && /^\d+$/.test(parts[0]) ? parts[1] : parts[0];
    const resolvedUnit = unit || (parts.length >= 3 ? parts[2] : undefined);
    const matches = catalog.filter(
      (item) =>
        normalizeHeader(item.nombre) === normalizeHeader(name) &&
        (!resolvedUnit || normalizeHeader(item.unidad) === normalizeHeader(resolvedUnit)),
    );
    if (!matches.length) throw new Error(`El ${type} ${reference} no existe en la empresa`);
    if (matches.length > 1) {
      throw new Error(`El ${type} ${reference} es ambiguo; indica también la unidad o el ID`);
    }
    return matches[0];
  }

  private idReferencia(value: string): string {
    const text = String(value ?? "").trim();
    const first = text.split("|")[0].trim();
    return first || text;
  }

  private construirArbolUbicaciones(rows: UbicacionFila[]) {
    const ubicaciones = new Map<
      string,
      { nombre: string; zonas: Map<string, { nombre: string; areas: Map<string, string> }> }
    >();
    for (const row of rows) {
      const ubicacionKey = normalizeHeader(row.ubicacion);
      const zonaKey = normalizeHeader(row.zona);
      const areaKey = normalizeHeader(row.area);
      let ubicacion = ubicaciones.get(ubicacionKey);
      if (!ubicacion) {
        ubicacion = { nombre: normalizeLocationPart(row.ubicacion), zonas: new Map() };
        ubicaciones.set(ubicacionKey, ubicacion);
      }
      let zona = ubicacion.zonas.get(zonaKey);
      if (!zona) {
        zona = { nombre: normalizeLocationPart(row.zona), areas: new Map() };
        ubicacion.zonas.set(zonaKey, zona);
      }
      if (!zona.areas.has(areaKey)) {
        zona.areas.set(areaKey, normalizeLocationPart(row.area));
      }
    }
    return [...ubicaciones.values()].map((ubicacion) => ({
      nombre: ubicacion.nombre,
      elementos: [...ubicacion.zonas.values()].map((zona) => ({
        nombre: zona.nombre,
        hijos: [...zona.areas.values()].map((area) => ({ nombre: area, hijos: [] })),
      })),
    }));
  }

  private async crearOperarioPlan(
    tx: Prisma.TransactionClient,
    empresaId: string,
    plan: OperarioPlan,
  ): Promise<void> {
    const row = plan.row;
    if (plan.mode === "CREATE_USER") {
      await tx.usuario.create({
        data: {
          id: row.cedula,
          nombre: row.nombre,
          correo: row.correo,
          contrasena: plan.passwordHash!,
          rol: Rol.operario,
          activo: row.activo,
          requiereCambioContrasena: !row.contrasena,
          telefono: BigInt(row.telefono),
          fechaNacimiento: row.fechaNacimiento,
          direccion: row.direccion ?? null,
          estadoCivil: row.estadoCivil ?? null,
          numeroHijos: row.numeroHijos ?? null,
          padresVivos: row.padresVivos,
          tipoSangre: row.tipoSangre ?? null,
          eps: row.eps ?? null,
          fondoPensiones: row.fondoPensiones ?? null,
          tallaCamisa: row.tallaCamisa ?? null,
          tallaPantalon: row.tallaPantalon ?? null,
          tallaCalzado: row.tallaCalzado ?? null,
          tipoContrato: row.tipoContrato ?? null,
          jornadaLaboral: row.jornadaLaboral ?? null,
          patronJornada:
            row.jornadaLaboral === JornadaLaboral.MEDIO_TIEMPO
              ? (row.patronJornada ?? null)
              : null,
        },
      });
    }
    if (plan.mode !== "REUSE") {
      await tx.operario.create({
        data: {
          id: row.cedula,
          empresaId,
          funciones: row.funciones,
          cursoSalvamentoAcuatico: row.cursoSalvamentoAcuatico,
          urlEvidenciaSalvamento: row.urlEvidenciaSalvamento ?? null,
          cursoAlturas: row.cursoAlturas,
          urlEvidenciaAlturas: row.urlEvidenciaAlturas ?? null,
          examenIngreso: row.examenIngreso,
          urlEvidenciaExamenIngreso: row.urlEvidenciaExamenIngreso ?? null,
          fechaIngreso: row.fechaIngreso,
          fechaSalida: row.fechaSalida ?? null,
          fechaUltimasVacaciones: row.fechaUltimasVacaciones ?? null,
          observaciones: row.observaciones ?? null,
          disponibilidadPeriodos: {
            create: plan.disponibilidad.map((periodo) => ({
              fechaInicio: periodo.fechaInicio,
              fechaFin: periodo.fechaFin ?? null,
              trabajaDomingo: periodo.trabajaDomingo,
              diaDescanso: periodo.diaDescanso ?? null,
              observaciones: periodo.observaciones ?? null,
            })),
          },
        },
      });
    }
  }

  private async resolverRutasCreadas(conjuntoId: string) {
    const createdLocations = await this.prisma.ubicacion.findMany({
      where: { conjuntoId },
      select: {
        id: true,
        nombre: true,
        elementos: { select: { id: true, nombre: true, padreId: true } },
      },
    });
    const paths = new Map<string, { ubicacionId: number; elementoId: number }>();
    for (const ubicacion of createdLocations) {
      const zonas = new Map(
        ubicacion.elementos
          .filter((elemento) => elemento.padreId == null)
          .map((elemento) => [elemento.id, elemento]),
      );
      for (const area of ubicacion.elementos.filter(
        (elemento) => elemento.padreId != null,
      )) {
        const zona = zonas.get(area.padreId!);
        if (!zona) continue;
        paths.set(
          normalizedLocationKey(ubicacion.nombre, zona.nombre, area.nombre),
          { ubicacionId: ubicacion.id, elementoId: area.id },
        );
      }
    }
    return paths;
  }

  private resumenVacio(preventivasTotal: number) {
    return {
      horarios: 0,
      ubicaciones: 0,
      operariosCreados: 0,
      operariosReutilizados: 0,
      preventivasTotal,
      preventivasCreadas: 0,
      preventivasFallidas: preventivasTotal,
      definicionesCreadas: 0,
      insumosPreventivas: 0,
      maquinariaPreventivas: 0,
      herramientasPreventivas: 0,
    };
  }
}
