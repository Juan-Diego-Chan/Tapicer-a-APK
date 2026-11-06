import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapiceria/datos/repositorio_privado.dart';
import 'package:tapiceria/datos/repositorio_usuarios.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';
import 'package:tapiceria/funciones/usuarios/servicio_alta_usuario.dart';

class _CreadorFalso implements CreadorCuentas {
  final Object? error;
  int llamadas = 0;
  _CreadorFalso({this.error});

  @override
  Future<String> crear(String email, String contrasena) async {
    llamadas++;
    if (error != null) throw error!;
    return 'uid-nuevo';
  }
}

void main() {
  late FakeFirebaseFirestore db;

  ServicioAltaUsuario servicio(CreadorCuentas c) =>
      ServicioAltaUsuario(c, RepositorioUsuarios(db), RepositorioPrivado(db));

  setUp(() => db = FakeFirebaseFirestore());

  test('el alta guarda usuario empleado activo y su sueldo', () async {
    await servicio(_CreadorFalso()).altaEmpleado(
      nombre: 'Luis',
      email: 'luis@x.com',
      contrasena: 'secreto1',
      sueldoSemanal: 2100,
    );
    final u = (await db.collection('usuarios').doc('uid-nuevo').get()).data()!;
    expect(u['rol'], 'empleado');
    expect(u['activo'], true);
    expect(u['nombre'], 'Luis');
    expect(u['email'], 'luis@x.com');
    final p = (await db.collection('usuarios_privado').doc('uid-nuevo').get())
        .data()!;
    expect(p['sueldoSemanal'], 2100);
  });

  test('correo repetido lanza ErrorSesion y no escribe', () async {
    final s = servicio(
      _CreadorFalso(error: FirebaseAuthException(code: 'email-already-in-use')),
    );
    await expectLater(
      s.altaEmpleado(
        nombre: 'Luis',
        email: 'luis@x.com',
        contrasena: 'secreto1',
        sueldoSemanal: 2100,
      ),
      throwsA(
        isA<ErrorSesion>().having(
          (e) => e.mensaje,
          'mensaje',
          'Ese correo ya está registrado',
        ),
      ),
    );
    expect((await db.collection('usuarios').get()).docs, isEmpty);
    expect((await db.collection('usuarios_privado').get()).docs, isEmpty);
  });

  test('sueldo <= 0 lanza ArgumentError sin llamar al creador', () async {
    final c = _CreadorFalso();
    for (final v in [0.0, -5.0]) {
      await expectLater(
        servicio(c).altaEmpleado(
          nombre: 'Luis',
          email: 'luis@x.com',
          contrasena: 'secreto1',
          sueldoSemanal: v,
        ),
        throwsArgumentError,
      );
    }
    expect(c.llamadas, 0);
  });
}
