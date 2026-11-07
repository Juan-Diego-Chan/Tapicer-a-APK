import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/repositorio_costos.dart';
import '../../datos/repositorio_inventario.dart';
import '../../dominio/inventario.dart';
import '../auth/providers.dart';
import '../auth/servicio_sesion.dart';
import 'servicio_inventario.dart';

final repositorioInventarioProvider = Provider<RepositorioInventario>(
  (ref) => RepositorioInventario(ref.watch(firestoreProvider)),
);

final repositorioCostosProvider = Provider<RepositorioCostos>(
  (ref) => RepositorioCostos(ref.watch(firestoreProvider)),
);

final servicioInventarioProvider = Provider<ServicioInventario>((ref) {
  final estado = ref.watch(estadoSesionProvider).value;
  if (estado is! SesionActiva) {
    throw StateError('No hay sesión activa');
  }
  return ServicioInventario(ref.watch(firestoreProvider), estado.usuario.uid);
});

final materialesProvider = StreamProvider<List<Material>>(
  (ref) => ref.watch(repositorioInventarioProvider).observarMateriales(),
);

final materialProvider = StreamProvider.autoDispose.family<Material?, String>(
  (ref, id) => ref.watch(repositorioInventarioProvider).observarMaterial(id),
);

final rollosProvider = StreamProvider.autoDispose.family<List<Rollo>, String>(
  (ref, materialId) =>
      ref.watch(repositorioInventarioProvider).observarRollos(materialId),
);

final movimientosProvider =
    StreamProvider.autoDispose.family<List<Movimiento>, String>(
  (ref, materialId) =>
      ref.watch(repositorioInventarioProvider).observarMovimientos(materialId),
);

final costoPromedioProvider =
    StreamProvider.autoDispose.family<double?, String>(
  (ref, materialId) =>
      ref.watch(repositorioCostosProvider).observarCostoPromedio(materialId),
);

final costoRolloProvider = StreamProvider.autoDispose.family<double?, String>(
  (ref, rolloId) =>
      ref.watch(repositorioCostosProvider).observarCostoRollo(rolloId),
);
