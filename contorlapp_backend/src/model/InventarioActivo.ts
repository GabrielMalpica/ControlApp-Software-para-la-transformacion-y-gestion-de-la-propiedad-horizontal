import {
  CategoriaHerramienta,
  CondicionActivo,
  EstadoHerramienta,
  EstadoMaquinaria,
  ModoControlHerramienta,
  PropietarioMaquinaria,
  TipoMaquinaria,
} from "@prisma/client";
import { z } from "zod";

const textoOpcional = z.string().trim().max(120).nullish();

const ListaActivosQueryBase = z.object({
  q: z.string().trim().max(120).optional(),
  aprobacion: z.enum(["PENDIENTE", "APROBADA", "RECHAZADA"]).optional(),
  propietario: z.nativeEnum(PropietarioMaquinaria).optional(),
  catalogoId: z.coerce.number().int().positive().optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

export const ListaMaquinariaQuery = ListaActivosQueryBase.extend({
  estado: z.nativeEnum(EstadoMaquinaria).optional(),
}).strict();

export const ListaHerramientasQuery = ListaActivosQueryBase.extend({
  estado: z.nativeEnum(EstadoHerramienta).optional(),
}).strict();

export const TipoMaquinariaPropuesto = z.object({
  nombre: z.string().trim().min(2).max(100),
  tipoLegacy: z.nativeEnum(TipoMaquinaria).optional().default(TipoMaquinaria.OTRO),
}).strict();

export const CrearMaquinariaInventarioBody = z.object({
  tipoCatalogoId: z.coerce.number().int().positive().optional(),
  tipoPropuesto: TipoMaquinariaPropuesto.optional(),
  marca: z.string().trim().min(1).max(100).default("Sin especificar"),
  modelo: textoOpcional,
  serial: textoOpcional,
  alias: textoOpcional,
  estado: z.nativeEnum(EstadoMaquinaria).optional().default(EstadoMaquinaria.OPERATIVA),
  condicion: z.nativeEnum(CondicionActivo).optional(),
}).strict().superRefine((value, ctx) => {
  if (Boolean(value.tipoCatalogoId) === Boolean(value.tipoPropuesto)) {
    ctx.addIssue({
      code: "custom",
      message: "Selecciona un tipo de maquinaria o propón uno nuevo.",
      path: ["tipoCatalogoId"],
    });
  }
});

export const TipoHerramientaPropuesto = z.object({
  nombre: z.string().trim().min(2).max(100),
  unidad: z.string().trim().min(1).max(30).default("UNIDAD"),
  categoria: z.nativeEnum(CategoriaHerramienta).optional().default(CategoriaHerramienta.OTROS),
  modoControl: z.nativeEnum(ModoControlHerramienta).optional().default(ModoControlHerramienta.PRESTAMO),
  vidaUtilDias: z.coerce.number().int().positive().max(36500).nullish(),
  umbralBajo: z.coerce.number().int().min(0).nullish(),
}).strict();

export const CrearHerramientasInventarioBody = z.object({
  herramientaId: z.coerce.number().int().positive().optional(),
  tipoPropuesto: TipoHerramientaPropuesto.optional(),
  cantidad: z.coerce.number().int().min(1).max(500).default(1),
  marca: textoOpcional,
  modelo: textoOpcional,
  serial: textoOpcional,
  alias: textoOpcional,
  estado: z.nativeEnum(EstadoHerramienta).optional().default(EstadoHerramienta.OPERATIVA),
  condicion: z.nativeEnum(CondicionActivo).optional(),
}).strict().superRefine((value, ctx) => {
  if (Boolean(value.herramientaId) === Boolean(value.tipoPropuesto)) {
    ctx.addIssue({
      code: "custom",
      message: "Selecciona un tipo de herramienta o propón uno nuevo.",
      path: ["herramientaId"],
    });
  }
  if (value.cantidad > 1 && value.serial) {
    ctx.addIssue({
      code: "custom",
      message: "El serial solo puede registrarse cuando se crea una unidad.",
      path: ["serial"],
    });
  }
});

export const EditarActivoBody = z.object({
  alias: textoOpcional,
  marca: textoOpcional,
  modelo: textoOpcional,
  serial: textoOpcional,
}).strict().refine((value) => Object.values(value).some((item) => item !== undefined), {
  message: "Debes enviar al menos un campo para actualizar.",
});

export const AprobarActivoBody = z.object({
  catalogoDestinoId: z.coerce.number().int().positive().optional(),
}).strict();

export const RechazarActivoBody = z.object({
  motivo: z.string().trim().min(5).max(500),
}).strict();

export const CambiarEstadoMaquinariaBody = z.object({
  estado: z.nativeEnum(EstadoMaquinaria),
  motivo: z.string().trim().min(3).max(500),
  condicion: z.nativeEnum(CondicionActivo).optional(),
}).strict();

export const CambiarEstadoHerramientaBody = z.object({
  estado: z.nativeEnum(EstadoHerramienta),
  motivo: z.string().trim().min(3).max(500),
  condicion: z.nativeEnum(CondicionActivo).optional(),
}).strict();

export const PrestarActivoBody = z.object({
  conjuntoId: z.string().trim().min(3),
  fechaInicio: z.coerce.date(),
  fechaDevolucionEstimada: z.coerce.date(),
  responsableId: z.string().trim().min(1).optional(),
  tareaId: z.coerce.number().int().positive().optional(),
}).strict().refine((value) => value.fechaDevolucionEstimada > value.fechaInicio, {
  message: "La devolución estimada debe ser posterior al inicio.",
  path: ["fechaDevolucionEstimada"],
});

export const IdActivoParam = z.object({ id: z.coerce.number().int().positive() });
export const LoteActivoParam = z.object({ loteId: z.string().trim().min(8).max(100) });
