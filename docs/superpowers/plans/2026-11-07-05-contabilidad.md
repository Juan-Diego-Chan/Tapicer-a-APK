# Plan 5: Contabilidad y entrega — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El dueño elige una semana, un mes o un rango de fechas y ve en una pantalla:
- lo cobrado, desglosado por pedido, por forma de pago y por quién lo recibió;
- el dinero pendiente de entregar;
- lo gastado en material y sueldos;
- la ganancia real de cada mueble y pedido entregado, empezando por los de menor margen;
- los cambios de precio del periodo;
- los pedidos pendientes de cobro;
- las diferencias de material.

Además, el proyecto publica un **APK firmado** desde GitHub Actions.

**Architecture:**
- Cálculos puros en `dominio/contabilidad.dart`.
- Las lecturas son de **una sola vez**, con `get()`, en `datos/repositorio_contabilidad.dart`, y siempre van acotadas por fecha.
- `funciones/contabilidad/armar_resumen.dart` junta lecturas y cálculos en un `ResumenPeriodo`. La pantalla lo pide con un `FutureProvider.family` por periodo y se recalcula al cambiar de periodo o al tocar "Actualizar".
- Para el historial de precios del periodo se agrega una consulta de grupo sobre `cambios_precio`, con su regla y su índice.
- La firma del APK se lee de `key.properties` o de variables de entorno. Un workflow nuevo publica el APK en GitHub Releases cuando se sube una etiqueta `v*`.

**Tech Stack:** igual que el Plan 4. No se agregan dependencias de Dart. En GitHub Actions se agrega `softprops/action-gh-release@v2`.

**Spec:** `docs/superpowers/specs/2026-11-04-app-tapiceria-design.md`. Secciones que aplica: §4 (distribución), §6.6, §6.8 y §9. **Hoja de ruta:** `docs/superpowers/plans/2026-11-04-00-hoja-de-ruta.md`.

## Global Constraints

### Firebase y acceso
- **Plan Spark únicamente.** Todas las consultas están **acotadas por fecha**, para no rebasar las cuotas diarias de lectura (§4).
- **Solo el dueño.** La pantalla, el repositorio y los providers de contabilidad son del dueño. `/contabilidad` ya es `soloDueno` en el menú. El empleado no puede leer `cambios_precio`, ni directamente ni por consulta de grupo.

### Asignación al periodo (§6.8)
- Lo cobrado y lo gastado se asignan por la **fecha en que ocurrieron**: la del pago, la de la compra o la del pago de sueldo.
- La ganancia de un pedido se asigna al periodo de su `fechaEntregado`, y **solo cuenta si el pedido está `entregado`**. Un pedido cancelado aparece en lo cobrado (su anticipo retenido), pero no en la ganancia.

### Periodos
- **Semana:** de lunes 00:00 al lunes siguiente 00:00, hora local.
- **Mes:** del día 1 a las 00:00 al día 1 del mes siguiente.
- **Rango:** del día inicial a las 00:00 al día siguiente del día final.
- En los tres casos el límite `hasta` es **exclusivo**.

### Lo cobrado
- Es la Σ de `pagos.monto` del periodo. Las devoluciones son negativas y restan.
- Se desglosa:
  - por forma de pago (Efectivo, Transferencia);
  - por quién lo recibió (nombre del usuario, o "Usuario desconocido");
  - por pedido (folio).

### Por entregar
- `enMano` de cada caja con monto ≠ 0, más el total de entregas pendientes. Se reutilizan `cajasProvider` y `entregasPendientesProvider`. No depende del periodo: es el estado actual.

### Lo gastado
- **Compras de material:** Σ `precioTotal` de `compras` con `tipo == 'compra'` en el periodo. La carga inicial (`tipo == 'inicial'`) **no** es un gasto, porque es material que ya se tenía.
- **Sueldos:** Σ `pagos_sueldo.monto` del periodo.

### Ganancia
- **Ganancia de un mueble no cancelado** = precio − materiales − mano de obra. Se calcula con `costoLineas` y `costoManoObra` de `dominio/costos_pedido.dart`:
  - costo por día = sueldo semanal ÷ `diasLaborales`;
  - el dueño cuesta 0.
- **Ganancia de un pedido** = `totalPedido` (muebles no cancelados + envío) − Σ costos de **todos** sus muebles. Se incluyen los cancelados, porque el material y los días ya se gastaron.
- **Costo desconocido:**
  - un rollo sin precio, un material sin costo o un empleado sin sueldo marcan el resultado como **"Costo incompleto"**;
  - nunca se presenta como si el costo fuera 0 sin esa marca.
