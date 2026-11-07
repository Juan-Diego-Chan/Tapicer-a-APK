import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_inventario.dart';
import 'package:tapiceria/dominio/inventario.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioInventario repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioInventario(db);
  });

  Map<String, dynamic> mapa(String nombre, {String categoria = 'guata'}) => {
        'nombre': nombre,
        'categoria': categoria,
        'unidad': 'kg',
        'stockMinimo': 1,
        'existencia': 0,
        'usaRollos': false,
        'marcadoAgotandose': false,
      };

  test('observarMateriales omite mal formados y ordena por nombre', () async {
    await db.collection('materiales').doc('b').set(mapa('Zeta'));
    await db.collection('materiales').doc('a').set(mapa('Alfa'));
    await db.collection('materiales').doc('x').set(mapa('Mala', categoria: 'madera'));
    final lista = await repo.observarMateriales().first;
    expect(lista.map((m) => m.nombre), ['Alfa', 'Zeta']);
  });

  test('editarMaterial no cambia existencia', () async {
    await db.collection('materiales').doc('a').set({...mapa('Alfa'), 'existencia': 7});
    await repo.editarMaterial('a',
        nombre: 'Beta',
        categoria: Categoria.espuma,
        unidad: Unidad.m,
        stockMinimo: 3);
    final d = (await db.collection('materiales').doc('a').get()).data()!;
    expect(d['existencia'], 7);
    expect(d['nombre'], 'Beta');
    expect(d['categoria'], 'espuma');
  });

  test('marcarAgotandose pone true', () async {
    await db.collection('materiales').doc('a').set(mapa('Alfa'));
    await repo.marcarAgotandose('a');
    final m = await repo.observarMaterial('a').first;
    expect(m!.marcadoAgotandose, true);
  });

  test('crearMaterial devuelve id y guarda 7 llaves', () async {
    final id = await repo.crearMaterial(const Material(
        id: '',
        nombre: 'Hilo',
        categoria: Categoria.otros,
        unidad: Unidad.pza,
        stockMinimo: 2,
        existencia: 0,
        usaRollos: false,
        marcadoAgotandose: false));
    final d = (await db.collection('materiales').doc(id).get()).data()!;
    expect(d.length, 7);
  });
}
