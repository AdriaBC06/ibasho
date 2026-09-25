// Ibasho — tests de las reglas de las clasificaciones (0.6.0): quien manda su
// puntuacion, que solo mejore, que no se pueda jugar un periodo pasado, que
// `results` solo nazca una vez con el periodo ya cerrado y que el cobro del
// premio exija salir en `results` y suba el ticket justo lo que toca.
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
import { ref, serverTimestamp, set, update } from 'firebase/database';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', '..', 'database.rules.json'), 'utf8');

const ADMIN = 'uid-admin';
const ANA = 'uid-ana';
const BEN = 'uid-ben';

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
const WEEK = 604800000;
const day = Math.floor(now / DAY);
const week = Math.floor(now / WEEK);

const entry = (username, extra = {}) => ({
  accountId: `uid-${username}`,
  username,
  createdAt: now,
  createdBy: ADMIN,
  disabled: false,
  ...extra,
});

async function seed(extra = {}) {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      admins: { [ADMIN]: true },
      allowlist: { [ADMIN]: entry('admin'), [ANA]: entry('ana'), [BEN]: entry('ben') },
      usernames: { admin: ADMIN, ana: ANA, ben: BEN },
      users: {
        [ADMIN]: {},
        [ANA]: { tickets: { gachaken: 5, kinken: 0 } },
        [BEN]: { tickets: { gachaken: 5, kinken: 0 } },
      },
      leaderboards: {},
      ...extra,
    });
  });
}

const db = (uid) => testEnv.authenticatedContext(uid).database();

test.beforeEach(() => seed());
test.after(async () => {
  await testEnv.cleanup();
});

// --- Mandar la puntuacion propia --------------------------------------------

test('cada cuenta manda su propia puntuacion del periodo en curso', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/day`]: day,
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 120,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('nadie puede escribir la puntuacion de otra cuenta', async () => {
  await assertFails(
    update(ref(db(BEN), '/'), {
      [`leaderboards/tsumiki/daily/${day}/day`]: day,
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 999999,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('sin el recibo `at` fresco, la puntuacion no cuela', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/day`]: day,
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 120,
    }),
  );
});

test('sin el numero de dia de verdad al lado, la puntuacion no cuela', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 120,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('el numero fuera del tope de un juego por puntos no cuela', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/day`]: day,
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 1000000,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('el numero fuera del tope de un juego por tiempo no cuela', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/minesweeper_easy/daily/${day}/day`]: day,
      [`leaderboards/minesweeper_easy/daily/${day}/scores/${ANA}`]: 3600001,
      [`leaderboards/minesweeper_easy/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

// --- Solo mejora, no empeora -------------------------------------------------

test('tsumiki (mas alto mejor): una puntuacion peor no sustituye a la mejor', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day]: { day, scores: { [ANA]: 100 } } } } },
  });
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 90,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
  // Igual tampoco: no es una mejora de verdad.
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 100,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 150,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('buscaminas (mas bajo mejor): un tiempo peor no sustituye al mejor', async () => {
  await seed({
    leaderboards: { minesweeper_easy: { daily: { [day]: { day, scores: { [ANA]: 5000 } } } } },
  });
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/minesweeper_easy/daily/${day}/scores/${ANA}`]: 6000,
      [`leaderboards/minesweeper_easy/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`leaderboards/minesweeper_easy/daily/${day}/scores/${ANA}`]: 4000,
      [`leaderboards/minesweeper_easy/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('ohirune (tiempo, mas bajo mejor): solo mejora bajando, con el tope de una hora', async () => {
  await seed({
    leaderboards: { ohirune: { daily: { [day]: { day, scores: { [ANA]: 90000 } } } } },
  });
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/ohirune/daily/${day}/scores/${ANA}`]: 95000,
      [`leaderboards/ohirune/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`leaderboards/ohirune/daily/${day}/scores/${ANA}`]: 70000,
      [`leaderboards/ohirune/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('tsumiki: las filas van con la puntuacion, nunca solas', async () => {
  await seed({});
  await assertFails(set(ref(db(ANA), `/leaderboards/tsumiki/daily/${day}/lines/${ANA}`), 12));
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/day`]: day,
      [`leaderboards/tsumiki/daily/${day}/scores/${ANA}`]: 1200,
      [`leaderboards/tsumiki/daily/${day}/at/${ANA}`]: serverTimestamp(),
      [`leaderboards/tsumiki/daily/${day}/lines/${ANA}`]: 12,
    }),
  );
});