- **Margen** = ganancia ÷ precio. Los muebles se ordenan por margen ascendente, separados en Fabricación y Reparación. Un mueble con precio 0 va primero.

### Pendientes y diferencias
- **Pendientes de cobro:** pedidos `terminado` (todos), más pedidos `entregado` con `fechaEntregado` en los **últimos 180 días**, cuyo saldo (`totalPedido − pagado`) sea mayor a 0.005.
- **Diferencias de material:** en los pedidos entregados del periodo, cada material de un mueble con plantilla donde `usado > estimado × 1.10`. Esto incluye los materiales que la plantilla no tenía (estimado 0, usado > 0).

### Formato
- Dinero con `formatearDinero`; fechas con `formatearFecha`.
- Margen con un decimal: "86.8%".
- Textos en español (México).

### APK firmado
- La llave **nunca** entra al repositorio (`key.properties`, `*.jks` y `*.keystore` ya están en `app/android/.gitignore`).
- Si no hay llave, la compilación local de release usa la firma de depuración y Gradle muestra un aviso.
- El workflow de publicación **falla** si faltan los secretos, para nunca publicar un APK firmado con la llave de depuración.

## Review Focus

1. **Semana que cruza mes y año.**
   - Un pago del domingo 03/01/2027 a las 23:59 cae en la semana del 28/12/2026. Uno del lunes 04/01/2027 a las 00:00 cae en la siguiente.
   - La etiqueta es "Semana del 28/12/2026 al 03/01/2027".
   - → Tarea 1.
2. **Costo desconocido.** Un mueble con tela de un rollo sin precio muestra "Costo incompleto" y no una ganancia limpia. Un empleado sin sueldo hace lo mismo con la mano de obra. → Tareas 2 y 6.
3. **Devoluciones y cancelaciones.**
   - Una devolución de −$200 resta de lo cobrado y del total del dueño.
   - Un pedido cancelado con anticipo aparece en lo cobrado, pero no en la ganancia.
   - Un pedido entregado con un mueble cancelado resta los costos de ese mueble.
   - → Tareas 1, 2 y 5.
4. **Periodo vacío.** Una semana sin movimientos muestra el texto vacío de cada sección y $0.00, sin errores ni indicador de carga infinito. → Tarea 6.
5. **Empleado curioso.** Una consulta de grupo a `cambios_precio` como empleado falla. Como dueño funciona. → Tarea 3.

---

### Task 1: Periodos y resúmenes de dinero

**Files:**
- Create: `app/lib/dominio/contabilidad.dart`
- Test: `app/test/dominio/contabilidad_test.dart`

**Interfaces:**
- Consumes: `Pago`, `FormaPago` y `PagoSueldo` (`dominio/dinero.dart`); `redondear2` (`dominio/inventario.dart`); `leerTexto`, `leerNumero` y `leerTextoOpcional` (`dominio/lectura.dart`).
- Produces:
  - `enum TipoPeriodo { semana, mes, rango }`.
  - `class Periodo { final TipoPeriodo tipo; final DateTime desde; final DateTime hasta; }`. Debe implementar `==` y `hashCode`, porque se usa como llave de un provider family. Además:
    - `factory Periodo.semana(DateTime dia)`, `factory Periodo.mes(DateTime dia)` y `factory Periodo.rango(DateTime inicio, DateTime fin)`. Para el rango, `hasta` es el día siguiente a `fin`, y si `fin` es anterior a `inicio` los intercambia.
    - `Periodo anterior()` y `Periodo siguiente()`, solo para semana y mes; en un rango lanzan `StateError`.
    - `bool contiene(DateTime f)`, que cumple `desde <= f < hasta`.
    - `String get etiqueta`:
      - semana: "Semana del dd/MM/yyyy al dd/MM/yyyy", con el domingo como último día;
      - mes: "Noviembre 2026", con el mes en español y mayúscula inicial, tomado de una lista fija (sin `intl` con locale);
      - rango: "Del dd/MM/yyyy al dd/MM/yyyy".
  - `class Compra { String id; String materialId; double? precioTotal; DateTime fecha; String tipo; }`, con `desdeMapa(id, m, aFecha)`. `precioTotal` puede ser null.
  - `class ResumenCobros { double total; Map<FormaPago, double> porForma; Map<String, double> porUsuario; Map<String, double> porPedido; }` y `ResumenCobros resumirCobros(Iterable<Pago> pagos)`. Todos los montos van redondeados con `redondear2`.
  - `class ResumenGastos { double compras; double sueldos; double get total; }` y `ResumenGastos resumirGastos({required Iterable<Compra> compras, required Iterable<PagoSueldo> sueldos})`. Solo cuenta `tipo == 'compra'` con `precioTotal != null`.

