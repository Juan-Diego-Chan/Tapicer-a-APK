import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  serverTimestamp,
  setDoc,
  Timestamp,
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

const rollo = (extra: Record<string, unknown> = {}) => ({
  materialId: 'm1',
  codigo: 'R-1',
  cantidadInicial: 50,
  existencia: 50,
  fechaCompra: Timestamp.now(),
  ...extra,
});

const movimiento = (extra: Record<string, unknown> = {}) => ({
  tipo: 'compra',
  materialId: 'm1',
  cantidad: 5,
  usuarioId: 'dueno1',
  fecha: Timestamp.now(),
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
  await sembrar('rollos', 'r1', rollo());
  await sembrar('rollos_costos', 'r1', { costo: 100 });
  await sembrar('compras', 'c1', { materialId: 'm1', total: 100 });
  await sembrar('movimientos', 'mv1', movimiento());
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

  it('dueño no crea material sin nombre', async () => {
    const { nombre: _n, ...sinNombre } = material();
    await assertFails(setDoc(doc(como(env, 'dueno1'), 'materiales', 'nuevo'), sinNombre));
  });

  it('dueño no crea material sin usaRollos', async () => {
    const { usaRollos: _u, ...sinUsa } = material();
    await assertFails(setDoc(doc(como(env, 'dueno1'), 'materiales', 'nuevo'), sinUsa));
  });

  it('dueño no crea material con campo extra', async () => {
    await assertFails(setDoc(doc(como(env, 'dueno1'), 'materiales', 'nuevo'), material({ costo: 50 })));
  });

  it('empleado no mezcla marcadoAgotandose con existencia', async () => {
    await assertFails(
      updateDoc(doc(como(env, 'emp1'), 'materiales', 'm1'), { marcadoAgotandose: true, existencia: 99 }),
    );
  });

  it('usuario sin doc en usuarios no lee materiales, rollos ni movimientos', async () => {
    const db = como(env, 'fantasma');
    await assertFails(getDocs(collection(db, 'materiales')));
    await assertFails(getDoc(doc(db, 'rollos', 'r1')));
    await assertFails(getDocs(collection(db, 'movimientos')));
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
    await assertFails(getDocs(collection(db, ruta)));
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
    await assertFails(setDoc(doc(db, 'rollos', 'nuevo'), rollo()));
    await assertFails(updateDoc(doc(db, 'rollos', 'r1'), { existencia: 1 }));
  });

  it('dueño escribe', async () => {
    await assertSucceeds(setDoc(doc(como(env, 'dueno1'), 'rollos', 'nuevo'), rollo()));
  });

  it('dueño no crea rollo con cantidadInicial 0', async () => {
    await assertFails(setDoc(doc(como(env, 'dueno1'), 'rollos', 'nuevo'), rollo({ cantidadInicial: 0 })));
  });

  it('dueño descuenta existencia de un rollo con increment(-2)', async () => {
    await assertSucceeds(updateDoc(doc(como(env, 'dueno1'), 'rollos', 'r1'), { existencia: increment(-2) }));
  });
});

describe('movimientos', () => {
  it('empleado lee pero no crea', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDoc(doc(db, 'movimientos', 'mv1')));
    await assertFails(setDoc(doc(db, 'movimientos', 'nuevo'), movimiento({ tipo: 'consumo', usuarioId: 'emp1' })));
  });

  it('dueño crea un movimiento válido', async () => {
    const db = como(env, 'dueno1');
    await assertSucceeds(setDoc(doc(db, 'movimientos', 'nuevo'), movimiento()));
    await assertSucceeds(
      setDoc(doc(db, 'movimientos', 'n2'), movimiento({ rolloId: 'r1', pedidoId: null, fecha: serverTimestamp() })),
    );
  });

  it('dueño no crea movimientos mal formados', async () => {
    const db = como(env, 'dueno1');
    await assertFails(setDoc(doc(db, 'movimientos', 'x'), movimiento({ cantidad: '5' })));
    await assertFails(setDoc(doc(db, 'movimientos', 'x'), movimiento({ usuarioId: 'emp1' })));
    await assertFails(setDoc(doc(db, 'movimientos', 'x'), movimiento({ tipo: 'robo' })));
  });

  it('nadie actualiza ni borra un movimiento', async () => {
    for (const uid of ['dueno1', 'emp1']) {
      const db = como(env, uid);
      await assertFails(updateDoc(doc(db, 'movimientos', 'mv1'), { cantidad: 1 }));
      await assertFails(deleteDoc(doc(db, 'movimientos', 'mv1')));
    }
  });
});
