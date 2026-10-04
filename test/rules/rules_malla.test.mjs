// Ibasho — tests de las reglas de Malla online (0.9.1): sala por código,
// invitaciones, partida con saltos e historial.
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
import { get, ref, remove, serverTimestamp, set, update } from 'firebase/database';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', '..', 'database.rules.json'), 'utf8');

const ADMIN = 'uid-admin';
const ANA = 'uid-ana';
const BEA = 'uid-bea';
const CRIS = 'uid-cris';
const DANI = 'uid-dani';
const CODE = 'ABC234';
const ROOM = `malla/${CODE}`;

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

const tama = { name: 'Mochi', personality: 'calm', look: { body: 2, eyes: 1, color: '#5BC8F5', colorMode: 'solid' } };

const member = (name, at = now - 5000, over = {}) => ({ name, marker: name[0], color: '#397d79', at, ping: at, tama, ...over });

/// Ana y Bea son amigas; Cris y Dani no lo son de nadie. [room] es lo que
/// haya ya en la sala.
async function seed(room = null, extra = {}) {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      admins: { [ADMIN]: true },
      allowlist: {
        [ADMIN]: entry('admin'),
        [ANA]: entry('ana'),
        [BEA]: entry('bea'),
        [CRIS]: entry('cris'),
        [DANI]: entry('dani'),
      },
      users: {
        [ANA]: { friends: { [BEA]: { since: now } } },
        [BEA]: { friends: { [ANA]: { since: now } } },
        [CRIS]: { coins: 0 },
      },
      ...(room ? { malla: { [CODE]: room } } : {}),
      ...extra,
    });
  });
}

const db = (uid) => testEnv.authenticatedContext(uid).database();

/// La sala recién creada por Ana, como la escribe la app.
const created = (over = {}) => ({
  host: ANA,
  at: serverTimestamp(),
  size: 3,
  max: 3,
  chain: false,
  state: 'wait',
  count: 1,
  members: { [ANA]: { ...member('Ana'), at: serverTimestamp(), ping: serverTimestamp() } },
  ...over,
});

/// Una sala esperando con [members] dentro.
const waiting = (members = { [ANA]: member('Ana', now - 9000), [BEA]: member('Bea', now - 8000) }, over = {}) => ({
  host: ANA,
  at: now - 10000,
  size: 3,
  max: 3,
  chain: false,
  state: 'wait',
  count: Object.keys(members).length,
  members,
  ...over,
});

/// En juego: Ana asiento 0, Bea 1, Cris 2; le toca a [turn] con [n] jugadas.
/// [pings] son los ms desde la última señal de cada una.
const playing = ({ turn = 0, n = 0, moves = undefined, pings = {} } = {}) => ({
  ...waiting({
    [ANA]: member('Ana', now - 9000, { ping: now - (pings[ANA] ?? 1000) }),
    [BEA]: member('Bea', now - 8000, { ping: now - (pings[BEA] ?? 1000) }),
    [CRIS]: member('Cris', now - 7000, { ping: now - (pings[CRIS] ?? 1000) }),
  }),
  state: 'play',
  order: { 0: ANA, 1: BEA, 2: CRIS },
  start: 0,
  startAt: now - 6000,
  turn,
  n,
  ...(moves ? { moves } : {}),
});

const EDGE = '41.98,16.0|67.96,31.0';

/// La jugada de [seat] como la escribe la app.
const move = (seat, n, nextTurn, over = {}) => ({
  [`${ROOM}/moves/${n}`]: { k: EDGE, p: seat },
  [`${ROOM}/n`]: n + 1,
  [`${ROOM}/turn`]: nextTurn,
  ...over,
});

test.beforeEach(() => seed());
test.after(async () => {
  await testEnv.cleanup();
});

// --- Crear y leer ---------------------------------------------------------

test('Ana crea una sala a su nombre con un código libre', async () => {
  await assertSucceeds(set(ref(db(ANA), ROOM), created()));
});

