// Siembra los emuladores locales (proyecto demo-tapiceria): un dueño, un empleado
// y dos materiales (Tela lino gris con el rollo #1 y Guata).
// Uso: con los emuladores corriendo (firebase emulators:start --only auth,firestore --project demo-tapiceria):
//   node firebase/semilla_emulador.mjs
// Es idempotente: se puede correr varias veces. Solo para desarrollo local:
// nunca apunta a producción.

const PROYECTO = 'demo-tapiceria';
const AUTH = 'http://127.0.0.1:9099';
const FIRESTORE = 'http://127.0.0.1:8080';

const DUENO = {
  nombre: 'Dueño de Prueba',
  email: 'dueno@prueba.test',
  contrasena: 'prueba123',
  rol: 'dueno',
};
const EMPLEADO = {
  nombre: 'Empleado de Prueba',
  email: 'empleado@prueba.test',
  contrasena: 'prueba123',
  rol: 'empleado',
};
const SUELDO_SEMANAL_EMPLEADO = 2100;

async function postAuth(accion, cuerpo) {
  const res = await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:${accion}?key=demo`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...cuerpo, returnSecureToken: true }),
    },
  );
  return { res, datos: await res.json() };
}

// Crea la cuenta; si ya existe, inicia sesión para obtener su uid.
async function crearCuenta({ email, contrasena }) {
  const cuerpo = { email, password: contrasena };
  let { res, datos } = await postAuth('signUp', cuerpo);
  if (!res.ok && datos.error?.message === 'EMAIL_EXISTS') {
    ({ res, datos } = await postAuth('signInWithPassword', cuerpo));
  }
  if (!res.ok) throw new Error(`Auth: ${JSON.stringify(datos.error ?? datos)}`);
  return datos.localId;
}

// Valores tipados de la API REST de Firestore.
const texto = (v) => ({ stringValue: v });
const entero = (v) => ({ integerValue: String(v) });
const booleano = (v) => ({ booleanValue: v });
const nulo = () => ({ nullValue: null });
const fecha = (v) => ({ timestampValue: v });

// PATCH reemplaza el documento (los campos van completos), así que re-correr
// el script lo deja igual.
async function escribir(ruta, campos) {
  const url = `${FIRESTORE}/v1/projects/${PROYECTO}/databases/(default)/documents/${ruta}`;
  const res = await fetch(url, {
    method: 'PATCH',
    // "Bearer owner" salta las reglas solo en el emulador.
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ fields: campos }),
  });
  if (!res.ok) throw new Error(`Firestore ${ruta}: ${await res.text()}`);
}

async function crearDocUsuario(uid, { nombre, email, rol }) {
  await escribir(`usuarios/${uid}`, {
    nombre: texto(nombre),
    email: texto(email),
    rol: texto(rol),
    activo: booleano(true),
    creadoEn: fecha(new Date().toISOString()),
  });
}

async function crearMaterial(id, m) {
  await escribir(`materiales/${id}`, {
    nombre: texto(m.nombre),
    categoria: texto(m.categoria),
    unidad: texto(m.unidad),
    stockMinimo: entero(m.stockMinimo),
    existencia: entero(m.existencia),
    usaRollos: booleano(m.usaRollos),
    marcadoAgotandose: booleano(false),
  });
}

// Una compra inicial y su movimiento.
async function registrarCompra(id, { materialId, rolloId, cantidad, precioTotal, uidDueno, ahora }) {
  const rollo = rolloId ? texto(rolloId) : nulo();
  await escribir(`compras/${id}`, {
    materialId: texto(materialId),
    rolloId: rollo,
    cantidad: entero(cantidad),
    precioTotal: entero(precioTotal),
    fecha: fecha(ahora),
    tipo: texto('compra'),
  });
  await escribir(`movimientos/${id}`, {
    tipo: texto('compra'),
    materialId: texto(materialId),
    rolloId: rollo,
    cantidad: entero(cantidad),
    usuarioId: texto(uidDueno),
    fecha: fecha(ahora),
  });
}

const ahora = new Date().toISOString();

const uidDueno = await crearCuenta(DUENO);
await crearDocUsuario(uidDueno, DUENO);
console.log(`Dueño de prueba: ${DUENO.email} (uid ${uidDueno})`);

const uidEmpleado = await crearCuenta(EMPLEADO);
await crearDocUsuario(uidEmpleado, EMPLEADO);
await escribir(`usuarios_privado/${uidEmpleado}`, {
  sueldoSemanal: entero(SUELDO_SEMANAL_EMPLEADO),
});
console.log(`Empleado de prueba: ${EMPLEADO.email} (uid ${uidEmpleado})`);

// Tela lino gris: 30 m en el rollo #1 a $110/m.
await crearMaterial('tela-lino-gris', {
  nombre: 'Tela lino gris',
  categoria: 'tela',
  unidad: 'm',
  stockMinimo: 10,
  existencia: 30,
  usaRollos: true,
});
await escribir('rollos/rollo-1', {
  materialId: texto('tela-lino-gris'),
  codigo: texto('#1'),
  cantidadInicial: entero(30),
  existencia: entero(30),
  fechaCompra: fecha(ahora),
});
await escribir('rollos_costos/rollo-1', { costoPorUnidad: entero(110) });
await registrarCompra('semilla-tela', {
  materialId: 'tela-lino-gris',
  rolloId: 'rollo-1',
  cantidad: 30,
  precioTotal: 3300,
  uidDueno,
  ahora,
});
console.log('Material: Tela lino gris (rollo #1, 30 m a $110/m)');

// Guata: 2 kg a $60/kg, bajo el mínimo de 5.
await crearMaterial('guata', {
  nombre: 'Guata',
  categoria: 'guata',
  unidad: 'kg',
  stockMinimo: 5,
  existencia: 2,
  usaRollos: false,
});
await escribir('materiales_costos/guata', {
  cantidadComprada: entero(2),
  costoTotalComprado: entero(120),
});
await registrarCompra('semilla-guata', {
  materialId: 'guata',
  rolloId: null,
  cantidad: 2,
  precioTotal: 120,
  uidDueno,
  ahora,
});
console.log('Material: Guata (2 kg, mínimo 5, $60/kg)');
