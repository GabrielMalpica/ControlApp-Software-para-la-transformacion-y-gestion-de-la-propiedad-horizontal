// Prueba contra una base REAL de PostgreSQL (clon con la migración aplicada).
// Se omite si TEST_DATABASE_URL no está definida. Por seguridad solo corre
// contra bases cuyo nombre contenga "test" (nunca contra controlapp_bd).
//
//   TEST_DATABASE_URL=postgresql://...:55432/controlapp_migtest?schema=public \
//     npx jest tests/integration/catalogo-operativo.db.test.ts --runInBand
import { PrismaClient } from "@prisma/client";

import {
  CATEGORIAS_POR_DEFECTO,
  CatalogoOperativoService,
} from "../../src/services/CatalogoOperativoService";
import { ConjuntoNecesidadService } from "../../src/services/ConjuntoNecesidadService";
import { DefinicionTareaPreventivaService } from "../../src/services/DefinicionTareaPreventivaService";

const URL = process.env.TEST_DATABASE_URL;
const seguro = !!URL && /test/i.test(URL.split("/").pop() ?? "");
const suite = seguro ? describe : describe.skip;

const EMPRESA = "TEST-CAT-EMPRESA";
const EMPRESA_B = "TEST-CAT-EMPRESA-B";

suite("CatalogoOperativoService (PostgreSQL real)", () => {
  const prisma = new PrismaClient({ datasourceUrl: URL });
  const service = new CatalogoOperativoService(prisma);

  async function limpiar() {
    for (const nit of [EMPRESA, EMPRESA_B]) {
      await prisma.conjuntoNecesidadOperario.deleteMany({ where: { conjunto: { empresaId: nit } } });
      await prisma.perfilOperativo.deleteMany({ where: { empresaId: nit } });
      await prisma.definicionTareaPreventiva.deleteMany({ where: { conjunto: { empresaId: nit } } });
      await prisma.conjunto.deleteMany({ where: { empresaId: nit } });
      await prisma.operario.deleteMany({ where: { empresaId: nit } });
      await prisma.usuario.deleteMany({ where: { correo: { startsWith: `test-cat-${nit}` } } });
      await prisma.empresa.deleteMany({ where: { nit } });
    }
  }

  beforeAll(async () => {
    await limpiar();
    await prisma.empresa.create({ data: { nombre: "Empresa test", nit: EMPRESA } });
    await prisma.empresa.create({ data: { nombre: "Empresa test B", nit: EMPRESA_B } });
  });

  afterAll(async () => {
    await limpiar();
    await prisma.$disconnect();
  });

  it("siembra las 7 categorías por defecto una sola vez (idempotente) en el orden pedido", async () => {
    const a = await service.listarCategorias(EMPRESA);
    const b = await service.listarCategorias(EMPRESA);
    expect(a.map((c) => c.nombre)).toEqual(CATEGORIAS_POR_DEFECTO.map((c) => c.nombre));
    expect(a.map((c) => c.ordenProgramacion)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(b).toHaveLength(7);
  });

  it("crea categorías nuevas al final, rechaza duplicados (sin importar acentos/mayúsculas) y valida el color", async () => {
    const nueva = await service.crearCategoria(EMPRESA, {
      nombre: "Control de plagas",
      colorHex: "#aa00bb",
      palabrasClave: ["plaga", "Plaga", " fumigacion "],
    });
    expect(nueva.ordenProgramacion).toBe(8);
    expect(nueva.colorHex).toBe("#AA00BB");
    expect(nueva.palabrasClave).toEqual(["plaga", "fumigacion"]);
    await expect(service.crearCategoria(EMPRESA, { nombre: "JARDINERIA" })).rejects.toMatchObject({
      status: 409,
    });
    await expect(service.crearCategoria(EMPRESA, { nombre: "X", colorHex: "rojo" })).rejects.toMatchObject({
      status: 400,
    });
    await expect(service.crearCategoria(EMPRESA, { nombre: "  " })).rejects.toMatchObject({ status: 400 });
  });

  it("el mismo nombre se permite en otra empresa (alcance por empresa)", async () => {
    const otras = await service.listarCategorias(EMPRESA_B);
    expect(otras.some((c) => c.nombre === "Poda")).toBe(true);
    await expect(
      service.editarCategoria(EMPRESA_B, (await service.listarCategorias(EMPRESA)).find((c) => c.nombre === "Poda")!.id, {
        activa: false,
      }),
    ).rejects.toMatchObject({ status: 404 });
  });

  it("reordena reescribiendo 1..n y rechaza listas incompletas o con ids ajenos", async () => {
    const cats = await service.listarCategorias(EMPRESA);
    const invertido = [...cats].reverse().map((c) => c.id);
    const r = await service.reordenarCategorias(EMPRESA, invertido);
    expect(r.map((c) => c.id)).toEqual(invertido);
    expect(r.map((c) => c.ordenProgramacion)).toEqual(cats.map((_, i) => i + 1));

    await expect(service.reordenarCategorias(EMPRESA, invertido.slice(1))).rejects.toMatchObject({ status: 400 });
    await expect(service.reordenarCategorias(EMPRESA, [...invertido.slice(1), 999999])).rejects.toMatchObject({
      status: 400,
    });
    await expect(service.reordenarCategorias(EMPRESA, [...invertido.slice(1), invertido[1]])).rejects.toMatchObject({
      status: 400,
    });
    // Se restaura el orden de fábrica para los demás casos.
    await service.reordenarCategorias(EMPRESA, cats.map((c) => c.id));
  });

  it("cambiar la prioridad de una categoría solo cambia su orden (Poda antes que Piscinas)", async () => {
    const cats = await service.listarCategorias(EMPRESA);
    const piscinas = cats.find((c) => c.nombre === "Mantenimiento de piscinas")!;
    const poda = cats.find((c) => c.nombre === "Poda")!;
    const ids = cats.map((c) => c.id);
    ids.splice(ids.indexOf(poda.id), 1);
    ids.splice(ids.indexOf(piscinas.id), 0, poda.id);
    const r = await service.reordenarCategorias(EMPRESA, ids);
    expect(r[0].id).toBe(poda.id);
    expect(r[1].id).toBe(piscinas.id);
    await service.reordenarCategorias(EMPRESA, cats.map((c) => c.id));
  });

  it("crea, edita y consulta perfiles con sus categorías permitidas", async () => {
    const cats = await service.listarCategorias(EMPRESA);
    const id = (n: string) => cats.find((c) => c.nombre === n)!.id;
    const perfil = await service.crearPerfil(EMPRESA, {
      nombre: "Todero-Salvavidas",
      roles: ["SALVAVIDAS", "TODERO"],
      categoriasIds: [id("Poda"), id("Jardinería"), id("Salvamento acuático")],
    });
    expect(perfil.roles).toEqual(["TODERO", "SALVAVIDAS"]);
    expect(perfil.categoriasIds).toEqual(
      [id("Poda"), id("Jardinería"), id("Salvamento acuático")].sort((a, b) => a - b),
    );
    expect(perfil.plazas).toBe(0);

    const editado = await service.editarPerfil(EMPRESA, perfil.id, {
      categoriasIds: [id("Poda")],
      activo: false,
    });
    expect(editado.categoriasIds).toEqual([id("Poda")]);
    expect(editado.activo).toBe(false);

    await expect(
      service.crearPerfil(EMPRESA, { nombre: "todero-salvavidas", roles: ["TODERO"] }),
    ).rejects.toMatchObject({ status: 409 });
    await expect(
      service.crearPerfil(EMPRESA, { nombre: "Sin roles", roles: [] }),
    ).rejects.toMatchObject({ status: 400 });
    await expect(
      service.crearPerfil(EMPRESA, { nombre: "Cat ajena", roles: ["ASEO"], categoriasIds: [999999] }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("resolverPerfilParaRoles reutiliza el perfil de esos roles o lo crea sin categorías", async () => {
    const a = await service.resolverPerfilParaRoles(EMPRESA, ["TODERO", "SALVAVIDAS"]);
    const b = await service.resolverPerfilParaRoles(EMPRESA, ["SALVAVIDAS", "TODERO"]);
    expect(b.id).toBe(a.id);
    const nuevo = await service.resolverPerfilParaRoles(EMPRESA, ["JARDINERO"]);
    expect(nuevo.nombre).toBe("Jardinero");
    const categorias = await prisma.perfilOperativoCategoria.count({ where: { perfilId: nuevo.id } });
    expect(categorias).toBe(0);
  });

  describe("plazas enlazadas a perfiles (ConjuntoNecesidadService)", () => {
    const NIT = "TEST-CAT-CONJ-PLAZAS";
    let plazas: ConjuntoNecesidadService;

    beforeAll(async () => {
      await prisma.conjunto.create({
        data: { nit: NIT, nombre: "Conjunto plazas", direccion: "x", correo: "p@x.com", empresaId: EMPRESA },
      });
      plazas = new ConjuntoNecesidadService(prisma, NIT);
    });

    it("crear con perfilId toma los roles del perfil", async () => {
      const perfil = await service.crearPerfil(EMPRESA, { nombre: "Perfil Aseo Test", roles: ["ASEO"] });
      const plaza = await plazas.crear({ perfilId: perfil.id, etiqueta: "Aseo test #1" });
      expect(plaza.perfilId).toBe(perfil.id);
      expect(plaza.roles).toEqual(["ASEO"]);
      expect(plaza.perfil?.nombre).toBe("Perfil Aseo Test");
    });

    it("crear solo con roles reutiliza el perfil de esa combinación (no deja plazas aisladas)", async () => {
      const existente = await service.resolverPerfilParaRoles(EMPRESA, ["PISCINERO"]);
      const plaza = await plazas.crear({ roles: ["PISCINERO"], etiqueta: "Piscinero test #1" });
      expect(plaza.perfilId).toBe(existente.id);
      const otra = await plazas.crear({ roles: ["PISCINERO"], etiqueta: "Piscinero test #2" });
      expect(otra.perfilId).toBe(existente.id);
    });

    it("rechaza un perfil de otra empresa y un perfil desactivado", async () => {
      const ajeno = await service.crearPerfil(EMPRESA_B, { nombre: "Ajeno", roles: ["ASEO"] });
      await expect(plazas.crear({ perfilId: ajeno.id, etiqueta: "X ajeno" })).rejects.toThrow(/no encontrado/i);
      const inactivo = await service.crearPerfil(EMPRESA, { nombre: "Inactivo test", roles: ["ASEO"] });
      await service.editarPerfil(EMPRESA, inactivo.id, { activo: false });
      await expect(plazas.crear({ perfilId: inactivo.id, etiqueta: "X inactivo" })).rejects.toThrow(/desactivado/i);
    });

    it("editar con otro perfilId cambia perfil y roles; sin perfil ni roles no cambia nada", async () => {
      const a = await service.crearPerfil(EMPRESA, { nombre: "Edit A", roles: ["ASEO"] });
      const b = await service.crearPerfil(EMPRESA, { nombre: "Edit B", roles: ["JARDINERO"] });
      const plaza = await plazas.crear({ perfilId: a.id, etiqueta: "Edit plaza" });
      const editada = await plazas.editar(plaza.id, { perfilId: b.id });
      expect(editada.perfilId).toBe(b.id);
      expect(editada.roles).toEqual(["JARDINERO"]);
      const igual = await plazas.editar(plaza.id, { observaciones: "solo obs" });
      expect(igual.perfilId).toBe(b.id);
      expect(igual.roles).toEqual(["JARDINERO"]);
    });
  });

  describe("preventivas con categoría (DefinicionTareaPreventivaService)", () => {
    const NIT = "TEST-CAT-CONJ-PREV";
    let defs: DefinicionTareaPreventivaService;
    let ubicacionId: number;
    let elementoId: number;
    let catId: Record<string, number>;
    let plazaToderoId: number;
    let plazaSalvaId: number;

    const base = () => ({
      conjuntoId: NIT,
      ubicacionId,
      elementoId,
      frecuencia: "SEMANAL" as const,
      diaSemanaProgramado: "LUNES" as const,
      duracionMinutosFija: 30,
    });

    beforeAll(async () => {
      await prisma.conjunto.create({
        data: { nit: NIT, nombre: "Conjunto prev", direccion: "x", correo: "q@x.com", empresaId: EMPRESA },
      });
      await prisma.conjuntoHorario.create({
        data: { conjuntoId: NIT, dia: "LUNES", horaApertura: "07:00", horaCierre: "17:00" },
      });
      const u = await prisma.ubicacion.create({ data: { nombre: "U prev", conjuntoId: NIT } });
      ubicacionId = u.id;
      elementoId = (await prisma.elemento.create({ data: { nombre: "E prev", ubicacionId } })).id;
      defs = new DefinicionTareaPreventivaService(prisma);
      const cats = await service.listarCategorias(EMPRESA);
      catId = Object.fromEntries(cats.map((c) => [c.nombre, c.id]));
      const toderoPerfil = await service.crearPerfil(EMPRESA, {
        nombre: "Todero prev",
        roles: ["TODERO"],
        categoriasIds: [catId["Poda"], catId["Jardinería"]],
      });
      const salvaPerfil = await service.crearPerfil(EMPRESA, {
        nombre: "Salva prev",
        roles: ["SALVAVIDAS"],
      }); // sin capacidades configuradas
      plazaToderoId = (
        await prisma.conjuntoNecesidadOperario.create({
          data: { conjuntoId: NIT, roles: ["TODERO"], etiqueta: "Todero prev #1", perfilId: toderoPerfil.id },
        })
      ).id;
      plazaSalvaId = (
        await prisma.conjuntoNecesidadOperario.create({
          data: { conjuntoId: NIT, roles: ["SALVAVIDAS"], etiqueta: "Salva prev #1", perfilId: salvaPerfil.id },
        })
      ).id;
    });

    it("crea con categoría y orden interno; sin categoría descarta el orden", async () => {
      const a = await defs.crear({ ...base(), descripcion: "Poda zona A", categoriaId: catId["Poda"], ordenEnCategoria: 1 });
      expect(a.categoriaId).toBe(catId["Poda"]);
      expect(a.ordenEnCategoria).toBe(1);
      const sin = await defs.crear({ ...base(), descripcion: "Sin categoria", ordenEnCategoria: 5 });
      expect(sin.categoriaId).toBeNull();
      expect(sin.ordenEnCategoria).toBeNull();
    });

    it("conserva la prioridad de selección independiente de la categoría", async () => {
      const d = await defs.crear({ ...base(), descripcion: "Poda P1", prioridad: 1, categoriaId: catId["Poda"] });
      expect(d.prioridad).toBe(1);
      expect(d.categoriaId).toBe(catId["Poda"]);
    });

    it("rechaza categoría inexistente/ajena o desactivada", async () => {
      await expect(defs.crear({ ...base(), descripcion: "Cat falsa", categoriaId: 999999 })).rejects.toMatchObject({
        status: 400,
      });
      const ajena = (await service.listarCategorias(EMPRESA_B))[0];
      await expect(defs.crear({ ...base(), descripcion: "Cat ajena", categoriaId: ajena.id })).rejects.toMatchObject({
        status: 400,
      });
      await service.editarCategoria(EMPRESA, catId["Aseo"], { activa: false });
      await expect(defs.crear({ ...base(), descripcion: "Cat inactiva", categoriaId: catId["Aseo"] })).rejects.toThrow(
        /desactivada/,
      );
      await service.editarCategoria(EMPRESA, catId["Aseo"], { activa: true });
    });

    it("rechaza una plaza cuyo perfil tiene capacidades y no incluye la categoría; un perfil sin configurar no bloquea", async () => {
      await expect(
        defs.crear({
          ...base(),
          descripcion: "Aseo con todero",
          categoriaId: catId["Aseo"],
          necesidadesIds: [plazaToderoId],
        }),
      ).rejects.toThrow(/no está habilitada para la categoría 'Aseo'/);
      const ok = await defs.crear({
        ...base(),
        descripcion: "Poda con todero",
        categoriaId: catId["Poda"],
        necesidadesIds: [plazaToderoId],
      });
      expect(ok.categoriaId).toBe(catId["Poda"]);
      const sinConfigurar = await defs.crear({
        ...base(),
        descripcion: "Aseo con salvavidas sin configurar",
        categoriaId: catId["Aseo"],
        necesidadesIds: [plazaSalvaId],
      });
      expect(sinConfigurar.categoriaId).toBe(catId["Aseo"]);
    });

    it("actualizar: cambia categoría, reinicia el orden anterior, valida compatibilidad al cambiar responsables", async () => {
      const d = await defs.crear({ ...base(), descripcion: "Editable", categoriaId: catId["Poda"], ordenEnCategoria: 3 });
      const movida = await defs.actualizar(NIT, d.id, { categoriaId: catId["Jardinería"] });
      expect(movida.categoriaId).toBe(catId["Jardinería"]);
      expect(movida.ordenEnCategoria).toBeNull();
      const conOrden = await defs.actualizar(NIT, d.id, { ordenEnCategoria: 2 });
      expect(conOrden.ordenEnCategoria).toBe(2);
      // Cambiar responsables a una plaza no habilitada para su categoría
      await defs.actualizar(NIT, d.id, { categoriaId: catId["Aseo"] }); // sin responsables: ok
      await expect(defs.actualizar(NIT, d.id, { necesidadesIds: [plazaToderoId] })).rejects.toThrow(/no está habilitada/);
      const sinCat = await defs.actualizar(NIT, d.id, { categoriaId: null });
      expect(sinCat.categoriaId).toBeNull();
      expect(sinCat.ordenEnCategoria).toBeNull();
    });

    it("una categoría ya asignada que luego se desactiva no impide editar otros campos", async () => {
      const d = await defs.crear({ ...base(), descripcion: "Con categoria que se desactiva", categoriaId: catId["Mantenimientos básicos"] });
      await service.editarCategoria(EMPRESA, catId["Mantenimientos básicos"], { activa: false });
      const r = await defs.actualizar(NIT, d.id, { descripcion: "Descripcion nueva" });
      expect(r.descripcion).toBe("Descripcion nueva");
      expect(r.categoriaId).toBe(catId["Mantenimientos básicos"]);
      await service.editarCategoria(EMPRESA, catId["Mantenimientos básicos"], { activa: true });
    });

    it("asignación en lote: aplica, omite incompatibles y reinicia el orden al cambiar de categoría", async () => {
      const x = await defs.crear({ ...base(), descripcion: "Lote X", necesidadesIds: [plazaToderoId] });
      const y = await defs.crear({ ...base(), descripcion: "Lote Y" });
      const r = await service.asignarCategoriaLote(NIT, { ids: [x.id, y.id], categoriaId: catId["Aseo"] });
      expect(r.actualizadas).toBe(1); // y; x tiene plaza Todero sin Aseo
      expect(r.omitidas.map((o) => o.id)).toEqual([x.id]);
      const yy = await prisma.definicionTareaPreventiva.findUnique({ where: { id: y.id } });
      expect(yy?.categoriaId).toBe(catId["Aseo"]);
      await expect(service.asignarCategoriaLote(NIT, { ids: [x.id, 999999], categoriaId: catId["Poda"] })).rejects.toMatchObject({
        status: 404,
      });
      const quitar = await service.asignarCategoriaLote(NIT, { ids: [y.id], categoriaId: null });
      expect(quitar.actualizadas).toBe(1);
    });

    it("ordenarEnCategoria numera 1..n y exige exactamente las preventivas de esa categoría", async () => {
      const lista = await prisma.definicionTareaPreventiva.findMany({
        where: { conjuntoId: NIT, categoriaId: catId["Poda"] },
        orderBy: { id: "asc" },
      });
      expect(lista.length).toBeGreaterThanOrEqual(3);
      const invertida = [...lista].reverse().map((d) => d.id);
      await service.ordenarEnCategoria(NIT, { categoriaId: catId["Poda"], ids: invertida });
      const tras = await prisma.definicionTareaPreventiva.findMany({
        where: { conjuntoId: NIT, categoriaId: catId["Poda"] },
        orderBy: { ordenEnCategoria: "asc" },
      });
      expect(tras.map((d) => d.id)).toEqual(invertida);
      expect(tras.map((d) => d.ordenEnCategoria)).toEqual(invertida.map((_, i) => i + 1));
      await expect(
        service.ordenarEnCategoria(NIT, { categoriaId: catId["Poda"], ids: invertida.slice(1) }),
      ).rejects.toMatchObject({ status: 400 });
    });

    it("sugerirCategorias propone solo para preventivas sin categoría y no guarda nada", async () => {
      await defs.crear({ ...base(), descripcion: "Aspirado de piscina" });
      await defs.crear({ ...base(), descripcion: "Reunión mensual" });
      const antes = await prisma.definicionTareaPreventiva.count({ where: { conjuntoId: NIT, categoriaId: null } });
      const r = await service.sugerirCategorias(NIT);
      const piscina = r.sugerencias.find((x) => x.descripcion === "Aspirado de piscina");
      expect(piscina?.categoriaNombre).toBe("Mantenimiento de piscinas");
      expect(r.sinSugerencia.some((x) => x.descripcion === "Reunión mensual")).toBe(true);
      const despues = await prisma.definicionTareaPreventiva.count({ where: { conjuntoId: NIT, categoriaId: null } });
      expect(despues).toBe(antes);
    });

    it("listarPorConjunto incluye la categoría", async () => {
      const lista = await defs.listarPorConjunto(NIT);
      const con = lista.find((d) => d.categoriaId != null);
      expect(con?.categoria?.nombre).toBeTruthy();
    });
  });

  describe("con plazas, operarios y preventivas", () => {
    let perfilId: number;
    let categoriaId: number;
    let plazaId: number;
    let operarioId: string;

    beforeAll(async () => {
      await prisma.conjunto.create({
        data: { nit: "TEST-CAT-CONJ", nombre: "Conjunto test", direccion: "x", correo: "x@x.com", empresaId: EMPRESA },
      });
      const usuario = await prisma.usuario.create({
        data: {
          id: `test-cat-${EMPRESA}-op1`,
          nombre: "Operario Test",
          correo: `test-cat-${EMPRESA}-op1@x.com`,
          contrasena: "x",
          rol: "operario",
          telefono: BigInt(3000000000),
          fechaNacimiento: new Date(1990, 0, 1),
        },
      });
      operarioId = usuario.id;
      await prisma.operario.create({
        data: {
          id: operarioId,
          funciones: ["TODERO"],
          cursoSalvamentoAcuatico: false,
          cursoAlturas: false,
          examenIngreso: false,
          fechaIngreso: new Date(2024, 0, 1),
          empresaId: EMPRESA,
        },
      });
      const perfil = await service.crearPerfil(EMPRESA, { nombre: "Todero", roles: ["TODERO"] });
      perfilId = perfil.id;
      const plaza = await prisma.conjuntoNecesidadOperario.create({
        data: {
          conjuntoId: "TEST-CAT-CONJ",
          roles: ["TODERO"],
          etiqueta: "Todero #1",
          perfilId,
          operarioId,
        },
      });
      plazaId = plaza.id;
      categoriaId = (await service.crearCategoria(EMPRESA, { nombre: "Categoria uso test" })).id;
      const ubicacion = await prisma.ubicacion.create({ data: { nombre: "U", conjuntoId: "TEST-CAT-CONJ" } });
      const elemento = await prisma.elemento.create({ data: { nombre: "E", ubicacionId: ubicacion.id } });
      await prisma.definicionTareaPreventiva.create({
        data: {
          conjuntoId: "TEST-CAT-CONJ",
          ubicacionId: ubicacion.id,
          elementoId: elemento.id,
          descripcion: "Poda de prueba",
          frecuencia: "SEMANAL",
          categoriaId,
          ordenEnCategoria: 1,
        },
      });
    });

    it("no permite eliminar un perfil con plazas ni una categoría en uso (409)", async () => {
      await expect(service.eliminarPerfil(EMPRESA, perfilId)).rejects.toMatchObject({ status: 409 });
      await expect(service.eliminarCategoria(EMPRESA, categoriaId)).rejects.toMatchObject({ status: 409 });
      const lista = await service.listarCategorias(EMPRESA);
      expect(lista.find((c) => c.id === categoriaId)!.preventivas).toBe(1);
    });

    it("desactivar una categoría en uso siempre se permite y conserva la preventiva", async () => {
      const r = await service.editarCategoria(EMPRESA, categoriaId, { activa: false });
      expect(r.activa).toBe(false);
      const def = await prisma.definicionTareaPreventiva.findFirst({
        where: { conjuntoId: "TEST-CAT-CONJ" },
      });
      expect(def?.categoriaId).toBe(categoriaId);
      await service.editarCategoria(EMPRESA, categoriaId, { activa: true });
    });

    it("cambiar los roles propaga a las plazas si el ocupante cumple todos los roles", async () => {
      await prisma.operario.update({ where: { id: operarioId }, data: { funciones: ["TODERO", "ASEO"] } });
      const r = await service.editarPerfil(EMPRESA, perfilId, { roles: ["ASEO", "TODERO"] });
      expect(r.roles).toEqual(["TODERO", "ASEO"]);
      const plaza = await prisma.conjuntoNecesidadOperario.findUnique({ where: { id: plazaId } });
      expect(plaza?.roles).toEqual(["TODERO", "ASEO"]);
    });

    it("rechaza cambiar roles si un ocupante no tiene todos los roles nuevos", async () => {
      await expect(
        service.editarPerfil(EMPRESA, perfilId, { roles: ["TODERO", "SALVAVIDAS"] }),
      ).rejects.toMatchObject({ status: 409 });
      const plaza = await prisma.conjuntoNecesidadOperario.findUnique({ where: { id: plazaId } });
      expect(plaza?.roles).toEqual(["TODERO", "ASEO"]);
    });

    it("al liberar la plaza se puede eliminar el perfil y la categoría sin uso", async () => {
      await prisma.conjuntoNecesidadOperario.delete({ where: { id: plazaId } });
      await expect(service.eliminarPerfil(EMPRESA, perfilId)).resolves.toEqual({ ok: true });
      await prisma.definicionTareaPreventiva.deleteMany({ where: { conjuntoId: "TEST-CAT-CONJ" } });
      await expect(service.eliminarCategoria(EMPRESA, categoriaId)).resolves.toEqual({ ok: true });
    });
  });
});
