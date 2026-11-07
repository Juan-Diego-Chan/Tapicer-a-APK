import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { assertFails, assertSucceeds, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  increment,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
  type Firestore,
} from 'firebase/firestore';
import { como, crearEntorno, sembrarUsuario } from './ayuda';

let env: RulesTestEnvironment;

const RUTA_MUEBLE = 'pedidos/p1/muebles/mu1';

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

const linea = (extra: Record<string, unknown> = {}) => ({
  materialId: 'tela1',
  rolloId: 'r1',
  cantidad: 2.5,
  delCliente: false,
  usuarioId: 'emp1',
  fecha: serverTimestamp(),
  ...extra,
});

const consumo = (extra: Record<string, unknown> = {}) => ({
  tipo: 'consumo',
  materialId: 'tela1',
  rolloId: 'r1',
  cantidad: -2.5,
  pedidoId: 'p1',
  muebleId: 'mu1',
  usuarioId: 'emp1',
  fecha: serverTimestamp(),
  ...extra,
});

const dia = (extra: Record<string, unknown> = {}) => ({
  usuarioId: 'emp1',
  dias: 1.5,
  fecha: serverTimestamp(),
  ...extra,
});

// Lote de consumo como lo escribe la app (Task 6).
function loteConsumo(
  db: Firestore,
  {
    id = 'l1',
    idMovimiento = id,
    cantidad = 2.5,
    l = {},
    mov = {},
    sinMovimiento = false,
    usuarioId = 'emp1',
  }: {
    id?: string;
    idMovimiento?: string;
    cantidad?: number;
    l?: Record<string, unknown>;
    mov?: Record<string, unknown>;
    sinMovimiento?: boolean;
    usuarioId?: string;
  } = {},
) {
  const b = writeBatch(db);
  b.set(doc(db, `${RUTA_MUEBLE}/materiales`, id), linea({ cantidad, usuarioId, ...l }));
  if (!sinMovimiento) {
    b.set(doc(db, 'movimientos', idMovimiento), consumo({ cantidad: -cantidad, usuarioId, ...mov }));
  }
  b.update(doc(db, 'materiales', 'tela1'), { existencia: increment(-cantidad) });
  b.update(doc(db, 'rollos', 'r1'), { existencia: increment(-cantidad) });
  return b.commit();
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
  await sembrarUsuario(env, 'emp2', { rol: 'empleado', activo: true });
  await sembrarUsuario(env, 'inact', { rol: 'empleado', activo: false });
  await sembrar('pedidos', 'p1', {
    folio: '261107-ABCD',
    clienteId: 'cl1',
    cliente: { nombre: 'Ana López', telefono: '', direccion: '' },
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
  });
  const mueble = {
    tipoTrabajo: 'reparacion',
    tipoMueble: 'Sillón',
    plantillaId: null,
    precio: 650,
    comentarios: '',
    estado: 'recibido',
    ultimoCambioId: null,
  };
  await sembrar('pedidos/p1/muebles', 'mu1', mueble);
  await sembrar('pedidos', 'p2', { folio: '261107-WXYZ' });
  await sembrar('pedidos/p2/muebles', 'mu2', mueble);
  await sembrar('materiales', 'tela1', {
    nombre: 'Tela gris',
    categoria: 'tela',
    unidad: 'm',
    stockMinimo: 5,
    existencia: 30,
    usaRollos: true,
    marcadoAgotandose: false,
  });
  await sembrar('rollos', 'r1', {
    materialId: 'tela1',
    codigo: 'R-001',
    cantidadInicial: 30,
    existencia: 30,
    fechaCompra: Timestamp.now(),
  });
  await sembrar('materiales', 'guata1', {
    nombre: 'Guata',
    categoria: 'guata',
    unidad: 'kg',
    stockMinimo: 1,
    existencia: 2,
    usaRollos: false,
    marcadoAgotandose: false,
  });
});