- [ ] **Step 1: Pruebas que fallan**

```dart
test('semana que cruza el año', () {
  final s = Periodo.semana(DateTime(2027, 1, 3, 23, 59));
  expect(s.desde, DateTime(2026, 12, 28));
  expect(s.hasta, DateTime(2027, 1, 4));
  expect(s.contiene(DateTime(2027, 1, 3, 23, 59)), isTrue);
  expect(s.contiene(DateTime(2027, 1, 4)), isFalse);
  expect(s.etiqueta, 'Semana del 28/12/2026 al 03/01/2027');
  expect(s.siguiente().desde, DateTime(2027, 1, 4));
});
test('mes y rango', () {
  final m = Periodo.mes(DateTime(2026, 11, 7));
  expect(m.desde, DateTime(2026, 11, 1));
  expect(m.hasta, DateTime(2026, 12, 1));
  expect(m.etiqueta, 'Noviembre 2026');
  expect(m.anterior().etiqueta, 'Octubre 2026');
  final r = Periodo.rango(DateTime(2026, 11, 10), DateTime(2026, 11, 3));
  expect(r.desde, DateTime(2026, 11, 3));
  expect(r.hasta, DateTime(2026, 11, 11));
  expect(r.etiqueta, 'Del 03/11/2026 al 10/11/2026');
  expect(() => r.anterior(), throwsStateError);
  expect(Periodo.semana(DateTime(2026, 11, 7)), Periodo.semana(DateTime(2026, 11, 5)));
});
test('resumen de cobros con devolución', () {
  final r = resumirCobros([
    _pago('p1', 'pedA', 500, FormaPago.efectivo, 'emp1'),
    _pago('p2', 'pedA', 300, FormaPago.transferencia, 'due1'),
    _pago('p3', 'pedB', -200, FormaPago.efectivo, 'due1'),
  ]);
  expect(r.total, 600);
  expect(r.porForma[FormaPago.efectivo], 300);
  expect(r.porUsuario['due1'], 100);
  expect(r.porPedido['pedB'], -200);
});
test('gastos ignoran la carga inicial', () {
  final g = resumirGastos(
    compras: [_compra(1500, 'compra'), _compra(9000, 'inicial'), _compra(null, 'inicial')],
    sueldos: [_sueldo(1800)],
  );
  expect(g.compras, 1500);
  expect(g.total, 3300);
});
```

`_pago`, `_compra` y `_sueldo` son auxiliares del archivo de pruebas.

- [ ] **Step 2:** `cd app && flutter test test/dominio/contabilidad_test.dart`. Esperado: FALLA (no existe `contabilidad.dart`).
- [ ] **Step 3:** Implementa las interfaces.
- [ ] **Step 4:** `flutter test test/dominio` y `dart analyze`. Esperado: todo pasa, sin issues.
- [ ] **Step 5:** Commit `feat: periodos y resúmenes de cobros y gastos`.

---

### Task 2: Ganancias y diferencias de material

**Files:**
- Modify: `app/lib/dominio/contabilidad.dart`
- Test: `app/test/dominio/contabilidad_test.dart`

**Interfaces:**
- Consumes: `Costo`, `costoLineas`, `costoManoObra`, `estimadoVsUsado`, `usadoPorMaterial` y `Comparacion` (`dominio/costos_pedido.dart`); `Pedido`, `Mueble`, `LineaMaterial`, `DiaTrabajado`, `Plantilla`, `TipoTrabajo`, `EstadoMueble` y `totalPedido` (`dominio/pedidos.dart`).
- Produces:
  - `class CostosConocidos { double? Function(String materialId) costoMaterial; double? Function(String rolloId) costoRollo; double? Function(String usuarioId) costoDiaDe; }`.
  - `class GananciaMueble { Pedido pedido; Mueble mueble; Costo materiales; Costo manoObra; double get ganancia; double? get margen; bool get incompleto; }`:
    - `ganancia` = `redondear2(precio − materiales.monto − manoObra.monto)`;
    - `margen` = ganancia ÷ precio, o null si el precio es 0;
    - `incompleto` = materiales o mano de obra incompletos.
  - `class GananciaPedido { Pedido pedido; double total; List<GananciaMueble> muebles; Costo costos; double get ganancia; bool get incompleto; }`:
    - `muebles` incluye solo los no cancelados;
    - `costos` suma los de **todos** los muebles, cancelados incluidos;
    - `ganancia` = `redondear2(total − costos.monto)`.
  - `GananciaPedido gananciaPedido({required Pedido pedido, required List<Mueble> muebles, required List<LineaMaterial> Function(String muebleId) lineasDe, required List<DiaTrabajado> Function(String muebleId) diasDe, required CostosConocidos costos})`.
  - `Map<TipoTrabajo, List<GananciaMueble>> porMenorMargen(Iterable<GananciaMueble> muebles)`. Ordena por margen ascendente; los de margen null van primero; si dos empatan, gana la menor ganancia. Siempre trae las dos llaves de `TipoTrabajo`, aunque estén vacías.
  - `class DiferenciaMaterial { Pedido pedido; Mueble mueble; Comparacion comparacion; }`.
  - `List<DiferenciaMaterial> diferenciasMaterial({required Pedido pedido, required List<Mueble> muebles, required List<LineaMaterial> Function(String muebleId) lineasDe, required Plantilla? Function(String? plantillaId) plantillaDe})`. Solo revisa muebles no cancelados con plantilla, y conserva las comparaciones con `usado > estimado * 1.10 + 1e-9`.
  - `double saldoPendiente(Pedido pedido, List<Mueble> muebles)`. Calcula `saldoPedido(totalPedido(precios no cancelados, envío), pedido.pagado)`.

