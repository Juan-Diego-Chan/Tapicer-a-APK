# Plan 1: Fundamentos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una app Flutter para Android conectada a Firebase (plan Spark) donde el dueño y los empleados inician sesión, ven un menú según su rol, y el dueño da de alta/baja empleados y registra sueldos; con reglas de Firestore probadas y CI.

**Architecture:** App Flutter en `app/` con capas `dominio/` (Dart puro), `datos/` (repositorios Firestore) y `funciones/` (pantallas + providers Riverpod). Rol y estado de cada usuario en `usuarios/{uid}`; datos sensibles en colecciones 🔒 protegidas por `firebase/firestore.rules`. Las reglas se prueban contra el emulador de Firestore con Node.

**Tech Stack:** Flutter 3.47 / Dart 3.13, `firebase_core`, `firebase_auth`, `cloud_firestore`, `flutter_riverpod`, `go_router`, `intl`, `flutter_localizations`; pruebas: `flutter_test`, `fake_cloud_firestore`, `firebase_auth_mocks`; reglas: `firebase-tools` (emulador), `@firebase/rules-unit-testing`, `vitest`.

**Spec:** `docs/superpowers/specs/2026-11-04-app-tapiceria-design.md` (§4, §5, §7). **Hoja de ruta (estructura del repo y modelo de datos fijos):** `docs/superpowers/plans/2026-11-04-00-hoja-de-ruta.md`.

## Global Constraints

- Firebase **plan Spark únicamente**: nada de Cloud Functions, Cloud Storage ni nada que pida Blaze.
- Solo Android. `minSdk` = el mayor entre 23 y el que exijan los paquetes de Firebase instalados.
- Idioma de la UI: español (México), `Locale('es', 'MX')`. Moneda: MXN, formato `$1,500.00`.
- Paquete Dart `tapiceria`; applicationId Android `mx.tapiceria.gestion`; nombre visible `Tapicería`.
- Persistencia sin conexión de Firestore activada con caché ilimitada.
- Roles exactos: `'dueno'` y `'empleado'`. Un usuario con `activo == false` no lee ni escribe nada.
- Las colecciones 🔒 (`usuarios_privado`, `config`) solo las lee/escribe un dueño activo.
- Todo texto visible en español; los identificadores de código en español sin acentos.

## Review Focus

1. **Usuario autenticado sin documento `usuarios/{uid}`** (creado a mano en la consola sin su doc): la app muestra "Tu cuenta no está configurada. Pide al dueño que la active." y un botón Cerrar sesión; no se cuelga ni queda en carga infinita. → Task 5.
2. **Empleado desactivado con la app abierta o sin conexión:** en cuanto el doc refleje `activo: false`, la app lo saca a la pantalla "Tu cuenta está desactivada" y las reglas le niegan todo. → Tasks 3 y 5.
3. **Dueño crea un empleado con correo ya usado o contraseña débil:** mensaje en español ("Ese correo ya está registrado" / "La contraseña debe tener al menos 6 caracteres") y el dueño **sigue con su sesión**. → Task 6.
4. **Empleado intenta subirse a dueño o reactivarse** escribiendo directo en Firestore: las reglas lo rechazan. → Task 3.
5. **Primer inicio de sesión sin internet:** mensaje "Se necesita internet para iniciar sesión por primera vez" en vez de un error crudo. → Task 5.

---

### Task 1: Proyecto Flutter base

**Files:**
- Create: `app/` (vía `flutter create`), `app/lib/main.dart`, `app/lib/app.dart`, `app/lib/nucleo/formatos.dart`
- Modify: `app/pubspec.yaml`, `app/android/app/build.gradle.kts`, `app/analysis_options.yaml`, `.gitignore`
- Test: `app/test/nucleo/formatos_test.dart`, `app/test/app_test.dart`

**Interfaces:**
- Produces: `String formatearDinero(num monto)` → `"$1,500.00"`; `String formatearFecha(DateTime f)` → `"04/11/2026"`; widget `TapiceriaApp` (recibe `GoRouter router`).

