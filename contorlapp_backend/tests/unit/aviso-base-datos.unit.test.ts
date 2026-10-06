import { avisarBaseDeDatos, describirBaseDeDatos } from '../../src/utils/avisoBaseDeDatos';

describe('aviso de base de datos', () => {
  test('reconoce una base local y una remota sin exponer credenciales', () => {
    expect(describirBaseDeDatos('postgresql://u:secreto@127.0.0.1:55432/controlapp_bd?schema=public')).toEqual({
      host: '127.0.0.1:55432',
      base: 'controlapp_bd',
      local: true,
    });
    const remota = describirBaseDeDatos('postgresql://u:secreto@centerbeam.proxy.rlwy.net:13802/railway');
    expect(remota).toMatchObject({ host: 'centerbeam.proxy.rlwy.net:13802', local: false });
    expect(JSON.stringify(remota)).not.toContain('secreto');
  });

  test('avisa si un servidor de desarrollo apunta a una base remota', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const log = jest.spyOn(console, 'log').mockImplementation(() => undefined);
    avisarBaseDeDatos({ DATABASE_URL: 'postgresql://u:p@centerbeam.proxy.rlwy.net:13802/railway' } as any);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('REMOTA'));
    warn.mockRestore();
    log.mockRestore();
  });

  test('no avisa en local ni en produccion', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const log = jest.spyOn(console, 'log').mockImplementation(() => undefined);
    avisarBaseDeDatos({ DATABASE_URL: 'postgresql://u:p@127.0.0.1:55432/x' } as any);
    avisarBaseDeDatos({ DATABASE_URL: 'postgresql://u:p@db.rlwy.net:1/x', RAILWAY_ENVIRONMENT: 'production' } as any);
    avisarBaseDeDatos({ DATABASE_URL: 'postgresql://u:p@db.rlwy.net:1/x', NODE_ENV: 'production' } as any);
    expect(warn).not.toHaveBeenCalled();
    warn.mockRestore();
    log.mockRestore();
  });
});