- [ ] **Step 1: Pruebas que fallan**, en el mismo archivo:
  - **Sillón de $6,500:**
    - tela 2.5 m de un rollo a $110/m y guata 1 kg a $60/kg dan materiales $335.00;
    - 1.5 días de un empleado con sueldo $2,100 y 6 días laborales dan mano de obra $525.00;
    - ganancia $5,640.00 y margen ≈ 0.8677.
  - **Rollo sin precio:** el mueble queda incompleto y la ganancia solo descuenta los costos conocidos.
  - **Pedido con un mueble cancelado:** muebles de $1,000 y $600 (este cancelado, con $100 de material) y envío $200. Total $1,200; los costos incluyen los $100; la lista `muebles` trae solo 1 mueble.
  - **`porMenorMargen`:** con precios y márgenes conocidos, el de precio 0 va primero, siguen los demás en orden ascendente y las dos llaves de `TipoTrabajo` están presentes.
  - **Diferencias (plantilla tela 6 y guata 1):**
    - tela usada 6.5 → no hay diferencia, porque 6.5 ≤ 6.6;
    - tela usada 6.7 → sí hay;
    - 0.5 de espuma, que no está en la plantilla → sí hay;
    - un mueble sin plantilla → sin diferencias.
  - **`saldoPendiente`:** con `pagado` 1,500 sobre un total de $6,800, da 5,300.
- [ ] **Step 2:** `flutter test test/dominio/contabilidad_test.dart`. Esperado: FALLAN las nuevas.
- [ ] **Step 3:** Implementa las interfaces.
- [ ] **Step 4:** `flutter test test/dominio` y `dart analyze`. Esperado: todo pasa.
- [ ] **Step 5:** Commit `feat: ganancias por mueble y pedido, y diferencias de material`.

---

### Task 3: Reglas e índices de contabilidad

**Files:**
- Modify: `firebase/firestore.rules`. Agrega, junto a la consulta de grupo de muebles:

```
// Cambios de precio del periodo (contabilidad, solo dueño).
match /{ruta=**}/cambios_precio/{c} {
  allow read: if esDueno();
}
```

- Modify: `firebase/firestore.indexes.json`:
  - un índice compuesto `pedidos (estado ASC, fechaEntregado ASC)`;
  - en `fieldOverrides`, el campo `fecha` de `cambios_precio` con índices de alcance `COLLECTION` (ASC y DESC) y `COLLECTION_GROUP` (ASC).
- Test: `firebase/pruebas_reglas/contabilidad.test.ts`, nuevo.

**Interfaces:**
- Produces:
  - **Consulta de cambios de precio:** `collectionGroup('cambios_precio')` con `where('fecha', '>=', desde)` y `where('fecha', '<', hasta)`, solo para el dueño.
  - **Consulta de pedidos entregados:** `pedidos` con `where('estado', '==', 'entregado')` y `where('fechaEntregado', '>=', t)`.

- [ ] **Step 1: Pruebas que fallan** en `contabilidad.test.ts`. Siembra dos `cambios_precio` en dos pedidos distintos.
  - Como dueño, la consulta de grupo por rango de fecha → éxito, y regresa 2 documentos.
  - La misma consulta como empleado → falla.
  - Como empleado, un `get` directo de un `cambios_precio` → falla (ya fallaba; la prueba lo confirma).
  - Como dueño, la consulta de pedidos `estado == 'entregado'` con `fechaEntregado >= t` → éxito.
