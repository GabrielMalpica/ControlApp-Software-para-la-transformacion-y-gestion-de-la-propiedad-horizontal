import { EPS } from "./enum/eps";
import { EstadoCivil } from "./enum/estadoCivil";
import { FondoPension } from "./enum/fondePensiones";
import { JornadaLaboral } from "./enum/jornadaLaboral";
import { TallaCalzado } from "./enum/tallaCalzado";
import { TallaCamisa } from "./enum/tallaCamisa";
import { TallaPantalon } from "./enum/tallaPantalon";
import { TipoContrato } from "./enum/tipoContrato";
import { TipoSangre } from "./enum/tipoSangre";

export class Usuario {
  id: number;
  nombre: string;
  correo: string;
  contrasena: string;
  rol: string;
  telefono: number;
  fechaNacimiento: Date;
  direccion?: string;
  estadoCivil?: EstadoCivil;
  numeroHijos?: number;
  padresVivos?: boolean;
  tipoSangre?: TipoSangre;
  eps?: EPS;
  fondoPensiones?: FondoPension;
  tallaCamisa?: TallaCamisa;
  tallaPantalon?: TallaPantalon;
  tallaCalzado?: TallaCalzado;
  tipoContrato?: TipoContrato;
  jornadaLaboral?: JornadaLaboral;

  constructor(
    id: number,
    nombre: string,
    correo: string,
    contrasena: string,
    rol: string,
    telefono: number,
    fechaNacimiento: Date,
    direccion?: string,
    estadoCivil?: EstadoCivil,
    numeroHijos?: number,
    padresVivos?: boolean,
    tipoSangre?: TipoSangre,
    eps?: EPS,
    fondoPensiones?: FondoPension,
    tallaCamisa?: TallaCamisa,
    tallaPantalon?: TallaPantalon,
    tallaCalzado?: TallaCalzado,
    tipoContrato?: TipoContrato,
    jornadaLaboral?: JornadaLaboral
  ) {
    this.id = id;
    this.nombre = nombre;
    this.correo = correo;
    this.contrasena = contrasena;
    this.rol = rol;
    this.telefono = telefono;
    this.fechaNacimiento = fechaNacimiento;
    this.direccion = direccion;
    this.estadoCivil = estadoCivil;
    this.numeroHijos = numeroHijos;
    this.padresVivos = padresVivos;
    this.tipoSangre = tipoSangre;
    this.eps = eps;
    this.fondoPensiones = fondoPensiones;
    this.tallaCamisa = tallaCamisa;
    this.tallaPantalon = tallaPantalon;
    this.tallaCalzado = tallaCalzado;
    this.tipoContrato = tipoContrato;
    this.jornadaLaboral = jornadaLaboral;
  }
}
