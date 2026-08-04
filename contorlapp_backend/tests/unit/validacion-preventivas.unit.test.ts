import { TipoMaquinaria } from '@prisma/client';

import {
  CrearDefinicionPreventivaDTO,
  EditarDefinicionPreventivaDTO,
} from '../../src/model/DefinicionTareaPreventiva';
import { mensajeValidacionAmigable } from '../../src/utils/errorFormat';

const basePreventiva = {
  conjuntoId: '9001',
  ubicacionId: 1,
  elementoId: 2,
  descripcion: 'Guadañada zonas verdes',
  frecuencia: 'SEMANAL',
  diaSemanaProgramado: 'LUNES',
  duracionMinutosFija: 120,
};

describe('Validación del plan de maquinaria', () => {
  test('PU-V1 - el DTO es idempotente: acepta su propia salida', () => {
    // El controller parsea y el servicio vuelve a parsear; el segundo parse
    // recibe `maquinariaSugeridaId: null` y no debe reventar.
    const primerParse = CrearDefinicionPreventivaDTO.parse({
      ...basePreventiva,
      maquinariaPlanJson: [{ tipo: 'GUADANIA', cantidad: 2 }],
    });

    expect(primerParse.maquinariaPlanJson).toEqual([
      { tipo: TipoMaquinaria.GUADANIA, cantidad: 2, maquinariaSugeridaId: null },
    ]);

    expect(() => CrearDefinicionPreventivaDTO.parse(primerParse)).not.toThrow();

    const segundoParse = CrearDefinicionPreventivaDTO.parse(primerParse);
    expect(segundoParse.maquinariaPlanJson).toEqual(
      primerParse.maquinariaPlanJson,
    );
  });

  test('PU-V2 - el DTO de edición también soporta el doble parseo', () => {
    const primerParse = EditarDefinicionPreventivaDTO.parse({
      maquinariaPlanJson: [{ tipo: 'CORTASETOS_MANO' }],
    });

    expect(primerParse.maquinariaPlanJson).toEqual([
      {
        tipo: TipoMaquinaria.CORTASETOS_MANO,
        cantidad: 1,
        maquinariaSugeridaId: null,
      },
    ]);

    expect(() =>
      EditarDefinicionPreventivaDTO.parse(primerParse),
    ).not.toThrow();
  });

  test('PU-V3 - acepta null explícito y maquinariaId como sugerencia', () => {
    const out = CrearDefinicionPreventivaDTO.parse({
      ...basePreventiva,
      maquinariaPlanJson: [
        { tipo: 'GUADANIA', maquinariaSugeridaId: null },
        { tipo: 'TALADRO', maquinariaId: 7 },
      ],
    });

    expect(out.maquinariaPlanJson?.[0].maquinariaSugeridaId).toBeNull();
    expect(out.maquinariaPlanJson?.[1].maquinariaSugeridaId).toBe(7);
  });

  test('PU-V4 - sigue rechazando un tipo que no existe', () => {
    expect(() =>
      CrearDefinicionPreventivaDTO.parse({
        ...basePreventiva,
        maquinariaPlanJson: [{ tipo: 'NO_EXISTE' }],
      }),
    ).toThrow();
  });
});

describe('mensajeValidacionAmigable', () => {
  test('PU-V5 - no filtra el mensaje técnico de Zod', () => {
    const salida = mensajeValidacionAmigable({
      code: 'invalid_type',
      message: 'Invalid input: expected number, received null',
    });

    expect(salida).not.toMatch(/expected|received|Invalid input/i);
    expect(salida).toBe('Falta este dato o tiene un formato que no corresponde.');
  });

  test('PU-V6 - conserva los mensajes propios (refine)', () => {
    const propio = 'Las preventivas quincenales deben tener un día de la semana programado.';
    expect(mensajeValidacionAmigable({ code: 'custom', message: propio })).toBe(
      propio,
    );
  });

  test('PU-V7 - cubre los códigos de longitud y de opción inválida', () => {
    expect(mensajeValidacionAmigable({ code: 'too_small', minimum: 3 })).toMatch(
      /mínimo 3/,
    );
    expect(mensajeValidacionAmigable({ code: 'too_big', maximum: 500 })).toMatch(
      /máximo 500/,
    );
    expect(mensajeValidacionAmigable({ code: 'invalid_value' })).toMatch(
      /opción válida/,
    );
  });

  test('PU-V8 - un código desconocido no revela nada', () => {
    const salida = mensajeValidacionAmigable({
      code: 'algo_raro',
      message: 'PrismaClientKnownRequestError: column "x" does not exist',
    });

    expect(salida).toBe('Revisa este dato.');
    expect(salida).not.toMatch(/Prisma|column/i);
  });
});
