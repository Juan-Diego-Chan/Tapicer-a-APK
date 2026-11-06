import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:tapiceria/datos/repositorio_usuarios.dart';
import 'package:tapiceria/dominio/usuario.dart';
import 'package:tapiceria/funciones/auth/servicio_sesion.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioUsuarios repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioUsuarios(db);
  });

  Future<void> crearDoc({bool activo = true}) => db.doc('usuarios/u1').set({
        'nombre': 'Ana',
        'email': 'a@x.mx',
        'rol': 'empleado',
        'activo': activo,
      });

  MockFirebaseAuth authCon({bool sesion = true}) => MockFirebaseAuth(
        signedIn: sesion,
        mockUser: MockUser(uid: 'u1', email: 'a@x.mx'),
      );

  test('sin sesion emite SinSesion', () async {
    final s = ServicioSesion(authCon(sesion: false), repo);
    expect(await s.estado().first, isA<SinSesion>());
  });

  test('con sesion y doc activo emite SesionActiva con su rol', () async {
    await crearDoc();
    final s = ServicioSesion(authCon(), repo);
    final e = await s.estado().firstWhere((e) => e is! CargandoSesion);
    expect(e, isA<SesionActiva>());
    expect((e as SesionActiva).usuario.rol, Rol.empleado);
  });

  test('con sesion sin doc emite CuentaSinConfigurar', () async {
    final s = ServicioSesion(authCon(), repo);
    expect(await s.estado().firstWhere((e) => e is! CargandoSesion),
        isA<CuentaSinConfigurar>());
  });

  test('doc inactivo emite CuentaDesactivada', () async {
    await crearDoc(activo: false);
    final s = ServicioSesion(authCon(), repo);
    expect(await s.estado().firstWhere((e) => e is! CargandoSesion),
        isA<CuentaDesactivada>());
  });

  test('si el doc pasa a inactivo mientras escucha, emite CuentaDesactivada',
      () async {
    await crearDoc();
    final s = ServicioSesion(authCon(), repo);
    final futuro = s.estado().firstWhere((e) => e is CuentaDesactivada);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.fijarActivo('u1', false);
    expect(await futuro.timeout(const Duration(seconds: 2)),
        isA<CuentaDesactivada>());
  });

  test('cerrar sesion con el doc activo escuchando emite SinSesion', () async {
    await crearDoc();
    final auth = authCon();
    final s = ServicioSesion(auth, repo);
    final emitidos = <EstadoSesion>[];
    final sub = s.estado().listen(emitidos.add);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emitidos.last, isA<SesionActiva>());
    await s.cerrarSesion();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emitidos.last, isA<SinSesion>());
    await sub.cancel();
  });

  test('iniciarSesion con error de Firebase lanza ErrorSesion en espanol',
      () async {
    final auth = MockFirebaseAuth();
    whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
        .on(auth)
        .thenThrow(FirebaseAuthException(code: 'wrong-password'));
    final s = ServicioSesion(auth, repo);
    await expectLater(
      s.iniciarSesion('a@x.mx', 'mala'),
      throwsA(isA<ErrorSesion>().having(
          (e) => e.mensaje, 'mensaje', 'Correo o contraseña incorrectos')),
    );
  });

  test('doc con rol invalido emite CuentaSinConfigurar', () async {
    await db.doc('usuarios/u1').set({
      'nombre': 'Ana',
      'email': 'a@x.mx',
      'rol': 'jefe',
      'activo': true,
    });
    final s = ServicioSesion(authCon(), repo);
    expect(await s.estado().firstWhere((e) => e is! CargandoSesion),
        isA<CuentaSinConfigurar>());
  });

  test('error permission-denied del stream del doc emite CuentaDesactivada',
      () async {
    final s = ServicioSesion(authCon(), _RepoConError(db));
    expect(await s.estado().firstWhere((e) => e is! CargandoSesion),
        isA<CuentaDesactivada>());
  });

  test('estadoParaErrorDeDoc: otros errores no se traducen', () {
    expect(estadoParaErrorDeDoc(StateError('x')), isNull);
    expect(
        estadoParaErrorDeDoc(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')),
        isNull);
  });

  group('mensajeErrorAuth', () {
    test('traducciones', () {
      expect(mensajeErrorAuth('invalid-credential'),
          'Correo o contraseña incorrectos');
      expect(mensajeErrorAuth('wrong-password'),
          'Correo o contraseña incorrectos');
      expect(mensajeErrorAuth('network-request-failed'),
          'Se necesita internet para iniciar sesión por primera vez');
      expect(mensajeErrorAuth('too-many-requests'),
          'Demasiados intentos. Espera unos minutos.');
      expect(mensajeErrorAuth('email-already-in-use'),
          'Ese correo ya está registrado');
      expect(mensajeErrorAuth('weak-password'),
          'La contraseña debe tener al menos 6 caracteres');
      expect(mensajeErrorAuth('invalid-email'), 'El correo no es válido');
      expect(mensajeErrorAuth('user-not-found'),
          'Correo o contraseña incorrectos');
      expect(mensajeErrorAuth('user-disabled'), 'Tu cuenta está desactivada');
      expect(mensajeErrorAuth('otro'), 'Ocurrió un error. Intenta de nuevo.');
    });
  });
}

class _RepoConError extends RepositorioUsuarios {
  _RepoConError(super.db);

  @override
  Stream<Usuario?> observar(String uid) => Stream.error(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
}
