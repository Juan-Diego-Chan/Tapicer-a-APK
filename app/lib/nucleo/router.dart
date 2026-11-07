import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../dominio/pedidos.dart' show TipoTrabajo;
import '../dominio/usuario.dart';
import '../funciones/auth/pantalla_estado_cuenta.dart';
import '../funciones/auth/pantalla_inicio_sesion.dart';
import '../funciones/auth/providers.dart';
import '../funciones/auth/servicio_sesion.dart';
import '../funciones/compras/pantalla_lista_compras.dart';
import '../funciones/inicio/pantalla_inicio.dart';
import '../funciones/inventario/pantalla_inventario.dart';
import '../funciones/inventario/pantalla_material.dart';
import '../funciones/pedidos/pantalla_mueble.dart';
import '../funciones/pedidos/pantalla_nuevo_pedido.dart';
import '../funciones/pedidos/pantalla_pedido.dart';
import '../funciones/pedidos/pantalla_pedidos.dart';
import '../funciones/plantillas/pantalla_plantillas.dart';
import '../funciones/trabajo/pantalla_trabajo.dart';
import '../funciones/usuarios/pantalla_usuarios.dart';
import 'pantalla_proximamente.dart';

final _rutasSoloDueno = entradasMenu
    .where((e) => e.soloDueno)
    .map((e) => e.ruta)
    .toList();

/// Rutas con pantalla real; el resto usa el marcador "Próximamente".
const _rutasConPantalla = {
  '/usuarios',
  '/inventario',
  '/compras',
  '/plantillas',
  '/pedidos',
  '/fabricacion',
  '/reparacion',
};

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
      final soloDueno = _rutasSoloDueno.any(
        (r) => ruta == r || ruta.startsWith('$r/'),
      );
      if (soloDueno && usuario.rol != Rol.dueno) {
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
    redirect: (context, state) =>
        redirigir(_aEstado(ref.read(estadoSesionProvider)), state.uri.path),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PantallaInicio()),
      GoRoute(path: '/entrar', builder: (_, _) => const PantallaInicioSesion()),
      GoRoute(path: '/cuenta', builder: (_, _) => const PantallaEstadoCuenta()),
      // Secciones sin pantalla todavía comparten el marcador "Próximamente".
      // Los planes siguientes reemplazan cada una por su pantalla real.
      GoRoute(path: '/usuarios', builder: (_, _) => const PantallaUsuarios()),
      GoRoute(
        path: '/inventario',
        builder: (_, _) => const PantallaInventario(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) =>
                PantallaMaterial(materialId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/compras',
        builder: (_, _) => const PantallaListaCompras(),
      ),
      GoRoute(
        path: '/plantillas',
        builder: (_, _) => const PantallaPlantillas(),
      ),
      GoRoute(
        path: '/pedidos',
        builder: (_, _) => const PantallaPedidos(),
        routes: [
          // `nuevo` va antes de `:id` para que no se tome como un id de pedido.
          GoRoute(path: 'nuevo', builder: (_, _) => const PantallaNuevoPedido()),
          GoRoute(
            path: ':id',
            builder: (_, s) => PantallaPedido(pedidoId: s.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'muebles/:muebleId',
                builder: (_, s) => PantallaMueble(
                  pedidoId: s.pathParameters['id']!,
                  muebleId: s.pathParameters['muebleId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/fabricacion',
        builder: (_, _) => const PantallaTrabajo(tipo: TipoTrabajo.fabricacion),
      ),
      GoRoute(
        path: '/reparacion',
        builder: (_, _) => const PantallaTrabajo(tipo: TipoTrabajo.reparacion),
      ),
      for (final e in entradasMenu.where(
        (e) => !_rutasConPantalla.contains(e.ruta),
      ))
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
