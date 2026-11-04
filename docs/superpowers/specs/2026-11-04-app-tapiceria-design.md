# App de gestión para tapicería — Documento de diseño

Fecha: 2026-11-04
Autor: Juan Diego Chan (con Claude)
Origen: `TapiceríaRF.docx` + conversación de diseño.

Convención: lo que no lleva marca lo decidió el usuario. Lo marcado **[decisión de Claude]** es una propuesta mía que el usuario no pidió de forma explícita; se puede cambiar.

---

## 1. Intención y el porqué

El cliente es dueño de una tapicería que **fabrica muebles nuevos** y **repara/retapiza** muebles. Tiene dos problemas:

1. **Las ganancias no le cuadran** con el trabajo que realiza: no sabe cuánto le cuesta realmente cada mueble.
2. **La bodega está desordenada**: hay trozos de tela e insumos sin saber de qué trabajo vienen.

Hoy todo se anota en una libreta: datos del cliente, precio acordado y, mientras se hace el mueble, el trabajador anota las medidas de tela y demás materiales usados.

La app reemplaza esa libreta. Su objetivo de fondo, en palabras del cliente: **"que no falte dinero"**. Es decir, poder comprobar que el dinero que entra corresponde a los trabajos hechos y saber cuánto deja realmente cada mueble.

## 2. Usuarios y contexto de uso

- **Dueño** y **empleados**, cada uno con **su propio teléfono Android de gama media** (modelo exacto desconocido).
- Los pedidos se toman en el taller **o en la casa del cliente**, donde **puede no haber internet**. Un pedido se captura en un solo teléfono, pero todos los teléfonos deben ver los mismos datos.
- **Requisito duro: funcionar sin conexión**. Todo se guarda en el teléfono y se sincroniza al recuperar la conexión, sin perder datos.
- Idioma: español (México). Moneda: pesos mexicanos (MXN).

## 3. Objetivos, no-objetivos y anti-objetivos

### Objetivos
- Registrar pedidos de **fabricación** y **reparación**, separados en módulos distintos.
- Inventario de materiales con **rollos de tela rastreables** (lotes) y existencias actualizadas por cada uso.
- Registrar **materiales usados por pedido** conforme se trabaja (sustituye la libreta).
- **Plantillas de materiales (BOM)** por tipo de mueble como estimado de costo.
- Calcular el **costo real** de cada pedido (materiales + mano de obra) y su **margen real**.
- Registrar **pagos** (anticipo, abonos, liquidación) y el **saldo pendiente**.
- **Lista de compras** automática cuando un material baja de su mínimo.
- **Resumen de contabilidad** semanal/mensual para el dueño.
- **Dos roles** (Dueño / Empleado) con permisos aplicados en el servidor.

### No-objetivos (fuera de esta versión)
- Proveedores: el cliente **no** quiere registrarlos. Él mismo va a comprar el material.
- Órdenes de compra enviadas a proveedores.
- Otros gastos del taller (renta, luz, gasolina): el cliente **no** quiere verlos.
- Registro aparte de retazos: un retazo sigue contando como parte de su rollo.
- iOS y versión web. *(Flutter permitiría agregarlos después.)*
- Fotos compartidas entre teléfonos (requeriría pagar almacenamiento en la nube).
- Facturación electrónica (CFDI).
- Notificaciones push (requieren servidor de pago).

### Anti-objetivos (sería un fracaso aunque "funcione")
- **Cualquier costo mensual.** El cliente no quiere pagar nada al mes. Restricción dura.
- **Perder datos** capturados sin conexión.
- Que un **empleado pueda ver costos, precios de material, sueldos o márgenes**, o que pueda **borrar o editar un cobro** ya registrado.
- Que capturar materiales sea más lento que la libreta, porque los trabajadores volverían a ella. La captura de una línea de material debe tomar pocos toques.

## 4. Stack tecnológico (decidido)

