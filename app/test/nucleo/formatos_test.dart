import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tapiceria/nucleo/formatos.dart';

void main() {
  setUp(() async {
    await initializeDateFormatting('es_MX');
  });

  test('formatea pesos', () {
    expect(formatearDinero(1500), r'$1,500.00');
    expect(formatearDinero(0.5), r'$0.50');
    expect(formatearDinero(-200), r'-$200.00');
  });

  test('formatea fecha dd/MM/yyyy', () {
    expect(formatearFecha(DateTime(2026, 11, 4)), '04/11/2026');
  });
}
