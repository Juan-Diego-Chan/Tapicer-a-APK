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

  test('leerCantidad rechaza no finitos y formatos ambiguos', () {
    for (final t in ['NaN', 'Infinity', '-Infinity', '1e999', '1.2.3', '2,5,0', '1,234.5']) {
      expect(leerCantidad(t), isNull, reason: t);
    }
  });

  test('formatearCantidad casos límite', () {
    expect(formatearCantidad(-0.001, Unidad.m), '0 m');
    expect(formatearCantidad(10, Unidad.m), '10 m');
  });

  test('siguienteCodigoRollo con ceros a la izquierda', () {
    expect(siguienteCodigoRollo(['#007']), '#8');
  });

  test('Material.desdeMapa rechaza campo ausente y NaN', () {
    final sinUnidad = _mapaValido()..remove('unidad');
    expect(() => Material.desdeMapa('x', sinUnidad), throwsFormatException);
    expect(() => Material.desdeMapa('x', {..._mapaValido(), 'existencia': double.nan}),
        throwsFormatException);
    expect(() => Material.desdeMapa('x', {..._mapaValido(), 'existencia': double.infinity}),
        throwsFormatException);
  });

  test('leerDinero: comas de miles y formatos inválidos', () {
    expect(leerDinero('1,500'), 1500);
    expect(leerDinero(r'$1,500.50'), 1500.5);
    expect(leerDinero('1500'), 1500);
    expect(leerDinero('300'), 300);
    expect(leerDinero('12.5'), 12.5);
    for (final t in ['1,5', 'abc', '1,50,0', '', '1e3', 'NaN']) {
      expect(leerDinero(t), isNull, reason: t);
    }
  });

  test('redondear2 y deriva de punto flotante', () {
    expect(redondear2(3.3 - 1.1), 2.2);
    expect(redondear2(-2.8e-17).isNegative, isFalse);
    expect(_material(existencia: 3.3 - 1.1, stockMinimo: 2.2).necesitaCompra,
        isFalse);
    expect(_material(existencia: 0.3 - 0.2 - 0.1).existenciaNegativa, isFalse);
    expect(_material(existencia: -0.5).existenciaNegativa, isTrue);
  });
}
