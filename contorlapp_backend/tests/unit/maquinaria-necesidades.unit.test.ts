import { TipoMaquinaria } from '@prisma/client';

import {
  agruparNecesidadesPorTipo,
  parseMaquinariaIdsComprometidos,
  parseNecesidadesMaquinaria,
} from '../../src/utils/maquinariaNecesidades';
import {
  DIAS_ENTREGA_RECOGIDA,
  calcularRangoReserva,
} from '../../src/utils/reservaMaquinaria';

const ymd = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

describe('Necesidades de maquinaria', () => {
  describe('parseNecesidadesMaquinaria', () => {
    test('PU-M1 - lee el formato nuevo por tipo', () => {
      const out = parseNecesidadesMaquinaria([
        { tipo: 'GUADANIA', cantidad: 2, maquinariaSugeridaId: 12 },
      ]);

      expect(out).toEqual([
        {
          tipo: TipoMaquinaria.GUADANIA,
          cantidad: 2,
          maquinariaSugeridaId: 12,
        },
      ]);
    });

    test('PU-M2 - la cantidad por defecto es 1', () => {
      const out = parseNecesidadesMaquinaria([{ tipo: 'PODADORA_CESPED' }]);
      expect(out[0].cantidad).toBe(1);
      expect(out[0].maquinariaSugeridaId).toBeNull();
    });

    test('PU-M3 - acepta maquinariaId como sugerencia cuando ya hay tipo', () => {
      const out = parseNecesidadesMaquinaria([
        { tipo: 'SOPLADORA', maquinariaId: 7 },
      ]);
      expect(out[0].maquinariaSugeridaId).toBe(7);
    });

    test('PU-M4 - descarta items sin tipo resoluble', () => {
      const out = parseNecesidadesMaquinaria([
        { maquinariaId: 12 },
        { tipo: 'NO_EXISTE', cantidad: 3 },
        { tipo: 'TALADRO' },
        null,
        'basura',
      ]);

      expect(out).toHaveLength(1);
      expect(out[0].tipo).toBe(TipoMaquinaria.TALADRO);
    });

    test('PU-M5 - tolera entradas que no son lista', () => {
      expect(parseNecesidadesMaquinaria(null)).toEqual([]);
      expect(parseNecesidadesMaquinaria({ tipo: 'GUADANIA' })).toEqual([]);
    });
  });

  describe('parseMaquinariaIdsComprometidos', () => {
    test('PU-M6 - solo devuelve ids del formato antiguo, sin tipo', () => {
      expect(
        parseMaquinariaIdsComprometidos([{ maquinariaId: 12 }, { maquinariaId: 5 }]),
      ).toEqual([12, 5]);
    });

    test('PU-M7 - una necesidad por tipo no compromete ninguna máquina', () => {
      // Esto es lo que hace que publicar deje de fallar por maquinaria.
      expect(
        parseMaquinariaIdsComprometidos([
          { tipo: 'GUADANIA', cantidad: 2, maquinariaSugeridaId: 12 },
        ]),
      ).toEqual([]);
    });
  });

  test('PU-M8 - agruparNecesidadesPorTipo suma las cantidades', () => {
    const agrupado = agruparNecesidadesPorTipo(
      parseNecesidadesMaquinaria([
        { tipo: 'GUADANIA', cantidad: 2 },
        { tipo: 'GUADANIA', cantidad: 1 },
        { tipo: 'TALADRO', cantidad: 1 },
      ]),
    );

    expect(agrupado.get(TipoMaquinaria.GUADANIA)).toBe(3);
    expect(agrupado.get(TipoMaquinaria.TALADRO)).toBe(1);
  });

  describe('calcularRangoReserva', () => {
    test('PU-M9 - entrega y recogida caen en lunes, miércoles o sábado', () => {
      // Jueves 5 de marzo de 2026.
      const rango = calcularRangoReserva({
        fechaInicioUso: new Date(2026, 2, 5, 8),
        fechaFinUso: new Date(2026, 2, 5, 12),
      });

      expect(DIAS_ENTREGA_RECOGIDA.has(rango.entregaDia.getDay())).toBe(true);
      expect(DIAS_ENTREGA_RECOGIDA.has(rango.recogidaDia.getDay())).toBe(true);
      // Miércoles 4 -> sábado 7
      expect(ymd(rango.entregaDia)).toBe('2026-03-04');
      expect(ymd(rango.recogidaDia)).toBe('2026-03-07');
      expect(rango.iniReserva.getHours()).toBe(0);
      expect(rango.finReserva.getHours()).toBe(23);
    });

    test('PU-M10 - salta los días festivos', () => {
      const rango = calcularRangoReserva({
        fechaInicioUso: new Date(2026, 2, 5, 8),
        fechaFinUso: new Date(2026, 2, 5, 12),
        festivosSet: new Set(['2026-03-04', '2026-03-07']),
      });

      // El miércoles 4 y el sábado 7 son festivos: retrocede al lunes 2 y avanza al lunes 9.
      expect(ymd(rango.entregaDia)).toBe('2026-03-02');
      expect(ymd(rango.recogidaDia)).toBe('2026-03-09');
    });

    test('PU-M11 - rechaza fechas inválidas', () => {
      expect(() =>
        calcularRangoReserva({
          fechaInicioUso: new Date('no-es-fecha'),
          fechaFinUso: new Date(2026, 2, 5),
        }),
      ).toThrow(/fechaInicioUso/);
    });
  });
});
