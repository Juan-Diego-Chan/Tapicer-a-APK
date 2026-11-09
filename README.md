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
materiales (Tela lino gris con el rollo #1, y Guata), una plantilla (Sillón 3
plazas), un cliente (María López) y un pedido de ejemplo con un mueble. Los correos y las
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
- La carga inicial puede llevar un costo opcional por unidad; si se deja vacío, el costo queda desconocido y se muestra «Sin costo».
- Los movimientos no se editan ni se borran; las correcciones se hacen con un ajuste.
- Los costos viven en `materiales_costos` y `rollos_costos`, que solo lee el dueño; el empleado no los ve.
- Un material entra a la lista de compras si su existencia está por debajo del mínimo, o si un empleado lo marca como "se está acabando".
- Registrar una compra quita esa marca; sale de la lista si la existencia ya no está por debajo del mínimo.

## Pedidos

- Un pedido tiene uno o varios muebles (fabricación o reparación); el estado del pedido es el del mueble menos avanzado, sin contar los cancelados.
- Los cambios de precio y de envío quedan en un historial que solo ve el dueño.
- Las líneas de material descuentan inventario con un movimiento de consumo, salvo las que trajo el cliente.
- Los días trabajados suman mano de obra: sueldo semanal del empleado entre los días laborales.
- Solo el dueño borra líneas y días; borrar una línea regresa el material al inventario.
- Los costos del mueble (materiales y mano de obra) son solo para el dueño, y marcan "(incompleto)" si falta algún costo.
- Fabricación y Reparación listan los muebles activos por fecha estimada de entrega.
- Límites conocidos: un empleado que escriba directo contra Firestore (saltándose la app) puede bajar existencias de más o registrar un consumo sin su descuento; nunca puede subirlas ni ver costos.

## Dinero

- Los pagos de un pedido se registran en efectivo o por transferencia; el saldo es precios + envío − pagado. Se puede dar un anticipo al crear el pedido.
- Una devolución es un pago con monto negativo; solo la registra el dueño.
- Cada empleado tiene una caja con el efectivo que lleva en las manos: sube con los pagos que cobra y baja con las entregas.
- El empleado registra una entrega de dinero al dueño; queda pendiente hasta que el dueño la confirma o la rechaza. Rechazada, el dinero sigue en manos del empleado.
- Solo el dueño borra pagos; borrar un pago ajusta el pagado del pedido y la caja de quien lo cobró.
- Los pagos de sueldo a empleados son solo del dueño: se registran en Usuarios y quedan en su historial.
- Cancelar un mueble y agregar uno nuevo quedan en el historial de precios ("Mueble cancelado", "Mueble agregado").
- Límites conocidos: la fecha de un pago o entrega registrado sin conexión es la de sincronización; un pago mayor al saldo solo lo bloquea la app.

## Contabilidad

Pantalla solo para el dueño (menú "Contabilidad"), por semana, por mes (con flechas para ir a otros periodos) o por rango de fechas. Un rango puede abarcar como máximo 3 meses (93 días): si eliges más, se recorta a los primeros 93 días desde la fecha inicial y la app lo avisa. Así se cuidan las lecturas diarias del plan Spark.

- **Lo cobrado:** pagos del periodo, con el desglose por quién cobró y por forma de pago. Las devoluciones restan.
- **Por entregar (al día de hoy):** no depende del periodo; es el efectivo que cada empleado lleva en las manos. Las entregas que esperan confirmación ya están incluidas en esa cantidad (se muestran como "De eso, por confirmar"); no se suman otra vez.
- **Lo gastado:** compras de inventario y pagos de sueldo del periodo.
- **Ganancia:** por cada mueble entregado, precio menos materiales (costo promedio) menos mano de obra (sueldo semanal entre días laborales, por los días trabajados). Marca "Costo incompleto" en el mueble, en el pedido y en la ganancia total si falta algún costo.
- **Pendientes de cobro (al día de hoy):** no depende del periodo; pedidos entregados (de los últimos 180 días) o terminados con saldo mayor a cero.
- **Cómo se asigna al periodo:** los cobros y los gastos, por su propia fecha (la del pago, la compra o el sueldo); la ganancia, por la `fechaEntregado` del pedido, y solo cuentan los pedidos entregados.
- Límites conocidos: los pendientes de cobro solo revisan entregas de los últimos 180 días; la mano de obra usa el sueldo actual, no el que tenía cuando se trabajó.

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

## Publicar una versión

**Respalda la llave de firma.** Guarda `tapiceria.jks` y sus contraseñas en al
menos dos lugares seguros (por ejemplo un USB y tu gestor de contraseñas),
fuera del repositorio. Si la pierdes, los teléfonos dejan de aceptar
actualizaciones de la app y tendrás que desinstalarla y perder los datos locales.
Nunca subas la llave ni `key.properties` a git.

1. Crea la llave (una sola vez) y guárdala fuera del repositorio:

   ```
   keytool -genkey -v -keystore tapiceria.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tapiceria
   ```

2. Carga los 4 secretos en GitHub. El keystore va en base64:

   ```
   base64 -w0 tapiceria.jks | gh secret set KEYSTORE_BASE64
   gh secret set KEYSTORE_PASSWORD
   gh secret set KEY_ALIAS
   gh secret set KEY_PASSWORD
   ```

   En PowerShell, el primero se hace así:

   ```
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("tapiceria.jks")) | gh secret set KEYSTORE_BASE64
   ```

3. Para compilar en local con la llave, crea `app/android/key.properties`
   (ya está en `.gitignore`):

   ```
   storeFile=C:/ruta/segura/tapiceria.jks
   storePassword=...
   keyAlias=tapiceria
   keyPassword=...
   ```

   También sirven las variables de entorno `TAPICERIA_KEYSTORE`,
   `TAPICERIA_KEYSTORE_PASSWORD`, `TAPICERIA_KEY_ALIAS` y
   `TAPICERIA_KEY_PASSWORD`, que tienen prioridad. Sin llave, el APK de release
   se firma con la de depuración y Gradle avisa (el aviso "Sin llave de firma"
   solo se ve con `flutter build apk --release -v`).

   **Ojo:** `flutter build apk --release` falla si la ruta del repositorio tiene
   caracteres no ASCII (por ejemplo `C:\Tapicería-APK`). Compila desde una copia
   en una ruta ASCII (por ejemplo `C:\tapbuild`) o sáltate la compilación local:
   para publicar no hace falta, porque el workflow compila el APK.

4. Sube la versión en `app/pubspec.yaml` (`version:`) y publica la etiqueta:

   ```
   git tag v1.0.0 && git push origin v1.0.0
   ```

   El workflow `.github/workflows/publicar.yml` prueba, compila el APK firmado
   y lo adjunta a un Release de GitHub.

5. En el teléfono: descarga el APK del Release, permite "instalar apps
   desconocidas" e instala. La app de release usa el Firebase de producción
   (`tapiceria-app`), no los emuladores.

## CI

`.github/workflows/ci.yml` corre en cada push a `main` o a ramas `plan-*` y en
los pull requests a `main`: análisis, pruebas de la app, pruebas de reglas y
compilación del APK de depuración (artefacto `tapiceria-debug-apk`).
