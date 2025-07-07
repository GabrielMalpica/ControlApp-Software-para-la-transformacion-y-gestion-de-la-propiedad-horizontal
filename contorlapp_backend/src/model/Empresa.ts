import { Maquinaria } from "./maquinaria";
import { Gerente } from "./gerente";
import { JefeOperaciones } from "./jefeOperaciones";
import { SolicitudTarea } from "./solicitudTarea";
import { SolicitudInsumo } from "./SolicitudInsumo";
import { SolicitudMaquinaria } from "./SolicitudMaquinaria";
import { Insumo } from "./insumo";

export class Empresa {
  nombre: string;
  nit: string;
  stockMaquinaria: Maquinaria[] = [];
  gerente: Gerente;
  jefesOperaciones: JefeOperaciones[] = [];
  solicitudesTareas: SolicitudTarea[] = [];
  solicitudesInsumos: SolicitudInsumo[] = [];
  solicitudesMaquinaria: SolicitudMaquinaria[] = [];
  catalogoInsumos: Insumo[] = [];

  constructor(nombre: string, nit: string, gerente: Gerente, jefesOperaciones?: JefeOperaciones[]) {
    this.nombre = nombre;
    this.nit = nit;
    this.gerente = gerente;
    this.jefesOperaciones = jefesOperaciones ?? [];
  }
}