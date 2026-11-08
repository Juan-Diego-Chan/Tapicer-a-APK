import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
  type Firestore,
} from 'firebase/firestore';
import { como, crearEntorno, sembrarUsuario } from './ayuda';

let env: RulesTestEnvironment;

const pedido = (extra: Record<string, unknown> = {}) => ({
  folio: '261107-PAGO',
  clienteId: 'cl1',
  cliente: { nombre: 'Ana López', telefono: '999 123 4567', direccion: 'Calle 60 #123' },
  entrega: 'recoge',
  envio: 0,
  comentarios: '',
  fechaIngreso: Timestamp.now(),
  fechaEstimada: Timestamp.now(),
  fechaTerminado: null,
  fechaEntregado: null,
  estado: 'recibido',
  creadoPor: 'emp1',
  ultimoCambioId: null,
  ...extra,
});

const mueble = (extra: Record<string, unknown> = {}) => ({
  tipoTrabajo: 'reparacion',
  tipoMueble: 'Sillón',
  plantillaId: null,
  precio: 650,
  comentarios: '',
  estado: 'recibido',
  ultimoCambioId: null,
  ...extra,
});

const pago = (extra: Record<string, unknown> = {}) => ({
  pedidoId: 'pe1',
  monto: 500,
  forma: 'efectivo',
  recibidoPor: 'emp1',
  fecha: serverTimestamp(),
  ...extra,
});

async function sembrar(ruta: string, id: string, datos: Record<string, unknown>) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore() as unknown as Firestore, ruta, id), datos);
  });
}

async function leer(ruta: string, id: string) {
  let datos: Record<string, unknown> | undefined;
  await env.withSecurityRulesDisabled(async (ctx) => {
    datos = (await getDoc(doc(ctx.firestore() as unknown as Firestore, ruta, id))).data();
  });
  return datos;
}

// Lote de cobro como lo escribe ServicioDinero.
function loteCobro(
  db: Firestore,
  uid: string,
  monto: number,
  {
    pagoExtra = {},
    incPedido = monto,
    conCaja = true,
    cajaDe = uid,
    pedidoId = 'pe1',
  }: {
    pagoExtra?: Record<string, unknown>;
    incPedido?: number;
    conCaja?: boolean;
    cajaDe?: string;
    pedidoId?: string;
  } = {},
) {
  const ref = doc(collection(db, 'pagos'));
  const b = writeBatch(db);
  b.set(ref, pago({ pedidoId, monto, recibidoPor: uid, ...pagoExtra }));
  b.update(doc(db, 'pedidos', pedidoId), { pagado: increment(incPedido), ultimoPagoId: ref.id });
  if (conCaja) {
    b.set(doc(db, 'cajas', cajaDe), { enMano: increment(monto), ultimoPagoId: ref.id }, { merge: true });
  }
  return { b, id: ref.id };
}

// Borrado de un pago (dueño).
function loteBorrado(
  db: Firestore,
  id: string,
  monto: number,
  { cajaDe = 'emp1' as string | null, pedidoId = 'pe1' } = {},
) {
  const b = writeBatch(db);
  b.delete(doc(db, 'pagos', id));
  b.update(doc(db, 'pedidos', pedidoId), { pagado: increment(-monto), ultimoPagoId: id });
  if (cajaDe) b.update(doc(db, 'cajas', cajaDe), { enMano: increment(-monto), ultimoPagoId: id });
  return b;
}

beforeAll(async () => {
  env = await crearEntorno();
});
afterAll(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await sembrarUsuario(env, 'emp1', { rol: 'empleado', activo: true });
  await sembrarUsuario(env, 'emp2', { rol: 'empleado', activo: true });
  await sembrarUsuario(env, 'due1', { rol: 'dueno', activo: true });
  await sembrar('pedidos', 'pe1', pedido());
});