- [ ] **Step 2:** `cd firebase/pruebas_reglas && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npx vitest run contabilidad`. Esperado: FALLA la consulta de grupo del dueño.
- [ ] **Step 3:** Implementa la regla y los índices.
- [ ] **Step 4:** Corre la suite completa de reglas. Esperado: todo pasa.
- [ ] **Step 5:** Commit `feat: reglas e índices para la contabilidad`.

---

### Task 4: Repositorio de contabilidad

**Files:**
- Create: `app/lib/datos/repositorio_contabilidad.dart`
- Test: `app/test/datos/repositorio_contabilidad_test.dart`

**Interfaces:**
- Consumes:
  - los modelos de las Tareas 1 y 2, y de `dominio/pedidos.dart` y `dominio/dinero.dart`;
  - las consultas de la Tarea 3.
- Produces: `RepositorioContabilidad(FirebaseFirestore db)`. Todos sus métodos devuelven `Future` (lecturas con `get()`) y omiten los documentos mal formados.
  - **Por periodo:**
    - `Future<List<Pago>> pagosEn(Periodo p)` (`fecha >= desde && < hasta`);
    - `Future<List<Compra>> comprasEn(Periodo p)`;
    - `Future<List<PagoSueldo>> sueldosEn(Periodo p)`;
    - `Future<List<Pedido>> entregadosEn(Periodo p)` (`estado == 'entregado'` y `fechaEntregado` en el periodo);
    - `Future<List<({String pedidoId, CambioPrecio cambio})>> cambiosEn(Periodo p)`: la consulta de grupo; `pedidoId` sale de `doc.reference.parent.parent!.id`.
  - **Pedidos:**
    - `Future<List<Pedido>> candidatosPendientes(DateTime ahora)`: todos los `terminado`, más los `entregado` con `fechaEntregado >= ahora − 180 días`;
    - `Future<Map<String, Pedido>> pedidosPorId(Iterable<String> ids)`: un `get` por id distinto; ignora los que no existen.
  - **Detalle de un pedido:**
    - `Future<List<Mueble>> mueblesDe(String pedidoId)`;
    - `Future<List<LineaMaterial>> lineasDe(String pedidoId, String muebleId)`;
    - `Future<List<DiaTrabajado>> diasDe(String pedidoId, String muebleId)`.
  - **Costos:** `Future<CostosConocidos> costos()`.
    - Lee completas `materiales_costos`, `rollos_costos`, `usuarios`, `usuarios_privado` y `config/general`.
    - `costoMaterial` usa `costoPromedio`.
    - `costoDiaDe` vale 0 para un usuario con rol dueño; para los demás usa `costoPorDia`, con `diasLaborales` 6 si falta.

- [ ] **Step 1: Pruebas que fallan** (`FakeFirebaseFirestore`):
  - **Pagos:** `pagosEn(semana)` trae los pagos de la semana. Excluye uno de 1 ms antes de `desde` y otro justo en `hasta`.
  - **Compras:** `comprasEn` incluye una compra `inicial`; el filtrado es trabajo del dominio.
  - **Entregados:** `entregadosEn` excluye un pedido `cancelado` aunque su `fechaEntregado` caiga en el periodo.
  - **Cambios de precio:** `cambiosEn` regresa el `pedidoId` correcto para registros de dos pedidos.
  - **Candidatos:** `candidatosPendientes` incluye un `terminado` de hace un año y un `entregado` de hace 10 días, pero no un `entregado` de hace 200 días.
  - **Costos:**
    - `costos().costoMaterial('guata')` es 60 con la semilla `{cantidadComprada: 2, costoTotalComprado: 120}`;
    - `costoDiaDe` del dueño es 0;
    - un empleado sin sueldo da null.
  - **Datos mal formados:** un pago con `monto: 'x'` se omite.
- [ ] **Step 2:** `flutter test test/datos/repositorio_contabilidad_test.dart`. Esperado: FALLA.
- [ ] **Step 3:** Implementa.
- [ ] **Step 4:** `flutter test` y `dart analyze`. Esperado: todo pasa.
- [ ] **Step 5:** Commit `feat: repositorio de contabilidad`.

---

### Task 5: Armar el resumen del periodo

**Files:**
- Create: `app/lib/funciones/contabilidad/armar_resumen.dart` y `app/lib/funciones/contabilidad/providers.dart`
- Test: `app/test/funciones/contabilidad/armar_resumen_test.dart`

