import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  addDoc,
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

const entrega = (extra: Record<string, unknown> = {}) => ({
  empleadoId: 'emp1',
  monto: 300,
  forma: 'efectivo',
  fecha: serverTimestamp(),
  estado: 'pendiente',
  revisadoEn: null,
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

// Lote de confirmación como lo escribe ServicioDinero (dueño).
function loteConfirmar(
  db: Firestore,
  id: string,
  monto: number,
  {
    conEntrega = true,
    conCaja = true,
    cajaDe = 'emp1',
  }: { conEntrega?: boolean; conCaja?: boolean; cajaDe?: string } = {},
) {
  const b = writeBatch(db);
  if (conEntrega) {
    b.update(doc(db, 'entregas', id), { estado: 'confirmada', revisadoEn: serverTimestamp() });
  }
  if (conCaja) {
    b.set(doc(db, 'cajas', cajaDe), { enMano: increment(-monto), ultimaEntregaId: id }, { merge: true });
  }
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
});

describe('registro de entregas (empleado)', () => {
  it('emp1 registra una entrega pendiente', async () => {
    await assertSucceeds(addDoc(collection(como(env, 'emp1'), 'entregas'), entrega()));
  });

  it("con estado 'confirmada' falla", async () => {
    await assertFails(addDoc(collection(como(env, 'emp1'), 'entregas'), entrega({ estado: 'confirmada' })));
  });

  it("con empleadoId 'emp2' falla", async () => {
    await assertFails(addDoc(collection(como(env, 'emp1'), 'entregas'), entrega({ empleadoId: 'emp2' })));
  });

  it('con monto 0 falla', async () => {
    await assertFails(addDoc(collection(como(env, 'emp1'), 'entregas'), entrega({ monto: 0 })));
  });

  it('con forma inválida, fecha pasada o revisadoEn falla', async () => {
    const db = como(env, 'emp1');
    await assertFails(addDoc(collection(db, 'entregas'), entrega({ forma: 'cheque' })));
    await assertFails(addDoc(collection(db, 'entregas'), entrega({ fecha: Timestamp.fromMillis(0) })));
    await assertFails(addDoc(collection(db, 'entregas'), entrega({ revisadoEn: serverTimestamp() })));
  });

  it('due1 registra una entrega → falla', async () => {
    await assertFails(
      addDoc(collection(como(env, 'due1'), 'entregas'), entrega({ empleadoId: 'due1' })),
    );
  });
});

describe('lecturas de entregas', () => {
  beforeEach(async () => {
    await sembrar('entregas', 'en1', entrega({ fecha: Timestamp.now() }));
    await sembrar('entregas', 'en2', entrega({ empleadoId: 'emp2', fecha: Timestamp.now() }));
  });

  it('emp1 lee su entrega; la de emp2, no', async () => {
    await assertSucceeds(getDoc(doc(como(env, 'emp1'), 'entregas', 'en1')));
    await assertFails(getDoc(doc(como(env, 'emp1'), 'entregas', 'en2')));
  });

  it('emp1 lista sus entregas con el filtro; sin filtro, no', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDocs(query(collection(db, 'entregas'), where('empleadoId', '==', 'emp1'))));
    await assertFails(getDocs(collection(db, 'entregas')));
  });

  it('el dueño lee cualquier entrega', async () => {
    await assertSucceeds(getDoc(doc(como(env, 'due1'), 'entregas', 'en2')));
  });
});