describe('cobro de un empleado', () => {
  it('emp1 cobra $500 y luego $300: pagado y enMano suben', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(loteCobro(db, 'emp1', 500).b.commit());
    expect((await leer('pedidos', 'pe1'))?.pagado).toBe(500);
    expect((await leer('cajas', 'emp1'))?.enMano).toBe(500);

    await assertSucceeds(loteCobro(db, 'emp1', 300).b.commit());
    expect((await leer('pedidos', 'pe1'))?.pagado).toBe(800);
    expect((await leer('cajas', 'emp1'))?.enMano).toBe(800);
  });

  it('cobrar sin escribir su caja falla', async () => {
    await assertFails(loteCobro(como(env, 'emp1'), 'emp1', 500, { conCaja: false }).b.commit());
  });

  it('pagado +400 con un pago de 500 falla', async () => {
    await assertFails(loteCobro(como(env, 'emp1'), 'emp1', 500, { incPedido: 400 }).b.commit());
  });

  it("un pago con recibidoPor 'emp2' falla", async () => {
    await assertFails(
      loteCobro(como(env, 'emp1'), 'emp1', 500, { pagoExtra: { recibidoPor: 'emp2' } }).b.commit(),
    );
  });

  it('un pago de -100 del empleado falla', async () => {
    await assertFails(loteCobro(como(env, 'emp1'), 'emp1', -100).b.commit());
  });

  it('un pago de 0 o con forma inválida falla', async () => {
    await assertFails(loteCobro(como(env, 'emp1'), 'emp1', 0).b.commit());
    await assertFails(loteCobro(como(env, 'emp1'), 'emp1', 500, { pagoExtra: { forma: 'cheque' } }).b.commit());
  });

  it('subir el pedido sin pago falla', async () => {
    await assertFails(
      updateDoc(doc(como(env, 'emp1'), 'pedidos', 'pe1'), { pagado: increment(500), ultimoPagoId: 'zz' }),
    );
  });

  it('subir su caja sin pago falla', async () => {
    await assertFails(
      setDoc(doc(como(env, 'emp1'), 'cajas', 'emp1'), { enMano: increment(500), ultimoPagoId: 'zz' }, { merge: true }),
    );
  });

  it('subir su caja con un pago que ya existía falla', async () => {
    const db = como(env, 'emp1');
    const { b, id } = loteCobro(db, 'emp1', 500);
    await assertSucceeds(b.commit());
    // Otro lote sin cambiar el id: el pedido no cambia y la caja reutiliza el pago.
    await assertFails(setDoc(doc(db, 'cajas', 'emp1'), { enMano: increment(500), ultimoPagoId: id }, { merge: true }));
    // Con otro id intermedio y volviendo al pago viejo, tampoco.
    await sembrar('cajas', 'emp1', { enMano: 500, ultimoPagoId: 'otro' });
    await assertFails(setDoc(doc(db, 'cajas', 'emp1'), { enMano: increment(500), ultimoPagoId: id }, { merge: true }));
  });

  it('cobrar y subir la caja de emp2 falla', async () => {
    await assertFails(loteCobro(como(env, 'emp1'), 'emp1', 500, { cajaDe: 'emp2' }).b.commit());
    await assertFails(
      setDoc(doc(como(env, 'emp1'), 'cajas', 'emp2'), { enMano: increment(500), ultimoPagoId: 'zz' }, { merge: true }),
    );
  });

  it('el pedido sigue sin pagado y se actualiza normalmente (Plan 3)', async () => {
    await assertSucceeds(updateDoc(doc(como(env, 'emp1'), 'pedidos', 'pe1'), { comentarios: 'Llamar antes' }));
  });
});

describe('lecturas', () => {
  beforeEach(async () => {
    await sembrar('cajas', 'emp1', { enMano: 100, ultimoPagoId: 'pg1' });
    await sembrar('cajas', 'emp2', { enMano: 200, ultimoPagoId: 'pg2' });
    await sembrar('pagos', 'pg1', pago({ monto: 100, fecha: Timestamp.now() }));
    await sembrar('pagos', 'pg2', pago({ monto: 200, recibidoPor: 'emp2', fecha: Timestamp.now() }));
  });

  it('emp1 lee su caja; la de emp2, no', async () => {
    await assertSucceeds(getDoc(doc(como(env, 'emp1'), 'cajas', 'emp1')));
    await assertFails(getDoc(doc(como(env, 'emp1'), 'cajas', 'emp2')));
  });

  it('el dueño lee cualquier caja', async () => {
    await assertSucceeds(getDoc(doc(como(env, 'due1'), 'cajas', 'emp2')));
  });

  it('emp1 lista sus pagos con el filtro; sin filtro, no', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDocs(query(collection(db, 'pagos'), where('recibidoPor', '==', 'emp1'))));
    await assertFails(getDocs(collection(db, 'pagos')));
  });
});

