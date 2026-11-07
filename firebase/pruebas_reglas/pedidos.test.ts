import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
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

const cliente = (extra: Record<string, unknown> = {}) => ({
  nombre: 'Ana López',
  telefono: '999 123 4567',
  direccion: 'Calle 60 #123, Centro',
  ...extra,
});

const pedido = (extra: Record<string, unknown> = {}) => ({
  folio: '261107-ABCD',
  clienteId: 'cl1',
  cliente: cliente(),
  entrega: 'domicilio',
  envio: 200,
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

const cambio = (extra: Record<string, unknown> = {}) => ({
  campo: 'precio',
  muebleId: 'mu1',
  anterior: 650,
  nuevo: 600,
  motivo: null,
  usuarioId: 'emp1',
  fecha: serverTimestamp(),
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
  await sembrar('clientes', 'cl1', cliente());
  await sembrar('pedidos', 'p1', pedido());
  await sembrar('pedidos/p1/muebles', 'mu1', mueble());
  await sembrar('pedidos/p1/cambios_precio', 'cp0', cambio({ usuarioId: 'dueno1', fecha: Timestamp.now() }));
  await sembrar('plantillas', 'pl1', { tipoMueble: 'Sillón', lineas: [] });
});

describe('clientes', () => {
  it('empleado crea un cliente válido', async () => {
    await assertSucceeds(setDoc(doc(como(env, 'emp1'), 'clientes', 'nuevo'), cliente()));
  });

  it('empleado no crea cliente con nombre vacío', async () => {
    await assertFails(setDoc(doc(como(env, 'emp1'), 'clientes', 'nuevo'), cliente({ nombre: '' })));
  });

  it('empleado no crea cliente con campo extra', async () => {
    await assertFails(setDoc(doc(como(env, 'emp1'), 'clientes', 'nuevo'), cliente({ saldo: 100 })));
  });

  it('empleado no borra clientes; el dueño sí', async () => {
    await assertFails(deleteDoc(doc(como(env, 'emp1'), 'clientes', 'cl1')));
    await assertSucceeds(deleteDoc(doc(como(env, 'dueno1'), 'clientes', 'cl1')));
  });

  it('inactivo no lee clientes', async () => {
    await assertFails(getDoc(doc(como(env, 'inact'), 'clientes', 'cl1')));
  });
});

describe('pedido + muebles en un lote', () => {
  function lotePedido(
    db: Firestore,
    { p = {}, m = {}, pedidoId }: { p?: Record<string, unknown>; m?: Record<string, unknown>; pedidoId?: string } = {},
  ) {
    const pedidoRef = pedidoId ? doc(db, 'pedidos', pedidoId) : doc(collection(db, 'pedidos'));
    const b = writeBatch(db);
    b.set(pedidoRef, pedido(p));
    b.set(doc(collection(db, 'pedidos', pedidoRef.id, 'muebles')), mueble(m));
    b.set(doc(collection(db, 'pedidos', pedidoRef.id, 'muebles')), mueble({ tipoTrabajo: 'fabricacion', plantillaId: 'pl1', ...m }));
    return b;
  }

  it('empleado crea un pedido con 2 muebles', async () => {
    await assertSucceeds(lotePedido(como(env, 'emp1')).commit());
  });

  it('falla si creadoPor es otro uid', async () => {
    await assertFails(lotePedido(como(env, 'emp1'), { p: { creadoPor: 'dueno1' } }).commit());
  });

  it("falla con estado 'listo'", async () => {
    await assertFails(lotePedido(como(env, 'emp1'), { p: { estado: 'listo' } }).commit());
  });

  it('falla con envio -1', async () => {
    await assertFails(lotePedido(como(env, 'emp1'), { p: { envio: -1 } }).commit());
  });

  it('falla con envio NaN', async () => {
    await assertFails(lotePedido(como(env, 'emp1'), { p: { envio: NaN } }).commit());
  });

  it("falla si el mueble trae ultimoCambioId 'x'", async () => {
    await assertFails(lotePedido(como(env, 'emp1'), { m: { ultimoCambioId: 'x' } }).commit());
  });

  it('falla si el mueble se crea en un pedido que no existe', async () => {
    const db = como(env, 'emp1');
    await assertFails(setDoc(doc(db, 'pedidos', 'noexiste', 'muebles', 'x'), mueble()));
  });
});

describe('cambio de precio', () => {
  it('empleado cambia precio 650→600 con su registro en el mismo lote', async () => {
    const db = como(env, 'emp1');
    const c = doc(collection(db, 'pedidos', 'p1', 'cambios_precio'));
    const b = writeBatch(db);
    b.set(c, cambio());
    b.update(doc(db, 'pedidos', 'p1', 'muebles', 'mu1'), { precio: 600, ultimoCambioId: c.id });
    await assertSucceeds(b.commit());
  });

  it('cambiar precio sin registro falla', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'pedidos', 'p1', 'muebles', 'mu1'), { precio: 600 }));
  });

  it('cambiar precio con registro de anterior 700 falla', async () => {
    const db = como(env, 'emp1');
    const c = doc(collection(db, 'pedidos', 'p1', 'cambios_precio'));
    const b = writeBatch(db);
    b.set(c, cambio({ anterior: 700 }));
    b.update(doc(db, 'pedidos', 'p1', 'muebles', 'mu1'), { precio: 600, ultimoCambioId: c.id });
    await assertFails(b.commit());
  });

  it('un cambios_precio suelto, sin cambiar el mueble, falla', async () => {
    const db = como(env, 'emp1');
    await assertFails(setDoc(doc(db, 'pedidos', 'p1', 'cambios_precio', 'suelto'), cambio()));
  });

  it('el dueño cambiando el precio sin registro falla', async () => {
    await assertFails(updateDoc(doc(como(env, 'dueno1'), 'pedidos', 'p1', 'muebles', 'mu1'), { precio: 600 }));
  });

  it('cambiar envio 200→0 con su registro funciona', async () => {
    const db = como(env, 'emp1');
    const c = doc(collection(db, 'pedidos', 'p1', 'cambios_precio'));
    const b = writeBatch(db);
    b.set(c, cambio({ campo: 'envio', muebleId: null, anterior: 200, nuevo: 0, motivo: 'Lo recoge' }));
    b.update(doc(db, 'pedidos', 'p1'), { entrega: 'recoge', envio: 0, ultimoCambioId: c.id });
    await assertSucceeds(b.commit());
  });

  it('registro falso: mover ultimoCambioId sin cambiar el precio falla', async () => {
    const db = como(env, 'emp1');
    const b = writeBatch(db);
    b.set(doc(db, 'pedidos', 'p1', 'cambios_precio', 'fake1'), cambio({ anterior: 650, nuevo: 5 }));
    b.update(doc(db, 'pedidos', 'p1', 'muebles', 'mu1'), { ultimoCambioId: 'fake1' });
    await assertFails(b.commit());
  });

  it('registro falso: mover ultimoCambioId sin cambiar el envío falla', async () => {
    const db = como(env, 'emp1');
    const b = writeBatch(db);
    b.set(
      doc(db, 'pedidos', 'p1', 'cambios_precio', 'fake2'),
      cambio({ campo: 'envio', muebleId: null, anterior: 200, nuevo: 0 }),
    );
    b.update(doc(db, 'pedidos', 'p1'), { ultimoCambioId: 'fake2' });
    await assertFails(b.commit());
  });

  it('reutilizar un registro viejo (A→B→A) falla', async () => {
    const db = como(env, 'emp1');
    const mu = doc(db, 'pedidos', 'p1', 'muebles', 'mu1');
    const a = writeBatch(db);
    a.set(doc(db, 'pedidos', 'p1', 'cambios_precio', 'A'), cambio({ anterior: 650, nuevo: 600 }));
    a.update(mu, { precio: 600, ultimoCambioId: 'A' });
    await assertSucceeds(a.commit());
    const b = writeBatch(db);
    b.set(doc(db, 'pedidos', 'p1', 'cambios_precio', 'B'), cambio({ anterior: 600, nuevo: 650 }));
    b.update(mu, { precio: 650, ultimoCambioId: 'B' });
    await assertSucceeds(b.commit());
    await assertFails(updateDoc(mu, { precio: 600, ultimoCambioId: 'A' }));
  });

  it('registro con fecha atrasada falla', async () => {
    const db = como(env, 'emp1');
    const c = doc(collection(db, 'pedidos', 'p1', 'cambios_precio'));
    const b = writeBatch(db);
    b.set(c, cambio({ fecha: Timestamp.fromDate(new Date('2020-01-01')) }));
    b.update(doc(db, 'pedidos', 'p1', 'muebles', 'mu1'), { precio: 600, ultimoCambioId: c.id });
    await assertFails(b.commit());
  });

  it('el dueño cambia el precio con su registro', async () => {
    const db = como(env, 'dueno1');
    const c = doc(collection(db, 'pedidos', 'p1', 'cambios_precio'));
    const b = writeBatch(db);
    b.set(c, cambio({ usuarioId: 'dueno1', motivo: 'Descuento' }));
    b.update(doc(db, 'pedidos', 'p1', 'muebles', 'mu1'), { precio: 600, ultimoCambioId: c.id });
    await assertSucceeds(b.commit());
  });

  it('cambiar precio apuntando a un registro inexistente falla', async () => {
    await assertFails(
      updateDoc(doc(como(env, 'emp1'), 'pedidos', 'p1', 'muebles', 'mu1'), { precio: 600, ultimoCambioId: 'noexiste' }),
    );
  });

  it('cambiar envio sin registro falla', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'pedidos', 'p1'), { envio: 0 }));
  });
});