**Interfaces:**
- Consumes: las Tareas 1, 2 y 4, y `plantillasProvider` o `RepositorioPlantillas` (Plan 3) para las plantillas.
- Produces:
  - `class ResumenPeriodo`, con:
    - `Periodo periodo`, `ResumenCobros cobros`, `Map<String, Pedido> pedidosDeCobros` y `ResumenGastos gastos`;
    - `List<GananciaPedido> ganancias`, ordenada por ganancia ascendente, y `double get gananciaTotal`;
    - `Map<TipoTrabajo, List<GananciaMueble>> muebles` (de `porMenorMargen`);
    - `List<({String pedidoId, CambioPrecio cambio})> cambios`, ordenada por fecha;
    - `List<({Pedido pedido, double saldo})> pendientes`, ordenada por saldo descendente;
    - `List<DiferenciaMaterial> diferencias`.
  - `Future<ResumenPeriodo> armarResumen(RepositorioContabilidad repo, {required Periodo periodo, required List<Plantilla> plantillas, DateTime? ahora})`:
    - los muebles de cada pedido se leen **una sola vez**, aunque el pedido aparezca en ganancias y en pendientes;
    - las lecturas independientes van en paralelo con `Future.wait`.
  - Providers:
    - `repositorioContabilidadProvider`;
    - `resumenProvider = FutureProvider.autoDispose.family<ResumenPeriodo, Periodo>`;
    - `periodoProvider = NotifierProvider<…, Periodo>`, que empieza en la semana actual.

- [ ] **Step 1: Pruebas que fallan** con `FakeFirebaseFirestore`, sembrado con:
  - un pedido entregado en la semana: sillón $6,500 con las líneas y días de la Tarea 2, y envío $300;
  - un pedido cancelado con anticipo de $500 en la semana;
  - un pago de $1,500 al pedido entregado y una devolución de −$200;
  - una compra de $1,200 y un sueldo de $1,800;
  - un cambio de precio.

  Verifica:
  - `cobros.total == 1800` (500 + 1500 − 200);
  - `gastos.total == 3000`;
  - `ganancias` trae solo el entregado, con ganancia $5,940.00 (6,800 − 335 − 525);
  - `muebles[TipoTrabajo.fabricacion]` o `[reparacion]` contienen el sillón según su tipo;
  - `cambios.length == 1`;
  - `pendientes` incluye el entregado con saldo $5,300.00 (pagado 1,500);
  - `pedidosDeCobros` tiene los folios de los dos pedidos.
- [ ] **Step 2:** `flutter test test/funciones/contabilidad`. Esperado: FALLA.
- [ ] **Step 3:** Implementa.
- [ ] **Step 4:** `flutter test` y `dart analyze`. Esperado: todo pasa.
- [ ] **Step 5:** Commit `feat: resumen del periodo para la contabilidad`.

---

### Task 6: Pantalla de contabilidad

**Files:**
- Create: `app/lib/funciones/contabilidad/pantalla_contabilidad.dart`
- Modify: `app/lib/nucleo/router.dart`. Asigna `/contabilidad` a `PantallaContabilidad` y agrégalo a `_rutasConPantalla`.
- Test: `app/test/funciones/contabilidad/pantalla_contabilidad_test.dart`

