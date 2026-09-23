// Ibasho — tests de las reglas de la 0.6.0: los tickets del gacha, el tope
// semanal, el deposito de bolas, cada bola del pinball, la coleccion de
// premios y el Catalogo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Se lanzan con:   ./tool/test_rules.sh
//
// Lo que protegen las reglas aqui es la economia, no la rareza: el sorteo lo
// hace la app. Por eso los tests miran que los tickets bajen lo que cuesta la
// tirada, que el deposito suba en tantas bolas como tiradas y que las bolas
// dirigidas del Catalogo no nazcan antes de las 70. Al cargar el pinball,
// que el deposito baje justo lo que dice el recibo y nada suba.

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
const WEEK = 604800000;
const week = Math.floor(now / WEEK);

const entry = (username, extra = {}) => ({
  accountId: `uid-${username}`,
  username,
  createdAt: now,
  createdBy: ADMIN,
  disabled: false,
  ...extra,
});

const noBalls = { n: 0, r: 0, sr: 0, ssr: 0, ur: 0, mu: 0 };

/// Ana tiene 500 monedas, 12 tickets normales y 1 dorado, y el deposito a
/// cero.
async function seed(extra = {}) {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      admins: { [ADMIN]: true },
      allowlist: { [ADMIN]: entry('admin'), [ANA]: entry('ana') },
      usernames: { admin: ADMIN, ana: ANA },
      shop: { prices: { ticket_gachaken: 25, ticket_kinken: 150 } },
      users: {
        [ADMIN]: {},
        [ANA]: {
          coins: 500,
          tickets: { gachaken: 12, kinken: 1 },
          gacha: { balls: noBalls },
          ...extra,
        },
      },
    });
  });
}

const db = (uid) => testEnv.authenticatedContext(uid).database();

test.beforeEach(() => seed());
test.after(async () => {
  await testEnv.cleanup();
});

// --- Comprar tickets --------------------------------------------------------

/// Una compra de [qty] tickets de [kind], con el contador semanal ya puesto.
const buy = (kind, qty, { coins, tickets, bought = {} }) => ({
  [`users/${ANA}/shop/last`]: { item: `ticket_${kind}`, qty, at: serverTimestamp() },
  [`users/${ANA}/coins`]: coins,
  [`users/${ANA}/tickets/${kind}`]: tickets,
  [`users/${ANA}/shop/week`]: { n: week, gachaken: 0, kinken: 0, ...bought },
});

test('comprar 3 tickets normales baja las monedas y sube el contador', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), buy('gachaken', 3, { coins: 425, tickets: 15, bought: { gachaken: 3 } })),
  );
});

test('sin tocar el contador semanal, la compra no cuela', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'ticket_gachaken', qty: 3, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 425,
      [`users/${ANA}/tickets/gachaken`]: 15,
    }),
  );
});

test('no se pueden comprar mas de 10 tickets normales en una semana', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), buy('gachaken', 11, { coins: 225, tickets: 23, bought: { gachaken: 11 } })),
  );
});

test('el segundo ticket dorado de la semana no cuela', async () => {
  await seed({ shop: { week: { n: week, gachaken: 0, kinken: 1 } } });
  await assertFails(
    update(ref(db(ANA), '/'), buy('kinken', 1, { coins: 350, tickets: 2, bought: { kinken: 2 } })),
  );
});

test('una semana vieja no sirve para saltarse el tope', async () => {
  await seed({ shop: { week: { n: week - 1, gachaken: 10, kinken: 1 } } });
  // La semana pasada ya no cuenta: se empieza de cero.
  await assertSucceeds(
    update(ref(db(ANA), '/'), buy('gachaken', 10, { coins: 250, tickets: 22, bought: { gachaken: 10 } })),
  );
  // Pero el contador tiene que ser el de esta semana.
  await seed({ shop: { week: { n: week - 1, gachaken: 10, kinken: 1 } } });
  await assertFails(
    update(ref(db(ANA), '/'), {
      ...buy('gachaken', 10, { coins: 250, tickets: 22 }),
      [`users/${ANA}/shop/week`]: { n: week - 1, gachaken: 20, kinken: 1 },
    }),
  );
});

test('nadie se regala tickets sin pasar por caja', async () => {
  await assertFails(set(ref(db(ANA), `/users/${ANA}/tickets/gachaken`), 99));
});

// --- Tirar ------------------------------------------------------------------

