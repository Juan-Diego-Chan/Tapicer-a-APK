import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  Timestamp,
  where,
  type Firestore,
} from 'firebase/firestore';
import { como, crearEntorno, sembrarUsuario } from './ayuda';

let env: RulesTestEnvironment;

async function sembrar(ruta: string, id: string, datos: Record<string, unknown>) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore() as unknown as Firestore, ruta, id), datos);
  });
}

const cambio = (extra: Record<string, unknown> = {}) => ({
  campo: 'envio',
  muebleId: null,
  anterior: 0,
  nuevo: 100,
  motivo: null,
  usuarioId: 'due1',
  fecha: Timestamp.fromDate(new Date('2026-11-05T12:00:00Z')),
  ...extra,
});

beforeAll(async () => {
  env = await crearEntorno();
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await sembrarUsuario(env, 'emp1', { rol: 'empleado', activo: true });
  await sembrarUsuario(env, 'due1', { rol: 'dueno', activo: true });
  await sembrar('pedidos/pe1/cambios_precio', 'c1', cambio());
  await sembrar('pedidos/pe2/cambios_precio', 'c2', cambio({ nuevo: 200 }));
});

const consultaCambios = (db: Firestore) =>
  query(
    collectionGroup(db, 'cambios_precio'),
    where('fecha', '>=', Timestamp.fromDate(new Date('2026-11-01T00:00:00Z'))),
    where('fecha', '<', Timestamp.fromDate(new Date('2026-12-01T00:00:00Z'))),
  );

describe('cambios de precio del periodo', () => {
  it('el dueño consulta el grupo por rango de fecha y recibe 2 documentos', async () => {
    const r = await assertSucceeds(getDocs(consultaCambios(como(env, 'due1'))));
    if (r.size !== 2) throw new Error(`se esperaban 2, llegaron ${r.size}`);
  });

  it('el empleado no puede hacer esa consulta', async () => {
    await assertFails(getDocs(consultaCambios(como(env, 'emp1'))));
  });

  it('el empleado no lee un cambio de precio directo', async () => {
    await assertFails(getDoc(doc(como(env, 'emp1'), 'pedidos', 'pe1', 'cambios_precio', 'c1')));
  });
});

describe('pedidos entregados', () => {
  it('el dueño consulta estado entregado con fechaEntregado >= t', async () => {
    const db = como(env, 'due1');
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'pedidos'),
          where('estado', '==', 'entregado'),
          where('fechaEntregado', '>=', Timestamp.fromDate(new Date('2026-11-01T00:00:00Z'))),
        ),
      ),
    );
  });
});
