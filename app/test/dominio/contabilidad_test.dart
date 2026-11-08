import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/contabilidad.dart';
import 'package:tapiceria/dominio/dinero.dart';

Pago _pago(String id, String pedidoId, double monto, FormaPago forma,
        String recibidoPor) =>
    Pago(
      id: id,
      pedidoId: pedidoId,
      monto: monto,
      forma: forma,
      recibidoPor: recibidoPor,
      fecha: DateTime(2026, 11, 7),
    );

Compra _compra(double? precioTotal, String tipo) => Compra(
      id: 'c',
      materialId: 'm',
      precioTotal: precioTotal,
      fecha: DateTime(2026, 11, 7),
      tipo: tipo,
    );

PagoSueldo _sueldo(double monto) => PagoSueldo(
    id: 's', usuarioId: 'u', monto: monto, fecha: DateTime(2026, 11, 7));

void main() {
  test('semana que cruza el año', () {
    final s = Periodo.semana(DateTime(2027, 1, 3, 23, 59));
    expect(s.desde, DateTime(2026, 12, 28));
    expect(s.hasta, DateTime(2027, 1, 4));
    expect(s.contiene(DateTime(2027, 1, 3, 23, 59)), isTrue);
    expect(s.contiene(DateTime(2027, 1, 4)), isFalse);
    expect(s.etiqueta, 'Semana del 28/12/2026 al 03/01/2027');
    expect(s.siguiente().desde, DateTime(2027, 1, 4));
    expect(s.anterior().desde, DateTime(2026, 12, 21));
  });
  test('mes y rango', () {
    final m = Periodo.mes(DateTime(2026, 11, 7));
    expect(m.desde, DateTime(2026, 11, 1));
    expect(m.hasta, DateTime(2026, 12, 1));
    expect(m.etiqueta, 'Noviembre 2026');
    expect(m.anterior().etiqueta, 'Octubre 2026');
    expect(Periodo.mes(DateTime(2026, 12, 5)).siguiente().desde,
        DateTime(2027, 1, 1));
    expect(Periodo.mes(DateTime(2026, 1, 5)).anterior().desde,
        DateTime(2025, 12, 1));
    final r = Periodo.rango(DateTime(2026, 11, 10), DateTime(2026, 11, 3));
    expect(r.desde, DateTime(2026, 11, 3));
    expect(r.hasta, DateTime(2026, 11, 11));
    expect(r.etiqueta, 'Del 03/11/2026 al 10/11/2026');
    expect(() => r.anterior(), throwsStateError);
    expect(() => r.siguiente(), throwsStateError);
    expect(Periodo.semana(DateTime(2026, 11, 7)),
        Periodo.semana(DateTime(2026, 11, 5)));
    expect(Periodo.semana(DateTime(2026, 11, 7)).hashCode,
        Periodo.semana(DateTime(2026, 11, 5)).hashCode);
    expect(Periodo.mes(DateTime(2026, 11, 7)),
        isNot(Periodo.semana(DateTime(2026, 11, 7))));
  });
  test('resumen de cobros con devolución', () {
    final r = resumirCobros([
      _pago('p1', 'pedA', 500, FormaPago.efectivo, 'emp1'),
      _pago('p2', 'pedA', 300, FormaPago.transferencia, 'due1'),
      _pago('p3', 'pedB', -200, FormaPago.efectivo, 'due1'),
    ]);
    expect(r.total, 600);
    expect(r.porForma[FormaPago.efectivo], 300);
    expect(r.porUsuario['due1'], 100);
    expect(r.porPedido['pedB'], -200);
  });
  test('gastos ignoran la carga inicial', () {
    final g = resumirGastos(
      compras: [
        _compra(1500, 'compra'),
        _compra(9000, 'inicial'),
        _compra(null, 'inicial')
      ],
      sueldos: [_sueldo(1800)],
    );
    expect(g.compras, 1500);
    expect(g.total, 3300);
  });
  test('Compra.desdeMapa acepta precioTotal nulo', () {
    final c = Compra.desdeMapa(
        'c1',
        {'materialId': 'm1', 'tipo': 'compra', 'fecha': 1},
        (_) => DateTime(2026, 11, 7));
    expect(c.precioTotal, isNull);
    expect(c.materialId, 'm1');
  });
}
