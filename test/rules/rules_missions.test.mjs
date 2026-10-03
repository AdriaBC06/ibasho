// Ibasho — tests de las reglas de las misiones (0.6.0): la señal, el cobro
// diario con su recibo y sello, que no se pueda cobrar dos veces ni sin
// haber hecho la señal hoy, y el cobro semanal con el ticket dorado.
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
      allowlist: { [ADMIN]: entry('admin'), [ANA]: entry('ana') },
      usernames: { admin: ADMIN, ana: ANA },
      users: { [ADMIN]: {}, [ANA]: { tickets: { gachaken: 5, kinken: 0 } } },
      ...extra,
    });
  });
}

const db = (uid) => testEnv.authenticatedContext(uid).database();

test.beforeEach(() => seed());
test.after(async () => {
  await testEnv.cleanup();
});

test('la señal de dar de comer se apunta con la hora del servidor', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), { 'users/uid-ana/missions/signal/feed': { at: serverTimestamp() } }),
  );
});

test('nadie apunta la señal de otra cuenta', async () => {
  await assertFails(
    update(ref(db(ADMIN), '/'), { 'users/uid-ana/missions/signal/feed': { at: serverTimestamp() } }),
  );
});

test('cobrar la mision diaria sin haber dado de comer hoy no cuela', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'daily', event: 'feed', day, amount: 1, ticketKind: 'gachaken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/daily/${day}/feed`]: true,
      'users/uid-ana/tickets/gachaken': 6,
    }),
  );
});

test('dar de comer y cobrar la mision sube el gachaken exacto', async () => {
  await seed({ users: { [ANA]: { tickets: { gachaken: 5, kinken: 0 }, missions: { signal: { feed: { at: now } } } } } });
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'daily', event: 'feed', day, amount: 1, ticketKind: 'gachaken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/daily/${day}/feed`]: true,
      'users/uid-ana/tickets/gachaken': 6,
    }),
  );
});

test('la misma mision diaria no se puede cobrar dos veces', async () => {
  await seed({
    users: {
      [ANA]: {
        tickets: { gachaken: 6, kinken: 0 },
        missions: { signal: { feed: { at: now } }, daily: { [day]: { feed: true } } },
      },
    },
  });
  await assertFails(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'daily', event: 'feed', day, amount: 1, ticketKind: 'gachaken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/daily/${day}/feed`]: true,
      'users/uid-ana/tickets/gachaken': 7,
    }),
  );
});

test('subir mas gachaken del que toca no cuela', async () => {
  await seed({ users: { [ANA]: { tickets: { gachaken: 5, kinken: 0 }, missions: { signal: { feed: { at: now } } } } } });
  await assertFails(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'daily', event: 'feed', day, amount: 1, ticketKind: 'gachaken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/daily/${day}/feed`]: true,
      'users/uid-ana/tickets/gachaken': 9,
    }),
  );
});

test('la mision semanal de tirar del gacha da el ticket dorado', async () => {
  await seed({ users: { [ANA]: { tickets: { gachaken: 5, kinken: 0 }, missions: { signal: { pull: { at: now } } } } } });
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'weekly', event: 'pull', week, amount: 1, ticketKind: 'kinken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/weekly/${week}/pull`]: true,
      'users/uid-ana/tickets/kinken': 1,
    }),
  );
});

test('la mision semanal de comprar no puede colarse como si fuera la de tirar', async () => {
  await seed({ users: { [ANA]: { tickets: { gachaken: 5, kinken: 0 }, missions: { signal: { pull: { at: now } } } } } });
  await assertFails(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'weekly', event: 'buy', week, amount: 1, ticketKind: 'kinken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/weekly/${week}/buy`]: true,
      'users/uid-ana/tickets/kinken': 1,
    }),
  );
});

// --- 0.9.0: misiones nuevas, recuentos y repetibles ---

const withMissions = (missions, gachaken = 5) =>
  seed({ users: { [ANA]: { tickets: { gachaken, kinken: 0 }, missions } } });

const mark = (event, n, w = week) => ({
  [`users/uid-ana/missions/signal/${event}`]: { at: serverTimestamp() },
  [`users/uid-ana/missions/tally/${event}`]: { week: w, n, at: serverTimestamp() },
});

const repeat = (event, count, gachaken, w = week) => ({
  'users/uid-ana/missions/claim': {
    kind: 'repeat', event, week: w, amount: 1, ticketKind: 'gachaken', at: serverTimestamp(),
  },
  [`users/uid-ana/missions/repeat/${w}/${event}`]: count,
  'users/uid-ana/tickets/gachaken': gachaken,
});

