# ControlApp Frontend (Flutter)

## Configuración de API

El frontend usa una URL base configurable por `--dart-define`.

- Variable: `API_BASE_URL`
- Valor por defecto: `https://controlapp-software-para-la-transformacion-y-ges-production.up.railway.app`

### Producción (Railway)
No necesitas pasar nada extra si quieres usar la URL por defecto.

### Desarrollo local
Si quieres apuntar al backend local, ejecuta con:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

> En emulador Android normalmente debes usar `http://10.0.2.2:3000`.

## Nota
Todas las APIs deben usar `AppConstants.baseUrl` para evitar tener URLs hardcodeadas a `localhost`.