/// Una tirada de [count] bolas con [kind], con el deposito que queda.
const pull = (kind, count, { tickets, balls }) => ({
  [`users/${ANA}/gacha/last`]: { kind, count, at: serverTimestamp() },
  [`users/${ANA}/tickets/${kind}`]: tickets,
  [`users/${ANA}/gacha/balls`]: { ...noBalls, ...balls },
});

test('una tirada suelta gasta un ticket y da una bola', async () => {
  await assertSucceeds(update(ref(db(ANA), '/'), pull('gachaken', 1, { tickets: 11, balls: { n: 1 } })));
});

test('la tirada de 11 cuesta 10 tickets y da 11 bolas', async () => {
  await assertSucceeds(
    update(ref(db(ANA), '/'), pull('gachaken', 11, { tickets: 2, balls: { n: 8, r: 2, sr: 1 } })),
  );
});

test('once bolas por un ticket no cuelan', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), pull('gachaken', 1, { tickets: 11, balls: { n: 8, r: 2, sr: 1 } })),
  );
});

test('una tirada no puede dar mas bolas de las tiradas', async () => {
  await assertFails(update(ref(db(ANA), '/'), pull('gachaken', 1, { tickets: 11, balls: { ur: 2 } })));
});

test('el deposito no sube sin recibo de tirada', async () => {
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/balls`), { ...noBalls, ur: 5 }));
});

test('tirar sin tickets no cuela', async () => {
  await seed({ tickets: { gachaken: 0, kinken: 1 } });
  await assertFails(update(ref(db(ANA), '/'), pull('gachaken', 1, { tickets: -1, balls: { n: 1 } })));
});

test('una tirada de 11 con el dorado gasta 10 dorados, no 10 normales', async () => {
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/gacha/last`]: { kind: 'kinken', count: 11, at: serverTimestamp() },
      [`users/${ANA}/tickets/gachaken`]: 2,
      [`users/${ANA}/gacha/balls`]: { ...noBalls, sr: 11 },
    }),
  );
});

// --- El pinball: cargar bolas en la cola ------------------------------------

/// Ana con bolas en el deposito y una dirigida, lista para jugar.
const stocked = () =>
  seed({
    gacha: {
      balls: { ...noBalls, n: 4, sr: 2, ur: 1 },
      marked: { hats: { ssr: 2 } },
    },
  });

/// Cargar: `balls` y `marked` son lo cargado por rareza (y categoria);
/// `deposit` es como queda el deposito.
const play = (balls, marked, deposit, extra = {}, count) => ({
  [`users/${ANA}/gacha/play`]: {
    at: serverTimestamp(),
    count:
      count ??
      Object.values(balls).reduce((a, b) => a + b, 0) +
        Object.values(marked).reduce((a, m) => a + Object.values(m).reduce((x, y) => x + y, 0), 0),
    ...(Object.keys(balls).length ? { balls } : {}),
    ...(Object.keys(marked).length ? { marked } : {}),
  },
  [`users/${ANA}/gacha/balls`]: { ...noBalls, ...deposit },
  ...extra,
});

test('cargar 3 bolas en el pinball las quita del deposito', async () => {
  await stocked();
  await assertSucceeds(update(ref(db(ANA), '/'), play({ n: 2, sr: 1 }, {}, { n: 2, sr: 1, ur: 1 })));
});

test('cargar una dirigida la quita del Catalogo', async () => {
  await stocked();
  await assertSucceeds(
    update(
      ref(db(ANA), '/'),
      play({ n: 1 }, { hats: { ssr: 1 } }, { n: 3, sr: 2, ur: 1 }, { [`users/${ANA}/gacha/marked/hats/ssr`]: 1 }),
    ),
  );
});

test('el recibo tiene que cuadrar con lo que baja el deposito', async () => {
  await stocked();
  await assertFails(update(ref(db(ANA), '/'), play({ n: 1 }, {}, { n: 2, sr: 2, ur: 1 })));
});

test('cargar no puede subir ninguna rareza', async () => {
  await stocked();
  // Dice cargar dos N, pero ademas cambia un SR por un UR.
  await assertFails(update(ref(db(ANA), '/'), play({ n: 2 }, {}, { n: 2, sr: 1, ur: 2 })));
});

test('el recibo va por rareza: cargar N no puede bajar un UR', async () => {
  await stocked();
  await assertFails(update(ref(db(ANA), '/'), play({ n: 1 }, {}, { n: 4, sr: 2, ur: 0 })));
});

