import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Con `--dart-define=USAR_EMULADOR=true` la app usa los emuladores locales.
const bool usarEmulador = bool.fromEnvironment('USAR_EMULADOR');
const String hostEmulador = '10.0.2.2';
const int puertoAuthEmulador = 9099;
const int puertoFirestoreEmulador = 8080;

/// Opciones de Firebase. En modo emulador se usa un proyecto `demo-`, que no
/// puede alcanzar servicios de producción.
FirebaseOptions opcionesFirebase() {
  final base = DefaultFirebaseOptions.currentPlatform;
  return usarEmulador ? base.copyWith(projectId: 'demo-tapiceria') : base;
}

/// Inicializa Firebase. Con `--dart-define=USAR_EMULADOR=true` conecta
/// Auth y Firestore a los emuladores locales (10.0.2.2 desde el emulador Android).
Future<void> inicializarFirebase() async {
  await Firebase.initializeApp(options: opcionesFirebase());
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  if (usarEmulador) {
    await FirebaseAuth.instance.useAuthEmulator(hostEmulador, puertoAuthEmulador);
    FirebaseFirestore.instance.useFirestoreEmulator(hostEmulador, puertoFirestoreEmulador);
  }
}