**Interfaces:**
- Consumes: `resumenProvider`, `periodoProvider`, `cajasProvider`, `entregasPendientesProvider`, `usuariosProvider` y `materialesProvider`.
- Produces `PantallaContabilidad`, con el título "Contabilidad":
  - **Selector de periodo:**
    - un `SegmentedButton<TipoPeriodo>` con "Semana", "Mes" y "Rango";
    - "Rango" abre `showDateRangePicker`;
    - flechas con los tooltips "Periodo anterior" y "Periodo siguiente", solo para semana y mes;
    - `periodo.etiqueta` como texto;
    - un `IconButton` con el tooltip "Actualizar" que invalida `resumenProvider(periodo)`.
  - **Cargando:** un indicador de progreso. **Error:** "No se pudo cargar el resumen" y el botón "Reintentar".
  - **Secciones** (encabezado `titleMedium`; un texto vacío cuando no hay datos):
    1. **"Lo cobrado":**
       - "Total: $X";
       - una línea por cada forma de pago con monto ≠ 0, como "Efectivo: $X";
       - "Por quién", con "{nombre}: $X";
       - "Por pedido", con "{folio}: $X";
       - vacío: "Sin cobros en el periodo".
    2. **"Por entregar":**
       - "{nombre}: $X" por cada caja con monto ≠ 0;
       - "Entregas por confirmar: $Y" si hay pendientes;
       - vacío: "Nadie tiene dinero por entregar".
    3. **"Lo gastado":** "Compras de material: $X", "Sueldos: $Y" y "Total: $Z".
    4. **"Ganancia":**
       - "Ganancia total: $X (N pedidos entregados)";
       - subtítulos "Fabricación" y "Reparación". Cada mueble lleva como título "{tipoMueble} · {folio}" y como subtítulo "Precio $X · Materiales $Y · Mano de obra $Z". Al final, "$G (M%)", en color de error si G < 0. Si falta un costo, agrega en el subtítulo "Costo incompleto";
       - subtítulo "Pedidos", con "{folio} · {cliente}" y "$G", más "Costo incompleto" si aplica;
       - vacío: "Ningún pedido entregado en el periodo".
    5. **"Cambios de precio":**
       - "{folio} · {concepto}: $A → $N", con el mismo concepto del historial del pedido; las bajadas, en rojo;
       - vacío: "Sin cambios de precio en el periodo".
    6. **"Pendientes de cobro":**
       - "{folio} · {cliente}" con "Saldo: $X"; tocar la fila abre `/pedidos/{id}`;
       - vacío: "Nada pendiente de cobro".
    7. **"Diferencias de material":**
       - "{folio} · {tipoMueble}" con "{material}: estimado E, usado U", usando `formatearCantidad` y la unidad del material;
       - vacío: "Sin diferencias notables".
  - Si un no dueño llega a la ruta, la pantalla muestra un `Scaffold` vacío y no vigila ningún provider, igual que `PantallaSueldos`.

- [ ] **Step 1: Pruebas que fallan** (widget; sobrescribe `resumenProvider` con un `ResumenPeriodo` armado a mano):
  - Con los datos de la Tarea 5 se ven "Total: $1,800.00", "Compras de material: $1,200.00" y "$5,940.00".
  - El sillón muestra "86.8%". El desglose por quién muestra los nombres.
  - **Periodo vacío:** salen los siete textos vacíos, sin excepción.
  - **Costo incompleto:** un mueble con `materiales.incompleto` muestra "Costo incompleto".
  - **Navegación:**
    - "Periodo siguiente" cambia la etiqueta a la semana siguiente;
    - al elegir "Mes" aparece "Noviembre 2026", con un `periodoProvider` inicial sobrescrito al 07/11/2026.
  - Tocar un pendiente navega a `/pedidos/{id}`.
  - Como empleado, la pantalla está vacía y no lee `resumenProvider`; sobrescríbelo para que lance si se lee.
- [ ] **Step 2:** `flutter test test/funciones/contabilidad`. Esperado: FALLAN.
- [ ] **Step 3:** Implementa.
- [ ] **Step 4:** `flutter test` y `dart analyze`. Esperado: todo pasa.
- [ ] **Step 5:** Commit `feat: pantalla de contabilidad`.

---

### Task 7: APK firmado y publicación

**Files:**
- Modify: `app/android/app/build.gradle.kts`:
  - lee `key.properties` (en `app/android/`) o las variables de entorno `TAPICERIA_KEYSTORE`, `TAPICERIA_KEYSTORE_PASSWORD`, `TAPICERIA_KEY_ALIAS` y `TAPICERIA_KEY_PASSWORD`;
  - si hay datos de firma, crea `signingConfigs.release` y lo usa en `buildTypes.release`;
  - si no hay, usa la firma de depuración y muestra el aviso "Sin llave de firma: el APK de release usa la firma de depuración".
- Create: `.github/workflows/publicar.yml`.
- Modify: `app/pubspec.yaml`: `version: 1.0.0+1`, si no lo tiene ya.
- Modify: `README.md`: nueva sección "Publicar una versión".

**Interfaces:**
- Produces el workflow `publicar.yml`:
  - **Disparo:** `push` de una etiqueta `v*`.
  - **Pasos:**
    1. Revisa que existan los secretos `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` y `KEY_PASSWORD`. Si falta alguno, termina con el error "Faltan los secretos de firma".
    2. Decodifica el keystore a `$RUNNER_TEMP/tapiceria.jks`.
    3. Corre `flutter test`.
    4. Corre `flutter build apk --release`, con las variables `TAPICERIA_*` apuntando al keystore.
    5. Renombra el APK a `tapiceria-${{ github.ref_name }}.apk`.
    6. Publica un Release con `softprops/action-gh-release@v2` y adjunta el APK.
  - **Permisos:** `contents: write`.
  - Usa la misma configuración de Java y Flutter que `ci.yml`.
