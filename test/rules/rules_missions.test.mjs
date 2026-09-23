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