test('no se crea a nombre de otro, ya empezada ni con más gente', async () => {
  await assertFails(set(ref(db(BEA), ROOM), created()));
  await assertFails(set(ref(db(ANA), ROOM), created({ state: 'play' })));
  await assertFails(set(ref(db(ANA), ROOM), created({ members: { [ANA]: member('Ana'), [BEA]: member('Bea') } })));
  await assertFails(set(ref(db(ANA), ROOM), created({ members: { [ANA]: member('Ana'), [BEA]: member('Bea') }, count: 2 })));
  await assertFails(set(ref(db(ANA), ROOM), created({ order: { 0: ANA, 1: BEA } })));
  await assertFails(set(ref(db(ANA), 'malla/abc123'), created()));
  await assertFails(set(ref(db(ANA), 'malla/ABC12O'), created()));
  await assertFails(set(ref(db(ANA), ROOM), created({ size: 9 })));
  await assertFails(set(ref(db(ANA), ROOM), created({ max: 7 })));
});

test('no se pisa un código en uso; sí uno de hace más de un día', async () => {
  await seed(waiting());
  await assertFails(set(ref(db(CRIS), ROOM), { ...created(), host: CRIS, members: { [CRIS]: member('Cris', serverTimestamp(), { ping: serverTimestamp() }) } }));
  await seed(waiting(undefined, { at: now - 2 * 86400000 }));
  await assertSucceeds(set(ref(db(CRIS), ROOM), { ...created(), host: CRIS, members: { [CRIS]: member('Cris', serverTimestamp(), { ping: serverTimestamp() }) } }));
});

test('cualquiera lee una sala que espera; en juego, solo los de dentro', async () => {
  await seed(waiting());
  await assertSucceeds(get(ref(db(CRIS), ROOM)));
  await assertSucceeds(get(ref(db(DANI), 'malla/ZZZ999')));
  await assertFails(get(ref(db(CRIS), 'malla')));
  await seed({ ...playing(), members: { [ANA]: member('Ana'), [BEA]: member('Bea') }, order: { 0: ANA, 1: BEA } });
  await assertFails(get(ref(db(DANI), ROOM)));
  await assertSucceeds(get(ref(db(BEA), ROOM)));
});

// --- Entrar y salir -------------------------------------------------------

const enter = (uid, name, count) => ({
  [`${ROOM}/members/${uid}`]: member(name, serverTimestamp(), { ping: serverTimestamp() }),
  [`${ROOM}/count`]: count,
});

test('entra quien tiene el código, en su nombre y si cabe', async () => {
  await seed(waiting());
  await assertFails(set(ref(db(CRIS), `${ROOM}/members/${CRIS}`), member('Cris', serverTimestamp(), { ping: serverTimestamp() })));
  await assertFails(update(ref(db(CRIS), '/'), enter(CRIS, 'Cris', 2)));
  await assertSucceeds(update(ref(db(CRIS), '/'), enter(CRIS, 'Cris', 3)));
  await assertFails(update(ref(db(DANI), '/'), enter(DANI, 'Dani', 4)));
  await assertFails(update(ref(db(DANI), '/'), enter(DANI, 'Dani', 3)));
});

test('el contador no se toca a mano', async () => {
  await seed(waiting());
  await assertFails(set(ref(db(CRIS), `${ROOM}/count`), 1));
  await assertFails(set(ref(db(ANA), `${ROOM}/count`), 1));
});

test('no se mete a otro ni se entra con datos raros', async () => {
  await seed(waiting());
  await assertFails(set(ref(db(CRIS), `${ROOM}/members/${DANI}`), member('Dani')));
  await assertFails(set(ref(db(CRIS), `${ROOM}/members/${CRIS}`), member('Cris', now, { color: 'red' })));
  await assertFails(set(ref(db(CRIS), `${ROOM}/members/${CRIS}`), member('Cris', now, { coins: 9 })));
  await assertFails(set(ref(db(CRIS), `${ROOM}/members/${CRIS}`), member('Cris', now, { tama: { ...tama, personality: 'evil' } })));
  await assertFails(set(ref(db(CRIS), `${ROOM}/members/${CRIS}`), member('Cris', now, { marker: '' })));
});

test('no se entra en una partida empezada', async () => {
  await seed(playing());
  await assertFails(set(ref(db(DANI), `${ROOM}/members/${DANI}`), member('Dani', serverTimestamp())));
});

test('en la sala cada uno se va solo; quien la crea la cierra', async () => {
  await seed(waiting());
  await assertFails(remove(ref(db(BEA), `${ROOM}/members/${BEA}`)));
  await assertSucceeds(update(ref(db(BEA), '/'), { [`${ROOM}/members/${BEA}`]: null, [`${ROOM}/count`]: 1 }));
  await assertFails(update(ref(db(BEA), '/'), { [`${ROOM}/members/${ANA}`]: null, [`${ROOM}/count`]: 0 }));
  await assertFails(set(ref(db(BEA), `${ROOM}/state`), 'gone'));
  await assertSucceeds(set(ref(db(ANA), `${ROOM}/state`), 'gone'));
});