| Pieza | Elección |
|---|---|
| App | **Flutter (Dart)**, compilada para Android |
| Base de datos y sincronización | **Cloud Firestore** con persistencia sin conexión (activa por defecto en Android) |
| Inicio de sesión | **Firebase Authentication** (correo y contraseña) |
| Plan de Firebase | **Spark (gratuito)**, sin tarjeta. No se permite migrar a Blaze. |
| Código | Git + GitHub: `Juan-Diego-Chan/Tapicer-a-APK`, rama `main` |

Por qué: el usuario conoce Flutter (además de C#, JS y React). Firestore resuelve la sincronización sin conexión sin programarla a mano, y el plan gratuito alcanza para un taller con pocos teléfonos.

**Consecuencias del plan Spark (restricciones duras):**
- **Sin Cloud Functions.** Toda la lógica (costos, descuentos de inventario, alertas, reportes) vive en la app.
- **Sin Cloud Storage** (los buckets nuevos exigen Blaze). No hay archivos compartidos.
- **Sin envío de push ni correos desde servidor.**
- Cuotas diarias aproximadas: 50k lecturas, 20k escrituras, 1 GiB almacenado. El diseño debe evitar lecturas masivas (por ejemplo, reportes con consultas acotadas por rango de fechas).

**Detalles de stack [decisión de Claude]:**
- Manejo de estado: **Riverpod**. Navegación: **go_router**.
- Android `minSdk` 23 o el mínimo que exijan los paquetes de Firebase vigentes.
- Distribución: **APK instalado directamente** (por ejemplo, desde GitHub Releases), sin Play Store, que cobra una cuota de registro.
- Compilación del APK con **GitHub Actions** (el plan gratuito alcanza).

## 5. Roles y permisos

Los permisos se aplican en las **reglas de seguridad de Firestore**, no solo ocultando pantallas.

### Empleado puede
- Ver y crear pedidos (fabricación y reparación), con datos del cliente, precio acordado, envío, comentarios y fechas.
- Editar pedidos: agregar muebles y cambiar estado, fechas y comentarios.
- Cambiar el **precio de un mueble o el envío**. El cambio queda en un historial que ve el dueño (sección 6.1).
- Agregar **líneas de materiales** usados en un mueble, eligiendo el rollo si es tela.
- Registrar **días trabajados** en un mueble.
- Registrar **pagos recibidos** de clientes, que quedan a su nombre.
- Registrar **entregas de dinero** al dueño (sección 6.7.1) y ver su propio saldo por entregar.
- Ver **existencias** de materiales (cantidades), **sin precios**.
- Marcar un material como **"se está acabando"**.

### Solo el dueño puede
- Dar de alta y editar materiales, rollos y mínimos de stock.
- Registrar **compras** con su precio.
- Definir **plantillas (BOM)**.
- Dar de alta y desactivar usuarios, y registrar **sueldos semanales**.
- Ver costos, márgenes, el resumen de contabilidad, **cuánto cobró cada trabajador** y el historial de cambios de precio.
- **Confirmar o rechazar** las entregas de dinero de los empleados.
- **Corregir o borrar** cualquier registro, incluidos los pagos.

**[decisión de Claude]** Un empleado **no puede editar ni borrar** pagos ni líneas de material ya guardadas. Si se equivoca, el dueño lo corrige. Así un cobro no puede "desaparecer". *(Si en el uso real resulta molesto para las líneas de material, se puede permitir que el empleado borre sus propias líneas durante unos minutos.)*

### Implicación técnica importante
Las reglas de Firestore protegen **documentos completos, no campos**. Por eso **toda información sensible (costos, precios de compra, sueldos) debe vivir en documentos o colecciones que el empleado no puede leer**. Las líneas que escribe el empleado no llevan costo; el costo lo calcula la app del dueño a partir de los datos protegidos.

## 6. Módulos y comportamiento

### 6.1 Pedidos y muebles
Un **pedido puede tener uno o varios muebles**. Ejemplos: una sala con un sofá y dos sillones, o cuatro sillas del mismo cliente.

**El pedido** tiene:
- **Cliente:** nombre, teléfono, dirección.
- **Entrega:** el cliente **lo recoge** o se **lleva a domicilio**. El envío es un **costo aparte**, uno por pedido. Ejemplo: muebles $1,300 + envío $200 = **$1,500 total**.
- **Comentarios** generales sobre lo que desea el cliente.
- **Fechas:** ingreso y estimada de terminado (al crear); terminado y entregado (reales).
- **Pagos** (sección 6.7) y **quién lo capturó**.
- **Total del pedido** = Σ precios de sus muebles + envío.

**Cada mueble** del pedido tiene:
- **Tipo de trabajo:** Fabricación (mueble nuevo) o Reparación (retapizado o arreglo). **[decisión de Claude]** El tipo se define por mueble, así un pedido puede mezclar ambos. Los módulos **Fabricación** y **Reparación** de la app muestran los muebles de su tipo.
- **Tipo de mueble** (por ejemplo, "sillón 3 plazas") y **plantilla opcional** (sección 6.3).
- **Precio acordado** de ese mueble.
- **Comentarios** propios (por ejemplo, "cambiar resortes del asiento").
- Su **pestaña de materiales** (6.2) y sus **días trabajados** (6.6).
- **[decisión de Claude]** Un estado propio, para saber cuál ya está terminado. El estado del pedido es el del mueble menos avanzado.

Así el costo, la ganancia y la comparación estimado vs. real se calculan **por mueble**, y se suman para el pedido.

**[decisión de Claude]** Estados: *Recibido → En proceso → Terminado → Entregado*, además de *Cancelado*.
**[decisión de Claude]** Los clientes se guardan en un catálogo reutilizable, buscable por nombre o teléfono, para no recapturar a quien regresa.

#### Cambios de precio con historial
- Tanto el empleado como el dueño pueden cambiar el **precio de un mueble** o el **envío** después de crear el pedido.
- Cada cambio deja un registro que **no se puede editar ni borrar**: quién, cuándo, valor anterior, valor nuevo y motivo opcional.
- El dueño ve el historial en el pedido. En contabilidad ve además una lista de **cambios de precio del periodo**, con las bajadas de precio resaltadas.
- Implementación: el cambio del precio y su registro de historial se escriben en el **mismo lote (batch)**, que funciona sin conexión. Las reglas de Firestore (`getAfter`) rechazan un cambio de precio que no venga con su registro.

### 6.2 Pestaña de materiales (en cada mueble)
- El trabajador agrega líneas al mueble **conforme avanza**: material, cantidad y, si es tela, **el rollo** del que salió. Ejemplos: "2.5 m de tela, rollo #12", "1 kg de guata", "20 resortes".
- Cada línea **descuenta del inventario** al guardarse, aunque no haya conexión.
- Unidades por material: metros, kg, piezas, etc.

### 6.3 Plantillas de materiales (BOM)
- El dueño define, por **tipo de mueble** (por ejemplo, "sillón 3 plazas"), las líneas estimadas: "6 m de tela", "1 kg de guata", "grapas"...
- En la plantilla la tela es **genérica**. El rollo concreto se elige al usarlo.
- Usos:
  - **Estimado de costo** al acordar el precio con el cliente (solo lo ve el dueño).
  - **Revisión de disponibilidad** antes de empezar: avisa si no alcanza algún material.
  - **Comparación estimado vs. real** al terminar el pedido.
- En **Fabricación** la plantilla es lo normal. En **Reparación** es opcional, porque cada mueble es distinto; ahí sobre todo se anota lo que se va usando.

**[decisión de Claude]** La revisión de disponibilidad **avisa pero no bloquea**: sin conexión, el inventario del teléfono puede estar desactualizado. Por la misma razón se permite que una existencia quede negativa, mostrándola en rojo al dueño como algo a revisar.

### 6.4 Inventario
- **Materiales:** nombre, categoría (tela, espuma, guata, resortes, cinchas, grapas, otros), unidad y **stock mínimo**.
- **Rollos (lotes) de tela:** cada rollo tiene un identificador visible (por ejemplo "#12"), la tela a la que pertenece, la cantidad inicial y la fecha de compra. El costo por metro va en un documento protegido. Los retazos siguen contando como parte del rollo.
- **Compras (solo dueño):** material, cantidad, precio total pagado y, si es tela, el rollo nuevo que se crea.
- **Ajustes de inventario (solo dueño):** para corregir contra un conteo físico.

**Regla de diseño obligatoria (sincronización segura):** las existencias **nunca se sobrescriben**. Cada entrada o salida es un **movimiento** independiente (compra +, consumo −, ajuste ±). El total se mantiene con incrementos atómicos (`FieldValue.increment`), que sí se combinan bien cuando dos teléfonos sin conexión descuentan el mismo material. No usar transacciones para esto, porque fallan sin conexión.

**[decisión de Claude] Costo de materiales que no son rollo:** **costo promedio ponderado** de sus compras. El costo de una línea de tela es el costo por metro de su rollo.

**[decisión de Claude] Carga inicial del inventario:** el primer día, el dueño captura lo que ya hay en bodega (rollos y otros materiales) con un **costo estimado** por unidad. Esa carga se registra como un movimiento de tipo "inventario inicial". Si no conoce el costo, puede dejarlo vacío. En ese caso los pedidos que usen ese material muestran su costo como **incompleto**, en lugar de calcularlo con cero.

**[decisión de Claude] Material del cliente:** una línea de material puede marcarse como **"lo trajo el cliente"**, sobre todo en reparaciones. Esa línea queda registrada en el pedido, pero no descuenta inventario ni suma costo.

### 6.5 Lista de compras
- Si la existencia de un material baja de su mínimo, o un empleado lo marca como "se está acabando", aparece en la **lista de compras** del dueño.
- Es un aviso **dentro de la app**, sin push. El dueño compra el material en persona y lo registra como compra; con eso sale de la lista.

### 6.6 Mano de obra
- El dueño registra el **sueldo semanal** de cada trabajador (dato protegido).
- **Costo por día** = sueldo semanal ÷ días laborales por semana. **[decisión de Claude]** Los días laborales son configurables; valor por defecto: 6.
- En cada mueble se anota **quién trabajó y cuántos días** le dedicó, permitiendo medios días.
- Mano de obra del mueble = Σ (días × costo por día del trabajador). La del pedido es la suma de sus muebles.
- El **dueño también trabaja** en los muebles, pero **su tiempo no cuenta como costo**. Puede anotar sus días como referencia; su costo por día es siempre 0.
- **[decisión de Claude]** El dueño registra el **pago semanal de sueldos** como gasto real del periodo, para que el resumen muestre el dinero que salió de verdad.

### 6.7 Pagos de clientes
- Cada pedido tiene una lista de pagos: anticipo, abonos y liquidación. También puede ser un solo pago por el total.
- Cada pago guarda fecha, monto, forma (efectivo / transferencia) y **quién lo recibió** (dueño o empleado).
- **[decisión de Claude]** Los pagos son del **pedido completo**, no de cada mueble.
- **Saldo pendiente** = total del pedido − Σ pagos. Lo ven todos, porque el empleado necesita saber cuánto cobrar.

### 6.7.1 Entregas de dinero al dueño
- Cuando un empleado le entrega al dueño el dinero que cobró, el empleado registra una **entrega**: monto, fecha y forma (efectivo / transferencia).
- La entrega queda **pendiente** hasta que el **dueño la confirma** (o la rechaza, si no recibió ese monto). Solo el dueño puede confirmar o rechazar.
- El empleado no puede editar ni borrar una entrega después de registrarla.
- **Dinero en manos de cada empleado** = Σ cobros que recibió − Σ entregas confirmadas. El dueño lo ve en todo momento. **[decisión de Claude]** El empleado ve su propio saldo, para saber cuánto debe entregar.
- Los cobros que recibe el propio dueño no generan entrega.

### 6.8 Contabilidad (solo dueño)
Resumen **semanal y mensual**, con rango de fechas elegible:
- **Lo cobrado:** total y desglose por pedido, por forma de pago y **por quién lo recibió**.
- **Dinero pendiente de entregar:** por empleado, más las entregas sin confirmar.
- **Lo gastado:** compras de material y sueldos pagados.
- **Ganancia real** por mueble y por pedido: precio − materiales − mano de obra, más el envío a nivel pedido. Los de menor margen van primero, separados por Fabricación y Reparación.
- **Cambios de precio** del periodo (sección 6.1).
- **Pendientes de cobro:** pedidos terminados o entregados con saldo mayor a cero.
- **Diferencias de material:** pedidos donde lo usado superó notablemente lo estimado por la plantilla.

**[decisión de Claude]** Lo cobrado y lo gastado se asignan al periodo por la **fecha en que ocurrieron** (fecha del pago, de la compra o del pago de sueldos). La **ganancia de un pedido** se asigna al periodo de su **fecha de entrega**.

**[decisión de Claude] Cancelaciones:** por defecto el anticipo se **queda** con el taller. Si se devuelve dinero, solo el dueño registra una **devolución**: un pago negativo que resta de lo cobrado.

**[decisión de Claude]** No se contemplan muebles fabricados sin cliente (para exhibición o venta posterior); todo pedido tiene un cliente.

**[decisión de Claude]** El envío cuenta como ingreso del pedido; su costo real (gasolina) no se registra, porque el cliente no quiere ver otros gastos.

## 7. Usuarios e inicio de sesión
- Cada persona inicia sesión con correo y contraseña. La sesión persiste, así que la app funciona sin conexión una vez iniciada.
- El rol y el estado (activo/inactivo) de cada usuario viven en un documento `usuarios/{uid}`, que las reglas de Firestore consultan.
- **Primer dueño:** se crea a mano desde la consola de Firebase, incluido su documento de rol. Esto va documentado en el README.
- **Alta de empleados desde la app (dueño):** sin Cloud Functions no hay Admin SDK. Se crea el usuario con una **segunda instancia de Firebase App** en el teléfono del dueño, para no cerrar su sesión, y luego se escribe su documento de rol.
- **Baja:** el dueño marca al usuario como inactivo y las reglas le niegan el acceso. Sus registros históricos se conservan.

## 8. Lo que queda a criterio del constructor
- Estructura exacta de colecciones y documentos en Firestore, respetando: separación de datos sensibles (sección 5), movimientos con incrementos atómicos (sección 6.4) y consultas acotadas por fecha (cuotas de Spark).
- Diseño visual y navegación, siempre que la captura de materiales y pagos sea rápida.
- Identificadores de pedidos y rollos legibles para humanos que no choquen si se crean sin conexión en dos teléfonos (por ejemplo, prefijo por dispositivo o usuario).
- Estrategia de pruebas. Mínimo esperado: **pruebas unitarias** de cálculos (costos, margen, saldo, promedio ponderado, mano de obra) y **pruebas de reglas de seguridad** con el emulador de Firebase.
- Orden de construcción de los módulos.

## 9. Criterios de éxito
- Un empleado sin internet en casa de un cliente crea un pedido, registra el anticipo y, al volver la conexión, el dueño lo ve en su teléfono sin pérdida de datos.
- Dos teléfonos sin conexión descuentan del mismo rollo y, al sincronizar, la existencia refleja ambos consumos.
- Con la sesión de un empleado, es imposible leer costos, sueldos o márgenes, aun intentándolo directamente contra Firestore.
- El dueño puede ver, para cualquier semana, cuánto se cobró, quién lo cobró, cuánto se gastó y cuánto dejó cada pedido y cada mueble.
- El dueño sabe en todo momento cuánto dinero cobrado sigue en manos de cada empleado.
- Ningún cambio de precio pasa sin quedar registrado.
- El proyecto funciona completo en el plan gratuito de Firebase, sin tarjeta.
