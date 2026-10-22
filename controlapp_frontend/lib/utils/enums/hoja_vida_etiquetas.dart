/// Nombres para mostrar de la ARL y la caja de compensación del usuario
/// (enums `ARL` y `CajaCompensacion` del backend). Los usan los formularios
/// de crear/editar usuario, el detalle y la planilla de personal.
library;

const Map<String, String> _arl = {
  'SURA': 'Sura',
  'POSITIVA': 'Positiva',
  'COLMENA': 'Colmena',
  'BOLIVAR': 'Seguros Bolívar',
  'AXA_COLPATRIA': 'AXA Colpatria',
  'EQUIDAD': 'La Equidad',
  'ALFA': 'Seguros Alfa',
  'HDI_LIBERTY': 'HDI (antes Liberty)',
  'MAPFRE': 'Mapfre',
  'AURORA': 'Aurora',
};

const Map<String, String> _cajas = {
  'COMPENSAR': 'Compensar',
  'COLSUBSIDIO': 'Colsubsidio',
  'CAFAM': 'Cafam',
  'COMFACUNDI': 'Comfacundi',
  'COMFAMA': 'Comfama',
  'COMFENALCO_ANTIOQUIA': 'Comfenalco Antioquia',
  'COMFANDI': 'Comfandi',
  'COMFENALCO_VALLE': 'Comfenalco Valle',
  'COMFACARTAGO': 'Comfacartago',
  'COMFAMILIAR_ATLANTICO': 'Comfamiliar Atlántico',
  'COMBARRANQUILLA': 'Combarranquilla',
  'CAJACOPI': 'Cajacopi',
  'COMFENALCO_CARTAGENA': 'Comfenalco Cartagena',
  'COMFAMILIAR_CARTAGENA': 'Comfamiliar Cartagena',
  'COMFABOY': 'Comfaboy',
  'CONFA': 'Confa',
  'COMFACA': 'Comfaca',
  'COMFACAUCA': 'Comfacauca',
  'COMFACESAR': 'Comfacesar',
  'COMFACOR': 'Comfacor',
  'COMFACHOCO': 'Comfachocó',
  'COMFAMILIAR_HUILA': 'Comfamiliar Huila',
  'COMFAGUAJIRA': 'Comfaguajira',
  'CAJAMAG': 'Cajamag',
  'COFREM': 'Cofrem',
  'COMFAMILIAR_NARINO': 'Comfamiliar Nariño',
  'COMFANORTE': 'Comfanorte',
  'COMFAORIENTE': 'Comfaoriente',
  'COMFENALCO_QUINDIO': 'Comfenalco Quindío',
  'COMFAMILIAR_RISARALDA': 'Comfamiliar Risaralda',
  'CAJASAN': 'Cajasan',
  'COMFENALCO_SANTANDER': 'Comfenalco Santander',
  'CAFABA': 'Cafaba',
  'COMFASUCRE': 'Comfasucre',
  'COMFATOLIMA': 'Comfatolima',
  'COMFENALCO_TOLIMA': 'Comfenalco Tolima',
  'COMFIAR': 'Comfiar',
  'COMFACASANARE': 'Comfacasanare',
  'COMFAMILIAR_PUTUMAYO': 'Comfamiliar Putumayo',
  'CAJASAI': 'Cajasai',
  'CAFAMAZ': 'Cafamaz',
  'COMCAJA': 'Comcaja',
};

/// `HDI_LIBERTY` → `HDI (antes Liberty)`. Vacío si no hay valor.
String etiquetaArl(String? valor) => _etiqueta(_arl, valor);

/// `COMFAMILIAR_NARINO` → `Comfamiliar Nariño`. Vacío si no hay valor.
String etiquetaCajaCompensacion(String? valor) => _etiqueta(_cajas, valor);

/// Un valor que el backend agregue y la app aún no conozca se muestra con
/// cada palabra en mayúscula inicial.
String _etiqueta(Map<String, String> nombres, String? valor) {
  final v = valor?.trim() ?? '';
  if (v.isEmpty) return '';
  return nombres[v] ??
      v
          .toLowerCase()
          .split('_')
          .where((p) => p.isNotEmpty)
          .map((p) => p[0].toUpperCase() + p.substring(1))
          .join(' ');
}
