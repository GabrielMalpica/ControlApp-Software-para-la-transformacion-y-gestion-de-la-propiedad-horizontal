import bcrypt from 'bcrypt';
import { Gerente } from "../model/gerente";
import { Usuario } from "../model/usuario";

type UsuarioRegistrado = {
  correo: string;
  contrasena: string;
  rol: string;
};

export class AuthService {
  private usuariosRegistrados: UsuarioRegistrado[] = [];

  constructor(private empresa: any) {} // Puedes tipar mejor si defines una interfaz

  // ─── Registro inicial del gerente ─────────────────────
  preRegistrarGerente(gerente: Gerente): void {
    this.usuariosRegistrados.push({
      correo: gerente.correo,
      contrasena: gerente.contrasena,
      rol: 'Gerente'
    });
  }

  // ─── Registrar nuevos usuarios ────────────────────────
  registrarUsuario(registradoPor: Usuario, nuevoUsuario: Usuario): void {
    const esGerente = registradoPor instanceof Gerente;

    if (!esGerente) {
      throw new Error("Solo el gerente puede registrar nuevos usuarios.");
    }

    const yaExiste = this.usuariosRegistrados.find(u => u.correo === nuevoUsuario.correo);
    if (yaExiste) {
      throw new Error("Este correo ya está registrado.");
    }

    const passwordHash = bcrypt.hashSync(nuevoUsuario.contrasena, 10);

    this.usuariosRegistrados.push({
      correo: nuevoUsuario.correo,
      contrasena: passwordHash,
      rol: nuevoUsuario.constructor.name
    });
  }

  // ─── Login de usuario ────────────────────────────────
  login(correo: string, password: string): UsuarioRegistrado | null {
    const usuario = this.usuariosRegistrados.find(u => u.correo === correo);

    if (!usuario) return null;

    const match = bcrypt.compareSync(password, usuario.contrasena);
    return match ? usuario : null;
  }

  // ─── Obtener lista de usuarios (opcional para pruebas) ──
  listarUsuarios(): UsuarioRegistrado[] {
    return this.usuariosRegistrados;
  }
}
