// Crea un dueño de prueba en los emuladores locales (proyecto demo-tapiceria).
// Uso: con los emuladores corriendo (firebase emulators:start --only auth,firestore --project demo-tapiceria):
//   node firebase/semilla_emulador.mjs
// Solo para desarrollo local: nunca apunta a producción.

const PROYECTO = 'demo-tapiceria';
const AUTH = 'http://127.0.0.1:9099';
const FIRESTORE = 'http://127.0.0.1:8080';

const DUENO = {
  nombre: 'Dueño de Prueba',
  email: 'dueno@prueba.test',
  contrasena: 'prueba123',
};

async function crearCuenta({ email, contrasena }) {
  const res = await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: contrasena, returnSecureToken: true }),
    },
  );
  const datos = await res.json();
  if (!res.ok) throw new Error(`Auth: ${JSON.stringify(datos.error ?? datos)}`);
  return datos.localId;
}

async function crearDocUsuario(uid, { nombre, email }) {
  const url = `${FIRESTORE}/v1/projects/${PROYECTO}/databases/(default)/documents/usuarios/${uid}`;
  const res = await fetch(url, {
    method: 'PATCH',
    // "Bearer owner" salta las reglas solo en el emulador.
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({
      fields: {
        nombre: { stringValue: nombre },
        email: { stringValue: email },
        rol: { stringValue: 'dueno' },
        activo: { booleanValue: true },
        creadoEn: { timestampValue: new Date().toISOString() },
      },
    }),
  });
  if (!res.ok) throw new Error(`Firestore: ${await res.text()}`);
}

const uid = await crearCuenta(DUENO);
await crearDocUsuario(uid, DUENO);
console.log(`Dueño de prueba creado: ${DUENO.email} (uid ${uid})`);
