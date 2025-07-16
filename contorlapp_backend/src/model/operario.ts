import { Usuario } from "./usuario";
import { TipoFuncion } from "./enum/tipoFuncion";
import { Tarea } from "./tarea";
import { Conjunto } from "./conjunto";
import { EstadoCivil } from "./enum/estadoCivil";
import { TipoSangre } from "./enum/tipoSangre";
import { EPS } from "./enum/eps";
import { FondoPension } from "./enum/fondePensiones";
import { TallaCamisa } from "./enum/tallaCamisa";
import { TallaPantalon } from "./enum/tallaPantalon";
import { TallaCalzado } from "./enum/tallaCalzado";
import { TipoContrato } from "./enum/tipoContrato";
import { JornadaLaboral } from "./enum/jornadaLaboral";

export class Operario extends Usuario {
  funciones: TipoFuncion[];
  tareas: Tarea[] = [];
  conjuntos: Conjunto[] = [];
  static LIMITE_SEMANAL_HORAS = 46;

  cursoSalvamentoAcuatico: boolean;
  urlEvidenciaSalvamento?: string;

  cursoAlturas: boolean;
  urlEvidenciaAlturas?: string;

  examenIngreso: boolean;
  urlEvidenciaExamenIngreso?: string;

  fechaIngreso: Date;
  fechaUltimasVacaciones?: Date;
  observaciones?: string;

  constructor(
    id: number,
    nombre: string,
    correo: string,
    contrasena: string,
    telefono: number,
    fechaNacimiento: Date,
    direccion: string,
    estadoCivil: EstadoCivil,
    numeroHijos: number,
    padresVivos: boolean,
    tipoSangre: TipoSangre,
    eps: EPS,
    fondoPensiones: FondoPension,
    tallaCamisa: TallaCamisa,
    tallaPantalon: TallaPantalon,
    tallaCalzado: TallaCalzado,
    tipoContrato: TipoContrato,
    jornadaLaboral: JornadaLaboral,
    funciones: TipoFuncion[],
    cursoSalvamentoAcuatico: boolean,
    urlEvidenciaSalvamento: string | undefined,
    cursoAlturas: boolean,
    urlEvidenciaAlturas: string | undefined,
    examenIngreso: boolean,
    urlEvidenciaExamenIngreso: string | undefined,
    fechaIngreso: Date
  ) {
    super(
      id,
      nombre,
      correo,
      contrasena,
      'operario',
      telefono,
      fechaNacimiento,
      direccion,
      estadoCivil,
      numeroHijos,
      padresVivos,
      tipoSangre,
      eps,
      fondoPensiones,
      tallaCamisa,
      tallaPantalon,
      tallaCalzado,
      tipoContrato,
      jornadaLaboral
    );

    this.funciones = funciones;
    this.cursoSalvamentoAcuatico = cursoSalvamentoAcuatico;
    this.urlEvidenciaSalvamento = urlEvidenciaSalvamento;
    this.cursoAlturas = cursoAlturas;
    this.urlEvidenciaAlturas = urlEvidenciaAlturas;
    this.examenIngreso = examenIngreso;
    this.urlEvidenciaExamenIngreso = urlEvidenciaExamenIngreso;
    this.fechaIngreso = fechaIngreso;
  }
}
