import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/dominio/inventario.dart';

Material _material({
  double existencia = 0,
  double stockMinimo = 10,
  bool marcado = false,
}) =>
    Material(
      id: 'm1',
      nombre: 'Tela gris',
      categoria: Categoria.tela,
      unidad: Unidad.m,
      stockMinimo: stockMinimo,
      existencia: existencia,
      usaRollos: true,
      marcadoAgotandose: marcado,
    );

Map<String, dynamic> _mapaValido() => {
      'nombre': 'Tela gris',
      'categoria': 'tela',
      'unidad': 'm',
      'stockMinimo': 10,
      'existencia': 3,
      'usaRollos': true,
      'marcadoAgotandose': false,
    };

void main() {
  test('costo promedio ponderado', () {
    expect(costoPromedio(cantidadComprada: 30, costoTotalComprado: 1500), 50);
    expect(costoPromedio(cantidadComprada: 0, costoTotalComprado: 0), isNull);
  });

  test('siguiente código de rollo', () {
    expect(siguienteCodigoRollo([]), '#1');
    expect(siguienteCodigoRollo(['#3', '#12', 'viejo', '#7']), '#13');
  });

  test('leerCantidad acepta coma y rechaza basura', () {
    expect(leerCantidad('2,5'), 2.5);
    expect(leerCantidad(' 3 '), 3);
    expect(leerCantidad('abc'), isNull);
    expect(leerCantidad(''), isNull);
  });

  test('formatearCantidad', () {
    expect(formatearCantidad(2.5, Unidad.m), '2.5 m');
    expect(formatearCantidad(12, Unidad.pza), '12 pza');
    expect(formatearCantidad(-1.5, Unidad.m), '-1.5 m');
    expect(formatearCantidad(0.25, Unidad.kg), '0.25 kg');
  });

  test('necesitaCompra: debajo del mínimo o marcado; igual al mínimo no', () {
    expect(_material(existencia: 9.9).necesitaCompra, isTrue);
    expect(_material(existencia: 10).necesitaCompra, isFalse);
    expect(_material(existencia: -1.5).necesitaCompra, isTrue);
    expect(_material(existencia: 50, marcado: true).necesitaCompra, isTrue);
  });

  test('Categoria y Unidad: etiquetas, claves y texto desconocido', () {
    expect(Categoria.tela.etiqueta, 'Tela');
    expect(Categoria.desdeTexto('guata'), Categoria.guata);
    expect(() => Categoria.desdeTexto('madera'), throwsFormatException);
    expect(Unidad.pza.clave, 'pza');
    expect(Unidad.desdeTexto('kg'), Unidad.kg);
    expect(() => Unidad.desdeTexto('yd'), throwsFormatException);
  });

  test('Material.desdeMapa valida', () {
    expect(() => Material.desdeMapa('x', {..._mapaValido(), 'categoria': 'madera'}),
        throwsFormatException);
    expect(() => Material.desdeMapa('x', {..._mapaValido(), 'stockMinimo': 'diez'}),
        throwsFormatException);
    final m = Material.desdeMapa('x', _mapaValido());
    expect(m.existencia, 3.0);
    expect(m.existencia, isA<double>());
    expect(m.id, 'x');
  });

  test('aMapaAlta de una tela', () {
    final mapa = _material(existencia: 7).aMapaAlta();
    expect(mapa['usaRollos'], isTrue);
    expect(mapa['existencia'], 0);
    expect(mapa['marcadoAgotandose'], isFalse);
    expect(mapa['categoria'], 'tela');
    expect(mapa['unidad'], 'm');
  });

  test('Rollo.desdeMapa', () {
    final fecha = DateTime(2026, 1, 2);
    final r = Rollo.desdeMapa('r1', {
      'materialId': 'm1',
      'codigo': '#1',
      'cantidadInicial': 30,
      'existencia': 12.5,
    }, fecha);
    expect(r.cantidadInicial, 30.0);
    expect(r.existencia, 12.5);
    expect(r.fechaCompra, fecha);
    expect(() => Rollo.desdeMapa('r1', {'materialId': 'm1'}, fecha),
        throwsFormatException);
  });

  test('Movimiento.desdeMapa', () {
    final fecha = DateTime(2026, 1, 2);
    final base = {
      'tipo': 'consumo',
      'materialId': 'm1',
      'rolloId': null,
      'cantidad': -2,
      'usuarioId': 'u1',
    };
    final mov = Movimiento.desdeMapa('mv1', base, fecha);
    expect(mov.tipo, TipoMovimiento.consumo);
    expect(mov.rolloId, isNull);
    expect(mov.cantidad, -2.0);
    expect(() => Movimiento.desdeMapa('mv1', {...base, 'tipo': 'robo'}, fecha),
        throwsFormatException);
  });
}