test('no caben mas de 5 bolas en la cola', async () => {
  await seed({ gacha: { balls: { ...noBalls, n: 9 } } });
  await assertFails(update(ref(db(ANA), '/'), play({ n: 6 }, {}, { n: 3 })));
});

test('una dirigida no puede subir con el recibo del pinball', async () => {
  await stocked();
  await assertFails(
    update(ref(db(ANA), '/'), play({ n: 1 }, {}, { n: 3, sr: 2, ur: 1 }, { [`users/${ANA}/gacha/marked/hats/ssr`]: 3 })),
  );
});

test('sin recibo del pinball el deposito no baja', async () => {
  await stocked();
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/balls`), { ...noBalls, n: 3, sr: 2, ur: 1 }));
});

// --- El pinball: cancelar y devolver ------------------------------------------

/// Ana con una partida cargada: 2 N, 1 UR y una SSR dirigida de sombreros.
/// En el deposito le quedan 2 N, 2 SR y ninguna UR.
const playing = () =>
  seed({
    gacha: {
      balls: { ...noBalls, n: 2, sr: 2 },
      marked: { hats: { ssr: 1 } },
      play: { at: 1, count: 4, balls: { n: 2, ur: 1 }, marked: { hats: { ssr: 1 } } },
    },
  });

const back = (deposit, extra = {}) => ({
  [`users/${ANA}/gacha/back`]: { at: serverTimestamp() },
  [`users/${ANA}/gacha/play`]: null,
  [`users/${ANA}/gacha/balls`]: { ...noBalls, ...deposit },
  ...extra,
});

test('cancelar devuelve las bolas que quedaban', async () => {
  await playing();
  // Ya se jugo una N: vuelven una N, la UR y la dirigida.
  await assertSucceeds(
    update(ref(db(ANA), '/'), back({ n: 3, sr: 2, ur: 1 }, { [`users/${ANA}/gacha/marked/hats/ssr`]: 2 })),
  );
});

test('cancelar no devuelve mas de lo cargado de cada rareza', async () => {
  await playing();
  await assertFails(update(ref(db(ANA), '/'), back({ n: 2, sr: 2, ur: 2 })));
  await assertFails(update(ref(db(ANA), '/'), back({ n: 2, sr: 3 })));
  await assertFails(
    update(ref(db(ANA), '/'), back({ n: 2, sr: 2 }, { [`users/${ANA}/gacha/marked/hats/ssr`]: 3 })),
  );
});

test('cancelar tiene que cerrar la partida', async () => {
  await playing();
  const { [`users/${ANA}/gacha/play`]: _, ...keep } = back({ n: 3, sr: 2 });
  await assertFails(update(ref(db(ANA), '/'), keep));
});

test('sin partida cargada no hay nada que devolver', async () => {
  await stocked();
  await assertFails(update(ref(db(ANA), '/'), back({ n: 5, sr: 2, ur: 1 })));
});

test('una partida cancelada no se devuelve dos veces', async () => {
  await playing();
  await assertSucceeds(update(ref(db(ANA), '/'), back({ n: 4, sr: 2, ur: 1 })));
  await assertFails(update(ref(db(ANA), '/'), back({ n: 6, sr: 2, ur: 2 })));
});

test('play no se borra sin cancelar', async () => {
  await playing();
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/play`), null));
});

// --- El pinball: cada bola jugada ---------------------------------------------

/// Ana a mitad de partida: le quedan 1 N, 1 UR y una SSR dirigida de
/// sombreros, y ya ha jugado una bola.
const midGame = (extra = {}) =>
  seed({
    gacha: {
      balls: noBalls,
      play: { at: 1, count: 4, done: 1, balls: { n: 1, ur: 1 }, marked: { hats: { ssr: 1 } } },
      ...extra,
    },
  });

/// Una jugada: el recibo `turn` y lo que cambia en la partida.
const turn = (receipt, played, extra = {}) => ({
  [`users/${ANA}/gacha/turn`]: { at: serverTimestamp(), ...receipt },
  [`users/${ANA}/gacha/play/done`]: 2,
  ...played,
  ...extra,
});

test('una bola perdida solo baja la partida', async () => {
  await midGame();
  await assertSucceeds(update(ref(db(ANA), '/'), turn({ rarity: 'n' }, { [`users/${ANA}/gacha/play/balls/n`]: null })));
});

