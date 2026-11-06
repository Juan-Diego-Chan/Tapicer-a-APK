import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../dominio/usuario.dart';
import '../funciones/auth/pantalla_estado_cuenta.dart';
import '../funciones/auth/pantalla_inicio_sesion.dart';
import '../funciones/auth/providers.dart';
import '../funciones/auth/servicio_sesion.dart';
import '../funciones/inicio/pantalla_inicio.dart';
import 'pantalla_proximamente.dart';

const _rutasSoloDueno = {'/compras', '/contabilidad', '/usuarios'};

/// Lógica pura de guardia. Devuelve la ruta destino o null si no hay que
/// redirigir.
String? redirigir(EstadoSesion estado, String ruta) {
  switch (estado) {
    case CargandoSesion():
      return null;
    case SinSesion():
      return ruta == '/entrar' ? null : '/entrar';
    case CuentaSinConfigurar() || CuentaDesactivada():
      return ruta == '/cuenta' ? null : '/cuenta';
    case SesionActiva(:final usuario):
      if (ruta == '/entrar' || ruta == '/cuenta') return '/';
      if (_rutasSoloDueno.contains(ruta) && usuario.rol != Rol.dueno) {
        return '/';
      }
      return null;
  }
}

EstadoSesion _aEstado(AsyncValue<EstadoSesion> v) => v.when(
      data: (e) => e,
      loading: () => const CargandoSesion(),
      error: (_, _) => const SinSesion(),
    );

GoRouter crearRouter(Ref ref) {
  final cambios = ValueNotifier<int>(0);
  ref.listen(estadoSesionProvider, (_, _) => cambios.value++);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: cambios,
    redirect: (context, state) => redirigir(
      _aEstado(ref.read(estadoSesionProvider)),
      state.uri.path,
    ),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PantallaInicio()),
      GoRoute(path: '/entrar', builder: (_, _) => const PantallaInicioSesion()),
      GoRoute(path: '/cuenta', builder: (_, _) => const PantallaEstadoCuenta()),
      // Secciones sin pantalla todavía comparten el marcador "Próximamente".
      // Los planes siguientes reemplazan cada una por su pantalla real.
      for (final e in entradasMenu)
        GoRoute(
          path: e.ruta,
          builder: (_, _) => PantallaProximamente(titulo: e.titulo),
        ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    cambios.dispose();
  });
  return router;
}

final routerProvider = Provider<GoRouter>((ref) => crearRouter(ref));