test('la señal de vida es la propia y con la hora del servidor', async () => {
  await seed(playing());
  await assertSucceeds(set(ref(db(BEA), `${ROOM}/members/${BEA}/ping`), serverTimestamp()));
  await assertFails(set(ref(db(BEA), `${ROOM}/members/${ANA}/ping`), serverTimestamp()));
  await assertFails(set(ref(db(BEA), `${ROOM}/members/${BEA}/ping`), now + 60000));
  await assertFails(set(ref(db(DANI), `${ROOM}/members/${DANI}/ping`), serverTimestamp()));
});

// --- Invitar --------------------------------------------------------------

test('se invita a un amigo con el código, no a quien no lo es', async () => {
  await assertSucceeds(set(ref(db(ANA), `users/${BEA}/mallaInbox/${ANA}`), { at: serverTimestamp(), code: CODE }));
  await assertFails(set(ref(db(ANA), `users/${CRIS}/mallaInbox/${ANA}`), { at: serverTimestamp(), code: CODE }));
  await assertFails(set(ref(db(CRIS), `users/${BEA}/mallaInbox/${CRIS}`), { at: serverTimestamp(), code: CODE }));
  await assertFails(set(ref(db(ANA), `users/${BEA}/mallaInbox/${ANA}`), { at: serverTimestamp(), code: 'nope' }));
});

test('la invitación la tira quien invita o el dueño del buzón', async () => {
  await seed(null, { users: { [ANA]: { friends: { [BEA]: { since: now } } }, [BEA]: { friends: { [ANA]: { since: now } }, mallaInbox: { [ANA]: { at: now, code: CODE } } } } });
  await assertFails(remove(ref(db(CRIS), `users/${BEA}/mallaInbox/${ANA}`)));
  await assertSucceeds(remove(ref(db(BEA), `users/${BEA}/mallaInbox/${ANA}`)));
});

// --- Empezar --------------------------------------------------------------

const start = (over = {}) => ({
  [`${ROOM}/state`]: 'play',
  [`${ROOM}/order`]: { 0: ANA, 1: BEA },
  [`${ROOM}/start`]: 1,
  [`${ROOM}/startAt`]: serverTimestamp(),
  [`${ROOM}/turn`]: 1,
  [`${ROOM}/n`]: 0,
  ...over,
});

test('quien la crea la empieza con los de dentro', async () => {
  await seed(waiting());
  await assertFails(update(ref(db(BEA), '/'), start()));
  await assertFails(update(ref(db(ANA), '/'), start({ [`${ROOM}/order`]: { 0: ANA, 1: DANI } })));
  await assertFails(update(ref(db(ANA), '/'), start({ [`${ROOM}/order`]: { 0: ANA } })));
  await assertFails(update(ref(db(ANA), '/'), start({ [`${ROOM}/turn`]: 0 })));
  await assertSucceeds(update(ref(db(ANA), '/'), start()));
});

// --- Jugar ----------------------------------------------------------------

test('juega a quien le toca, en su asiento, con n + 1', async () => {
  await seed(playing({ turn: 0 }));
  await assertFails(update(ref(db(BEA), '/'), move(1, 0, 2)));
  await assertFails(update(ref(db(BEA), '/'), move(0, 0, 1)));
  await assertFails(update(ref(db(ANA), '/'), move(0, 0, 1, { [`${ROOM}/n`]: 2 })));
  await assertFails(update(ref(db(ANA), '/'), { [`${ROOM}/moves/0`]: { k: EDGE, p: 0 } }));
  await assertFails(update(ref(db(DANI), '/'), move(0, 0, 1)));
  await assertSucceeds(update(ref(db(ANA), '/'), move(0, 0, 1)));
});

test('no se reescribe una jugada ni se salta el hueco', async () => {
  await seed(playing({ turn: 1, n: 1, moves: { 0: { k: EDGE, p: 0 } } }));
  await assertFails(update(ref(db(BEA), '/'), move(1, 0, 2, { [`${ROOM}/n`]: 1 })));
  await assertFails(update(ref(db(BEA), '/'), move(1, 2, 2, { [`${ROOM}/n`]: 2 })));
  await assertSucceeds(update(ref(db(BEA), '/'), move(1, 1, 2)));
});

