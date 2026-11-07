import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_trabajo.dart';
import 'package:tapiceria/dominio/inventario.dart';
import 'package:tapiceria/funciones/pedidos/servicio_trabajo.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ServicioTrabajo servicio;
  late RepositorioTrabajo repo;

  const tela = Material(
    id: 'm1',
    nombre: 'Tela',
    categoria: Categoria.tela,
    unidad: Unidad.m,
    stockMinimo: 5,
    existencia: 50,
    usaRollos: true,
    marcadoAgotandose: false,
  );

  setUp(() async {
    db = FakeFirebaseFirestore();
    servicio = ServicioTrabajo(db, 'u1');
    repo = RepositorioTrabajo(db);
    await db.collection('materiales').doc('m1').set({'existencia': 50});
    await db.collection('rollos').doc('r1').set({'existencia': 30});
  });

  CollectionReference<Map<String, dynamic>> lineas() => db
      .collection('pedidos')
      .doc('p1')
      .collection('muebles')
      .doc('mu1')
      .collection('materiales');

  Future<double> existencia(String col, String id) async =>
      ((await db.collection(col).doc(id).get()).data()!['existencia'] as num)
          .toDouble();

  Future<void> agregar(
    double cantidad, {
    String? rolloId = 'r1',
    bool delCliente = false,
  }) => servicio.agregarLinea(
    pedidoId: 'p1',
    muebleId: 'mu1',
    material: tela,
    cantidad: cantidad,
    rolloId: rolloId,
    delCliente: delCliente,
    fecha: DateTime(2026, 11, 7),
  );

  test('2.5 m de tela: línea y movimiento con el mismo id', () async {
    await agregar(2.5);
    final ls = await lineas().get();
    expect(ls.size, 1);
    final movs = await db.collection('movimientos').get();
    expect(movs.size, 1);
    expect(movs.docs.single.id, ls.docs.single.id);
    final mov = movs.docs.single.data();
    expect(mov['tipo'], 'consumo');
    expect(mov['cantidad'], -2.5);
    expect(mov['pedidoId'], 'p1');
    expect(mov['muebleId'], 'mu1');
    expect(mov['rolloId'], 'r1');
    expect(mov['usuarioId'], 'u1');
    final l = ls.docs.single.data();
    expect(l['delCliente'], false);
    expect(l['rolloId'], 'r1');
    expect(l['fecha'], mov['fecha']);
    expect(await existencia('rollos', 'r1'), 27.5);
    expect(await existencia('materiales', 'm1'), 47.5);
  });

  test('dos líneas sobre el mismo rollo', () async {
    await agregar(2.5);
    await agregar(1.5);
    expect(await existencia('rollos', 'r1'), 26);
    expect(await existencia('materiales', 'm1'), 46);
  });

  test(
    'línea del cliente: rolloId nulo, sin movimiento ni existencias',
    () async {
      await agregar(2, delCliente: true);
      final l = (await lineas().get()).docs.single.data();
      expect(l['rolloId'], isNull);
      expect(l['delCliente'], true);
      expect((await db.collection('movimientos').get()).size, 0);
      expect(await existencia('rollos', 'r1'), 30);
      expect(await existencia('materiales', 'm1'), 50);
    },
  );

  test(
    'tela de inventario sin rollo lanza ArgumentError sin escribir',
    () async {
      expect(() => agregar(2, rolloId: null), throwsArgumentError);
      expect((await lineas().get()).size, 0);
      expect((await db.collection('movimientos').get()).size, 0);
      expect(await existencia('materiales', 'm1'), 50);
    },
  );

  test('cantidad inválida lanza ArgumentError', () {
    expect(() => agregar(0), throwsArgumentError);
    expect(() => agregar(-1), throwsArgumentError);
    expect(() => agregar(double.nan), throwsArgumentError);
    expect(() => agregar(double.infinity), throwsArgumentError);
  });

  test('borrarLinea devuelve existencias y deja un ajuste', () async {
    await agregar(2.5);
    final linea = (await repo.observarLineas('p1', 'mu1').first).single;
    await servicio.borrarLinea(
      pedidoId: 'p1',
      muebleId: 'mu1',
      linea: linea,
      material: tela,
    );
    expect((await lineas().get()).size, 0);
    expect(await existencia('rollos', 'r1'), 30);
    expect(await existencia('materiales', 'm1'), 50);
    final movs = (await db.collection('movimientos').get()).docs;
    expect(movs.length, 2);
    final ajuste = movs.firstWhere((d) => d.data()['tipo'] == 'ajuste');
    expect(ajuste.id, isNot(linea.id));
    expect(ajuste.data()['cantidad'], 2.5);
    expect(ajuste.data()['pedidoId'], 'p1');
    expect(ajuste.data()['muebleId'], 'mu1');
    expect(ajuste.data()['rolloId'], 'r1');
    expect(ajuste.data()['usuarioId'], 'u1');
  });

  test('borrarLinea del cliente solo borra la línea', () async {
    await agregar(2, delCliente: true);
    final linea = (await repo.observarLineas('p1', 'mu1').first).single;
    await servicio.borrarLinea(
      pedidoId: 'p1',
      muebleId: 'mu1',
      linea: linea,
      material: tela,
    );
    expect((await lineas().get()).size, 0);
    expect((await db.collection('movimientos').get()).size, 0);
    expect(await existencia('materiales', 'm1'), 50);
  });

  test('registrarDias valida y guarda; borrarDias elimina', () async {
    await servicio.registrarDias(
      pedidoId: 'p1',
      muebleId: 'mu1',
      usuarioId: 'u2',
      dias: 1.5,
      fecha: DateTime(2026, 11, 7),
    );
    final dias = await repo.observarDias('p1', 'mu1').first;
    expect(dias.single.dias, 1.5);
    expect(dias.single.usuarioId, 'u2');
    for (final malo in [0.3, 0.0, -1.0, 7.5, double.nan]) {
      expect(
        () => servicio.registrarDias(
          pedidoId: 'p1',
          muebleId: 'mu1',
          usuarioId: 'u2',
          dias: malo,
        ),
        throwsArgumentError,
      );
    }
    await servicio.borrarDias(
      pedidoId: 'p1',
      muebleId: 'mu1',
      diaId: dias.single.id,
    );
    expect(await repo.observarDias('p1', 'mu1').first, isEmpty);
  });
}
