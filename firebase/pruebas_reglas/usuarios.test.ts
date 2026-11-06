import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';
import { anonimo, como, crearEntorno, sembrarUsuario } from './ayuda';

let env: RulesTestEnvironment;

const nuevoUsuario = (rol: string) => ({
  nombre: 'N',
  email: 'n@e.com',
  rol,
  activo: true,
  creadoEn: new Date(),
});

beforeAll(async () => {
  env = await crearEntorno();
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await sembrarUsuario(env, 'dueno1', { rol: 'dueno', activo: true });
  await sembrarUsuario(env, 'emp1', { rol: 'empleado', activo: true });
  await sembrarUsuario(env, 'emp2', { rol: 'empleado', activo: true });
  await sembrarUsuario(env, 'inact', { rol: 'empleado', activo: false });
  await sembrarUsuario(env, 'duenoInact', { rol: 'dueno', activo: false });
});

describe('usuarios', () => {
  it('dueño activo lee, actualiza y crea cualquier usuario', async () => {
    const db = como(env, 'dueno1');
    await assertSucceeds(getDoc(doc(db, 'usuarios', 'emp1')));
    await assertSucceeds(updateDoc(doc(db, 'usuarios', 'emp1'), { activo: false }));
    await assertSucceeds(setDoc(doc(db, 'usuarios', 'nuevo'), nuevoUsuario('empleado')));
  });

  it('empleado activo lee su doc y la lista de usuarios', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDoc(doc(db, 'usuarios', 'emp1')));
    await assertSucceeds(getDocs(collection(db, 'usuarios')));
  });

  it('empleado activo puede cambiar su nombre', async () => {
    await assertSucceeds(updateDoc(doc(como(env, 'emp1'), 'usuarios', 'emp1'), { nombre: 'Nuevo' }));
  });

  it('empleado no puede cambiar su rol', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'usuarios', 'emp1'), { rol: 'dueno' }));
  });

  it('empleado no puede cambiar su activo', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'usuarios', 'emp1'), { activo: false }));
  });

  it('empleado no edita a otro usuario ni crea usuarios', async () => {
    const db = como(env, 'emp1');
    await assertFails(updateDoc(doc(db, 'usuarios', 'emp2'), { nombre: 'X' }));
    await assertFails(setDoc(doc(db, 'usuarios', 'otro'), nuevoUsuario('dueno')));
  });

  it('empleado inactivo lee su propio doc pero no la lista ni otros', async () => {
    const db = como(env, 'inact');
    await assertSucceeds(getDoc(doc(db, 'usuarios', 'inact')));
    await assertFails(getDocs(collection(db, 'usuarios')));
    await assertFails(getDoc(doc(db, 'usuarios', 'emp1')));
  });

  it('empleado inactivo no puede modificar su doc', async () => {
    await assertFails(updateDoc(doc(como(env, 'inact'), 'usuarios', 'inact'), { nombre: 'X' }));
  });

  it('dueño inactivo no escribe usuarios', async () => {
    await assertFails(updateDoc(doc(como(env, 'duenoInact'), 'usuarios', 'emp1'), { nombre: 'X' }));
  });

  it('no autenticado no lee usuarios', async () => {
    const db = anonimo(env);
    await assertFails(getDocs(collection(db, 'usuarios')));
    await assertFails(getDoc(doc(db, 'usuarios', 'emp1')));
  });

  it('autenticado sin doc de usuario no lee nada', async () => {
    const db = como(env, 'fantasma');
    await assertFails(getDocs(collection(db, 'usuarios')));
    await assertFails(getDoc(doc(db, 'usuarios', 'emp1')));
    await assertFails(getDoc(doc(db, 'usuarios_privado', 'fantasma')));
    await assertFails(getDoc(doc(db, 'config', 'general')));
    await assertFails(getDoc(doc(db, 'otra', 'x')));
  });
});

describe('usuarios_privado', () => {
  it('empleado no lee ni escribe el suyo', async () => {
    const db = como(env, 'emp1');
    await assertFails(getDoc(doc(db, 'usuarios_privado', 'emp1')));
    await assertFails(setDoc(doc(db, 'usuarios_privado', 'emp1'), { pin: '1' }));
  });

  it('dueño activo lee y escribe', async () => {
    const db = como(env, 'dueno1');
    await assertSucceeds(setDoc(doc(db, 'usuarios_privado', 'emp1'), { pin: '1' }));
    await assertSucceeds(getDoc(doc(db, 'usuarios_privado', 'emp1')));
  });

  it('dueño inactivo no escribe', async () => {
    await assertFails(setDoc(doc(como(env, 'duenoInact'), 'usuarios_privado', 'x'), { a: 1 }));
  });
});

describe('config', () => {
  it('empleado no lee config/general', async () => {
    await assertFails(getDoc(doc(como(env, 'emp1'), 'config', 'general')));
  });

  it('dueño lee y escribe config/general', async () => {
    const db = como(env, 'dueno1');
    await assertSucceeds(setDoc(doc(db, 'config', 'general'), { moneda: 'MXN' }));
    await assertSucceeds(getDoc(doc(db, 'config', 'general')));
  });
});
