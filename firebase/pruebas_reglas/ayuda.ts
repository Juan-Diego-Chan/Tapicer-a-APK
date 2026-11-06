import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, type Firestore } from 'firebase/firestore';

const RUTA_REGLAS = fileURLToPath(new URL('../firestore.rules', import.meta.url));

export async function crearEntorno(): Promise<RulesTestEnvironment> {
  const destino = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
  const corte = destino.lastIndexOf(':');
  const host = destino.slice(0, corte);
  const port = destino.slice(corte + 1);
  return initializeTestEnvironment({
    projectId: 'demo-tapiceria',
    firestore: {
      rules: readFileSync(RUTA_REGLAS, 'utf8'),
      host,
      port: Number(port),
    },
  });
}

export async function sembrarUsuario(
  env: RulesTestEnvironment,
  uid: string,
  { rol, activo }: { rol: 'dueno' | 'empleado'; activo: boolean },
): Promise<void> {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore() as unknown as Firestore, 'usuarios', uid), {
      nombre: `Usuario ${uid}`,
      email: `${uid}@ejemplo.com`,
      rol,
      activo,
      creadoEn: new Date(),
    });
  });
}

export function como(env: RulesTestEnvironment, uid: string): Firestore {
  return env.authenticatedContext(uid).firestore() as unknown as Firestore;
}

export function anonimo(env: RulesTestEnvironment): Firestore {
  return env.unauthenticatedContext().firestore() as unknown as Firestore;
}