- [ ] **Step 1:** Aceptar licencias Android: `flutter doctor --android-licenses` (el usuario responde `y`). Esperado: `flutter doctor` sin `!` en Android toolchain.
- [ ] **Step 2:** Desde la raíz del repo: `flutter create --org mx.tapiceria --project-name tapiceria --platforms android app`. Ajustar `applicationId = "mx.tapiceria.gestion"` y `android:label="Tapicería"`.
- [ ] **Step 3:** Agregar dependencias: `cd app && flutter pub add firebase_core firebase_auth cloud_firestore flutter_riverpod go_router intl flutter_localizations --sdk=flutter` (flutter_localizations aparte con `--sdk=flutter`) y `flutter pub add --dev fake_cloud_firestore firebase_auth_mocks`.
- [ ] **Step 4: Prueba que falla** `app/test/nucleo/formatos_test.dart`:

```dart
test('formatea pesos', () {
  expect(formatearDinero(1500), r'$1,500.00');
  expect(formatearDinero(0.5), r'$0.50');
  expect(formatearDinero(-200), r'-$200.00');
});
test('formatea fecha dd/MM/yyyy', () {
  expect(formatearFecha(DateTime(2026, 11, 4)), '04/11/2026');
});
```

- [ ] **Step 5:** `cd app && flutter test test/nucleo/formatos_test.dart` → FAIL (no definido).
- [ ] **Step 6:** Implementar en `nucleo/formatos.dart` con `NumberFormat.currency(locale: 'es_MX', symbol: r'$')` y `DateFormat('dd/MM/yyyy')`. Llamar `initializeDateFormatting('es_MX')` en el `setUp` de la prueba y en `main`.
- [ ] **Step 7:** `flutter test test/nucleo/formatos_test.dart` → PASS.
- [ ] **Step 8:** `app.dart`: `TapiceriaApp` con `MaterialApp.router`, `locale: Locale('es','MX')`, delegados `GlobalMaterialLocalizations` y tema Material 3 (`colorSchemeSeed: Colors.brown`). `app_test.dart` monta `TapiceriaApp` con un `GoRouter` de una ruta que muestra `Text('ok')` y verifica `find.text('ok')`. `main.dart` temporal: `runApp(ProviderScope(child: TapiceriaApp(router: ...)))`.
- [ ] **Step 9:** `flutter analyze` → "No issues found!"; `flutter test` → PASS; `flutter build apk --debug` → genera `app-debug.apk`.
- [ ] **Step 10:** Commit: `git add app .gitignore && git commit -m "feat: proyecto Flutter base"`.

---

### Task 2: Conectar Firebase y emuladores

Esta tarea tiene **pasos que hace el usuario** (inicio de sesión en Google, consola de Firebase). El implementador se detiene y le pide hacerlos con `! <comando>` o en el navegador.

**Files:**
- Create: `firebase.json`, `.firebaserc`, `firebase/firestore.rules` (todo denegado), `firebase/firestore.indexes.json` (`{"indexes":[],"fieldOverrides":[]}`), `app/lib/firebase_options.dart` (generado), `app/android/app/google-services.json` (generado)
- Modify: `app/lib/main.dart`

**Interfaces:**
- Produces: `Future<void> inicializarFirebase()` en `app/lib/nucleo/firebase_init.dart`: `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` y luego `FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED)`. Si `--dart-define=USAR_EMULADOR=true`, conecta Auth (`10.0.2.2:9099`) y Firestore (`10.0.2.2:8080`).

- [ ] **Step 1:** `npm install -g firebase-tools` y `dart pub global activate flutterfire_cli`. Esperado: `firebase --version` y `flutterfire --version` responden.
- [ ] **Step 2 (usuario):** `! firebase login`.
- [ ] **Step 3 (usuario, consola):** Crear el proyecto `tapiceria-app` (o el ID libre más cercano) **sin Google Analytics**, plan Spark. Activar Authentication → Correo/contraseña. Crear la base Firestore en modo producción, región `us-central1` (o la más cercana a México que ofrezca la consola).
- [ ] **Step 4:** `cd app && flutterfire configure --project=<id> --platforms=android`. Esperado: se crean `firebase_options.dart` y `google-services.json`.
- [ ] **Step 5:** En la raíz: `firebase.json` con `firestore.rules: "firebase/firestore.rules"`, `firestore.indexes: "firebase/firestore.indexes.json"`, emuladores `auth: 9099`, `firestore: 8080`, `ui.enabled: true`. Reglas iniciales: `allow read, write: if false;` para todo.
- [ ] **Step 6:** `main.dart` llama `inicializarFirebase()` antes de `runApp`.
- [ ] **Step 7:** `firebase emulators:start --only auth,firestore` arranca sin errores (Ctrl+C). `flutter build apk --debug` → OK.
- [ ] **Step 8:** `firebase deploy --only firestore:rules,firestore:indexes` → "Deploy complete!".
- [ ] **Step 9:** Commit: `feat: conectar Firebase y emuladores`. *(Los archivos de configuración de Firebase para Android no son secretos y se versionan.)*