test('una bola que entra da un premio de su rareza', async () => {
  await midGame();
  await assertSucceeds(
    update(
      ref(db(ANA), '/'),
      turn(
        { rarity: 'ur', prize: 'halo_gold' },
        { [`users/${ANA}/gacha/play/balls/ur`]: null },
        { [`users/${ANA}/prizes/halo_gold`]: 1 },
      ),
    ),
  );
});

test('un repetido suma una copia', async () => {
  await midGame();
  await testEnv.withSecurityRulesDisabled((c) => set(ref(c.database(), `/users/${ANA}/prizes/cap_red`), 2));
  await assertSucceeds(
    update(
      ref(db(ANA), '/'),
      turn({ rarity: 'n', prize: 'cap_red' }, { [`users/${ANA}/gacha/play/balls/n`]: null }, { [`users/${ANA}/prizes/cap_red`]: 3 }),
    ),
  );
});

test('el premio tiene que ser de la rareza de la bola', async () => {
  await midGame();
  // Una N no da una corona RGB.
  await assertFails(
    update(
      ref(db(ANA), '/'),
      turn(
        { rarity: 'n', prize: 'crown_rgb_rainbow' },
        { [`users/${ANA}/gacha/play/balls/n`]: null },
        { [`users/${ANA}/prizes/crown_rgb_rainbow`]: 1 },
      ),
    ),
  );
  // Ni un premio que no existe.
  await assertFails(
    update(
      ref(db(ANA), '/'),
      turn({ rarity: 'n', prize: 'cap_gold' }, { [`users/${ANA}/gacha/play/balls/n`]: null }, { [`users/${ANA}/prizes/cap_gold`]: 1 }),
    ),
  );
});

test('la bola dirigida da un premio de su categoria', async () => {
  await midGame();
  await assertSucceeds(
    update(
      ref(db(ANA), '/'),
      turn(
        { rarity: 'ssr', category: 'hats', prize: 'crown_gold' },
        { [`users/${ANA}/gacha/play/marked/hats/ssr`]: null },
        { [`users/${ANA}/prizes/crown_gold`]: 1 },
      ),
    ),
  );
  await midGame();
  await assertFails(
    update(
      ref(db(ANA), '/'),
      turn(
        { rarity: 'ssr', category: 'hats', prize: 'microphone_silver' },
        { [`users/${ANA}/gacha/play/marked/hats/ssr`]: null },
        { [`users/${ANA}/prizes/microphone_silver`]: 1 },
      ),
    ),
  );
});

test('una jugada tiene que gastar una bola de la partida', async () => {
  await midGame();
  // No baja nada.
  await assertFails(update(ref(db(ANA), '/'), turn({ rarity: 'n' }, {})));
  // Una SR que no esta en la partida.
  await assertFails(update(ref(db(ANA), '/'), turn({ rarity: 'sr' }, { [`users/${ANA}/gacha/play/balls/n`]: null })));
  // Sin subir `done`.
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/gacha/turn`]: { at: serverTimestamp(), rarity: 'n' },
      [`users/${ANA}/gacha/play/balls/n`]: null,
    }),
  );
});

test('una jugada no sube otras bolas de la partida', async () => {
  await midGame();
  await assertFails(
    update(
      ref(db(ANA), '/'),
      turn({ rarity: 'n' }, { [`users/${ANA}/gacha/play/balls/n`]: null, [`users/${ANA}/gacha/play/balls/ur`]: 3 }),
    ),
  );
});

test('la coleccion no sube sin jugada', async () => {
  await midGame();
  await assertFails(set(ref(db(ANA), `/users/${ANA}/prizes/halo_gold`), 1));
  // Ni dos premios con una bola.
  await assertFails(
    update(
      ref(db(ANA), '/'),
      turn(
        { rarity: 'ur', prize: 'halo_gold' },
        { [`users/${ANA}/gacha/play/balls/ur`]: null },
        { [`users/${ANA}/prizes/halo_gold`]: 1, [`users/${ANA}/prizes/devil_horns_red`]: 1 },
      ),
    ),
  );
});

test('no se juegan mas bolas de las cargadas', async () => {
  await seed({ gacha: { balls: noBalls, play: { at: 1, count: 1, done: 1, balls: { n: 1 } } } });
  await assertFails(update(ref(db(ANA), '/'), turn({ rarity: 'n' }, { [`users/${ANA}/gacha/play/balls/n`]: null })));
});

test('cancelar tras jugar solo devuelve lo que queda', async () => {
  await midGame();
  await assertSucceeds(update(ref(db(ANA), '/'), turn({ rarity: 'n' }, { [`users/${ANA}/gacha/play/balls/n`]: null })));
  // Ya no queda ninguna N.
  await assertFails(update(ref(db(ANA), '/'), back({ n: 1, ur: 1 }, { [`users/${ANA}/gacha/marked/hats/ssr`]: 1 })));
  await assertSucceeds(update(ref(db(ANA), '/'), back({ ur: 1 }, { [`users/${ANA}/gacha/marked/hats/ssr`]: 1 })));
});

// --- El Catalogo ------------------------------------------------------------

const wish = (count) => ({ category: 'hats', rarity: 'ssr', count });

test('poner un deseo no toca el contador', async () => {
  await midGame({ wish: wish(30) });
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/gacha/wish`), { category: 'music', rarity: 'sr', count: 30 }));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/wish`), { category: 'music', rarity: 'sr', count: 0 }));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/wish`), { category: 'music', rarity: 'sr', count: 69 }));
});