// --- No se puede jugar un periodo pasado ------------------------------------

test('no se puede escribir la puntuacion de un dia que ya paso', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day - 1}/day`]: day - 1,
      [`leaderboards/tsumiki/daily/${day - 1}/scores/${ANA}`]: 999,
      [`leaderboards/tsumiki/daily/${day - 1}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

test('no se puede escribir la puntuacion de una semana que ya paso', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/weekly/${week - 1}/week`]: week - 1,
      [`leaderboards/tsumiki/weekly/${week - 1}/scores/${ANA}`]: 999,
      [`leaderboards/tsumiki/weekly/${week - 1}/at/${ANA}`]: serverTimestamp(),
    }),
  );
});

// --- Cerrar el periodo con `results` -----------------------------------------

test('no se puede cerrar el periodo en curso: aun no ha terminado', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day}/day`]: day,
      [`leaderboards/tsumiki/daily/${day}/results`]: { 1: ANA, 2: BEN },
    }),
  );
});

test('cualquier cuenta puede cerrar un periodo ya pasado con el top', async () => {
  await assertSucceeds(
    update(ref(db(BEN), '/'), {
      [`leaderboards/tsumiki/daily/${day - 1}/day`]: day - 1,
      [`leaderboards/tsumiki/daily/${day - 1}/results`]: { 1: ANA, 2: BEN },
    }),
  );
});

test('los resultados ya cerrados no se pueden reescribir', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day - 1]: { results: { 1: ANA, 2: BEN } } } } },
  });
  await assertFails(
    update(ref(db(BEN), '/'), {
      [`leaderboards/tsumiki/daily/${day - 1}/results`]: { 1: BEN, 2: ANA },
    }),
  );
});

test('los resultados necesitan al menos el primero, sin huecos ni cuentas repetidas', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day - 1}/day`]: day - 1,
      [`leaderboards/tsumiki/daily/${day - 1}/results`]: { 2: ANA },
    }),
  );
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day - 1}/day`]: day - 1,
      [`leaderboards/tsumiki/daily/${day - 1}/results`]: { 1: ANA, 3: BEN },
    }),
  );
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day - 1}/day`]: day - 1,
      [`leaderboards/tsumiki/daily/${day - 1}/results`]: { 1: ANA, 2: ANA },
    }),
  );
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`leaderboards/tsumiki/daily/${day - 1}/day`]: day - 1,
      [`leaderboards/tsumiki/daily/${day - 1}/results`]: { 1: ANA, 2: BEN, 3: ADMIN },
    }),
  );
});

// --- Cobrar el premio --------------------------------------------------------

/// El cobro de [kind] por el puesto [rank] de [accountId], subiendo los
/// tickets a [tickets].
const claim = (accountId, game, period, key, rank, kind, tickets) => ({
  [`users/${accountId}/leaderboardClaims/last`]: {
    game,
    period,
    key,
    kind,
    at: serverTimestamp(),
  },
  [`users/${accountId}/leaderboardClaims/${game}/${period}/${key}/${kind}`]: true,
  [`users/${accountId}/tickets/${kind}`]: tickets,
});

test('el primero de la tabla diaria cobra 2 gachaken', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day - 1]: { results: { 1: ANA, 2: BEN } } } } },
  });
  await assertSucceeds(
    update(ref(db(ANA), '/'), claim(ANA, 'tsumiki', 'daily', day - 1, 1, 'gachaken', 7)),
  );
});

test('el segundo de la tabla diaria cobra 1 gachaken, no 2', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day - 1]: { results: { 1: ANA, 2: BEN } } } } },
  });
  await assertFails(
    update(ref(db(BEN), '/'), claim(BEN, 'tsumiki', 'daily', day - 1, 2, 'gachaken', 7)),
  );
  await assertSucceeds(
    update(ref(db(BEN), '/'), claim(BEN, 'tsumiki', 'daily', day - 1, 2, 'gachaken', 6)),
  );
});

test('quien no sale en los resultados no cobra nada', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day - 1]: { results: { 1: ANA, 2: BEN } } } } },
  });
  await assertFails(
    update(
      ref(testEnv.authenticatedContext(ADMIN).database(), '/'),
      claim(ADMIN, 'tsumiki', 'daily', day - 1, 3, 'gachaken', 1),
    ),
  );
});

test('el mismo premio no se puede cobrar dos veces', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day - 1]: { results: { 1: ANA, 2: BEN } } } } },
  });
  await assertSucceeds(
    update(ref(db(ANA), '/'), claim(ANA, 'tsumiki', 'daily', day - 1, 1, 'gachaken', 7)),
  );
  await assertFails(
    update(ref(db(ANA), '/'), claim(ANA, 'tsumiki', 'daily', day - 1, 1, 'gachaken', 9)),
  );
});

test('la tabla diaria no da kinken, aunque se sea el primero', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day - 1]: { results: { 1: ANA, 2: BEN } } } } },
  });
  await assertFails(
    update(ref(db(ANA), '/'), claim(ANA, 'tsumiki', 'daily', day - 1, 1, 'kinken', 1)),
  );
});

test('el primero de la tabla semanal cobra 1 kinken', async () => {
  await seed({
    leaderboards: { tsumiki: { weekly: { [week - 1]: { results: { 1: ANA, 2: BEN, 3: ADMIN } } } } },
  });
  await assertSucceeds(
    update(ref(db(ANA), '/'), claim(ANA, 'tsumiki', 'weekly', week - 1, 1, 'kinken', 1)),
  );
});

test('el segundo y el tercero de la semanal cobran 3 y 2 gachaken', async () => {
  await seed({
    leaderboards: { tsumiki: { weekly: { [week - 1]: { results: { 1: ANA, 2: BEN, 3: ADMIN } } } } },
  });
  await assertSucceeds(
    update(ref(db(BEN), '/'), claim(BEN, 'tsumiki', 'weekly', week - 1, 2, 'gachaken', 8)),
  );
  await assertFails(
    update(
      ref(testEnv.authenticatedContext(ADMIN).database(), '/'),
      claim(ADMIN, 'tsumiki', 'weekly', week - 1, 3, 'gachaken', 6),
    ),
  );
});

test('sin el recibo `leaderboardClaims/last` fresco, el ticket no sube', async () => {
  await seed({
    leaderboards: { tsumiki: { daily: { [day - 1]: { results: { 1: ANA, 2: BEN } } } } },
  });
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/leaderboardClaims/tsumiki/daily/${day - 1}/gachaken`]: true,
      [`users/${ANA}/tickets/gachaken`]: 7,
    }),
  );
});

