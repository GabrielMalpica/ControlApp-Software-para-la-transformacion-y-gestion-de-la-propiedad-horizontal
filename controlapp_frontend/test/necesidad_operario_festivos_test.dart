import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/model/necesidad_operario_model.dart';
import 'package:flutter_application_1/model/asistencia_model.dart';

void main() {
  group('NecesidadOperario - festivos y descanso compensatorio', () {
    test('fromJson arma horarioFestivo a partir de las columnas planas del backend', () {
      final n = NecesidadOperario.fromJson({
        'id': 1,
        'conjuntoId': 'C-1',
        'roles': ['SALVAVIDAS'],
        'etiqueta': 'Salvavidas #1',
        'orden': 0,
        'horarioEspecial': false,
        'trabajaFestivos': true,
        'festivoHoraApertura': '09:00',
        'festivoHoraCierre': '15:00',
        'festivoDescansoInicio': null,
        'festivoDescansoFin': null,
        'descansoCompensatorio': true,
        'diasDescansoCompensatorio': 1,
        'activo': true,
        'horarios': [],
      });

      expect(n.trabajaFestivos, isTrue);
      expect(n.horarioFestivo, isNotNull);
      expect(n.horarioFestivo!.horaApertura, '09:00');
      expect(n.horarioFestivo!.horaCierre, '15:00');
      expect(n.descansoCompensatorio, isTrue);
      expect(n.diasDescansoCompensatorio, 1);
    });

    test('sin trabajaFestivos, horarioFestivo queda null aunque falten las columnas', () {
      final n = NecesidadOperario.fromJson({
        'id': 2,
        'conjuntoId': 'C-1',
        'roles': ['TODERO'],
        'etiqueta': 'Todero #1',
        'orden': 0,
        'horarioEspecial': false,
        'activo': true,
        'horarios': [],
      });

      expect(n.trabajaFestivos, isFalse);
      expect(n.horarioFestivo, isNull);
      expect(n.descansoCompensatorio, isFalse);
      expect(n.diasDescansoCompensatorio, 1);
    });

    test('toJson conserva los campos nuevos para crear/editar la plaza', () {
      final n = NecesidadOperario(
        id: 3,
        conjuntoId: 'C-1',
        roles: const ['SALVAVIDAS'],
        etiqueta: 'Salvavidas #1',
        orden: 0,
        horarioEspecial: false,
        trabajaFestivos: true,
        horarioFestivo: HorarioFranja(horaApertura: '08:00', horaCierre: '12:00'),
        descansoCompensatorio: true,
        diasDescansoCompensatorio: 2,
        activo: true,
      );

      final json = n.toJson();
      expect(json['trabajaFestivos'], isTrue);
      expect(json['horarioFestivo'], {'horaApertura': '08:00', 'horaCierre': '12:00'});
      expect(json['descansoCompensatorio'], isTrue);
      expect(json['diasDescansoCompensatorio'], 2);
    });
  });

  group('NecesidadCalendarioPlaza', () {
    test('fromJson parsea los días de festivo/domingo/descanso', () {
      final plaza = NecesidadCalendarioPlaza.fromJson({
        'necesidadId': 5,
        'etiqueta': 'Salvavidas #1',
        'operarioId': 'op-1',
        'dias': [
          {'fecha': '2026-04-01', 'tipo': 'FESTIVO', 'origen': null},
          {'fecha': '2026-04-02', 'tipo': 'DESCANSO', 'origen': '2026-04-01'},
        ],
      });

      expect(plaza.dias, hasLength(2));
      expect(plaza.dias[0].tipo, 'FESTIVO');
      expect(plaza.dias[1].origen, '2026-04-01');
    });
  });

  group('AsistenciaDiaCelda / AsistenciaResumenOperario - festivos y compensatorio', () {
    test('AsistenciaDiaCelda parsea esFestivo, festivoNombre y descansoProgramado', () {
      final dia = AsistenciaDiaCelda.fromJson({
        'dia': 1,
        'fecha': '2026-04-01',
        'diaSemana': 3,
        'esFestivo': true,
        'festivoNombre': 'Día del trabajo',
        'pendiente': false,
        'incompleto': false,
        'descansoProgramado': {'origen': '2026-04-01'},
      });

      expect(dia.esFestivo, isTrue);
      expect(dia.festivoNombre, 'Día del trabajo');
      expect(dia.descansoProgramado, isNotNull);
      expect(dia.descansoProgramado!.origen, '2026-04-01');
    });

    test('AsistenciaResumenOperario parsea los conteos de descansos trabajados/festivos/compensatorios', () {
      final resumen = AsistenciaResumenOperario.fromJson({
        'operarioId': 'op-1',
        'nombre': 'Carlos',
        'cedula': 'op-1',
        'cargo': 'Salvavidas',
        'pendientes': 0,
        'conteoPorConcepto': {'DFC': 1},
        'descansosTrabajados': 2,
        'festivosTrabajados': 1,
        'compensatoriosProgramados': 3,
        'compensatoriosTomados': 2,
      });

      expect(resumen.descansosTrabajados, 2);
      expect(resumen.festivosTrabajados, 1);
      expect(resumen.compensatoriosProgramados, 3);
      expect(resumen.compensatoriosTomados, 2);
    });
  });
}
