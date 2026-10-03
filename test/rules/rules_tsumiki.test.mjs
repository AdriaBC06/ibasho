// Ibasho — tests de las reglas de Tsumiki versus (0.9.0): invitación, sala,
// partida, resultado, historial y marcador.
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
import { get, push, ref, remove, serverTimestamp, set, update } from 'firebase/database';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', '..', 'database.rules.json'), 'utf8');

const ADMIN = 'uid-admin';
const ANA = 'uid-ana';
const BEA = 'uid-bea';
const CRIS = 'uid-cris';
const PAIR = `${ANA}_${BEA}`;
const ROOM = `tsumiki/${PAIR}`;

const testEnv = await initializeTestEnvironment({
  projectId: process.env.GCLOUD_PROJECT ?? 'demo-ibasho',
  database: {
    rules,
    host: process.env.IBASHO_EMULATOR_HOST ?? '127.0.0.1',
    port: Number(process.env.IBASHO_EMULATOR_DB_PORT ?? 9000),
  },
});

const now = Date.now();

const entry = (username) => ({
  accountId: `uid-${username}`,
  username,
  createdAt: now,
  createdBy: ADMIN,
  disabled: false,
});

/// Ana y Bea son amigas; Cris no lo es de ninguna. [room] es lo que haya ya
/// en la sala.
async function seed(room = null) {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      admins: { [ADMIN]: true },
      allowlist: { [ADMIN]: entry('admin'), [ANA]: entry('ana'), [BEA]: entry('bea'), [CRIS]: entry('cris') },
      users: {
        [ANA]: { friends: { [BEA]: { since: now } } },
        [BEA]: { friends: { [ANA]: { since: now } } },
        [CRIS]: { coins: 0 },
      },
      ...(room ? { tsumiki: { [PAIR]: { a: ANA, b: BEA, ...room } } } : {}),
    });
  });
}

const db = (uid) => testEnv.authenticatedContext(uid).database();

/// La invitación de Ana a Bea, como la escribe la app.
const invite = (over = {}) => ({
  [`${ROOM}/a`]: ANA,
  [`${ROOM}/b`]: BEA,
  [`${ROOM}/live`]: {
    id: 'm1',
    seed: 1234,
    host: ANA,
    guest: BEA,
    state: 'wait',
    at: serverTimestamp(),
    p: { [ANA]: { ping: serverTimestamp() } },
  },
  [`users/${BEA}/tsumikiInbox/${ANA}`]: { at: serverTimestamp(), id: 'm1' },
  ...over,
});

/// Una sala esperando a Bea, creada hace [ago] ms.
const waiting = (ago = 1000) => ({
  live: { id: 'm1', seed: 1234, host: ANA, guest: BEA, state: 'wait', at: now - ago, p: { [ANA]: { ping: now - ago } } },
});

/// Una partida en juego; [pings] son los ms desde el último `ping` de cada una.
const playing = (pings = { [ANA]: 1000, [BEA]: 1000 }, extra = {}) => ({
  live: {
    id: 'm1',
    seed: 1234,
    host: ANA,
    guest: BEA,
    state: 'play',
    at: now - 60000,
    start: now - 50000,
    p: {
      [ANA]: { ping: now - pings[ANA], board: '', lines: 0, sent: 0 },
      [BEA]: { ping: now - pings[BEA], board: '', lines: 0, sent: 0 },
    },
  },
  ...extra,
});

/// Lo que escribe quien pierde (o quien gana por abandono): resultado,
/// historial, marcador y `done`, todo junto.
const finish = (w, why, over = {}) => ({
  [`${ROOM}/live/result`]: { w, why, at: serverTimestamp() },
  [`${ROOM}/live/state`]: 'done',
  [`${ROOM}/history/m1`]: { w, why, at: serverTimestamp(), dur: 50, s: { [ANA]: 3, [BEA]: 1 }, l: { [ANA]: 9, [BEA]: 4 } },
  [`${ROOM}/score/${w}`]: 1,
  ...over,
});