---

### Task 3: Reglas base de seguridad con pruebas

**Files:**
- Create: `firebase/pruebas_reglas/package.json`, `firebase/pruebas_reglas/vitest.config.ts`, `firebase/pruebas_reglas/usuarios.test.ts`, `firebase/pruebas_reglas/ayuda.ts`
- Modify: `firebase/firestore.rules`

**Interfaces:**
- Produces (en `firestore.rules`, para que los planes 2–5 los reutilicen): `function autenticado()`, `function usuario()` (= `get(/databases/$(database)/documents/usuarios/$(request.auth.uid)).data`), `function activo()`, `function esDueno()` (activo y rol `'dueno'`), `function esEmpleado()` (activo y rol `'empleado'`), `function soloCambia(campos)` (= `request.resource.data.diff(resource.data).affectedKeys().hasOnly(campos)`).
- Produces (en `ayuda.ts`): `crearEntorno(): Promise<RulesTestEnvironment>`, `sembrarUsuario(env, uid, {rol, activo})`, `como(env, uid): Firestore`.
- Script: `npm test` dentro de `firebase/pruebas_reglas` corre `firebase emulators:exec --only firestore --project demo-tapiceria "vitest run"`.

- [ ] **Step 1: Pruebas que fallan** en `usuarios.test.ts` (cada `it` usa `assertSucceeds` / `assertFails`):
  - dueño activo lee y escribe cualquier `usuarios/{uid}` → éxito
  - empleado activo lee **su** `usuarios/{uid}` y la lista de `usuarios` (para mostrar nombres) → éxito
  - empleado actualiza su `rol` a `'dueno'` → falla
  - empleado actualiza su `activo` → falla
  - empleado inactivo lee su `usuarios/{uid}` → **éxito** (la app necesita saber que está inactivo); lee la lista de `usuarios` → falla
  - empleado lee/escribe `usuarios_privado/{suUid}` → falla; dueño → éxito
  - empleado lee `config/general` → falla; dueño → éxito
  - no autenticado lee `usuarios` → falla
  - usuario autenticado sin doc `usuarios/{uid}` lee cualquier colección salvo su propio doc → falla
  - dueño inactivo escribe `usuarios_privado/x` → falla
- [ ] **Step 2:** `cd firebase/pruebas_reglas && npm install && npm test` → las pruebas de "éxito" FALLAN (todo está denegado).
- [ ] **Step 3:** Escribir las funciones de ayuda y las reglas para `usuarios`, `usuarios_privado` y `config`. Nadie crea docs en `usuarios` salvo el dueño. Deny por defecto para todo lo demás.
- [ ] **Step 4:** `npm test` → todas PASS.
- [ ] **Step 5:** `firebase deploy --only firestore:rules`.
- [ ] **Step 6:** Commit: `feat: reglas base de roles con pruebas`.

---

### Task 4: Modelo de usuario, repositorio y sesión

**Files:**
- Create: `app/lib/dominio/usuario.dart`, `app/lib/datos/repositorio_usuarios.dart`, `app/lib/funciones/auth/servicio_sesion.dart`, `app/lib/funciones/auth/providers.dart`
- Test: `app/test/dominio/usuario_test.dart`, `app/test/datos/repositorio_usuarios_test.dart`, `app/test/funciones/auth/servicio_sesion_test.dart`

