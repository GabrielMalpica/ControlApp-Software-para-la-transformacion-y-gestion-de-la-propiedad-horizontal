import { EPS } from "./enum/eps";
import { EstadoCivil } from "./enum/estadoCivil";
import { FondoPension } from "./enum/fondePensiones";
import { JornadaLaboral } from "./enum/jornadaLaboral";
import { TallaCalzado } from "./enum/tallaCalzado";
import { TallaCamisa } from "./enum/tallaCamisa";
import { TallaPantalon } from "./enum/tallaPantalon";
import { TipoContrato } from "./enum/tipoContrato";
import { TipoSangre } from "./enum/tipoSangre";
import { Usuario } from "./usuario";

export class JefeOperaciones extends Usuario{

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
  ) {
    super(
      id,
      nombre,
      correo,
      contrasena,
      'jefe-operaciones',
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
  }
}