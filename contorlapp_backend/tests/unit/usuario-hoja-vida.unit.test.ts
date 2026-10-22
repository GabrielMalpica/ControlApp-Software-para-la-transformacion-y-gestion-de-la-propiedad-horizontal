// Datos de hoja de vida del usuario: ARL, caja de compensación y contacto de
// emergencia (nombre, parentesco, teléfono). Son opcionales, se editan desde
// crear/editar usuario y la edición rápida del administrador, y no salen por
// MCP. Ver docs/planilla-personal.md.
import { EditarAdministradorDTO } from "../../src/model/Administrador";
import { CrearUsuarioDTO, EditarUsuarioDTO, usuarioPublicSelect } from "../../src/model/Usuario";

const base = {
  id: "1032456789",
  nombre: "Carlos Pérez",
  correo: "carlos@test.com",
  contrasena: "12345678",
  rol: "operario",
  telefono: "3001234567",
  fechaNacimiento: "1992-06-15",
};

describe("hoja de vida del usuario", () => {
  test("crear acepta ARL, caja y contacto de emergencia, y recorta espacios", () => {
    const dto = CrearUsuarioDTO.parse({
      ...base,
      arl: "POSITIVA",
      cajaCompensacion: "COLSUBSIDIO",
      contactoEmergenciaNombre: "  Rosa Pérez ",
      contactoEmergenciaParentesco: "Madre",
      contactoEmergenciaTelefono: " +57 (310) 555-1234 ",
    });
    expect(dto).toMatchObject({
      arl: "POSITIVA",
      cajaCompensacion: "COLSUBSIDIO",
      contactoEmergenciaNombre: "Rosa Pérez",
      contactoEmergenciaParentesco: "Madre",
      contactoEmergenciaTelefono: "+57 (310) 555-1234",
    });
  });

  test("todo es opcional y el texto vacío se guarda como vacío (null)", () => {
    expect(CrearUsuarioDTO.parse(base).arl).toBeUndefined();
    const dto = EditarUsuarioDTO.parse({
      arl: null,
      cajaCompensacion: null,
      contactoEmergenciaNombre: "",
      contactoEmergenciaParentesco: "   ",
      contactoEmergenciaTelefono: "",
    });
    expect(dto).toEqual({
      arl: null,
      cajaCompensacion: null,
      contactoEmergenciaNombre: null,
      contactoEmergenciaParentesco: null,
      contactoEmergenciaTelefono: null,
    });
  });

  test("rechaza valores fuera de la lista y teléfonos inválidos", () => {
    expect(EditarUsuarioDTO.safeParse({ arl: "OTRA" }).success).toBe(false);
    expect(EditarUsuarioDTO.safeParse({ cajaCompensacion: "CAJA_X" }).success).toBe(false);
    for (const telefono of ["310-ABC-1234", "12345", "1234567890123456"]) {
      const r = EditarUsuarioDTO.safeParse({ contactoEmergenciaTelefono: telefono });
      expect(r.success).toBe(false);
    }
    expect(EditarUsuarioDTO.safeParse({ contactoEmergenciaTelefono: "6011234567" }).success).toBe(true);
    expect(EditarUsuarioDTO.safeParse({ contactoEmergenciaNombre: "x".repeat(121) }).success).toBe(false);
  });

  test("la edición rápida del administrador también los acepta", () => {
    const dto = EditarAdministradorDTO.parse({
      arl: "SURA",
      cajaCompensacion: "COMPENSAR",
      contactoEmergenciaTelefono: "3105551234",
    });
    expect(dto).toMatchObject({ arl: "SURA", cajaCompensacion: "COMPENSAR" });
  });

  test("la lista de usuarios los devuelve (crear/editar/detalle los leen de ahí)", () => {
    for (const campo of [
      "arl",
      "cajaCompensacion",
      "contactoEmergenciaNombre",
      "contactoEmergenciaParentesco",
      "contactoEmergenciaTelefono",
    ]) {
      expect(usuarioPublicSelect).toHaveProperty(campo, true);
    }
    expect(usuarioPublicSelect).not.toHaveProperty("contrasena");
  });
});
