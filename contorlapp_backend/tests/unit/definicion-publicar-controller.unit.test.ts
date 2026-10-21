describe("DefinicionTareaPreventivaController.publicarCronograma", () => {
  const publicarCronograma = jest.fn();

  beforeEach(() => {
    jest.resetModules();
    publicarCronograma.mockReset().mockResolvedValue({ publicadas: 3 });
    jest.doMock("../../src/db/prisma", () => ({ prisma: {} }));
    jest.doMock("../../src/utils/auditoria", () => ({
      extraerActorAuditoriaConNombre: jest.fn().mockResolvedValue(null),
    }));
    jest.doMock("../../src/services/DefinicionTareaPreventivaService", () => ({
      DefinicionTareaPreventivaService: class {
        publicarCronograma = publicarCronograma;
      },
    }));
  });

  afterEach(() => jest.dontMock("../../src/db/prisma"));

  test("acepta año y mes por query sin body", async () => {
    const { DefinicionTareaPreventivaController } = await import(
      "../../src/controller/DefinicionTareaPreventivaController"
    );
    const res: any = { json: jest.fn() };

    await new DefinicionTareaPreventivaController().publicarCronograma(
      { params: { nit: "901203437-5" }, query: { anio: "2026", mes: "10" }, body: undefined } as any,
      res,
    );

    expect(publicarCronograma).toHaveBeenCalledWith({
      conjuntoId: "901203437-5",
      anio: 2026,
      mes: 10,
    });
    expect(res.json).toHaveBeenCalledWith({ publicadas: 3 });
  });

  test("devuelve 400 si no hay periodo en body ni query", async () => {
    const { DefinicionTareaPreventivaController } = await import(
      "../../src/controller/DefinicionTareaPreventivaController"
    );
    const res: any = { status: jest.fn().mockReturnThis(), json: jest.fn() };

    await new DefinicionTareaPreventivaController().publicarCronograma(
      { params: { nit: "901203437-5" }, query: {}, body: undefined } as any,
      res,
    );

    expect(res.status).toHaveBeenCalledWith(400);
    expect(publicarCronograma).not.toHaveBeenCalled();
  });
});
