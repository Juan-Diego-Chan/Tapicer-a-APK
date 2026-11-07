import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dominio/usuario.dart';
import '../auth/providers.dart';
import 'servicio_alta_usuario.dart';

final usuariosProvider = StreamProvider.autoDispose<List<Usuario>>(
  (ref) => ref.watch(repositorioUsuariosProvider).observarTodos(),
);

/// Solo para el dueño.
final sueldoProvider = StreamProvider.autoDispose.family<double?, String>(
  (ref, uid) => ref.watch(repositorioPrivadoProvider).observarSueldo(uid),
);

/// Solo para el dueño.
final diasLaboralesProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(repositorioPrivadoProvider).observarDiasLaborales(),
);