describe('consumo de material', () => {
  it('empleado registra consumo de tela en un lote', async () => {
    await assertSucceeds(loteConsumo(como(env, 'emp1')));
    expect((await leer('materiales', 'tela1'))?.existencia).toBe(27.5);
    expect((await leer('rollos', 'r1'))?.existencia).toBe(27.5);
  });

  it('empleado registra consumo de guata (sin rollo)', async () => {
    const db = como(env, 'emp1');
    const b = writeBatch(db);
    b.set(doc(db, `${RUTA_MUEBLE}/materiales`, 'l1'), linea({ materialId: 'guata1', rolloId: null, cantidad: 0.5 }));
    b.set(doc(db, 'movimientos', 'l1'), consumo({ materialId: 'guata1', rolloId: null, cantidad: -0.5 }));
    b.update(doc(db, 'materiales', 'guata1'), { existencia: increment(-0.5) });
    await assertSucceeds(b.commit());
  });

  it('falla sin movimiento', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { sinMovimiento: true }));
  });

  it('falla si el movimiento dice -3', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { mov: { cantidad: -3 } }));
  });

  it('falla si el movimiento tiene otro id', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { idMovimiento: 'otro' }));
  });

  it('falla si el movimiento es de tipo ajuste', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { mov: { tipo: 'ajuste' } }));
  });

  it('falla si el movimiento es de otro material o rollo', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { mov: { materialId: 'guata1' } }));
    await assertFails(loteConsumo(como(env, 'emp1'), { mov: { rolloId: null } }));
  });

  it('falla si el movimiento apunta a otro pedido o mueble', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { mov: { pedidoId: 'p2', muebleId: 'mu2' } }));
    await assertFails(loteConsumo(como(env, 'emp1'), { mov: { muebleId: 'mu9' } }));
  });

  it('falla en un mueble que no existe', async () => {
    const db = como(env, 'emp1');
    const b = writeBatch(db);
    b.set(doc(db, 'pedidos/p1/muebles/mu9/materiales', 'l1'), linea());
    b.set(doc(db, 'movimientos', 'l1'), consumo({ muebleId: 'mu9' }));
    await assertFails(b.commit());
  });

  it('falla con cantidad no positiva o enorme', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { cantidad: 0 }));
    await assertFails(loteConsumo(como(env, 'emp1'), { cantidad: -2 }));
    await assertFails(loteConsumo(como(env, 'emp1'), { cantidad: 1000000 }));
  });

  it('falla con campo extra o usuario ajeno en la línea', async () => {
    await assertFails(loteConsumo(como(env, 'emp1'), { l: { costo: 10 } }));
    await assertFails(loteConsumo(como(env, 'emp1'), { l: { usuarioId: 'emp2' } }));
  });

  it('inactivo no registra consumo', async () => {
    await assertFails(loteConsumo(como(env, 'inact'), { usuarioId: 'inact' }));
  });

  it('línea del cliente sin movimiento ni incrementos', async () => {
    await assertSucceeds(
      setDoc(
        doc(como(env, 'emp1'), `${RUTA_MUEBLE}/materiales`, 'l2'),
        linea({ rolloId: null, delCliente: true }),
      ),
    );
  });

  it('línea del cliente no permite movimiento de consumo con su id', async () => {
    const db = como(env, 'emp1');
    const b = writeBatch(db);
    b.set(doc(db, `${RUTA_MUEBLE}/materiales`, 'l2'), linea({ rolloId: null, delCliente: true }));
    b.set(doc(db, 'movimientos', 'l2'), consumo({ rolloId: null }));
    await assertFails(b.commit());
  });

  it('movimiento de consumo suelto, sin línea, falla', async () => {
    await assertFails(setDoc(doc(como(env, 'emp1'), 'movimientos', 'suelto'), consumo()));
  });

  it('no reutiliza el movimiento de una línea borrada', async () => {
    await assertSucceeds(loteConsumo(como(env, 'emp1')));
    await assertSucceeds(deleteDoc(doc(como(env, 'dueno1'), `${RUTA_MUEBLE}/materiales`, 'l1')));
    await assertFails(setDoc(doc(como(env, 'emp1'), `${RUTA_MUEBLE}/materiales`, 'l1'), linea()));
  });

  it('dos consumos seguidos dejan el rollo en 26', async () => {
    await assertSucceeds(loteConsumo(como(env, 'emp1'), { id: 'l1', cantidad: 2.5 }));
    await assertSucceeds(loteConsumo(como(env, 'emp1'), { id: 'l2', cantidad: 1.5 }));
    expect((await leer('rollos', 'r1'))?.existencia).toBe(26);
    expect((await leer('materiales', 'tela1'))?.existencia).toBe(26);
  });

  it('dueño también registra consumo', async () => {
    await assertSucceeds(loteConsumo(como(env, 'dueno1'), { usuarioId: 'dueno1' }));
  });
});

describe('empleado y existencias', () => {
  it('no sube la existencia de un material', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'materiales', 'tela1'), { existencia: increment(1) }));
  });

  it('no baja la existencia cambiando también el nombre', async () => {
    await assertFails(
      updateDoc(doc(como(env, 'emp1'), 'materiales', 'tela1'), { existencia: increment(-1), nombre: 'Otra' }),
    );
  });

  it('no sube la existencia de un rollo', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'rollos', 'r1'), { existencia: increment(1) }));
  });

  it('no cambia otros campos del rollo', async () => {
    await assertFails(
      updateDoc(doc(como(env, 'emp1'), 'rollos', 'r1'), { existencia: increment(-1), cantidadInicial: 100 }),
    );
  });

  it('no pone existencia no numérica', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), 'materiales', 'tela1'), { existencia: '1' }));
  });

  it('inactivo no baja existencias', async () => {
    await assertFails(updateDoc(doc(como(env, 'inact'), 'materiales', 'tela1'), { existencia: increment(-1) }));
    await assertFails(updateDoc(doc(como(env, 'inact'), 'rollos', 'r1'), { existencia: increment(-1) }));
  });
});