test('si solo jugo una cuenta, el periodo se cierra con ella sola y cobra el primer puesto', async () => {
  await seed({
    leaderboards: { odori: { daily: { [day - 1]: { day: day - 1, scores: { [ANA]: 1200000 } } } } },
  });
  await assertSucceeds(
    update(ref(db(BEN), '/'), {
      [`leaderboards/odori/daily/${day - 1}/results`]: { 1: ANA },
    }),
  );
  await assertSucceeds(update(ref(db(ANA), '/'), claim(ANA, 'odori', 'daily', day - 1, 1, 'gachaken', 7)));
});

test('odori admite hasta 1.500.000 (millon por la dificultad) y no mas', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`leaderboards/odori/daily/${day}/day`]: day,
      [`leaderboards/odori/daily/${day}/scores/${ANA}`]: 1500000,
      [`leaderboards/odori/daily/${day}/at/${ANA}`]: serverTimestamp(),
    }),
  );
  await assertFails(
    update(ref(db(BEN), '/'), {
      [`leaderboards/odori/daily/${day}/day`]: day,
      [`leaderboards/odori/daily/${day}/scores/${BEN}`]: 1500001,
      [`leaderboards/odori/daily/${day}/at/${BEN}`]: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    update(ref(db(BEN), '/'), {
      [`leaderboards/odori_butai/daily/${day}/day`]: day,
      [`leaderboards/odori_butai/daily/${day}/scores/${BEN}`]: 1500000,
      [`leaderboards/odori_butai/daily/${day}/at/${BEN}`]: serverTimestamp(),
    }),
  );
  await assertFails(
    update(ref(db(BEN), '/'), {
      [`leaderboards/tsumiki/daily/${day}/day`]: day,
      [`leaderboards/tsumiki/daily/${day}/scores/${BEN}`]: 1000000,
      [`leaderboards/tsumiki/daily/${day}/at/${BEN}`]: serverTimestamp(),
    }),
  );
});
