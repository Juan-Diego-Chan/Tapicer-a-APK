import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../datos/repositorio_usuarios.dart';
import '../../dominio/usuario.dart';

sealed class EstadoSesion {
  const EstadoSesion();
}

class SinSesion extends EstadoSesion {
  const SinSesion();
}

class CargandoSesion extends EstadoSesion {
  const CargandoSesion();
}

class CuentaSinConfigurar extends EstadoSesion {
  const CuentaSinConfigurar();
}

class CuentaDesactivada extends EstadoSesion {
  const CuentaDesactivada();
}

class SesionActiva extends EstadoSesion {
  final Usuario usuario;
  const SesionActiva(this.usuario);
}

class ErrorSesion implements Exception {
  final String mensaje;
  const ErrorSesion(this.mensaje);

  @override
  String toString() => mensaje;
}

String mensajeErrorAuth(String codigo) {
  switch (codigo) {
    case 'invalid-credential':
    case 'wrong-password':
      return 'Correo o contraseña incorrectos';
    case 'network-request-failed':
      return 'Se necesita internet para iniciar sesión por primera vez';
    case 'too-many-requests':
      return 'Demasiados intentos. Espera unos minutos.';
    case 'email-already-in-use':
      return 'Ese correo ya está registrado';
    case 'weak-password':
      return 'La contraseña debe tener al menos 6 caracteres';
    default:
      return 'Ocurrió un error. Intenta de nuevo.';
  }
}

class ServicioSesion {
  final FirebaseAuth _auth;
  final RepositorioUsuarios _repo;

  ServicioSesion(this._auth, this._repo);

  /// Combina el estado de autenticación con el documento del usuario.
  /// Al cambiar el usuario de auth se cancela la escucha del documento
  /// anterior (switchMap), de modo que un cierre de sesión siempre se refleja
  /// aunque el stream del documento nunca termine.
  Stream<EstadoSesion> estado() {
    late StreamController<EstadoSesion> salida;
    StreamSubscription<User?>? subAuth;
    StreamSubscription<Usuario?>? subDoc;

    salida = StreamController<EstadoSesion>(
      onListen: () {
        subAuth = _auth.authStateChanges().listen(
          (user) {
            subDoc?.cancel();
            subDoc = null;
            if (user == null) {
              salida.add(const SinSesion());
              return;
            }
            salida.add(const CargandoSesion());
            subDoc = _repo.observar(user.uid).listen(
                  (u) => salida.add(_aEstado(u)),
                  onError: salida.addError,
                );
          },
          onError: salida.addError,
          onDone: () => salida.close(),
        );
      },
      onCancel: () async {
        await subDoc?.cancel();
        await subAuth?.cancel();
      },
    );
    return salida.stream;
  }

  EstadoSesion _aEstado(Usuario? u) {
    if (u == null) return const CuentaSinConfigurar();
    if (!u.activo) return const CuentaDesactivada();
    return SesionActiva(u);
  }

  Future<void> iniciarSesion(String email, String contrasena) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email, password: contrasena);
    } on FirebaseAuthException catch (e) {
      throw ErrorSesion(mensajeErrorAuth(e.code));
    }
  }

  Future<void> cerrarSesion() => _auth.signOut();
}