**Interfaces:**
- Produces:
  - `enum Rol { dueno, empleado }`; `class Usuario { String uid; String nombre; String email; Rol rol; bool activo; }` con `factory Usuario.desdeMapa(String uid, Map<String, dynamic>)` y `Map<String, dynamic> aMapa()`.
  - `sealed class EstadoSesion`: `SinSesion`, `CargandoSesion`, `CuentaSinConfigurar`, `CuentaDesactivada`, `SesionActiva(Usuario usuario)`.
  - `class RepositorioUsuarios(FirebaseFirestore db)`: `Stream<Usuario?> observar(String uid)`, `Stream<List<Usuario>> observarTodos()`, `Future<void> guardar(Usuario u)`, `Future<void> fijarActivo(String uid, bool activo)`.
  - `class ServicioSesion(FirebaseAuth auth, RepositorioUsuarios repo)`: `Stream<EstadoSesion> estado()`, `Future<void> iniciarSesion(String email, String contrasena)` (lanza `ErrorSesion(String mensaje)` con el texto en español), `Future<void> cerrarSesion()`.
  - Providers: `firestoreProvider`, `authProvider`, `repositorioUsuariosProvider`, `servicioSesionProvider`, `estadoSesionProvider` (StreamProvider<EstadoSesion>).

- [ ] **Step 1: Pruebas que fallan:**
  - `usuario_test`: `Usuario.desdeMapa('u1', {'nombre':'Ana','email':'a@x.mx','rol':'empleado','activo':true}).rol == Rol.empleado`; un `rol` desconocido lanza `FormatException`; `aMapa()` ida y vuelta conserva todos los campos.
  - `repositorio_usuarios_test` (con `FakeFirebaseFirestore`): `guardar` y luego `observar('u1')` emite el usuario; `observar('nadie')` emite `null`; `fijarActivo('u1', false)` hace que `observar` emita `activo == false`.
  - `servicio_sesion_test` (con `MockFirebaseAuth` + `FakeFirebaseFirestore`): sin sesión → `SinSesion`; con sesión y doc activo → `SesionActiva` con su rol; con sesión sin doc → `CuentaSinConfigurar`; con doc `activo:false` → `CuentaDesactivada`; si el doc cambia a `activo:false` mientras escucha, el stream emite `CuentaDesactivada`.
  - Traducción de errores (función pura `String mensajeErrorAuth(String codigo)` en `servicio_sesion.dart`, junto con `class ErrorSesion implements Exception { final String mensaje; }`): `'invalid-credential'` y `'wrong-password'` → `'Correo o contraseña incorrectos'`; `'network-request-failed'` → `'Se necesita internet para iniciar sesión por primera vez'`; `'too-many-requests'` → `'Demasiados intentos. Espera unos minutos.'`; `'email-already-in-use'` → `'Ese correo ya está registrado'`; `'weak-password'` → `'La contraseña debe tener al menos 6 caracteres'`; otro → `'Ocurrió un error. Intenta de nuevo.'`.
- [ ] **Step 2:** `flutter test test/dominio test/datos test/funciones/auth` → FAIL.
- [ ] **Step 3:** Implementar. `estado()` = `auth.authStateChanges()` combinado (`asyncExpand`) con `repo.observar(uid)`.
- [ ] **Step 4:** Mismo comando → PASS.
- [ ] **Step 5:** Commit: `feat: sesión y modelo de usuario`.

---

### Task 5: Inicio de sesión, router con guardias y menú por rol

**Files:**
- Create: `app/lib/nucleo/router.dart`, `app/lib/funciones/auth/pantalla_inicio_sesion.dart`, `app/lib/funciones/auth/pantalla_estado_cuenta.dart`, `app/lib/funciones/inicio/pantalla_inicio.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/nucleo/router_test.dart`, `app/test/funciones/auth/pantalla_inicio_sesion_test.dart`, `app/test/funciones/auth/pantalla_estado_cuenta_test.dart`, `app/test/funciones/inicio/pantalla_inicio_test.dart`

