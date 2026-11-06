import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/repositorio_usuarios.dart';
import 'servicio_sesion.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final authProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final repositorioUsuariosProvider = Provider<RepositorioUsuarios>(
  (ref) => RepositorioUsuarios(ref.watch(firestoreProvider)),
);

final servicioSesionProvider = Provider<ServicioSesion>(
  (ref) => ServicioSesion(
    ref.watch(authProvider),
    ref.watch(repositorioUsuariosProvider),
  ),
);

final estadoSesionProvider = StreamProvider<EstadoSesion>(
  (ref) => ref.watch(servicioSesionProvider).estado(),
);
