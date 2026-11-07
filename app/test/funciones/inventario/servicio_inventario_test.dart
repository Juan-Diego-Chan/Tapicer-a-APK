import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapiceria/funciones/auth/providers.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/inventario/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_costos.dart';
import 'package:tapiceria/datos/repositorio_inventario.dart';
import 'package:tapiceria/dominio/inventario.dart';
import 'package:tapiceria/funciones/inventario/servicio_inventario.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ServicioInventario servicio;
  late RepositorioInventario repo;
  late RepositorioCostos costos;

  setUp(() {
    db = FakeFirebaseFirestore();
    servicio = ServicioInventario(db, 'u1');
    repo = RepositorioInventario(db);
    costos = RepositorioCostos(db);
  });

  Future<Material> crear(String nombre, Categoria c, Unidad u,
      {double existencia = 0, bool agotandose = false}) async {
    final m = Material(
        id: '',
        nombre: nombre,
        categoria: c,
        unidad: u,
        stockMinimo: 1,
        existencia: 0,
        usaRollos: c == Categoria.tela,
        marcadoAgotandose: false);
    final id = await repo.crearMaterial(m);
    await db.collection('materiales').doc(id).update(
        {'existencia': existencia, 'marcadoAgotandose': agotandose});
    return Material(
        id: id,
        nombre: nombre,
        categoria: c,
        unidad: u,
        stockMinimo: 1,
        existencia: existencia,
        usaRollos: c == Categoria.tela,
        marcadoAgotandose: agotandose);
  }

  Future<Map<String, dynamic>> mat(String id) async =>
      (await db.collection('materiales').doc(id).get()).data()!;

  test('compra de guata', () async {
    final m = await crear('Guata', Categoria.guata, Unidad.kg,
        existencia: 2, agotandose: true);
    await servicio.registrarCompra(material: m, cantidad: 10, precioTotal: 500);
    final d = await mat(m.id);
    expect(d['existencia'], 12);
    expect(d['marcadoAgotandose'], false);
    final c = (await db.collection('materiales_costos').doc(m.id).get()).data();
    expect(c, {'cantidadComprada': 10, 'costoTotalComprado': 500});
    final compras = await db.collection('compras').get();
    expect(compras.docs.length, 1);
    expect(compras.docs.first['tipo'], 'compra');
    final movs = await db.collection('movimientos').get();
    expect(movs.docs.length, 1);
    expect(movs.docs.first['cantidad'], 10);
    expect(movs.docs.first['usuarioId'], 'u1');
    expect(movs.docs.first['fecha'], isA<Timestamp>());
    expect(movs.docs.first.data().keys.toSet(), {
      'tipo', 'materialId', 'rolloId', 'cantidad', 'usuarioId', 'fecha'
    });
  });

  test('dos compras dan costo promedio 65', () async {
    final m = await crear('Guata', Categoria.guata, Unidad.kg);
    await servicio.registrarCompra(material: m, cantidad: 10, precioTotal: 500);
    await servicio.registrarCompra(material: m, cantidad: 30, precioTotal: 2100);
    expect(await costos.observarCostoPromedio(m.id).first, 65);
  });

  test('compra de tela crea rollo y costo', () async {
    final m = await crear('Tela', Categoria.tela, Unidad.m);
    await servicio.registrarCompra(
        material: m, cantidad: 25, precioTotal: 3000, codigoRollo: '#4');
    final rollos = await repo.observarRollos(m.id).first;
    expect(rollos.length, 1);
    expect(rollos.first.codigo, '#4');
    expect(rollos.first.cantidadInicial, 25);
    expect(rollos.first.existencia, 25);
    final rc = await db.collection('rollos_costos').doc(rollos.first.id).get();
    expect(rc['costoPorUnidad'], 120);
    expect(await costos.observarCostoRollo(rollos.first.id).first, 120);
    expect((await mat(m.id))['existencia'], 25);
    final mov = (await db.collection('movimientos').get()).docs.first;
    expect(mov['rolloId'], rollos.first.id);
  });

  test('carga inicial sin costo', () async {
    final m = await crear('Guata', Categoria.guata, Unidad.kg, agotandose: true);
    await servicio.registrarCargaInicial(material: m, cantidad: 5);
    final d = await mat(m.id);
    expect(d['existencia'], 5);
    expect(d['marcadoAgotandose'], true);
    expect((await db.collection('materiales_costos').doc(m.id).get()).exists,
        false);
    expect(await costos.observarCostoPromedio(m.id).first, isNull);
    final c = (await db.collection('compras').get()).docs.first;
    expect(c['precioTotal'], isNull);
    expect(c['tipo'], 'inicial');
  });

  test('carga inicial con costo', () async {
    final m = await crear('Guata', Categoria.guata, Unidad.kg);
    await servicio.registrarCargaInicial(
        material: m, cantidad: 4, costoPorUnidad: 50);
    final c = (await db.collection('materiales_costos').doc(m.id).get()).data();
    expect(c, {'cantidadComprada': 4, 'costoTotalComprado': 200});
    expect((await db.collection('compras').get()).docs.first['precioTotal'], 200);
  });

  test('ajuste -3.5 sobre tela', () async {
    final m = await crear('Tela', Categoria.tela, Unidad.m);
    await servicio.registrarCompra(
        material: m, cantidad: 25, precioTotal: 3000, codigoRollo: '#1');
    final rollo = (await repo.observarRollos(m.id).first).first;
    await servicio.registrarAjuste(
        material: m, cantidad: -3.5, rolloId: rollo.id);
    expect((await mat(m.id))['existencia'], 21.5);
    final r = (await repo.observarRollos(m.id).first).first;
    expect(r.existencia, 21.5);
    final movs = await repo.observarMovimientos(m.id).first;
    expect(movs.any((x) => x.tipo == TipoMovimiento.ajuste), true);
  });

  test('validaciones no escriben nada', () async {
    final g = await crear('Guata', Categoria.guata, Unidad.kg);
    final t = await crear('Tela', Categoria.tela, Unidad.m);
    await expectLater(
        servicio.registrarCompra(material: g, cantidad: 0, precioTotal: 1),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCompra(material: g, cantidad: 1, precioTotal: -1),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCompra(material: g, cantidad: 1, precioTotal: 0),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCargaInicial(
            material: g, cantidad: 1, costoPorUnidad: 0),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCompra(material: t, cantidad: 5, precioTotal: 10),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCargaInicial(material: t, cantidad: 5),
        throwsArgumentError);
    await expectLater(
        servicio.registrarAjuste(material: g, cantidad: 0), throwsArgumentError);
    await expectLater(
        servicio.registrarAjuste(material: t, cantidad: 1), throwsArgumentError);
    for (final c in ['compras', 'movimientos', 'materiales_costos', 'rollos']) {
      expect((await db.collection(c).get()).docs, isEmpty, reason: c);
    }
    expect((await mat(g.id))['existencia'], 0);
  });

  test('valores no finitos y código largo no escriben nada', () async {
    final g = await crear('Guata', Categoria.guata, Unidad.kg);
    final t = await crear('Tela', Categoria.tela, Unidad.m);
    await expectLater(
        servicio.registrarCompra(
            material: g, cantidad: double.nan, precioTotal: 1),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCompra(
            material: g, cantidad: double.infinity, precioTotal: 1),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCompra(
            material: g, cantidad: 1, precioTotal: double.nan),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCargaInicial(
            material: g, cantidad: 1, costoPorUnidad: double.infinity),
        throwsArgumentError);
    await expectLater(
        servicio.registrarAjuste(material: g, cantidad: double.nan),
        throwsArgumentError);
    await expectLater(
        servicio.registrarCompra(
            material: t,
            cantidad: 1,
            precioTotal: 1,
            codigoRollo: 'x' * 21),
        throwsArgumentError);
    for (final c in ['compras', 'movimientos', 'materiales_costos', 'rollos']) {
      expect((await db.collection(c).get()).docs, isEmpty, reason: c);
    }
  });

  test('fechas guardadas como Timestamp', () async {
    final t = await crear('Tela', Categoria.tela, Unidad.m);
    await servicio.registrarCompra(
        material: t, cantidad: 2, precioTotal: 10, codigoRollo: '#1');
    final r = (await db.collection('rollos').get()).docs.first;
    final c = (await db.collection('compras').get()).docs.first;
    expect(r['fechaCompra'], isA<Timestamp>());
    expect(c['fecha'], isA<Timestamp>());
  });

  test('servicioInventarioProvider lanza StateError sin sesión activa', () async {
    final container = ProviderContainer(overrides: [
      estadoSesionProvider.overrideWith((ref) => Stream.value(const SinSesion())),
    ]);
    addTearDown(container.dispose);
    container.listen(estadoSesionProvider, (_, _) {});
    await container.read(estadoSesionProvider.future);
    expect(() => container.read(servicioInventarioProvider),
        throwsA(predicate((e) => e.toString().contains('Bad state: No hay sesión activa'))));
  });
}
