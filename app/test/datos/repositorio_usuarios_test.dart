import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_usuarios.dart';
import 'package:tapiceria/dominio/usuario.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioUsuarios repo;
  final ana = Usuario(
    uid: 'u1',
    nombre: 'Ana',
    email: 'a@x.mx',
    rol: Rol.empleado,
    activo: true,
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioUsuarios(db);
  });

  test('guardar y observar emite el usuario', () async {
    await repo.guardar(ana);
    final u = await repo.observar('u1').first;
    expect(u?.nombre, 'Ana');
    expect(u?.rol, Rol.empleado);
  });

  test('guardar fija creadoEn al crear y no lo pisa al actualizar', () async {
    await repo.guardar(ana);
    final primero = (await db.doc('usuarios/u1').get()).data()!['creadoEn'];
    expect(primero, isNotNull);
    await repo.guardar(Usuario(
      uid: 'u1',
      nombre: 'Ana B',
      email: 'a@x.mx',
      rol: Rol.empleado,
      activo: true,
    ));
    final doc = (await db.doc('usuarios/u1').get()).data()!;
    expect(doc['creadoEn'], primero);
    expect(doc['nombre'], 'Ana B');
  });

  test('observar usuario inexistente emite null', () async {
    expect(await repo.observar('nadie').first, isNull);
  });

  test('fijarActivo cambia activo', () async {
    await repo.guardar(ana);
    await repo.fijarActivo('u1', false);
    final u = await repo.observar('u1').first;
    expect(u?.activo, false);
  });

  test('observarTodos lista los usuarios', () async {
    await repo.guardar(ana);
    final lista = await repo.observarTodos().first;
    expect(lista.map((u) => u.uid), ['u1']);
  });

  test('observarTodos omite documentos mal formados', () async {
    await repo.guardar(ana);
    await db.doc('usuarios/malo').set({
      'nombre': 123,
      'email': 'm@x.mx',
      'rol': 'empleado',
      'activo': true,
    });
    final lista = await repo.observarTodos().first;
    expect(lista.map((u) => u.uid), ['u1']);
  });
}
