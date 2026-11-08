import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/repositorio_dinero.dart';
import '../../dominio/dinero.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';
import 'servicio_dinero.dart';

final repositorioDineroProvider = Provider<RepositorioDinero>(
  (ref) => RepositorioDinero(ref.watch(firestoreProvider)),
);

final servicioDineroProvider = Provider<ServicioDinero>((ref) {
  final estado = ref.watch(estadoSesionProvider).value;
  if (estado is! SesionActiva) {
    throw StateError('No hay sesión activa');
  }
  return ServicioDinero(
      ref.watch(firestoreProvider), estado.usuario.uid, estado.usuario.rol);
});

/// Solo para el dueño: todos los pagos del pedido.
final pagosPedidoProvider =
    StreamProvider.autoDispose.family<List<Pago>, String>(
  (ref, pedidoId) =>
      ref.watch(repositorioDineroProvider).observarPagosPedido(pedidoId),
);

/// Pagos del pedido recibidos por el usuario de la sesión.
final misPagosPedidoProvider =
    StreamProvider.autoDispose.family<List<Pago>, String>((ref, pedidoId) {
  final estado = ref.watch(estadoSesionProvider).value;
  if (estado is! SesionActiva) {
    throw StateError('No hay sesión activa');
  }
  return ref
      .watch(repositorioDineroProvider)
      .observarMisPagosPedido(pedidoId, estado.usuario.uid);
});

final enManoProvider = StreamProvider.autoDispose.family<double, String>(
  (ref, uid) => ref.watch(repositorioDineroProvider).observarEnMano(uid),
);

final cajasProvider = StreamProvider.autoDispose<Map<String, double>>(
  (ref) => ref.watch(repositorioDineroProvider).observarCajas(),
);

final entregasPendientesProvider =
    StreamProvider.autoDispose<List<EntregaDinero>>(
  (ref) => ref.watch(repositorioDineroProvider).observarEntregasPendientes(),
);

final entregasDeProvider =
    StreamProvider.autoDispose.family<List<EntregaDinero>, String>(
  (ref, uid) => ref.watch(repositorioDineroProvider).observarEntregasDe(uid),
);

final pagosSueldoProvider =
    StreamProvider.autoDispose.family<List<PagoSueldo>, String>(
  (ref, uid) => ref.watch(repositorioDineroProvider).observarPagosSueldo(uid),
);
