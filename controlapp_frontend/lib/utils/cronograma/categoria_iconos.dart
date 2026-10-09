import 'package:flutter/material.dart';

/// Ícono configurable de una categoría de tarea.
///
/// La [clave] es el contrato con el backend (ver
/// contorlapp_backend/src/utils/categoriaIconos.ts). Los íconos son
/// constantes a propósito: en Flutter web un `IconData` construido en
/// tiempo de ejecución rompe el tree-shaking de la fuente de íconos.
class CategoriaIcono {
  final String clave;
  final IconData icono;
  final String etiqueta;

  const CategoriaIcono(this.clave, this.icono, this.etiqueta);
}

const List<CategoriaIcono> kIconosCategoria = [
  CategoriaIcono('limpieza', Icons.cleaning_services, 'Limpieza'),
  CategoriaIcono('desinfeccion', Icons.sanitizer, 'Desinfección'),
  CategoriaIcono('jardin', Icons.eco, 'Jardín'),
  CategoriaIcono('cesped', Icons.grass, 'Césped'),
  CategoriaIcono('arboles', Icons.park, 'Árboles y poda'),
  CategoriaIcono('piscina', Icons.pool, 'Piscina'),
  CategoriaIcono('salvamento', Icons.support, 'Salvamento'),
  CategoriaIcono('agua', Icons.water_drop, 'Agua y riego'),
  CategoriaIcono('residuos', Icons.delete_outline, 'Residuos'),
  CategoriaIcono('reciclaje', Icons.recycling, 'Reciclaje'),
  CategoriaIcono('mantenimiento', Icons.handyman, 'Mantenimiento'),
  CategoriaIcono('reparacion', Icons.build, 'Reparación'),
  CategoriaIcono('electrico', Icons.electrical_services, 'Eléctrico'),
  CategoriaIcono('plomeria', Icons.plumbing, 'Plomería'),
  CategoriaIcono('pintura', Icons.format_paint, 'Pintura'),
  CategoriaIcono('fumigacion', Icons.pest_control, 'Fumigación'),
  CategoriaIcono('vigilancia', Icons.security, 'Vigilancia'),
  CategoriaIcono('supervision', Icons.fact_check, 'Supervisión'),
  CategoriaIcono('parqueadero', Icons.local_parking, 'Parqueadero'),
  CategoriaIcono('otra', Icons.construction, 'Otra'),
];

final Map<String, CategoriaIcono> _porClave = {
  for (final i in kIconosCategoria) i.clave: i,
};

CategoriaIcono? categoriaIconoPorClave(String? clave) =>
    clave == null ? null : _porClave[clave.trim()];

/// Reglas (en orden) para sugerir un ícono a partir de un texto: el nombre
/// de la categoría o, si no tiene, la descripción de la tarea.
const List<(List<String>, String)> _reglasSugerencia = [
  (['salvavid', 'salvament', 'vigilar piscina'], 'salvamento'),
  (['piscin', 'clor', 'retrolav', ' ph'], 'piscina'),
  (['fumig', 'plaga', 'roedor'], 'fumigacion'),
  (['desinfec'], 'desinfeccion'),
  (['reciclaj'], 'reciclaje'),
  (['residuo', 'basura', 'shut', 'desecho'], 'residuos'),
  (['poda', 'arbol', 'árbol', 'seto'], 'arboles'),
  (['cesped', 'césped', 'guadañ', 'corte de'], 'cesped'),
  (['riego', 'regar', 'agua'], 'agua'),
  (['jardin', 'jardín', 'zona verde', 'zonas verdes', 'deshierb', 'abono', 'fertiliz'], 'jardin'),
  (['electr', 'luminaria', 'bombillo'], 'electrico'),
  (['plomer', 'tuber', 'sifón', 'sifon', 'destap'], 'plomeria'),
  (['pintur', 'pintar'], 'pintura'),
  (['repar', 'arregl'], 'reparacion'),
  (['mantenim', 'revis', 'inspecc', 'locativ'], 'mantenimiento'),
  (['supervis'], 'supervision'),
  (['vigil', 'segurid', 'ronda'], 'vigilancia'),
  (['parqueader'], 'parqueadero'),
  (['aseo', 'limpi', 'barr', 'trape', 'lav', 'aspir', 'vidrio'], 'limpieza'),
];

/// Sugiere un ícono para [texto] (sin tildes ni mayúsculas importan).
/// Devuelve null si ninguna regla aplica.
String? sugerirIconoCategoria(String? texto) {
  final t = ' ${(texto ?? '').toLowerCase()} ';
  if (t.trim().isEmpty) return null;
  for (final (claves, icono) in _reglasSugerencia) {
    if (claves.any(t.contains)) return icono;
  }
  return null;
}