test.beforeEach(() => seed());
test.after(async () => {
  await testEnv.cleanup();
});

// --- Invitar --------------------------------------------------------------

test('Ana invita a Bea: sala y buzón a la vez', async () => {
  await assertSucceeds(update(ref(db(ANA), '/'), invite()));
});

test('no se invita a quien no es amigo', async () => {
  const pair = `${ANA}_${CRIS}`;
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`tsumiki/${pair}/a`]: ANA,
      [`tsumiki/${pair}/b`]: CRIS,
      [`tsumiki/${pair}/live`]: { id: 'm1', seed: 1, host: ANA, guest: CRIS, state: 'wait', at: serverTimestamp() },
    }),
  );
  await assertFails(set(ref(db(ANA), `users/${CRIS}/tsumikiInbox/${ANA}`), { at: serverTimestamp(), id: 'm1' }));
});

test('nadie de fuera escribe en la sala ni la lee', async () => {
  await seed(waiting());
  await assertFails(update(ref(db(CRIS), '/'), invite()));
  await assertFails(get(ref(db(CRIS), ROOM)));
  await assertSucceeds(get(ref(db(BEA), ROOM)));
});

test('la invitación es en nombre propio y en espera', async () => {
  await assertFails(
    update(ref(db(BEA), '/'), {
      [`${ROOM}/live`]: { id: 'm1', seed: 1, host: ANA, guest: BEA, state: 'wait', at: serverTimestamp() },
    }),
  );
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`${ROOM}/a`]: ANA,
      [`${ROOM}/b`]: BEA,
      [`${ROOM}/live`]: { id: 'm1', seed: 1, host: ANA, guest: BEA, state: 'play', at: serverTimestamp() },
    }),
  );
});

test('la invitación no trae resultado ni ataques', async () => {
  const live = invite()[`${ROOM}/live`];
  await assertFails(
    update(ref(db(ANA), '/'), invite({ [`${ROOM}/live`]: { ...live, result: { w: ANA, why: 'top', at: serverTimestamp() } } })),
  );
  await assertFails(
    update(ref(db(ANA), '/'), invite({ [`${ROOM}/live`]: { ...live, atk: { [ANA]: { x: { rows: 4, hole: 0 } } } } })),
  );
});

test('no se pisa una partida en juego, sí una vieja o sin señales', async () => {
  await seed(playing());
  await assertFails(update(ref(db(ANA), '/'), invite()));
  await seed(playing({ [ANA]: 70000, [BEA]: 70000 }));
  await assertSucceeds(update(ref(db(ANA), '/'), invite()));
  await seed(playing({ [ANA]: 1000, [BEA]: 70000 }));
  await assertFails(update(ref(db(ANA), '/'), invite()));
});

test('sí se pisa una que ya acabó (revancha)', async () => {
  await seed({ live: { ...playing().live, state: 'done', result: { w: ANA, why: 'top', at: now - 1000 } } });
  await assertSucceeds(update(ref(db(BEA), '/'), {
    [`${ROOM}/live`]: { id: 'm2', seed: 9, host: BEA, guest: ANA, state: 'wait', at: serverTimestamp(), p: { [BEA]: { ping: serverTimestamp() } } },
    [`users/${ANA}/tsumikiInbox/${BEA}`]: { at: serverTimestamp(), id: 'm2' },
  }));
});

// --- Responder ------------------------------------------------------------

const accept = (over = {}) => ({
  [`${ROOM}/live/state`]: 'play',
  [`${ROOM}/live/start`]: serverTimestamp(),
  [`${ROOM}/live/p/${BEA}`]: { ping: serverTimestamp(), board: '' },
  [`users/${BEA}/tsumikiInbox/${ANA}`]: null,
  ...over,
});

test('Bea acepta: en juego, su ping y fuera del buzón', async () => {
  await seed(waiting());
  await assertSucceeds(update(ref(db(BEA), '/'), accept()));
});