describe('revisión de entregas (dueño)', () => {
  beforeEach(async () => {
    await sembrar('cajas', 'emp1', { enMano: 800, ultimoPagoId: 'pg1' });
    await sembrar('entregas', 'en1', entrega({ fecha: Timestamp.now() }));
  });

  it('emp1 confirma su propia entrega → falla', async () => {
    await assertFails(loteConfirmar(como(env, 'emp1'), 'en1', 300).commit());
    await assertFails(
      updateDoc(doc(como(env, 'emp1'), 'entregas', 'en1'), { estado: 'confirmada', revisadoEn: serverTimestamp() }),
    );
  });

  it('due1 confirma la entrega de $300: la caja de emp1 queda en 500', async () => {
    await assertSucceeds(loteConfirmar(como(env, 'due1'), 'en1', 300).commit());
    expect((await leer('cajas', 'emp1'))?.enMano).toBe(500);
    expect((await leer('cajas', 'emp1'))?.ultimoPagoId).toBe('pg1');
    expect((await leer('entregas', 'en1'))?.estado).toBe('confirmada');
  });

  it('confirmar sin descontar la caja falla', async () => {
    await assertFails(loteConfirmar(como(env, 'due1'), 'en1', 300, { conCaja: false }).commit());
  });

  it('descontar la caja sin confirmar falla', async () => {
    await assertFails(loteConfirmar(como(env, 'due1'), 'en1', 300, { conEntrega: false }).commit());
  });

  it('confirmar descontando otra cantidad falla', async () => {
    await assertFails(loteConfirmar(como(env, 'due1'), 'en1', 200).commit());
    await assertFails(loteConfirmar(como(env, 'due1'), 'en1', 400).commit());
  });

  it('confirmar descontando la caja de otro empleado falla', async () => {
    await sembrar('cajas', 'emp2', { enMano: 800 });
    await assertFails(loteConfirmar(como(env, 'due1'), 'en1', 300, { cajaDe: 'emp2' }).commit());
  });

  it('confirmar cambiando ultimoPagoId de la caja falla', async () => {
    const db = como(env, 'due1');
    const b = writeBatch(db);
    b.update(doc(db, 'entregas', 'en1'), { estado: 'confirmada', revisadoEn: serverTimestamp() });
    b.set(
      doc(db, 'cajas', 'emp1'),
      { enMano: increment(-300), ultimaEntregaId: 'en1', ultimoPagoId: 'otro' },
      { merge: true },
    );
    await assertFails(b.commit());
  });

  it('due1 confirma una entrega ya confirmada o rechazada → falla', async () => {
    const db = como(env, 'due1');
    await assertSucceeds(loteConfirmar(db, 'en1', 300).commit());
    await assertFails(loteConfirmar(db, 'en1', 300).commit());
    // Descontar otra vez la caja apuntando a la entrega ya confirmada, tampoco.
    await assertFails(
      setDoc(doc(db, 'cajas', 'emp1'), { enMano: increment(-300), ultimaEntregaId: 'en1' }, { merge: true }),
    );

    await sembrar('entregas', 'en2', entrega({ estado: 'rechazada', revisadoEn: Timestamp.now(), fecha: Timestamp.now() }));
    await assertFails(loteConfirmar(db, 'en2', 300).commit());
    expect((await leer('cajas', 'emp1'))?.enMano).toBe(500);
  });

  it('due1 rechaza una entrega y la caja no cambia', async () => {
    await assertSucceeds(
      updateDoc(doc(como(env, 'due1'), 'entregas', 'en1'), { estado: 'rechazada', revisadoEn: serverTimestamp() }),
    );
    expect((await leer('entregas', 'en1'))?.estado).toBe('rechazada');
    expect((await leer('cajas', 'emp1'))?.enMano).toBe(800);
  });

  it('rechazar cambiando el monto o con revisadoEn pasado falla', async () => {
    const db = como(env, 'due1');
    await assertFails(
      updateDoc(doc(db, 'entregas', 'en1'), { estado: 'rechazada', revisadoEn: serverTimestamp(), monto: 10 }),
    );
    await assertFails(
      updateDoc(doc(db, 'entregas', 'en1'), { estado: 'rechazada', revisadoEn: Timestamp.fromMillis(0) }),
    );
  });

  it('nadie borra una entrega', async () => {
    await assertFails(deleteDoc(doc(como(env, 'due1'), 'entregas', 'en1')));
    await assertFails(deleteDoc(doc(como(env, 'emp1'), 'entregas', 'en1')));
  });

  it('confirmar la entrega de un empleado sin caja: la caja queda en -300', async () => {
    await sembrar('entregas', 'en3', entrega({ empleadoId: 'emp2', fecha: Timestamp.now() }));
    await assertSucceeds(loteConfirmar(como(env, 'due1'), 'en3', 300, { cajaDe: 'emp2' }).commit());
    expect((await leer('cajas', 'emp2'))?.enMano).toBe(-300);
  });
});

describe('pagos de sueldo', () => {
  const sueldo = (extra: Record<string, unknown> = {}) => ({
    usuarioId: 'emp1',
    monto: 1500,
    fecha: Timestamp.fromDate(new Date('2026-11-01T12:00:00')),
    ...extra,
  });

  it('due1 crea uno con una fecha pasada; emp1, no', async () => {
    await assertSucceeds(addDoc(collection(como(env, 'due1'), 'pagos_sueldo'), sueldo()));
    await assertFails(addDoc(collection(como(env, 'emp1'), 'pagos_sueldo'), sueldo()));
  });

  it('emp1 lee uno → falla', async () => {
    await sembrar('pagos_sueldo', 'ps1', sueldo());
    await assertFails(getDoc(doc(como(env, 'emp1'), 'pagos_sueldo', 'ps1')));
    await assertSucceeds(getDoc(doc(como(env, 'due1'), 'pagos_sueldo', 'ps1')));
  });

  it('monto -5 → falla', async () => {
    await assertFails(addDoc(collection(como(env, 'due1'), 'pagos_sueldo'), sueldo({ monto: -5 })));
  });

  it('campos extra o actualizar → falla', async () => {
    await assertFails(addDoc(collection(como(env, 'due1'), 'pagos_sueldo'), sueldo({ nota: 'x' })));
    await sembrar('pagos_sueldo', 'ps1', sueldo());
    await assertFails(updateDoc(doc(como(env, 'due1'), 'pagos_sueldo', 'ps1'), { monto: 10 }));
  });

  it('due1 lo borra', async () => {
    await sembrar('pagos_sueldo', 'ps1', sueldo());
    await assertSucceeds(deleteDoc(doc(como(env, 'due1'), 'pagos_sueldo', 'ps1')));
    await assertFails(deleteDoc(doc(como(env, 'emp1'), 'pagos_sueldo', 'ps1')));
  });
});