test('las señales nuevas se apuntan; una inventada no', async () => {
  for (const event of ['pet', 'gift', 'koen', 'chat']) {
    await assertSucceeds(
      update(ref(db(ANA), '/'), { [`users/uid-ana/missions/signal/${event}`]: { at: serverTimestamp() } }),
    );
  }
  await assertFails(
    update(ref(db(ANA), '/'), { 'users/uid-ana/missions/signal/dance': { at: serverTimestamp() } }),
  );
});

test('la mision diaria de acariciar se cobra como las demas', async () => {
  await withMissions({ signal: { pet: { at: now } } });
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'daily', event: 'pet', day, amount: 1, ticketKind: 'gachaken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/daily/${day}/pet`]: true,
      'users/uid-ana/tickets/gachaken': 6,
    }),
  );
});

test('las semanales del parque y de los mensajes dan 2 gachaken, no mas', async () => {
  for (const event of ['koen', 'chat']) {
    await withMissions({ signal: { [event]: { at: now } } });
    const claim = (gachaken, amount) => update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/claim': {
        kind: 'weekly', event, week, amount, ticketKind: 'gachaken', at: serverTimestamp(),
      },
      [`users/uid-ana/missions/weekly/${week}/${event}`]: true,
      'users/uid-ana/tickets/gachaken': gachaken,
    });
    await assertFails(claim(8, 3));
    await assertSucceeds(claim(7, 2));
  }
});

test('el recuento empieza en 1 y sube de uno en uno', async () => {
  await assertFails(update(ref(db(ANA), '/'), mark('play', 2)));
  await assertSucceeds(update(ref(db(ANA), '/'), mark('play', 1)));
  await assertFails(update(ref(db(ANA), '/'), mark('play', 3)));
  await assertSucceeds(update(ref(db(ANA), '/'), mark('play', 2)));
});

test('el recuento vuelve a 1 al cambiar de semana', async () => {
  await withMissions({ tally: { play: { week: week - 1, n: 7, at: now - WEEK } } });
  await assertFails(update(ref(db(ANA), '/'), mark('play', 8)));
  await assertSucceeds(update(ref(db(ANA), '/'), mark('play', 1)));
});

test('el recuento no vale sin su señal ni para otra semana', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      'users/uid-ana/missions/tally/play': { week, n: 1, at: serverTimestamp() },
    }),
  );
  await assertFails(update(ref(db(ANA), '/'), mark('play', 1, week + 1)));
});

test('la repetible se cobra cada 5 partidas, hasta 3 veces', async () => {
  await withMissions({ tally: { play: { week, n: 15, at: now } } });
  await assertSucceeds(update(ref(db(ANA), '/'), repeat('play', 1, 6)));
  await assertSucceeds(update(ref(db(ANA), '/'), repeat('play', 2, 7)));
  await assertSucceeds(update(ref(db(ANA), '/'), repeat('play', 3, 8)));
  await assertFails(update(ref(db(ANA), '/'), repeat('play', 4, 9)));
});

test('la repetible no se cobra antes de tiempo', async () => {
  await withMissions({ tally: { play: { week, n: 9, at: now } }, repeat: { [week]: { play: 1 } } });
  await assertFails(update(ref(db(ANA), '/'), repeat('play', 2, 6)));
});

test('acariciar tambien pide 5 por cobro', async () => {
  await withMissions({ tally: { pet: { week, n: 4, at: now } } });
  await assertFails(update(ref(db(ANA), '/'), repeat('pet', 1, 6)));
  await withMissions({ tally: { pet: { week, n: 5, at: now } } });
  await assertSucceeds(update(ref(db(ANA), '/'), repeat('pet', 1, 6)));
});

test('la repetible no se salta cobros, no da de mas ni usa el recuento viejo', async () => {
  await withMissions({ tally: { play: { week, n: 15, at: now } } });
  await assertFails(update(ref(db(ANA), '/'), repeat('play', 2, 6)));
  await assertFails(update(ref(db(ANA), '/'), repeat('play', 1, 7)));
  await withMissions({ tally: { play: { week: week - 1, n: 15, at: now - WEEK } } });
  await assertFails(update(ref(db(ANA), '/'), repeat('play', 1, 6)));
});

test('solo hay repetibles de jugar, comer y acariciar', async () => {
  await withMissions({ tally: { buy: { week, n: 15, at: now } } });
  await assertFails(update(ref(db(ANA), '/'), repeat('buy', 1, 6)));
});