test('no se acepta una invitación de hace más de 10 minutos', async () => {
  await seed(waiting(11 * 60000));
  await assertFails(update(ref(db(BEA), '/'), accept()));
});

test('quien invita no acepta su propia invitación', async () => {
  await seed(waiting());
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`${ROOM}/live/state`]: 'play',
      [`${ROOM}/live/start`]: serverTimestamp(),
    }),
  );
});

test('Bea rechaza y Ana cancela', async () => {
  await seed(waiting());
  await assertSucceeds(update(ref(db(BEA), '/'), { [`${ROOM}/live/state`]: 'no', [`users/${BEA}/tsumikiInbox/${ANA}`]: null }));
  await seed(waiting());
  await assertFails(set(ref(db(BEA), `${ROOM}/live/state`), 'gone'));
  await assertSucceeds(update(ref(db(ANA), '/'), { [`${ROOM}/live/state`]: 'gone', [`users/${BEA}/tsumikiInbox/${ANA}`]: null }));
});

test('solo el dueño del buzón y quien invita lo tocan', async () => {
  await seed(waiting());
  await testEnv.withSecurityRulesDisabled((c) =>
    set(ref(c.database(), `users/${BEA}/tsumikiInbox/${ANA}`), { at: now, id: 'm1' }),
  );
  await assertFails(remove(ref(db(CRIS), `users/${BEA}/tsumikiInbox/${ANA}`)));
  await assertFails(get(ref(db(ANA), `users/${BEA}/tsumikiInbox`)));
  await assertSucceeds(get(ref(db(BEA), `users/${BEA}/tsumikiInbox`)));
  await assertSucceeds(remove(ref(db(BEA), `users/${BEA}/tsumikiInbox/${ANA}`)));
});

// --- Jugar ----------------------------------------------------------------

test('cada una escribe su tablero y sus ataques, no los de la otra', async () => {
  await seed(playing());
  await assertSucceeds(
    update(ref(db(ANA), `${ROOM}/live/p/${ANA}`), { board: '.'.repeat(190) + 'gggggggggi', ping: serverTimestamp(), lines: 3, sent: 1, meter: 40.5, over: false, fx: { fog: true } }),
  );
  await assertFails(update(ref(db(ANA), `${ROOM}/live/p/${BEA}`), { lines: 3 }));
  await assertSucceeds(set(push(ref(db(ANA), `${ROOM}/live/atk/${ANA}`)), { rows: 2, hole: 5 }));
  await assertSucceeds(set(push(ref(db(ANA), `${ROOM}/live/atk/${ANA}`)), { sab: 'fog' }));
  await assertFails(set(push(ref(db(ANA), `${ROOM}/live/atk/${BEA}`)), { rows: 2, hole: 5 }));
});

test('los ataques tienen forma y no se borran', async () => {
  await seed(playing(undefined, {}));
  await assertFails(set(push(ref(db(ANA), `${ROOM}/live/atk/${ANA}`)), { rows: 0, hole: 5 }));
  await assertFails(set(push(ref(db(ANA), `${ROOM}/live/atk/${ANA}`)), { rows: 2, hole: 10 }));
  await assertFails(set(push(ref(db(ANA), `${ROOM}/live/atk/${ANA}`)), { sab: 'boom' }));
  await assertFails(set(push(ref(db(ANA), `${ROOM}/live/atk/${ANA}`)), { rows: 2, hole: 1, sab: 'fog' }));
  await testEnv.withSecurityRulesDisabled((c) => set(ref(c.database(), `${ROOM}/live/atk/${ANA}/x1`), { rows: 1, hole: 1 }));
  await assertFails(remove(ref(db(ANA), `${ROOM}/live/atk/${ANA}/x1`)));
});

test('el tablero son 200 letras de pieza como mucho', async () => {
  await seed(playing());
  await assertFails(update(ref(db(ANA), `${ROOM}/live/p/${ANA}`), { board: '.'.repeat(201) }));
  await assertFails(update(ref(db(ANA), `${ROOM}/live/p/${ANA}`), { board: 'xyz' }));
  await assertFails(update(ref(db(ANA), `${ROOM}/live/p/${ANA}`), { ping: now - 5000 }));
});