test('el deseo llega hasta UR', async () => {
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/gacha/wish`), wish(0)));
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/gacha/wish`), { ...wish(0), rarity: 'ur' }));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/wish`), { ...wish(0), rarity: 'mu' }));
});

test('cada bola jugada sube el contador', async () => {
  await midGame({ wish: wish(30) });
  await assertSucceeds(
    update(
      ref(db(ANA), '/'),
      turn({ rarity: 'n' }, { [`users/${ANA}/gacha/play/balls/n`]: null }, { [`users/${ANA}/gacha/wish`]: wish(31) }),
    ),
  );
  await midGame({ wish: wish(30) });
  await assertFails(
    update(
      ref(db(ANA), '/'),
      turn({ rarity: 'n' }, { [`users/${ANA}/gacha/play/balls/n`]: null }, { [`users/${ANA}/gacha/wish`]: wish(35) }),
    ),
  );
});

test('en la bola 70 nace la dirigida del deseo', async () => {
  await midGame({ wish: wish(69) });
  await assertSucceeds(
    update(
      ref(db(ANA), '/'),
      turn(
        { rarity: 'n' },
        { [`users/${ANA}/gacha/play/balls/n`]: null },
        { [`users/${ANA}/gacha/wish`]: wish(0), [`users/${ANA}/gacha/marked/hats/ssr`]: 1 },
      ),
    ),
  );
});

test('la dirigida no nace antes, ni distinta, ni sin reiniciar el contador', async () => {
  const lost = { [`users/${ANA}/gacha/play/balls/n`]: null };
  await midGame({ wish: wish(30) });
  await assertFails(
    update(ref(db(ANA), '/'), turn({ rarity: 'n' }, lost, { [`users/${ANA}/gacha/wish`]: wish(31), [`users/${ANA}/gacha/marked/hats/ssr`]: 1 })),
  );
  await midGame({ wish: wish(69) });
  await assertFails(
    update(ref(db(ANA), '/'), turn({ rarity: 'n' }, lost, { [`users/${ANA}/gacha/wish`]: wish(0), [`users/${ANA}/gacha/marked/music/ur`]: 1 })),
  );
  await midGame({ wish: wish(69) });
  await assertFails(update(ref(db(ANA), '/'), turn({ rarity: 'n' }, lost, { [`users/${ANA}/gacha/marked/hats/ssr`]: 1 })));
});

test('sin deseo no hay dirigida', async () => {
  await midGame();
  await assertFails(
    update(ref(db(ANA), '/'), turn({ rarity: 'n' }, { [`users/${ANA}/gacha/play/balls/n`]: null }, { [`users/${ANA}/gacha/marked/hats/ssr`]: 1 })),
  );
});

test('las bolas dirigidas no se regalan sueltas', async () => {
  await midGame({ wish: wish(69) });
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/marked/hats/ssr`), 1));
});

// --- El pachinko ---------------------------------------------------------------

/// Cargar una tanda: el recibo `pachinko` y el deposito que queda.
const pachinko = (balls, deposit, count) => ({
  [`users/${ANA}/gacha/pachinko`]: {
    at: serverTimestamp(),
    count: count ?? Object.values(balls).reduce((a, b) => a + b, 0),
    balls,
  },
  [`users/${ANA}/gacha/balls`]: { ...noBalls, ...deposit },
});

