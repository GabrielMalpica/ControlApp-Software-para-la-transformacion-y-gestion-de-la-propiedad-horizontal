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

## 2. Descargar y cargar en local

En la misma consola asigna el token que mostro el paso anterior y ejecuta:

```powershell
$env:TEMP_DB_EXPORT_TOKEN='PEGA_AQUI_EL_TOKEN'
npm.cmd run db:clone-production -- --api-url https://TU-BACKEND.up.railway.app --yes-replace-local
```

El comando valida el archivo, respalda la base local, la reemplaza y elimina los
archivos temporales sensibles cuando termina correctamente. La base local debe
estar encendida y `DATABASE_URL` debe seguir apuntando a `localhost`.

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