describe('días trabajados', () => {
  const dias = (db: Firestore, datos: Record<string, unknown>, id = 'd1') =>
    setDoc(doc(db, `${RUTA_MUEBLE}/dias`, id), datos);

  it('empleado registra 1.5 días para sí mismo', async () => {
    await assertSucceeds(dias(como(env, 'emp1'), dia()));
  });

  it('rechaza 0.3, 0 y 8 días', async () => {
    await assertFails(dias(como(env, 'emp1'), dia({ dias: 0.3 })));
    await assertFails(dias(como(env, 'emp1'), dia({ dias: 0 })));
    await assertFails(dias(como(env, 'emp1'), dia({ dias: 8 })));
  });

  it('acepta 7 días y 0.5 días', async () => {
    await assertSucceeds(dias(como(env, 'emp1'), dia({ dias: 7 }), 'd1'));
    await assertSucceeds(dias(como(env, 'emp1'), dia({ dias: 0.5 }), 'd2'));
  });

  it('empleado no registra días para otro', async () => {
    await assertFails(dias(como(env, 'emp1'), dia({ usuarioId: 'emp2' })));
  });

  it('dueño registra días para el empleado', async () => {
    await assertSucceeds(dias(como(env, 'dueno1'), dia()));
  });

  it('rechaza campos extra y mueble inexistente', async () => {
    await assertFails(dias(como(env, 'emp1'), dia({ costo: 100 })));
    await assertFails(setDoc(doc(como(env, 'emp1'), 'pedidos/p1/muebles/mu9/dias', 'd1'), dia()));
  });

  it('inactivo no registra ni lee días', async () => {
    await assertFails(dias(como(env, 'inact'), dia({ usuarioId: 'inact' })));
    await sembrar(`${RUTA_MUEBLE}/dias`, 'd0', dia({ fecha: Timestamp.now() }));
    await assertFails(getDoc(doc(como(env, 'inact'), `${RUTA_MUEBLE}/dias`, 'd0')));
    await assertSucceeds(getDoc(doc(como(env, 'emp2'), `${RUTA_MUEBLE}/dias`, 'd0')));
  });

  it('empleado no borra ni edita un día; el dueño lo borra', async () => {
    await sembrar(`${RUTA_MUEBLE}/dias`, 'd0', dia({ fecha: Timestamp.now() }));
    await assertFails(updateDoc(doc(como(env, 'emp1'), `${RUTA_MUEBLE}/dias`, 'd0'), { dias: 2 }));
    await assertFails(updateDoc(doc(como(env, 'dueno1'), `${RUTA_MUEBLE}/dias`, 'd0'), { dias: 2 }));
    await assertFails(deleteDoc(doc(como(env, 'emp1'), `${RUTA_MUEBLE}/dias`, 'd0')));
    await assertSucceeds(deleteDoc(doc(como(env, 'dueno1'), `${RUTA_MUEBLE}/dias`, 'd0')));
  });
});

describe('borrado de líneas', () => {
  beforeEach(async () => {
    await sembrar(`${RUTA_MUEBLE}/materiales`, 'l0', linea({ fecha: Timestamp.now() }));
  });

  it('empleado no borra una línea', async () => {
    await assertFails(deleteDoc(doc(como(env, 'emp1'), `${RUTA_MUEBLE}/materiales`, 'l0')));
  });

  it('nadie actualiza una línea', async () => {
    await assertFails(updateDoc(doc(como(env, 'emp1'), `${RUTA_MUEBLE}/materiales`, 'l0'), { cantidad: 1 }));
    await assertFails(updateDoc(doc(como(env, 'dueno1'), `${RUTA_MUEBLE}/materiales`, 'l0'), { cantidad: 1 }));
  });

  it('dueño borra la línea con su ajuste y devuelve existencias', async () => {
    const db = como(env, 'dueno1');
    const b = writeBatch(db);
    b.delete(doc(db, `${RUTA_MUEBLE}/materiales`, 'l0'));
    b.set(doc(db, 'movimientos', 'aj1'), consumo({ tipo: 'ajuste', cantidad: 2.5, usuarioId: 'dueno1' }));
    b.update(doc(db, 'materiales', 'tela1'), { existencia: increment(2.5) });
    b.update(doc(db, 'rollos', 'r1'), { existencia: increment(2.5) });
    await assertSucceeds(b.commit());
    expect((await leer('rollos', 'r1'))?.existencia).toBe(32.5);
  });

  it('empleado lee líneas; inactivo no', async () => {
    await assertSucceeds(getDoc(doc(como(env, 'emp1'), `${RUTA_MUEBLE}/materiales`, 'l0')));
    await assertFails(getDoc(doc(como(env, 'inact'), `${RUTA_MUEBLE}/materiales`, 'l0')));
  });
});
