import { Router } from "express";
import {
  Rol,
  EstadoCivil,
  EPS,
  FondoPension,
  JornadaLaboral,
  TipoSangre,
  TallaCamisa,
  TallaPantalon,
  TallaCalzado,
  TipoContrato,
  TipoFuncion,
  PatronJornada,
} from "../generated/prisma";

const router = Router();

router.get("/enums/usuario", (_req, res) => {
  res.json({
    rol: Object.values(Rol),
    estadoCivil: Object.values(EstadoCivil),
    eps: Object.values(EPS),
    fondoPensiones: Object.values(FondoPension),
    jornadaLaboral: Object.values(JornadaLaboral),
    tipoSangre: Object.values(TipoSangre),
    tallaCamisa: Object.values(TallaCamisa),
    tallaPantalon: Object.values(TallaPantalon),
    tallaCalzado: Object.values(TallaCalzado),
    tipoContrato: Object.values(TipoContrato),
    tipoFuncion: Object.values(TipoFuncion),
    patronesJornada: Object.values(PatronJornada)
  });
});

export default router;
