import {
  aplicarCambioOperarios,
  calcularCambioOperariosActividad,
} from "../../src/services/PlazaTitularSync";

describe("calcularCambioOperariosActividad", () => {
  test("reemplazo directo: sale el anterior y entra el nuevo", () => {
    expect(
      calcularCambioOperariosActividad({
        operariosActuales: ["pepito"],
        titularesOtrasPlazas: [],
        anteriorId: "pepito",
        nuevoId: "juanito",
      }),
    ).toEqual({ quitar: ["pepito"], agregar: ["juanito"] });
  });

  test("actividad compartida: solo cambia el puesto de esta plaza", () => {
    const cambio = calcularCambioOperariosActividad({
      operariosActuales: ["pepito", "maria"],
      titularesOtrasPlazas: ["maria"],
      anteriorId: "pepito",
      nuevoId: "juanito",
    });
    expect(cambio).toEqual({ quitar: ["pepito"], agregar: ["juanito"] });
    expect(aplicarCambioOperarios(["pepito", "maria"], cambio)).toEqual(["maria", "juanito"]);
  });

  test("plaza que estaba vacante: el nuevo entra solo si nadie cubre el puesto", () => {
    expect(
      calcularCambioOperariosActividad({
        operariosActuales: ["maria"],
        titularesOtrasPlazas: ["maria"],
        anteriorId: null,
        nuevoId: "juanito",
      }),
    ).toEqual({ quitar: [], agregar: ["juanito"] });

    // Alguien fue asignado a mano en ese puesto: se respeta.
    expect(
      calcularCambioOperariosActividad({
        operariosActuales: ["carlos"],
        titularesOtrasPlazas: [],
        anteriorId: null,
        nuevoId: "juanito",
      }),
    ).toEqual({ quitar: [], agregar: [] });
  });

  test("si el anterior sigue en la actividad por otra plaza, no sale", () => {
    expect(
      calcularCambioOperariosActividad({
        operariosActuales: ["pepito"],
        titularesOtrasPlazas: ["pepito"],
        anteriorId: "pepito",
        nuevoId: null,
      }),
    ).toEqual({ quitar: [], agregar: [] });
  });

  test("excepción puntual: si el anterior no estaba, no se toca", () => {
    expect(
      calcularCambioOperariosActividad({
        operariosActuales: ["carlos"],
        titularesOtrasPlazas: [],
        anteriorId: "pepito",
        nuevoId: "juanito",
      }),
    ).toEqual({ quitar: [], agregar: [] });
  });

  test("mismo titular: no hay cambio", () => {
    expect(
      calcularCambioOperariosActividad({
        operariosActuales: ["pepito"],
        titularesOtrasPlazas: [],
        anteriorId: "pepito",
        nuevoId: "pepito",
      }),
    ).toEqual({ quitar: [], agregar: [] });
  });
});
