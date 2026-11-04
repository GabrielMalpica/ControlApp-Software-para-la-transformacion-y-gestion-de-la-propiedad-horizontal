/// En web las peticiones siguen con el cliente del navegador.
R ejecutarConClienteApp<R>(R Function() cuerpo) => cuerpo();
