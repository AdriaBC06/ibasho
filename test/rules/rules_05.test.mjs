// Ibasho — tests de las reglas de la 0.5.0: el Yatai (tienda), la despensa y
// los juegos comprados.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Se lanzan con:   ./tool/test_rules.sh
//
// Va aparte de rules_04.test.mjs por el mismo motivo que aquel iba aparte de
// rules.test.mjs: el estado de partida (precios cargados, saldo de partida)
// no vale la pena mezclarlo con los demas.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { get, ref, serverTimestamp, set, update } from 'firebase/database';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', '..', 'database.rules.json'), 'utf8');

const ADMIN = 'uid-admin';
const ANA = 'uid-ana';
const LUIS = 'uid-luis';

const testEnv = await initializeTestEnvironment({
  projectId: process.env.GCLOUD_PROJECT ?? 'demo-ibasho',
  database: {
    rules,
    host: process.env.IBASHO_EMULATOR_HOST ?? '127.0.0.1',
    port: Number(process.env.IBASHO_EMULATOR_DB_PORT ?? 9000),
  },
});

const now = Date.now();

const entry = (username, extra = {}) => ({
  accountId: `uid-${username}`,
  username,
  createdAt: now,
  createdBy: ADMIN,
  disabled: false,
  ...extra,
});

/// Ana tiene 100 monedas y ya tiene su stock de serie. Luis no tiene nada
/// todavia: sirve para el stock inicial y para comprobar que nadie toca lo
/// de Ana.
async function seed() {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      admins: { [ADMIN]: true },
      allowlist: {
        [ADMIN]: entry('admin'),
        [ANA]: entry('ana'),
        [LUIS]: entry('luis'),
      },
      usernames: { admin: ADMIN, ana: ANA, luis: LUIS },
      shop: {
        prices: {
          game_minesweeper: 0,
          food_cookie: 3,
          food_candy: 3,
        },
      },
      users: {
        [ADMIN]: {},
        [ANA]: { coins: 100, pantry: { cookie: 5, candy: 5 } },
        [LUIS]: { coins: 2 },
      },
    });
  });
}

const db = (uid) =>
  uid === null
    ? testEnv.unauthenticatedContext().database()
    : testEnv.authenticatedContext(uid).database();

test.beforeEach(seed);
test.after(async () => {
  await testEnv.cleanup();
});

// --- Comprar comida ---------------------------------------------------------

test('comprar comida con saldo baja las monedas y sube la despensa', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'food_cookie', qty: 5, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 85,
      [`users/${ANA}/pantry/cookie`]: 10,
    }),
  );
});

test('comprar sin saldo suficiente no cuela', async () => {
  await assertFails(
    update(ref(db(LUIS), '/'), {
      [`users/${LUIS}/shop/last`]: { item: 'food_cookie', qty: 5, at: serverTimestamp() },
      // 2 monedas no llegan para 5 galletas a 3: la resta daria negativo, y
      // aunque no lo diera, esto no es lo que hay en el saldo real.
      [`users/${LUIS}/coins`]: -13,
      [`users/${LUIS}/pantry/cookie`]: 5,
    }),
  );
});

test('la resta tiene que cuadrar exactamente', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'food_cookie', qty: 5, at: serverTimestamp() },
      // Deberian ser 85 (100 - 3*5); con 90 no cuadra.
      [`users/${ANA}/coins`]: 90,
      [`users/${ANA}/pantry/cookie`]: 10,
    }),
  );
});

test('un recibo no se puede reutilizar para otra escritura', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'food_cookie', qty: 5, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 85,
      [`users/${ANA}/pantry/cookie`]: 10,
    }),
  );
  // El recibo ya escrito tiene un `at` que ya no es `now`: no sirve para
  // mover las monedas otra vez sin un recibo fresco en la misma operacion.
  await assertFails(set(ref(db(ANA), `/users/${ANA}/coins`), 70));
});

test('no se puede comprar una comida que no esta desbloqueada', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'food_mochi', qty: 1, at: serverTimestamp() },
      [`users/${ANA}/pantry/mochi`]: 1,
    }),
  );
});

// --- Comer -------------------------------------------------------------

test('comer resta una unidad, ni mas ni menos', async () => {
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/pantry/cookie`), 4));
  // Desde los 5 de partida, saltarse una unidad y restar 2 de golpe no cuela.
  await assertFails(set(ref(db(ANA), `/users/${ANA}/pantry/candy`), 3));
});

// --- Stock inicial -------------------------------------------------------

test('el stock inicial son 5 unidades, una sola vez, y solo de serie', async () => {
  await assertSucceeds(set(ref(db(LUIS), `/users/${LUIS}/pantry/cookie`), 5));
  // Ya existe: no se puede volver a pedir el stock inicial otra vez.
  await assertFails(set(ref(db(LUIS), `/users/${LUIS}/pantry/cookie`), 5));
  // Ni con otro valor que no sea 5, la primera vez.
  await assertFails(set(ref(db(LUIS), `/users/${LUIS}/pantry/candy`), 3));
  // Ni de una comida que todavia no viene de serie.
  await assertFails(set(ref(db(LUIS), `/users/${LUIS}/pantry/mochi`), 5));
});

test('la despensa no se puede borrar', async () => {
  await assertFails(set(ref(db(ANA), `/users/${ANA}/pantry/cookie`), null));
});

test('un desconocido no toca la despensa de otra cuenta', async () => {
  await assertFails(set(ref(db(LUIS), `/users/${ANA}/pantry/cookie`), 4));
});

// --- Juegos --------------------------------------------------------------

test('un juego sin recibo fresco no se puede regalar', async () => {
  await assertFails(
    set(ref(db(ANA), `/users/${ANA}/games/minesweeper`), { state: 'gift', at: serverTimestamp() }),
  );
});

test('comprar un juego a precio 0 no exige mover monedas', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'game_minesweeper', qty: 1, at: serverTimestamp() },
      [`users/${ANA}/games/minesweeper`]: { state: 'gift', at: serverTimestamp() },
    }),
  );
});

test('un juego pasa de regalo a abierto, y no al reves', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${ANA}/games/minesweeper`), {
      state: 'gift',
      at: now - 1000,
    });
  });
  await assertSucceeds(
    set(ref(db(ANA), `/users/${ANA}/games/minesweeper/state`), 'open'),
  );
  await assertFails(
    set(ref(db(ANA), `/users/${ANA}/games/minesweeper/state`), 'gift'),
  );
});

test('los juegos comprados no se pueden borrar', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${ANA}/games/minesweeper`), {
      state: 'open',
      at: now,
    });
  });
  await assertFails(set(ref(db(ANA), `/users/${ANA}/games/minesweeper`), null));
});

// --- Lo que no cambia ------------------------------------------------------

test('el admin sigue pudiendo dar monedas sin recibo', async () => {
  await assertSucceeds(set(ref(db(ADMIN), `/users/${LUIS}/coins`), 500));
});

test('los precios los lee cualquier cuenta con sesion y solo el admin los escribe', async () => {
  await assertSucceeds(get(ref(db(LUIS), '/shop/prices')));
  await assertFails(get(ref(db(null), '/shop/prices')));
  await assertSucceeds(set(ref(db(ADMIN), '/shop/prices/food_mochi'), 5));
  await assertFails(set(ref(db(ANA), '/shop/prices/food_mochi'), 5));
});

test('un desconocido no puede firmarse el recibo de otra cuenta', async () => {
  await assertFails(
    update(ref(db(LUIS), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'food_cookie', qty: 5, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 85,
      [`users/${ANA}/pantry/cookie`]: 10,
    }),
  );
  assert.ok(true);
});
