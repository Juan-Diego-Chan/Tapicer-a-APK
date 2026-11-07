# Tapicería-APK

App Android de gestión para un taller de tapicería (Flutter + Firebase).

```
app/                       App Flutter
firebase/firestore.rules   Reglas de seguridad de Firestore
firebase/pruebas_reglas/   Pruebas de las reglas (Node, vitest, emulador)
```

## Requisitos

- Flutter 3.47 (Dart 3.13)
- Android SDK (con un emulador o un teléfono)
- Node.js 22
- Java 21 (los emuladores de Firebase y Gradle lo necesitan)
- Firebase CLI: `npm i -g firebase-tools`

## Pruebas

App:

```
cd app
flutter pub get
flutter test
```

Reglas de Firestore (levanta el emulador solo):

```
cd firebase/pruebas_reglas
npm ci
npm test
```

> En local, `flutter analyze` falla si la ruta del repositorio tiene caracteres
> no ASCII (como la "í" de Tapicería). Usa `dart analyze` o mueve el repositorio
> a una ruta ASCII. Por la misma razón `app/android/gradle.properties` tiene
> `android.overridePathCheck=true`.

## Correr con emuladores

Inicia los emuladores de Auth y Firestore desde la raíz:

```
firebase emulators:start --only auth,firestore --project demo-tapiceria
```

Luego corre la app apuntando a ellos (10.0.2.2:9099 para Auth y 10.0.2.2:8080
para Firestore, la dirección del anfitrión vista desde el emulador de Android):

```
cd app
flutter run --dart-define=USAR_EMULADOR=true
```

En modo emulador la app usa el proyecto `demo-tapiceria` (igual que los
emuladores), por lo que no puede tocar servicios de producción. Para crear un
dueño de prueba, con los emuladores corriendo:

```
node firebase/semilla_emulador.mjs
```

El script es idempotente y, además del dueño, crea un empleado de prueba y dos
materiales (Tela lino gris con el rollo #1, y Guata). Los correos y las
contraseñas de prueba están en ese archivo. También puedes
hacerlo a mano en la Emulator UI (http://localhost:4000, proyecto
`demo-tapiceria`): crea el usuario en Authentication y el documento
`usuarios/{uid}` en Firestore con los campos de la sección siguiente.

Notas para el emulador de Android:

- Si el emulador está en modo avión, la app no llega a los emuladores de Firebase.
- En compilaciones de depuración, `app/android/app/src/debug/` permite HTTP sin
  cifrar hacia `10.0.2.2` y desactiva la inicialización automática de Firebase
  en Android, para que la app use `demo-tapiceria` en vez de `tapiceria-app`.
- Si la ruta del repositorio tiene caracteres no ASCII (como "í"), `flutter run`
  compila e instala pero no logra abrir la app; ábrela desde el emulador.

## Crear el primer dueño

Solo la primera vez en cada proyecto, porque después el dueño da de alta a los
demás empleados desde la app.

1. En la consola de Firebase: Authentication → Agregar usuario (correo y contraseña).
2. Copia el UID del usuario creado.
3. En Firestore, crea el documento `usuarios/{UID}` con estos campos:
   - `nombre`: texto
   - `email`: texto
   - `rol`: `"dueno"`
   - `activo`: `true` (booleano)
   - `creadoEn`: timestamp

## Inventario

- Cada cambio de existencia es un movimiento (`compra`, `inicial`, `consumo` o `ajuste`) en `movimientos`; la existencia del material y del rollo se actualiza con él.
- Las telas se llevan por rollo; el resto de los materiales, por existencia total.
- La existencia puede quedar negativa: un consumo o ajuste nunca se bloquea, se registra y se muestra tal cual.
- La carga inicial de un material se registra sin costo.
- Los costos viven en `materiales_costos` y `rollos_costos`, que solo lee el dueño; el empleado no los ve.
- Un material entra a la lista de compras si su existencia está por debajo del mínimo, o si un empleado lo marca como "se está acabando".
- Registrar una compra quita esa marca; sale de la lista si la existencia ya no está por debajo del mínimo.

## Despliegue de reglas

```
firebase deploy --only firestore:rules,firestore:indexes
```

## Plan Spark

**El proyecto de Firebase (`tapiceria-app`) debe quedarse en el plan Spark
(gratuito).** No actives Blaze ni servicios que lo requieran (por ejemplo Cloud
Functions).

## Limitación conocida

Si las escrituras en Firestore fallan después de que se creó la cuenta de
Authentication de un empleado, la cuenta queda huérfana. Reintenta con otro
correo, o crea el documento `usuarios/{uid}` a mano.

## CI

`.github/workflows/ci.yml` corre en cada push a `main` o a ramas `plan-*` y en
los pull requests a `main`: análisis, pruebas de la app, pruebas de reglas y
compilación del APK de depuración (artefacto `tapiceria-debug-apk`).
