{{flutter_js}}
{{flutter_build_config}}

// Evita cache inconsistentes de assets (incluyendo fuentes de iconos)
// que dejan los IconData como "tofu" en algunas actualizaciones.
_flutter.loader.load({
  config: {
    assetBase: "/",
  },
  serviceWorkerSettings: null,
});
