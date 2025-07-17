import { Maquinaria } from "./Maquinaria";
import { Gerente } from "./Gerente";
import { JefeOperaciones } from "./JefeOperaciones";
import { SolicitudTarea } from "./SolicitudTarea";
import { SolicitudInsumo } from "./SolicitudInsumo";
import { SolicitudMaquinaria } from "./SolicitudMaquinaria";
import { Insumo } from "./Insumo";
import { Tarea } from "./Tarea";
import { Conjunto } from "./Conjunto";

export class Empresa {
  nombre: string;
  nit: string;
  stockMaquinaria: Maquinaria[] = [];
  gerente: Gerente;
  conjuntos: Conjunto[] = [];
  jefesOperaciones: JefeOperaciones[] = [];
  solicitudesTareas: SolicitudTarea[] = [];
  solicitudesInsumos: SolicitudInsumo[] = [];
  solicitudesMaquinaria: SolicitudMaquinaria[] = [];
  catalogoInsumos: Insumo[] = [];
  tareasAprobadas: Tarea[] = [];
  tareasRechazadas: Tarea[] = [];
  insumosConsumidos: { insumo: Insumo, cantidad: number, fecha: Date }[] = [];

  constructor(nombre: string, nit: string, gerente: Gerente, jefesOperaciones?: JefeOperaciones[]) {
    this.nombre = nombre;
    this.nit = nit;
    this.gerente = gerente;
    this.jefesOperaciones = jefesOperaciones ?? [];
  }
}