describe('actualizaciones del empleado', () => {
  it('cambia estado y comentarios del mueble', async () => {
    await assertSucceeds(
      updateDoc(doc(como(env, 'emp1'), 'pedidos', 'p1', 'muebles', 'mu1'), {
        estado: 'en_proceso',
        comentarios: 'Falta tela',
      }),
    );
  });

  it('no cambia tipoMueble', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'pedidos', 'p1', 'muebles', 'mu1'), { tipoMueble: 'Silla' }));
  });

  it('no cambia folio ni creadoPor del pedido', async () => {
    const ref = doc(como(env, 'emp1'), 'pedidos', 'p1');
    await assertFails(updateDoc(ref, { folio: '000000-ZZZZ' }));
    await assertFails(updateDoc(ref, { creadoPor: 'dueno1' }));
  });

  it('no borra un mueble', async () => {
    await assertFails(deleteDoc(doc(como(env, 'emp1'), 'pedidos', 'p1', 'muebles', 'mu1')));
  });
});

describe('lectura de cambios_precio', () => {
  it('el empleado no lee', async () => {
    const db = como(env, 'emp1');
    await assertFails(getDoc(doc(db, 'pedidos', 'p1', 'cambios_precio', 'cp0')));
    await assertFails(getDocs(collection(db, 'pedidos', 'p1', 'cambios_precio')));
  });

  it('el dueño lee', async () => {
    const db = como(env, 'dueno1');
    await assertSucceeds(getDoc(doc(db, 'pedidos', 'p1', 'cambios_precio', 'cp0')));
    await assertSucceeds(getDocs(collection(db, 'pedidos', 'p1', 'cambios_precio')));
  });

  it('nadie actualiza ni borra un registro', async () => {
    for (const uid of ['dueno1', 'emp1']) {
      const ref = doc(como(env, uid), 'pedidos', 'p1', 'cambios_precio', 'cp0');
      await assertFails(updateDoc(ref, { motivo: 'otro' }));
      await assertFails(deleteDoc(ref));
    }
  });
});

describe('plantillas', () => {
  it('el empleado lee pero no escribe', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDoc(doc(db, 'plantillas', 'pl1')));
    await assertFails(setDoc(doc(db, 'plantillas', 'nueva'), { tipoMueble: 'Sofá', lineas: [] }));
  });

  it('el dueño crea una válida', async () => {
    await assertSucceeds(
      setDoc(doc(como(env, 'dueno1'), 'plantillas', 'nueva'), {
        tipoMueble: 'Sofá',
        lineas: [{ materialId: 'm1', cantidad: 5 }],
      }),
    );
  });
});

describe('consulta de grupo de muebles', () => {
  it('el empleado consulta fabricación', async () => {
    const db = como(env, 'emp1');
    await assertSucceeds(getDocs(query(collectionGroup(db, 'muebles'), where('tipoTrabajo', '==', 'fabricacion'))));
  });

  it('un empleado inactivo no puede', async () => {
    const db = como(env, 'inact');
    await assertFails(getDocs(query(collectionGroup(db, 'muebles'), where('tipoTrabajo', '==', 'fabricacion'))));
  });
});
