// Ibasho — tests de las reglas del regalo diario del Yatai (0.9.0): una vez
// al dia, comida x2, 1 gachaken y de 5 a 10 monedas en la misma escritura.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Se lanzan con:   ./tool/test_rules.sh

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import test from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { ref, remove, serverTimestamp, set, update } from 'firebase/database';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', '..', 'database.rules.json'), 'utf8');

const ADMIN = 'uid-admin';
const ANA = 'uid-ana';

const testEnv = await initializeTestEnvironment({
  projectId: process.env.GCLOUD_PROJECT ?? 'demo-ibasho',
  database: {
    rules,
    host: process.env.IBASHO_EMULATOR_HOST ?? '127.0.0.1',
    port: Number(process.env.IBASHO_EMULATOR_DB_PORT ?? 9000),
  },
});

const now = Date.now();
const DAY = 86400000;
const day = Math.floor(now / DAY);

const entry = (username) => ({
  accountId: `uid-${username}`,
  username,
  createdAt: now,
  createdBy: ADMIN,
  disabled: false,
});

async function seed(ana = {}) {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      admins: { [ADMIN]: true },
      allowlist: { [ADMIN]: entry('admin'), [ANA]: entry('ana') },
      usernames: { admin: ADMIN, ana: ANA },
      users: {
        [ADMIN]: { coins: 0 },
        [ANA]: { coins: 100, tickets: { gachaken: 2, kinken: 0 }, pantry: { cookie: 3 }, ...ana },
      },
    });
  });
}

const db = (uid) => testEnv.authenticatedContext(uid).database();

/// El cobro entero, como lo hace la app; [over] cambia lo que haga falta.
/// Una clave a `null` se quita del cobro.
const claim = (over = {}) => {
  const all = {
    'users/uid-ana/gift': { day, at: serverTimestamp(), food: 'mochi', coins: 7 },
    'users/uid-ana/pantry/mochi': 2,
    'users/uid-ana/tickets/gachaken': 3,
    'users/uid-ana/coins': 107,
    ...over,
  };
  for (const k of Object.keys(all)) if (all[k] === null) delete all[k];
  return all;
};

test.beforeEach(() => seed());
test.after(async () => {
  await testEnv.cleanup();
});

test('el regalo de hoy da la comida x2, 1 gachaken y las monedas', async () => {
  await assertSucceeds(update(ref(db(ANA), '/'), claim()));
});

test('suma a la comida que ya habia', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), claim({
      'users/uid-ana/gift': { day, at: serverTimestamp(), food: 'cookie', coins: 5 },
      'users/uid-ana/pantry/mochi': null,
      'users/uid-ana/pantry/cookie': 5,
      'users/uid-ana/coins': 105,
    })),
  );
});

test('no se cobra dos veces el mismo dia', async () => {
  await seed({ gift: { day, at: now - 1000, food: 'apple', coins: 5 } });
  await assertFails(update(ref(db(ANA), '/'), claim()));
});

test('el de ayer no impide el de hoy', async () => {
  await seed({ gift: { day: day - 1, at: now - DAY, food: 'apple', coins: 5 } });
  await assertSucceeds(update(ref(db(ANA), '/'), claim()));
});

test('no se puede cobrar el de mañana', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), claim({ 'users/uid-ana/gift': { day: day + 1, at: serverTimestamp(), food: 'mochi', coins: 7 } })),
  );
});

test('el saquito va de 5 a 10', async () => {
  for (const coins of [4, 11]) {
    await assertFails(
      update(ref(db(ANA), '/'), claim({
        'users/uid-ana/gift': { day, at: serverTimestamp(), food: 'mochi', coins },
        'users/uid-ana/coins': 100 + coins,
      })),
    );
  }
});

test('las monedas suben justo lo del saquito', async () => {
  await assertFails(update(ref(db(ANA), '/'), claim({ 'users/uid-ana/coins': 110 })));
});

test('la comida sube 2, ni mas ni otra', async () => {
  await assertFails(update(ref(db(ANA), '/'), claim({ 'users/uid-ana/pantry/mochi': 5 })));
  await assertFails(
    update(ref(db(ANA), '/'), claim({ 'users/uid-ana/pantry/mochi': null, 'users/uid-ana/pantry/flan': 2 })),
  );
});

test('el gachaken sube 1 y el kinken no', async () => {
  await assertFails(update(ref(db(ANA), '/'), claim({ 'users/uid-ana/tickets/gachaken': 4 })));
  await assertFails(update(ref(db(ANA), '/'), claim({ 'users/uid-ana/tickets/kinken': 1 })));
});

test('una comida que no existe no vale', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), claim({
      'users/uid-ana/gift': { day, at: serverTimestamp(), food: 'pizza', coins: 7 },
      'users/uid-ana/pantry/mochi': null,
    })),
  );
});

test('nadie cobra el regalo de otra cuenta', async () => {
  await assertFails(update(ref(db(ADMIN), '/'), claim()));
});

test('solo un admin puede borrar su regalo', async () => {
  await seed({ gift: { day, at: now - 1000, food: 'apple', coins: 5 } });
  await assertFails(remove(ref(db(ANA), 'users/uid-ana/gift')));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), 'users/uid-admin/gift'), { day, at: now - 1000, food: 'apple', coins: 5 });
  });
  await assertSucceeds(remove(ref(db(ADMIN), 'users/uid-admin/gift')));
});
