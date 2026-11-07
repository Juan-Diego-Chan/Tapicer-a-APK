import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  setDoc,
  updateDoc,
  type Firestore,
} from 'firebase/firestore';
import { como, crearEntorno, sembrarUsuario } from './ayuda';

let env: RulesTestEnvironment;

const material = (extra: Record<string, unknown> = {}) => ({
  nombre: 'Tela gris',
  categoria: 'tela',
  unidad: 'm',
  stockMinimo: 10,
  existencia: 0,
  usaRollos: true,
  marcadoAgotandose: false,
  ...extra,
});

async function sembrar(ruta: string, id: string, datos: Record<string, unknown>) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore() as unknown as Firestore, ruta, id), datos);
  });
}

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
  await sembrarUsuario(env, 'inact', { rol: 'empleado', activo: false });
  await sembrar('materiales', 'm1', material());
  await sembrar('materiales_costos', 'm1', { costoPromedio: 5 });
  await sembrar('rollos', 'r1', { materialId: 'm1', largo: 50 });
  await sembrar('rollos_costos', 'r1', { costo: 100 });
  await sembrar('compras', 'c1', { materialId: 'm1', total: 100 });
  await sembrar('movimientos', 'mv1', { materialId: 'm1', tipo: 'entrada', cantidad: 5 });
});

describe('materiales', () => {
  it('dueño crea un material válido', async () => {
    await assertSucceeds(setDoc(doc(como(env, 'dueno1'), 'materiales', 'nuevo'), material()));
  });

  it('dueño no crea categoría inválida', async () => {
    await assertFails(
      setDoc(doc(como(env, 'dueno1'), 'materiales', 'nuevo'), material({ categoria: 'madera' })),
    );
  });

  it('dueño no crea con nombre que no es string', async () => {
    await assertFails(
      setDoc(doc(como(env, 'dueno1'), 'materiales', 'nuevo'), material({ nombre: 123 })),
    );
  });

  it('dueño incrementa existencia con increment', async () => {
    await assertSucceeds(updateDoc(doc(como(env, 'dueno1'), 'materiales', 'm1'), { existencia: increment(5) }));
  });

  it('dueño no pone stockMinimo negativo', async () => {
    await assertFails(updateDoc(doc(como(env, 'dueno1'), 'materiales', 'm1'), { stockMinimo: -1 }));
  });

  it('empleado activo lee lista y documento', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDocs(collection(db, 'materiales')));
    await assertSucceeds(getDoc(doc(db, 'materiales', 'm1')));
  });

  it('empleado puede marcar agotándose en true', async () => {
    await assertSucceeds(updateDoc(doc(como(env, 'emp1'), 'materiales', 'm1'), { marcadoAgotandose: true }));
  });

  it('empleado no puede poner marcadoAgotandose en false', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'materiales', 'm1'), { marcadoAgotandose: false }));
  });

  it('empleado no cambia existencia, stockMinimo ni nombre', async () => {
    const ref = doc(como(env, 'emp1'), 'materiales', 'm1');
    await assertFails(updateDoc(ref, { existencia: 99 }));
    await assertFails(updateDoc(ref, { stockMinimo: 1 }));
    await assertFails(updateDoc(ref, { nombre: 'Otro' }));
  });

  it('empleado no crea ni borra materiales', async () => {
    const db = como(env, 'emp1');
    await assertFails(setDoc(doc(db, 'materiales', 'nuevo'), material()));
    await assertFails(deleteDoc(doc(db, 'materiales', 'm1')));
  });

  it('empleado inactivo no lee', async () => {
    await assertFails(getDoc(doc(como(env, 'inact'), 'materiales', 'm1')));
  });
});

describe.each([
  ['materiales_costos', 'm1', { costoPromedio: 9 }],
  ['rollos_costos', 'r1', { costo: 9 }],
  ['compras', 'c1', { total: 9 }],
])('%s (solo dueño)', (ruta, id, datos) => {
  it('empleado no lee ni escribe', async () => {
    const db = como(env, 'emp1');
    await assertFails(getDoc(doc(db, ruta, id)));
    await assertFails(setDoc(doc(db, ruta, 'otro'), datos));
    await assertFails(updateDoc(doc(db, ruta, id), datos));
  });

  it('dueño lee y escribe', async () => {
    const db = como(env, 'dueno1');
    await assertSucceeds(getDoc(doc(db, ruta, id)));
    await assertSucceeds(setDoc(doc(db, ruta, 'otro'), datos));
  });
});

describe('rollos', () => {
  it('empleado lee pero no escribe', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDoc(doc(db, 'rollos', 'r1')));
    await assertFails(setDoc(doc(db, 'rollos', 'nuevo'), { materialId: 'm1', largo: 1 }));
    await assertFails(updateDoc(doc(db, 'rollos', 'r1'), { largo: 1 }));
  });

  it('dueño escribe', async () => {
    await assertSucceeds(setDoc(doc(como(env, 'dueno1'), 'rollos', 'nuevo'), { materialId: 'm1', largo: 1 }));
  });
});

describe('movimientos', () => {
  it('empleado lee pero no crea', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDoc(doc(db, 'movimientos', 'mv1')));
    await assertFails(setDoc(doc(db, 'movimientos', 'nuevo'), { materialId: 'm1', tipo: 'salida' }));
  });

  it('dueño crea', async () => {
    await assertSucceeds(setDoc(doc(como(env, 'dueno1'), 'movimientos', 'nuevo'), { materialId: 'm1', tipo: 'entrada' }));
  });

  it('nadie actualiza ni borra un movimiento', async () => {
    for (const uid of ['dueno1', 'emp1']) {
      const db = como(env, uid);
      await assertFails(updateDoc(doc(db, 'movimientos', 'mv1'), { cantidad: 1 }));
      await assertFails(deleteDoc(doc(db, 'movimientos', 'mv1')));
    }
  });
});
