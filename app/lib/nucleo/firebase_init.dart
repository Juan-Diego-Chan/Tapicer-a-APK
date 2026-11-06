import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

const bool _usarEmulador = bool.fromEnvironment('USAR_EMULADOR');

/// Inicializa Firebase. Con `--dart-define=USAR_EMULADOR=true` conecta
/// Auth y Firestore a los emuladores locales (10.0.2.2 desde el emulador Android).
Future<void> inicializarFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  if (_usarEmulador) {
    await FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);
  }
}
