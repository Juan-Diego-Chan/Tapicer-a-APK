import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/repositorio_privado.dart';
import '../../datos/repositorio_usuarios.dart';
import '../../dominio/usuario.dart';
import '../../nucleo/firebase_init.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';

/// Crea una cuenta de autenticación y devuelve su uid.
abstract class CreadorCuentas {
  Future<String> crear(String email, String contrasena);
}

/// Crea la cuenta en una app Firebase secundaria para no tocar la sesión del
/// dueño. No se prueba en unitarias (requiere Firebase real).
///
/// La app secundaria se crea una sola vez y se reutiliza: FlutterFire guarda
/// la instancia de FirebaseAuth por nombre de app, así que borrar y recrear
/// 'alta' dejaba una instancia vieja ligada a la app borrada y la segunda
/// alta fallaba.
class CreadorCuentasFirebase implements CreadorCuentas {
  static const _nombreApp = 'alta';
  static Future<FirebaseAuth>? _auth;

  static Future<FirebaseAuth> _authSecundaria() => _auth ??= () async {
        final existente =
            Firebase.apps.where((a) => a.name == _nombreApp).firstOrNull;
        final app = existente ??
            await Firebase.initializeApp(
              name: _nombreApp,
              options: opcionesFirebase(),
            );
        final auth = FirebaseAuth.instanceFor(app: app);
        if (usarEmulador) {
          await auth.useAuthEmulator(hostEmulador, puertoAuthEmulador);
        }
        return auth;
      }();

  @override
  Future<String> crear(String email, String contrasena) async {
    final Future<FirebaseAuth> pendiente = _authSecundaria();
    final FirebaseAuth auth;
    try {
      auth = await pendiente;
    } catch (_) {
      _auth = null; // permite reintentar la inicialización
      rethrow;
    }
    try {
      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: contrasena,
      );
      return cred.user!.uid;
    } finally {
      if (auth.currentUser != null) await auth.signOut();
    }
  }
}

class ServicioAltaUsuario {
  final CreadorCuentas _creador;
  final RepositorioUsuarios _usuarios;
  final RepositorioPrivado _privado;

  ServicioAltaUsuario(this._creador, this._usuarios, this._privado);

  /// Limitación conocida: si la cuenta se crea pero fallan las escrituras en
  /// Firestore, la cuenta de Auth queda huérfana (el SDK cliente no puede
  /// borrar a otro usuario). Ese usuario verá "cuenta sin configurar".
  Future<void> altaEmpleado({
    required String nombre,
    required String email,
    required String contrasena,
    required double sueldoSemanal,
  }) async {
    if (sueldoSemanal <= 0) {
      throw ArgumentError.value(
        sueldoSemanal,
        'sueldoSemanal',
        'Debe ser mayor a 0',
      );
    }
    final String uid;
    try {
      uid = await _creador.crear(email, contrasena);
    } on FirebaseAuthException catch (e) {
      throw ErrorSesion(mensajeErrorAuth(e.code));
    }
    await _usuarios.guardar(
      Usuario(
        uid: uid,
        nombre: nombre,
        email: email,
        rol: Rol.empleado,
        activo: true,
      ),
    );
    await _privado.fijarSueldo(uid, sueldoSemanal);
  }
}

final repositorioPrivadoProvider = Provider<RepositorioPrivado>(
  (ref) => RepositorioPrivado(ref.watch(firestoreProvider)),
);

final servicioAltaUsuarioProvider = Provider<ServicioAltaUsuario>(
  (ref) => ServicioAltaUsuario(
    CreadorCuentasFirebase(),
    ref.watch(repositorioUsuariosProvider),
    ref.watch(repositorioPrivadoProvider),
  ),
);