**Interfaces:**
- Consumes: `estadoSesionProvider`, `servicioSesionProvider`, `EstadoSesion` (Task 4).
- Produces: `GoRouter crearRouter(Ref ref)` (`routerProvider`). Rutas: `/entrar`, `/cuenta` (sin configurar / desactivada), `/` (inicio), y para el plan 1 `/usuarios` (solo dueño). Los planes siguientes agregan rutas aquí. La función pura `String? redirigir(EstadoSesion estado, String ruta)` contiene toda la lógica de guardia.
- Produces: `class EntradaMenu { String titulo; IconData icono; String ruta; bool soloDueno; }` y `const List<EntradaMenu> entradasMenu` en `pantalla_inicio.dart`. Plan 1 incluye: Pedidos (`/pedidos`), Fabricación (`/fabricacion`), Reparación (`/reparacion`), Inventario (`/inventario`), Lista de compras (`/compras`, solo dueño), Dinero (`/dinero`), Contabilidad (`/contabilidad`, solo dueño), Usuarios (`/usuarios`, solo dueño). Las entradas sin pantalla muestran "Próximamente".

- [ ] **Step 1: Pruebas que fallan:**
  - `router_test` sobre `redirigir`: `SinSesion` en `/` → `/entrar`; `CargandoSesion` → `null` (muestra cargando); `CuentaSinConfigurar` o `CuentaDesactivada` en cualquier ruta → `/cuenta`; `SesionActiva(empleado)` en `/usuarios` → `/`; `SesionActiva(dueño)` en `/usuarios` → `null`; `SesionActiva` en `/entrar` → `/`.
  - `pantalla_inicio_sesion_test`: con correo vacío, al tocar "Entrar" muestra `'Escribe tu correo'`; si `iniciarSesion` lanza `ErrorSesion('Se necesita internet para iniciar sesión por primera vez')`, ese texto aparece en pantalla; el botón se deshabilita mientras espera.
  - `pantalla_estado_cuenta_test`: con `CuentaSinConfigurar` muestra `'Tu cuenta no está configurada. Pide al dueño que la active.'`; con `CuentaDesactivada` muestra `'Tu cuenta está desactivada'`; ambas tienen el botón `'Cerrar sesión'`.
  - `pantalla_inicio_test`: un empleado **no** ve "Contabilidad", "Lista de compras" ni "Usuarios"; el dueño sí ve las 8 entradas; el encabezado muestra el nombre del usuario.
- [ ] **Step 2:** `flutter test test/nucleo test/funciones` → FAIL.
- [ ] **Step 3:** Implementar. `redirect` del GoRouter delega en `redirigir`; `refreshListenable` escucha `estadoSesionProvider`.
- [ ] **Step 4:** Mismo comando → PASS.
- [ ] **Step 5:** Prueba manual con emulador: `firebase emulators:start --only auth,firestore`; crear en la UI del emulador un usuario y su doc `usuarios/{uid}` con `rol:'dueno', activo:true`; `flutter run --dart-define=USAR_EMULADOR=true` en un emulador Android. Esperado: entra y ve las 8 entradas; al cambiar `activo` a `false` en la UI del emulador, la app pasa a "Tu cuenta está desactivada".
- [ ] **Step 6:** Commit: `feat: inicio de sesión, guardias y menú por rol`.

---

### Task 6: Gestión de usuarios y sueldos (dueño)

**Files:**
- Create: `app/lib/datos/repositorio_privado.dart`, `app/lib/funciones/usuarios/servicio_alta_usuario.dart`, `app/lib/funciones/usuarios/pantalla_usuarios.dart`, `app/lib/funciones/usuarios/dialogo_alta_empleado.dart`
- Modify: `app/lib/nucleo/router.dart`
- Test: `app/test/datos/repositorio_privado_test.dart`, `app/test/funciones/usuarios/servicio_alta_usuario_test.dart`, `app/test/funciones/usuarios/pantalla_usuarios_test.dart`

**Interfaces:**
- Consumes: `RepositorioUsuarios`, `Usuario`, `mensajeErrorAuth`, `ErrorSesion` (Task 4).
- Produces:
  - `class RepositorioPrivado(FirebaseFirestore db)`: `Stream<double?> observarSueldo(String uid)`, `Future<void> fijarSueldo(String uid, double sueldoSemanal)`, `Stream<int> observarDiasLaborales()` (por defecto `6` si el doc no existe), `Future<void> fijarDiasLaborales(int dias)`.
  - `abstract class CreadorCuentas { Future<String> crear(String email, String contrasena); }` (devuelve uid). Implementación real `CreadorCuentasFirebase`: `Firebase.initializeApp(name: 'alta', options: DefaultFirebaseOptions.currentPlatform)`, `FirebaseAuth.instanceFor(app: secundaria).createUserWithEmailAndPassword`, luego `signOut` en la secundaria y `delete()` de la app secundaria (en `finally`). La sesión del dueño nunca se toca.
  - `class ServicioAltaUsuario(CreadorCuentas creador, RepositorioUsuarios usuarios, RepositorioPrivado privado)`: `Future<void> altaEmpleado({required String nombre, required String email, required String contrasena, required double sueldoSemanal})` crea la cuenta, guarda `usuarios/{uid}` (`rol: empleado`, `activo: true`) y el sueldo. Traduce los `FirebaseAuthException` a `ErrorSesion(mensajeErrorAuth(code))`.