- Produces la sección del README, con los pasos que **hace el usuario**:
  1. Crear la llave con `keytool -genkey -v -keystore tapiceria.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tapiceria` y guardarla fuera del repositorio, con respaldo. Si se pierde, los teléfonos no aceptan actualizaciones.
  2. Cargar los 4 secretos con `gh secret set`. El keystore va en base64.
  3. Para compilar en local, crear `app/android/key.properties` con `storeFile`, `storePassword`, `keyAlias` y `keyPassword`.
  4. Subir la versión en `pubspec.yaml` y luego `git tag v1.0.0 && git push origin v1.0.0`.
  5. En el teléfono: descargar el APK del Release, permitir "instalar apps desconocidas" e instalar. La app de release usa Firebase de producción (`tapiceria-app`), no los emuladores.

- [ ] **Step 1:** `cd app && flutter build apk --release`, sin llave. Esperado: compila, muestra el aviso de firma de depuración y genera `build/app/outputs/flutter-apk/app-release.apk`.
- [ ] **Step 2:** Comprueba la ruta con llave usando una llave **temporal de prueba** en `$TEMP` (nunca en el repositorio), creada con `keytool` y una contraseña de prueba de usar y tirar, y las variables `TAPICERIA_*`. Esperado:
  - compila;
  - `keytool -printcert -jarfile app-release.apk` muestra el certificado de la llave temporal, no "Android Debug".
  - Después borra la llave temporal.
- [ ] **Step 3:** Revisa `publicar.yml` con `npx --yes @action-validator/cli .github/workflows/publicar.yml`; si no está disponible, léelo con cuidado. `ci.yml` no cambia.
- [ ] **Step 4:** `git status` no muestra ningún `.jks` ni `key.properties`.
- [ ] **Step 5:** Commit `feat: APK firmado y publicación en GitHub Releases`.

---

### Task 8: Semilla, documentación y prueba manual

**Files:**
- Modify: `firebase/semilla_emulador.mjs`. Agrega `pedido-entregado`:
  - folio `261105-ENTR` y `cliente-maria`;
  - `estado: 'entregado'`, con `fechaTerminado` y `fechaEntregado` de hoy;
  - envío $0 y `pagado` 2,000, con su pago en efectivo cobrado por el dueño (sin caja);
  - el mueble `mueble-entregado` es una silla de reparación de $2,500, `entregado`, con `plantillaId: null`;
  - una línea de guata de 1 kg cobrada por el empleado, con su movimiento de consumo; la existencia de guata baja 1;
  - 1 día del empleado.
- Modify: `README.md`, sección "Contabilidad": qué muestra, cómo se asigna cada cosa al periodo y los límites conocidos:
  - "los pendientes de cobro solo revisan entregas de los últimos 180 días";
  - "la mano de obra usa el sueldo actual, no el que tenía cuando se trabajó".
- Modify: `docs/superpowers/plans/2026-11-04-00-hoja-de-ruta.md`. Marca los 5 planes como completados y anota la regla de grupo de `cambios_precio`.

- [ ] **Step 1:** `node firebase/semilla_emulador.mjs` sin errores.
- [ ] **Step 2:** Suite completa: `flutter test`, `dart analyze` y las reglas. Esperado: todo pasa. Después vuelve a correr la semilla.
- [ ] **Step 3:** Commit `docs: semilla, README y hoja de ruta del Plan 5`.
- [ ] **Step 4:** Compila el APK de depuración con `--dart-define=USAR_EMULADOR=true` y lo instala en Flutter_API_36. Después, la **prueba manual del usuario**, como dueño, en Contabilidad, semana actual:
  1. **Lo cobrado:** $3,500.00 en total ($1,500 del empleado en 261107-PEDI y $2,000 del dueño en 261105-ENTR). El desglose por quién y por forma de pago coincide.
  2. **Por entregar:** el empleado tiene $1,500.00, más la entrega por confirmar de $1,000.00.
  3. **Lo gastado:** el sueldo de $1,800.00, y las compras de la semilla con fecha de esta semana.
  4. **Ganancia:** la silla de 261105-ENTR muestra precio $2,500 y materiales $60.00. La mano de obra se calcula con sueldo semanal ÷ días laborales. En la semilla, el empleado tiene sueldo $2,100 y 6 días laborales, así que 1 día cuesta $350.00 y la ganancia es $2,090.00.
  5. **Pendientes de cobro:** aparece 261105-ENTR con saldo $500.00.
  6. **Navegación:** cambia a "Mes" y luego al mes anterior; las secciones quedan vacías sin errores.
  7. **Como empleado:** la entrada "Contabilidad" no aparece en el menú.