test('las aristas son claves de Malla', async () => {
  await seed(playing({ turn: 0 }));
  await assertFails(update(ref(db(ANA), '/'), { ...move(0, 0, 1), [`${ROOM}/moves/0`]: { k: '<script>', p: 0 } }));
  await assertFails(update(ref(db(ANA), '/'), { ...move(0, 0, 1), [`${ROOM}/moves/0`]: { k: EDGE, p: 0, x: 1 } }));
});

const outMove = (seat, n, nextTurn) => ({
  [`${ROOM}/moves/${n}`]: { o: seat },
  [`${ROOM}/n`]: n + 1,
  [`${ROOM}/turn`]: nextTurn,
});

test('cada uno puede irse cuando quiera', async () => {
  await seed(playing({ turn: 0 }));
  await assertSucceeds(update(ref(db(BEA), '/'), outMove(1, 0, 0)));
});

test('a otro solo se le salta tras 20 s sin señal', async () => {
  await seed(playing({ turn: 1, pings: { [BEA]: 5000 } }));
  await assertFails(update(ref(db(ANA), '/'), outMove(1, 0, 2)));
  await seed(playing({ turn: 1, pings: { [BEA]: 30000 } }));
  await assertSucceeds(update(ref(db(ANA), '/'), outMove(1, 0, 2)));
  await seed(playing({ turn: 1, pings: { [BEA]: 30000 } }));
  await assertFails(update(ref(db(DANI), '/'), outMove(1, 0, 2)));
  await assertFails(update(ref(db(ANA), '/'), outMove(5, 0, 2)));
});

test('acabar la deja cualquiera de dentro; la borra quien la creó', async () => {
  await seed(playing());
  await assertFails(set(ref(db(DANI), `${ROOM}/state`), 'done'));
  await assertFails(remove(ref(db(ANA), ROOM)));
  await assertSucceeds(set(ref(db(CRIS), `${ROOM}/state`), 'done'));
  await assertFails(remove(ref(db(BEA), ROOM)));
  await assertSucceeds(remove(ref(db(ANA), ROOM)));
});

test('la revancha la apunta quien la creó, ya acabada', async () => {
  await seed({ ...playing(), state: 'done' });
  await assertFails(set(ref(db(BEA), `${ROOM}/next`), 'XYZ789'));
  await assertFails(set(ref(db(ANA), `${ROOM}/next`), CODE));
  await assertSucceeds(set(ref(db(ANA), `${ROOM}/next`), 'XYZ789'));
  await seed(playing());
  await assertFails(set(ref(db(ANA), `${ROOM}/next`), 'XYZ789'));
});

// --- Historial ------------------------------------------------------------

const record = (over = {}) => ({
  at: serverTimestamp(),
  size: 3,
  me: 0,
  why: 'board',
  p: {
    0: { a: ANA, name: 'Ana', s: 5, marker: 'A', color: '#397d79', tama },
    1: { a: CRIS, name: 'Cris', s: 4, marker: 'C', color: '#bd6f57' },
  },
  w: { 0: true },
  ...over,
});

test('cada uno guarda y lee solo su historial', async () => {
  await assertSucceeds(set(ref(db(ANA), `mallaHistory/${ANA}/${CODE}`), record()));
  await assertSucceeds(get(ref(db(ANA), `mallaHistory/${ANA}`)));
  await assertFails(get(ref(db(BEA), `mallaHistory/${ANA}`)));
  await assertFails(set(ref(db(BEA), `mallaHistory/${ANA}/${CODE}`), record()));
  await assertSucceeds(remove(ref(db(ANA), `mallaHistory/${ANA}/${CODE}`)));
});

test('el historial tiene la forma de la app', async () => {
  await assertFails(set(ref(db(ANA), `mallaHistory/${ANA}/${CODE}`), record({ why: 'cheat' })));
  await assertFails(set(ref(db(ANA), `mallaHistory/${ANA}/${CODE}`), record({ me: 3 })));
  await assertFails(set(ref(db(ANA), `mallaHistory/${ANA}/${CODE}`), record({ coins: 5 })));
  await assertFails(set(ref(db(ANA), `mallaHistory/${ANA}/nope`), record()));
});
