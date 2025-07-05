import { Maquinaria } from "./maquinaria";
import { Gerente } from "./gerente";
import { JefeOperaciones } from "./jefeOperaciones";
import { SolicitudTarea } from "./solicitudTarea";

export class Empresa {
  nombre: string;
  nit: string;
  stockMaquinaria: Maquinaria[] = [];
  gerente: Gerente;
  jefesOperaciones: JefeOperaciones[] = [];
  solicitudesPendientes: SolicitudTarea[] = [];

  constructor(nombre: string, nit: string, gerente: Gerente, jefesOperaciones: JefeOperaciones[]) {
    if (jefesOperaciones.length === 0) {
      throw new Error("Debe haber al menos un Jefe de Operaciones");
    }

    this.nombre = nombre;
    this.nit = nit;
    this.gerente = gerente;
    this.jefesOperaciones = jefesOperaciones;
  }
}