describe('cobros y devoluciones del dueño', () => {
  it('due1 cobra $200 sin caja', async () => {
    await assertSucceeds(loteCobro(como(env, 'due1'), 'due1', 200, { conCaja: false }).b.commit());
    expect((await leer('pedidos', 'pe1'))?.pagado).toBe(200);
  });

  it('due1 registra una devolución de -200; una que deja pagado < 0 falla', async () => {
    const db = como(env, 'due1');
    await assertSucceeds(loteCobro(db, 'due1', 200, { conCaja: false }).b.commit());
    await assertSucceeds(loteCobro(db, 'due1', -200, { conCaja: false }).b.commit());
    expect((await leer('pedidos', 'pe1'))?.pagado).toBe(0);
    await assertFails(loteCobro(db, 'due1', -200, { conCaja: false }).b.commit());
  });
});

describe('borrado de pagos', () => {
  let id300: string;
  beforeEach(async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(loteCobro(db, 'emp1', 500).b.commit());
    const lote = loteCobro(db, 'emp1', 300);
    id300 = lote.id;
    await assertSucceeds(lote.b.commit());
  });

  it('due1 borra el pago de $300 descontando pedido y caja', async () => {
    await assertSucceeds(loteBorrado(como(env, 'due1'), id300, 300).commit());
    expect((await leer('pedidos', 'pe1'))?.pagado).toBe(500);
    expect((await leer('cajas', 'emp1'))?.enMano).toBe(500);
    expect(await leer('pagos', id300)).toBeUndefined();
  });

  it('borrarlo sin descontar la caja falla', async () => {
    await assertFails(loteBorrado(como(env, 'due1'), id300, 300, { cajaDe: null }).commit());
  });

  it('borrarlo descontando otra cantidad falla', async () => {
    await assertFails(loteBorrado(como(env, 'due1'), id300, 200).commit());
  });

  it('emp1 no borra un pago', async () => {
    await assertFails(loteBorrado(como(env, 'emp1'), id300, 300).commit());
    await assertFails(deleteDoc(doc(como(env, 'emp1'), 'pagos', id300)));
  });

  it('nadie actualiza un pago', async () => {
    await assertFails(updateDoc(doc(como(env, 'due1'), 'pagos', id300), { forma: 'transferencia' }));
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'pagos', id300), { forma: 'transferencia' }));
  });

  it('residuos: pagos de 0.1 y 0.2, y el dueño borra el de 0.1', async () => {
    await sembrar('pedidos', 'pe2', pedido());
    const db = como(env, 'emp1');
    const a = loteCobro(db, 'emp1', 0.1, { pedidoId: 'pe2' });
    await assertSucceeds(a.b.commit());
    await assertSucceeds(loteCobro(db, 'emp1', 0.2, { pedidoId: 'pe2' }).b.commit());
    await assertSucceeds(loteBorrado(como(env, 'due1'), a.id, 0.1, { pedidoId: 'pe2' }).commit());
  });
});

describe('pedido nuevo con anticipo', () => {
  function loteAnticipo(db: Firestore, { conPago = true } = {}) {
    const pedidoRef = doc(collection(db, 'pedidos'));
    const pagoRef = doc(collection(db, 'pagos'));
    const b = writeBatch(db);
    b.set(pedidoRef, pedido({ pagado: 500, ultimoPagoId: pagoRef.id }));
    b.set(doc(collection(db, 'pedidos', pedidoRef.id, 'muebles')), mueble());
    if (conPago) {
      b.set(pagoRef, pago({ pedidoId: pedidoRef.id, monto: 500 }));
      b.set(doc(db, 'cajas', 'emp1'), { enMano: increment(500), ultimoPagoId: pagoRef.id }, { merge: true });
    }
    return b;
  }

  it('anticipo de $500 en el mismo lote (pedido, mueble, pago y caja)', async () => {
    await assertSucceeds(loteAnticipo(como(env, 'emp1')).commit());
  });

  it('pagado: 500 sin pago falla', async () => {
    await assertFails(loteAnticipo(como(env, 'emp1'), { conPago: false }).commit());
  });
});

describe('borrado de pedidos', () => {
  it('due1 no borra un pedido con pagado 500; con pagado 0, sí', async () => {
    await sembrar('pedidos', 'pe1', pedido({ pagado: 500, ultimoPagoId: 'pgx' }));
    await assertFails(deleteDoc(doc(como(env, 'due1'), 'pedidos', 'pe1')));
    await sembrar('pedidos', 'pe1', pedido({ pagado: 0, ultimoPagoId: 'pgx' }));
    await assertSucceeds(deleteDoc(doc(como(env, 'due1'), 'pedidos', 'pe1')));
  });
});