test('cargar el pachinko quita las bolas del deposito', async () => {
  await seed({ gacha: { balls: { ...noBalls, n: 30, sr: 5, ssr: 2 } } });
  await assertSucceeds(update(ref(db(ANA), '/'), pachinko({ n: 20, ssr: 2 }, { n: 10, sr: 5 })));
});

test('el recibo del pachinko tiene que cuadrar', async () => {
  await seed({ gacha: { balls: { ...noBalls, n: 30, sr: 5 } } });
  // Baja 20 N pero dice 19.
  await assertFails(update(ref(db(ANA), '/'), pachinko({ n: 19 }, { n: 10, sr: 5 })));
  // La cuenta no cuadra con las bolas.
  await assertFails(update(ref(db(ANA), '/'), pachinko({ n: 20 }, { n: 10, sr: 5 }, 21)));
});

test('al pachinko no entran UR ni ∞, ni mas de 50', async () => {
  await seed({ gacha: { balls: { ...noBalls, n: 60, ur: 2, mu: 1 } } });
  await assertFails(update(ref(db(ANA), '/'), pachinko({ ur: 1 }, { n: 60, ur: 1, mu: 1 })));
  await assertFails(update(ref(db(ANA), '/'), pachinko({ mu: 1 }, { n: 60, ur: 2 })));
  await assertFails(update(ref(db(ANA), '/'), pachinko({ n: 51 }, { n: 9, ur: 2, mu: 1 })));
});

/// Ana con una tanda cargada de 10 N, 2 SR y 1 SSR, y en el deposito 3 R.
const rolling = () =>
  seed({
    gacha: {
      balls: { ...noBalls, r: 3 },
      pachinko: { at: 1, count: 13, balls: { n: 10, sr: 2, ssr: 1 } },
    },
  });

const settle = (deposit) => ({
  [`users/${ANA}/gacha/settle`]: { at: serverTimestamp() },
  [`users/${ANA}/gacha/pachinko`]: null,
  [`users/${ANA}/gacha/balls`]: { ...noBalls, ...deposit },
});

test('cerrar la tanda devuelve lo que ha salido', async () => {
  await rolling();
  // 1 N igual, 2 N a R, 1 N a SR, 1 SR a SSR y la SSR a UR; lo demas, fuera.
  await assertSucceeds(update(ref(db(ANA), '/'), settle({ n: 1, r: 5, sr: 1, ssr: 1, ur: 1 })));
});

test('cerrar la tanda no puede sacar mas de lo cargado', async () => {
  await rolling();
  await assertFails(update(ref(db(ANA), '/'), settle({ n: 10, r: 3, sr: 2, ssr: 1, ur: 1 })));
});

test('cada rareza sube como mucho dos', async () => {
  await rolling();
  // Una N no llega a SSR.
  await assertFails(update(ref(db(ANA), '/'), settle({ r: 3, ssr: 4 })));
  // Solo hay una SSR y dos SR que puedan llegar a UR.
  await assertFails(update(ref(db(ANA), '/'), settle({ r: 3, ur: 4 })));
  // Del pachinko nunca sale ∞.
  await assertFails(update(ref(db(ANA), '/'), settle({ r: 3, mu: 1 })));
});

test('cerrar la tanda borra el recibo y solo vale una vez', async () => {
  await rolling();
  const { [`users/${ANA}/gacha/pachinko`]: _, ...keep } = settle({ r: 4 });
  await assertFails(update(ref(db(ANA), '/'), keep));
  await assertSucceeds(update(ref(db(ANA), '/'), settle({ r: 4 })));
  await assertFails(update(ref(db(ANA), '/'), settle({ r: 5 })));
});

test('sin tanda no hay nada que cerrar', async () => {
  await stocked();
  await assertFails(update(ref(db(ANA), '/'), settle({ n: 5, sr: 2, ur: 1 })));
});

test('el recibo del pachinko no se borra sin cerrar la tanda', async () => {
  await rolling();
  await assertFails(set(ref(db(ANA), `/users/${ANA}/gacha/pachinko`), null));
});

// --- Lo de otras cuentas ----------------------------------------------------

test('nadie mira ni toca el gacha de otra cuenta', async () => {
  await assertFails(set(ref(db(ADMIN), `/users/${ANA}/gacha/balls`), { ...noBalls, ur: 9 }));
  await assertFails(set(ref(db(ADMIN), `/users/${ANA}/tickets/kinken`), 99));
});