test('no se juega en una sala que no está en juego', async () => {
  await seed(waiting());
  await assertFails(update(ref(db(ANA), `${ROOM}/live/p/${ANA}`), { lines: 1 }));
  await assertFails(set(push(ref(db(ANA), `${ROOM}/live/atk/${ANA}`)), { rows: 1, hole: 1 }));
});

// --- Acabar ---------------------------------------------------------------

test('quien se llena da la victoria a la otra, con historial y marcador', async () => {
  await seed(playing());
  await assertSucceeds(update(ref(db(BEA), '/'), finish(ANA, 'top')));
});

test('nadie se da la victoria por llenarse la otra', async () => {
  await seed(playing());
  await assertFails(update(ref(db(ANA), '/'), finish(ANA, 'top')));
  await assertFails(update(ref(db(ANA), '/'), finish(ANA, 'leave')));
});

test('irse da la victoria a la otra', async () => {
  await seed(playing());
  await assertSucceeds(update(ref(db(ANA), '/'), finish(BEA, 'leave')));
});

test('ganar por abandono solo si la otra lleva 20 s callada', async () => {
  await seed(playing());
  await assertFails(update(ref(db(ANA), '/'), finish(ANA, 'quit')));
  await seed(playing({ [ANA]: 1000, [BEA]: 25000 }));
  await assertSucceeds(update(ref(db(ANA), '/'), finish(ANA, 'quit')));
});

test('el resultado es uno solo', async () => {
  await seed(playing());
  await assertSucceeds(update(ref(db(BEA), '/'), finish(ANA, 'top')));
  await assertFails(update(ref(db(ANA), '/'), finish(BEA, 'top', { [`${ROOM}/live/state`]: null })));
});

test('el historial va con su resultado y el marcador sube 1 al que gana', async () => {
  await seed(playing());
  await assertFails(update(ref(db(BEA), '/'), finish(ANA, 'top', { [`${ROOM}/history/m1`]: null })));
  await assertFails(update(ref(db(BEA), '/'), finish(ANA, 'top', { [`${ROOM}/score/${ANA}`]: 2 })));
  await assertFails(update(ref(db(BEA), '/'), finish(ANA, 'top', { [`${ROOM}/score/${ANA}`]: null, [`${ROOM}/score/${BEA}`]: 1 })));
  await assertFails(
    update(ref(db(BEA), '/'), finish(ANA, 'top', {
      [`${ROOM}/history/m1`]: { w: BEA, why: 'top', at: serverTimestamp(), dur: 50 },
    })),
  );
  await assertFails(
    update(ref(db(BEA), '/'), finish(ANA, 'top', {
      [`${ROOM}/history/m1`]: null,
      [`${ROOM}/history/otra`]: { w: ANA, why: 'top', at: serverTimestamp(), dur: 50 },
    })),
  );
});

test('el marcador suma a lo que había', async () => {
  await seed(playing(undefined, { score: { [ANA]: 4, [BEA]: 2 } }));
  await assertFails(update(ref(db(BEA), '/'), finish(ANA, 'top')));
  await assertSucceeds(update(ref(db(BEA), '/'), finish(ANA, 'top', { [`${ROOM}/score/${ANA}`]: 5 })));
});

test('el historial y el marcador no se tocan sueltos', async () => {
  await seed(playing(undefined, { score: { [ANA]: 4 }, history: { m0: { w: ANA, why: 'top', at: now - 9000, dur: 30 } } }));
  await assertFails(set(ref(db(ANA), `${ROOM}/score/${ANA}`), 5));
  await assertFails(remove(ref(db(BEA), `${ROOM}/history/m0`)));
  await assertFails(set(ref(db(BEA), `${ROOM}/live/state`), 'done'));
});
