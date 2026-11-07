import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/repositorio_clientes.dart';
import '../../datos/repositorio_pedidos.dart';
import '../../datos/repositorio_plantillas.dart';
import '../../dominio/pedidos.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';
import 'servicio_pedidos.dart';

final repositorioClientesProvider = Provider<RepositorioClientes>(
  (ref) => RepositorioClientes(ref.watch(firestoreProvider)),
);

final repositorioPedidosProvider = Provider<RepositorioPedidos>(
  (ref) => RepositorioPedidos(ref.watch(firestoreProvider)),
);

final repositorioPlantillasProvider = Provider<RepositorioPlantillas>(
  (ref) => RepositorioPlantillas(ref.watch(firestoreProvider)),
);

final servicioPedidosProvider = Provider<ServicioPedidos>((ref) {
  final estado = ref.watch(estadoSesionProvider).value;
  if (estado is! SesionActiva) {
    throw StateError('No hay sesión activa');
  }
  return ServicioPedidos(ref.watch(firestoreProvider), estado.usuario.uid);
});

final clientesProvider = StreamProvider<List<Cliente>>(
  (ref) => ref.watch(repositorioClientesProvider).observarClientes(),
);

final pedidosActivosProvider = StreamProvider<List<Pedido>>(
  (ref) => ref.watch(repositorioPedidosProvider).observarPedidosActivos(),
);

final pedidosRecientesProvider = StreamProvider<List<Pedido>>(
  (ref) => ref.watch(repositorioPedidosProvider).observarPedidosRecientes(),
);

final plantillasProvider = StreamProvider<List<Plantilla>>(
  (ref) => ref.watch(repositorioPlantillasProvider).observarPlantillas(),
);

final pedidoProvider = StreamProvider.autoDispose.family<Pedido?, String>(
  (ref, id) => ref.watch(repositorioPedidosProvider).observarPedido(id),
);

final mueblesProvider =
    StreamProvider.autoDispose.family<List<Mueble>, String>(
  (ref, pedidoId) =>
      ref.watch(repositorioPedidosProvider).observarMuebles(pedidoId),
);

final muebleProvider = StreamProvider.autoDispose
    .family<Mueble?, ({String pedidoId, String muebleId})>(
  (ref, k) => ref
      .watch(repositorioPedidosProvider)
      .observarMueble(k.pedidoId, k.muebleId),
);

final mueblesActivosProvider =
    StreamProvider.autoDispose.family<List<Mueble>, TipoTrabajo>(
  (ref, tipo) =>
      ref.watch(repositorioPedidosProvider).observarMueblesActivos(tipo),
);

/// Solo para el dueño: el empleado no puede leer el historial.
final cambiosPrecioProvider =
    StreamProvider.autoDispose.family<List<CambioPrecio>, String>(
  (ref, pedidoId) =>
      ref.watch(repositorioPedidosProvider).observarCambiosPrecio(pedidoId),
);
