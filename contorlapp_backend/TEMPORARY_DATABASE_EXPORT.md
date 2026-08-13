# Copiar temporalmente produccion a desarrollo

Este flujo descarga un `pg_dump` completo de PostgreSQL y reemplaza **solo** la
base local indicada por `contorlapp_backend/.env`. El script se niega a operar
si `DATABASE_URL` no apunta a `localhost`, crea un respaldo local antes de
reemplazarla y revierte automaticamente si la restauracion falla.

El respaldo contiene datos personales y hashes de contrasenas. No lo compartas,
no lo subas a Git y usa los datos solamente en tu equipo de desarrollo.

## 1. Generar acceso temporal

Desde la raiz del proyecto:

```powershell
npm.cmd run db:prepare-production-export
```

El comando muestra tres variables. Copialas en Railway, dentro de **Variables**
del servicio del backend, y despliega esta version. El acceso caduca una hora
despues aunque olvides apagarlo.

El proyecto incluye un `Dockerfile` en la raiz y otro dentro de
`contorlapp_backend/` para cubrir ambas configuraciones posibles de **Root
Directory** en Railway. La imagen fija `pg_dump` 18.4, la misma version mayor de
la base de produccion. En el log del nuevo despliegue debe aparecer
`Using detected Dockerfile`.

## 2. Descargar y cargar en local

En la misma consola asigna el token que mostro el paso anterior y ejecuta:

```powershell
$env:TEMP_DB_EXPORT_TOKEN='PEGA_AQUI_EL_TOKEN'
npm.cmd run db:clone-production -- --api-url https://TU-BACKEND.up.railway.app --yes-replace-local
```

El comando valida el archivo, respalda la base local, la reemplaza y elimina los
archivos temporales sensibles cuando termina correctamente. La base local debe
estar encendida y `DATABASE_URL` debe seguir apuntando a `localhost`.

Produccion usa PostgreSQL 18. Para evitar restaurar un respaldo nuevo sobre un
servidor local antiguo, el clonador crea automaticamente un PostgreSQL 18 en un
contenedor separado, conserva intacta la base anterior y actualiza `.env` solo
despues de validar la restauracion. Docker Desktop debe estar iniciado.

Para descargar sin restaurar:

```powershell
npm.cmd run db:clone-production -- --api-url https://TU-BACKEND.up.railway.app --download-only
```

## 3. Apagar inmediatamente

En Railway elimina estas variables del backend y vuelve a desplegar:

- `TEMP_DB_EXPORT_ENABLED`
- `TEMP_DB_EXPORT_TOKEN`
- `TEMP_DB_EXPORT_EXPIRES_AT`

Sin las tres variables la ruta responde como inexistente. Para retirar tambien
el codigo, elimina `src/routes/TemporaryDatabaseExport.ts` y su import/registro
marcados como `TEMPORARY` en `src/index.ts`.

## Diagnostico

Si vuelve a aparecer un error de herramienta o de version, confirma en los logs
de compilacion de Railway que aparece `Using detected Dockerfile` y ejecuta un
redeploy sin cache despues de subir el `Dockerfile` que corresponde al **Root
Directory** configurado para el servicio.