- [ ] **Step 1: Pruebas que fallan:**
  - `repositorio_privado_test`: sin doc, `observarDiasLaborales()` emite `6`; `fijarDiasLaborales(5)` → emite `5`; `fijarSueldo('u1', 2100)` → `observarSueldo('u1')` emite `2100`.
  - `servicio_alta_usuario_test` (con un `CreadorCuentas` falso): el alta guarda `usuarios/{uid}` con `rol: 'empleado'`, `activo: true` y `usuarios_privado/{uid}.sueldoSemanal == 2100`; si el creador lanza `FirebaseAuthException(code: 'email-already-in-use')`, el servicio lanza `ErrorSesion('Ese correo ya está registrado')` y **no** escribe nada en Firestore; un sueldo `<= 0` lanza `ArgumentError` sin llamar al creador.
  - `pantalla_usuarios_test`: lista a cada usuario con su rol y un interruptor "Activo"; el dueño no tiene interruptor sobre sí mismo (no puede desactivarse); muestra el sueldo semanal formateado (`$2,100.00`) por empleado; hay un campo "Días laborales por semana" que acepta solo valores del 1 al 7.
- [ ] **Step 2:** `flutter test test/datos test/funciones/usuarios` → FAIL.
- [ ] **Step 3:** Implementar. Diálogo de alta: nombre, correo, contraseña (mín. 6), sueldo semanal. Desactivar pide confirmación: "¿Desactivar a {nombre}? Ya no podrá entrar a la app."
- [ ] **Step 4:** Mismo comando → PASS.
- [ ] **Step 5:** Prueba manual con emuladores: el dueño crea un empleado y **sigue en su sesión**; con el empleado en otro emulador o dispositivo, el empleado no ve Usuarios; al desactivarlo, el otro dispositivo pasa a "Tu cuenta está desactivada".
- [ ] **Step 6:** Commit: `feat: alta y baja de empleados y sueldos`.

---

### Task 7: CI y guía de arranque

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `README.md`

- [ ] **Step 1:** `ci.yml`, que corre en push y PR a `main` con dos jobs:
  - `app`: `subosito/flutter-action` (canal stable, versión `3.47.x`) → `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, y sube el APK como artefacto `tapiceria-debug-apk`.
  - `reglas`: Node 22 + Java 21 → `npm i -g firebase-tools` → `cd firebase/pruebas_reglas && npm ci && npm test`.
- [ ] **Step 2:** README en español con estos puntos: requisitos (Flutter, Android SDK, Node, Java, Firebase CLI); cómo correr las pruebas de la app y las de reglas; cómo correr con emuladores (`--dart-define=USAR_EMULADOR=true`); **crear el primer dueño**: en la consola, Authentication → Agregar usuario, copiar el UID, y en Firestore crear `usuarios/{UID}` con `nombre`, `email`, `rol: "dueno"`, `activo: true`, `creadoEn` (timestamp); recordatorio de que **el proyecto debe quedarse en plan Spark**.
- [ ] **Step 3:** Push a una rama `plan-1-fundamentos`. En GitHub Actions, ambos jobs quedan en verde y el artefacto APK es descargable.
- [ ] **Step 4:** Commit: `ci: análisis, pruebas, reglas y APK de depuración`.

---

## Al terminar el Plan 1

- Crear el primer dueño real en el proyecto de producción con los pasos del README, instalar el APK de depuración en un teléfono y verificar el inicio de sesión.
- Escribir el **Plan 2: Inventario** a partir de la hoja de ruta.
