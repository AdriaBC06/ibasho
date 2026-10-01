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
          odori_kasa: 10,
          prize_poop_brown: 1,
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

test('una cancion de Odori se compra con su recibo, una vez y sin borrarse', async () => {
  const buy = (coins) =>
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'odori_kasa', qty: 1, at: serverTimestamp() },
      [`users/${ANA}/coins`]: coins,
      [`users/${ANA}/odori/songs/kasa`]: true,
    });
  // Sin recibo, o con el recibo de otra cancion, no.
  await assertFails(set(ref(db(ANA), `/users/${ANA}/odori/songs/kasa`), true));
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'odori_kasa', qty: 1, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 90,
      [`users/${ANA}/odori/songs/hanabi`]: true,
    }),
  );
  await assertFails(buy(95));
  await assertSucceeds(buy(90));
  await assertFails(buy(80));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/odori/songs/kasa`), null));
});

test('la caca del Yatai se compra con su recibo y entra en la coleccion', async () => {
  const buy = (coins, copies = 1, item = 'prize_poop_brown', key = 'poop_brown') =>
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item, qty: 1, at: serverTimestamp() },
      [`users/${ANA}/coins`]: coins,
      [`users/${ANA}/prizes/${key}`]: copies,
    });
  // Sin recibo no se crea, y un recibo de la caca no da otro premio.
  await assertFails(set(ref(db(ANA), `/users/${ANA}/prizes/poop_brown`), 1));
  await assertFails(buy(99, 1, 'prize_poop_brown', 'crown_gold'));
  // Ni gratis, ni de dos en dos.
  await assertFails(buy(100));
  await assertFails(buy(99, 2));
  await assertSucceeds(buy(99));
  // Y a otra cuenta no se la compra nadie.
  await assertFails(
    update(ref(db(LUIS), '/'), {
      [`users/${LUIS}/shop/last`]: { item: 'prize_poop_brown', qty: 1, at: serverTimestamp() },
      [`users/${LUIS}/coins`]: 1,
      [`users/${ANA}/prizes/poop_brown`]: 2,
    }),
  );
});

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

// --- Depuracion: el admin gestiona sus juegos --------------------------------

test('el admin se da un juego sin recibo y se lo quita', async () => {
  const game = ref(db(ADMIN), `/users/${ADMIN}/games/minesweeper`);
  await assertSucceeds(set(game, { state: 'open', at: serverTimestamp() }));
  await assertSucceeds(set(game, { state: 'gift', at: serverTimestamp() }));
  await assertSucceeds(set(game, null));
});

test('el admin no toca los juegos de otra cuenta', async () => {
  await assertFails(
    set(ref(db(ADMIN), `/users/${ANA}/games/minesweeper`), { state: 'open', at: serverTimestamp() }),
  );
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${ANA}/games/minesweeper`), { state: 'open', at: now });
  });
  await assertFails(set(ref(db(ADMIN), `/users/${ANA}/games/minesweeper`), null));
});

test('una cuenta normal sigue sin darse juegos sin recibo', async () => {
  await assertFails(
    set(ref(db(ANA), `/users/${ANA}/games/minesweeper`), { state: 'open', at: serverTimestamp() }),
  );
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

// --- Premios de los juegos (0.5.1: tope de 20 por juego) -------------------

const DAY = 86400000;
const today = () => Math.floor(Date.now() / DAY);

async function giveGame(uid, game = 'minesweeper') {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${uid}/games/${game}`), {
      state: 'open',
      at: now - 1000,
    });
  });
}

const giveMinesweeper = (uid) => giveGame(uid);

async function earnedBefore(uid, game, { day = today(), earned, lastAt = now - 60000 }) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await update(ref(context.database(), `/users/${uid}/earnings`), {
      [game]: { day, earned, at: lastAt },
      last: { game, at: lastAt },
    });
  });
}

const claim = (uid, { earned, coins, day = today(), game = 'minesweeper', last = game }) =>
  update(ref(db(uid), '/'), {
    [`users/${uid}/earnings/${game}`]: { day, earned, at: serverTimestamp() },
    [`users/${uid}/earnings/last`]: { game: last, at: serverTimestamp() },
    [`users/${uid}/coins`]: coins,
  });

test('ganar al buscaminas cobra el premio y sube las monedas lo mismo', async () => {
  await giveMinesweeper(ANA);
  await assertSucceeds(claim(ANA, { earned: 5, coins: 105 }));
});

test('sin el juego no hay premio', async () => {
  await assertFails(claim(ANA, { earned: 5, coins: 105 }));
});

test('ohirune es gratis: cobra sin tenerlo comprado, con el mismo tope', async () => {
  await assertSucceeds(claim(ANA, { earned: 8, coins: 108, game: 'ohirune' }));
  await earnedBefore(ANA, 'ohirune', { earned: 18 });
  await assertFails(claim(ANA, { earned: 21, coins: 111, game: 'ohirune' }));
  // Otro juego sin comprar sigue sin premio.
  await assertFails(claim(ANA, { earned: 5, coins: 105, game: 'tsumiki' }));
});

test('hataraki es gratis y paga de 1 en 1, con un minuto entre cobros', async () => {
  await assertSucceeds(claim(ANA, { earned: 1, coins: 101, game: 'hataraki' }));
  // Nada de 3, 5 u 8 de golpe.
  await earnedBefore(ANA, 'hataraki', { earned: 1, lastAt: now - 120000 });
  await assertFails(claim(ANA, { earned: 4, coins: 104, game: 'hataraki' }));
  await assertSucceeds(claim(ANA, { earned: 2, coins: 102, game: 'hataraki' }));
});

test('hataraki no cobra dos veces en el mismo minuto', async () => {
  await earnedBefore(ANA, 'hataraki', { earned: 5, lastAt: Date.now() - 30000 });
  await assertFails(claim(ANA, { earned: 6, coins: 101, game: 'hataraki' }));
});

test('hataraki no pasa de 20 al día', async () => {
  await earnedBefore(ANA, 'hataraki', { earned: 20, lastAt: now - 120000 });
  await assertFails(claim(ANA, { earned: 21, coins: 101, game: 'hataraki' }));
});

// --- Hatarakitama: la partida (0.7.0) ---------------------------------------

const hatarakiGame = {
  xp: { woodcutting: 1200, expedition: 60 },
  mastery: { wc_sugi: 1200 },
  bank: { log_sugi: 120, seed_rice: 5 },
  workers: { 0: { tama: '-Nabcdefghijklmnopqr', action: 'wc_sugi', progress: 0.4 } },
  kit: { bag: 'gear_basket' },
  tea: { item: 'tea_sencha', until: now + 60000 },
  expedition: {
    zone: 'meadow',
    tamas: { 0: '-Nabcdefghijklmnopqs' },
    start: now,
    end: now + 600000,
    power: 12,
  },
  last: now,
  seed: 42,
  prizes: 0,
  money: 340,
  earned: 900,
  period: { day: 20360, dayXp: 1200, week: 2908, weekXp: 5400, dayMoney: 120, weekMoney: 900 },
};

test('hataraki: los mon no pueden ser negativos ni un campo cualquiera', async () => {
  await assertFails(set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, money: -1 }));
  await assertFails(
    set(ref(db(ANA), `/users/${ANA}/hataraki`), {
      ...hatarakiGame,
      period: { ...hatarakiGame.period, dayGold: 1 },
    }),
  );
});

test('hataraki: la dueña guarda y lee su partida; nadie más', async () => {
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/hataraki`), hatarakiGame));
  await assertSucceeds(get(ref(db(ANA), `/users/${ANA}/hataraki`)));
  await assertFails(get(ref(db(LUIS), `/users/${ANA}/hataraki`)));
  await assertFails(set(ref(db(LUIS), `/users/${ANA}/hataraki`), hatarakiGame));
});

test('hataraki: hasta 8 ranuras de trabajo, con su cebo, abono o mecha', async () => {
  const worker = { tama: '-Nabcdefghijklmnopqr', action: 'fi_iwashi', progress: 0, boost: 'bait_worm' };
  await assertSucceeds(
    set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, workers: { 0: worker, 7: worker } }),
  );
  await assertFails(
    set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, workers: { 8: worker } }),
  );
  await assertFails(
    set(ref(db(ANA), `/users/${ANA}/hataraki`), {
      ...hatarakiGame,
      workers: { 0: { ...worker, boost: 'Cebo Gordo!' } },
    }),
  );
});

test('hataraki: el pueblo (niveles 1–5), la tienda del día y viajes de cuatro', async () => {
  const save = (extra) => set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, ...extra });
  await assertSucceeds(
    save({
      town: { workshop: 1, market: 5 },
      shop: { day: 20500, bought: { seed_rice: 12 } },
      expedition: { zone: 'meadow', tamas: { 0: 'a', 1: 'b', 2: 'c', 3: 'd' }, start: 1, end: 2, power: 10 },
    }),
  );
  await assertFails(save({ town: { workshop: 6 } }));
  await assertFails(save({ town: { workshop: 0 } }));
  await assertFails(save({ town: { workshop: 1.5 } }));
  await assertFails(save({ town: { Taller: 1 } }));
  await assertFails(save({ shop: { bought: { seed_rice: 1 } } }));
  await assertFails(save({ shop: { day: 1, bought: { seed_rice: 0 } } }));
  await assertFails(save({ shop: { day: 1, stock: 3 } }));
  await assertFails(
    save({ expedition: { zone: 'meadow', tamas: { 4: 'e' }, start: 1, end: 2, power: 10 } }),
  );
});

test('hataraki: viajes con mapa (dos a la vez) y guías del día', async () => {
  const save = (extra) => set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, ...extra });
  const trip = {
    zone: 'forest',
    tamas: { 0: 'a', 1: 'b' },
    start: 1,
    end: 5,
    power: 30,
    day: 20500,
    route: { 0: 1, 1: 2, 2: 1, 3: 0 },
    at: { 0: 2, 1: 3, 2: 4, 3: 5 },
    fails: { 0: 2 },
    done: 2,
    porter: true,
    luck: 1.5,
    log: { 0: { log_matsu: 4 }, 1: { rare_feather: 1, prize: 1 } },
  };
  await assertSucceeds(
    save({ expedition: null, expeditions: { 0: trip, 1: { ...trip, zone: 'meadow' } }, guides: { forest: 20500 } }),
  );
  await assertFails(save({ expeditions: { 2: trip } }));
  await assertFails(save({ expeditions: { 0: { ...trip, route: { 0: 3 } } } }));
  await assertFails(save({ expeditions: { 0: { ...trip, route: { 6: 1 } } } }));
  await assertFails(save({ expeditions: { 0: { ...trip, done: 7 } } }));
  await assertFails(save({ expeditions: { 0: { ...trip, luck: 9 } } }));
  await assertFails(save({ expeditions: { 0: { ...trip, log: { 0: { log_matsu: 0 } } } } }));
  await assertFails(save({ expeditions: { 0: { ...trip, cheat: true } } }));
  await assertFails(save({ guides: { forest: 'hoy' } }));
});

async function hatarakiWithPrizes(uid, { prizes, tickets = 3, claimAt }) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${uid}/hataraki`), {
      ...hatarakiGame,
      prizes,
      ...(claimAt ? { claimAt } : {}),
    });
    await set(ref(context.database(), `/users/${uid}/tickets/gachaken`), tickets);
  });
}

const redeem = (uid, { tickets, prizes, kind = 'gachaken' }) =>
  update(ref(db(uid), '/'), {
    [`users/${uid}/tickets/${kind}`]: tickets,
    [`users/${uid}/hataraki/prizes`]: prizes,
    [`users/${uid}/hataraki/claimAt`]: serverTimestamp(),
  });

test('hataraki: un tesoro se canjea por un gachaken, uno por hora', async () => {
  await hatarakiWithPrizes(ANA, { prizes: 2 });
  await assertFails(redeem(ANA, { tickets: 5, prizes: 1 }));
  await assertFails(redeem(ANA, { tickets: 4, prizes: 2 }));
  await assertFails(redeem(ANA, { tickets: 1, prizes: 1, kind: 'kinken' }));
  await assertSucceeds(redeem(ANA, { tickets: 4, prizes: 1 }));
  // El segundo, en la misma hora, no.
  await assertFails(redeem(ANA, { tickets: 5, prizes: 0 }));
});

test('hataraki: sin tesoros no hay ticket, y pasada la hora vuelve a haber', async () => {
  await hatarakiWithPrizes(ANA, { prizes: 0 });
  await assertFails(redeem(ANA, { tickets: 4, prizes: -1 }));
  await hatarakiWithPrizes(ANA, { prizes: 1, claimAt: now - 3700000 });
  await assertSucceeds(redeem(ANA, { tickets: 4, prizes: 0 }));
});

test('hataraki: guardar la partida con el mismo claimAt vale', async () => {
  await hatarakiWithPrizes(ANA, { prizes: 1, claimAt: now - 1000 });
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, prizes: 1, claimAt: now - 1000 }));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, prizes: 1, claimAt: now }));
});

const orderToday = today();

async function hatarakiWithOrderDay(uid, { orderDay, tickets = 3 }) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${uid}/hataraki`), {
      ...hatarakiGame,
      ...(orderDay ? { orderDay } : {}),
    });
    await set(ref(context.database(), `/users/${uid}/tickets/gachaken`), tickets);
  });
}

const claimOrder = (uid, { tickets, day = orderToday, kind = 'gachaken' }) =>
  update(ref(db(uid), '/'), {
    [`users/${uid}/tickets/${kind}`]: tickets,
    [`users/${uid}/hataraki/orderDay`]: day,
  });

test('hataraki: el gran encargo da un gachaken, uno al día', async () => {
  await hatarakiWithOrderDay(ANA, {});
  await assertFails(claimOrder(ANA, { tickets: 5 }));
  await assertFails(claimOrder(ANA, { tickets: 4, day: orderToday + 1 }));
  await assertFails(claimOrder(ANA, { tickets: 4, day: orderToday - 1 }));
  await assertFails(claimOrder(ANA, { tickets: 1, kind: 'kinken' }));
  await assertSucceeds(claimOrder(ANA, { tickets: 4 }));
  // El segundo, el mismo día, no.
  await assertFails(claimOrder(ANA, { tickets: 5 }));
  // Ni borrando el día al guardar la partida.
  await assertFails(set(ref(db(ANA), `/users/${ANA}/hataraki`), hatarakiGame));
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, orderDay: orderToday }));
  // El ticket no sube solo con cambiar el día.
  await hatarakiWithOrderDay(ANA, { orderDay: orderToday - 1 });
  await assertFails(update(ref(db(ANA), `/users/${ANA}/hataraki`), { orderDay: orderToday }));
  await assertSucceeds(claimOrder(ANA, { tickets: 4 }));
});

test('hataraki: el tablón de encargos', async () => {
  const save = (orders) => set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, orders });
  const order = { wants: { log_sugi: 120, parcel: 1 }, money: 900, skill: 'woodcutting', xp: 40, gift: 'rare_feather', giftN: 2 };
  await assertSucceeds(
    save({ day: orderToday, swap: orderToday, ticket: true, list: { 0: { ...order, big: true, done: true }, 1: order, 5: order } }),
  );
  await assertFails(save({ list: { 0: order } }));
  await assertFails(save({ day: orderToday, list: { 6: order } }));
  await assertFails(save({ day: orderToday, list: { 0: { money: 3 } } }));
  await assertFails(save({ day: orderToday, list: { 0: { ...order, wants: { log_sugi: 0 } } } }));
  await assertFails(save({ day: orderToday, list: { 0: { ...order, giftN: 0 } } }));
  await assertFails(save({ day: orderToday, list: { 0: { ...order, cheat: 1 } } }));
  await assertFails(save({ day: orderToday, extra: 1 }));
});

test('hataraki: casas con sus muebles y planos sabidos', async () => {
  const save = (extra) => set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, ...extra });
  const house = {
    floor: 'rustic',
    wall: 'floral',
    items: { 0: { id: 'fu_stool', x: 0, y: 0, r: 0 }, 35: { id: 'fu_orrery', x: 4, y: 4, r: 3 } },
  };
  await assertSucceeds(save({ houses: { 'tama-1': house, t2: { floor: 'magic', wall: 'marine' } }, plans: { fu_boat: true } }));
  await assertFails(save({ houses: { 'tama-1': { ...house, floor: 'gold' } } }));
  await assertFails(save({ houses: { 'tama-1': { wall: 'floral' } } }));
  await assertFails(save({ houses: { 'tama-1': { ...house, items: { 36: { id: 'fu_stool', x: 0, y: 0, r: 0 } } } } }));
  await assertFails(save({ houses: { 'tama-1': { ...house, items: { 0: { id: 'fu_stool', x: 6, y: 0, r: 0 } } } } }));
  await assertFails(save({ houses: { 'tama-1': { ...house, items: { 0: { id: 'fu_stool', x: 0, y: 0, r: 4 } } } } }));
  await assertFails(save({ houses: { 'tama-1': { ...house, items: { 0: { id: 'log_sugi', x: 0, y: 0, r: 0 } } } } }));
  await assertFails(save({ houses: { 'tama-1': { ...house, items: { 0: { id: 'fu_stool', x: 0, y: 0 } } } } }));
  await assertFails(save({ houses: { 'tama-1': { ...house, roof: 'red' } } }));
  await assertFails(save({ houses: { 'ta ma': house } }));
  await assertFails(save({ plans: { fu_boat: false } }));
  await assertFails(save({ plans: { gear_scarf: true } }));
  const order = { wants: { log_sugi: 120 }, money: 900, plan: 'fu_boat' };
  await assertSucceeds(save({ orders: { day: orderToday, list: { 1: order } } }));
  await assertFails(save({ orders: { day: orderToday, list: { 1: { ...order, plan: 'gear_scarf' } } } }));
});

test('hataraki: los amigos visitan el pueblo (solo leer) con la ficha de sus Tamas', async () => {
  const look = { body: 2, eyes: 1, bodyWidth: 55, color: '#5BC8F5', colorMode: 'palette', hat: 'hat_straw', acc: { a: 'acc_bell' } };
  const visit = { tamas: { '-Nabcdefghijklmnopqr': { name: 'Mochi', personality: 'shy', look } } };
  const save = (extra) => set(ref(db(ANA), `/users/${ANA}/hataraki`), { ...hatarakiGame, ...extra });
  await assertSucceeds(save({ visit }));
  // Sin ser amigos no se lee.
  await assertFails(get(ref(db(LUIS), `/users/${ANA}/hataraki`)));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${ANA}/friends/${LUIS}`), { since: now });
  });
  await assertSucceeds(get(ref(db(LUIS), `/users/${ANA}/hataraki`)));
  await assertFails(set(ref(db(LUIS), `/users/${ANA}/hataraki`), hatarakiGame));
  await assertFails(set(ref(db(LUIS), `/users/${ANA}/hataraki/visit`), visit));
  // La ficha solo lleva nombre, personalidad y aspecto.
  const tama = visit.tamas['-Nabcdefghijklmnopqr'];
  const one = (t) => save({ visit: { tamas: { '-Nabcdefghijklmnopqr': t } } });
  await assertFails(one({ ...tama, care: { food: 1 } }));
  await assertFails(one({ ...tama, name: '' }));
  await assertFails(one({ ...tama, personality: 'grumpy' }));
  await assertFails(one({ name: 'Mochi', personality: 'shy' }));
  await assertFails(one({ ...tama, look: { ...look, body: 101 } }));
  await assertFails(one({ ...tama, look: { ...look, acc: { d: 'acc_bell' } } }));
  await assertFails(save({ visit: { tamas: { 'ta ma': tama } } }));
  await assertFails(save({ visit: { ...visit, money: 1 } }));
});

test('hataraki: las reglas cuidan la forma', async () => {
  const bad = [
    { ...hatarakiGame, extra: 1 },
    { ...hatarakiGame, bank: { log_sugi: -3 } },
    { ...hatarakiGame, workers: { 8: hatarakiGame.workers[0] } },
    { ...hatarakiGame, workers: { 0: { ...hatarakiGame.workers[0], progress: 2 } } },
    { ...hatarakiGame, kit: { hat: 'gear_basket' } },
    { ...hatarakiGame, seed: undefined },
    { ...hatarakiGame, period: { ...hatarakiGame.period, month: 3 } },
    { ...hatarakiGame, period: { ...hatarakiGame.period, dayXp: -1 } },
  ];
  for (const game of bad) {
    await assertFails(set(ref(db(ANA), `/users/${ANA}/hataraki`), JSON.parse(JSON.stringify(game))));
  }
});

test('odori es gratis y su tope es de 30 al dia', async () => {
  await earnedBefore(ANA, 'odori', { earned: 22 });
  await assertSucceeds(claim(ANA, { earned: 30, coins: 108, game: 'odori' }));
  await earnedBefore(ANA, 'odori', { earned: 30 });
  await assertFails(claim(ANA, { earned: 33, coins: 103, game: 'odori' }));
});

test('el premio solo vale 3, 5 u 8, y las monedas tienen que cuadrar', async () => {
  await giveMinesweeper(ANA);
  await assertFails(claim(ANA, { earned: 20, coins: 120 }));
  await assertFails(claim(ANA, { earned: 4, coins: 104 }));
  await assertFails(claim(ANA, { earned: 5, coins: 110 }));
  // Tocar el premio sin mover las monedas tampoco.
  await assertFails(
    update(ref(db(ANA), `/users/${ANA}/earnings`), {
      minesweeper: { day: today(), earned: 5, at: serverTimestamp() },
      last: { game: 'minesweeper', at: serverTimestamp() },
    }),
  );
  // Ni el premio sin su puntero, ni el puntero a otro juego.
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/earnings/minesweeper`]: { day: today(), earned: 5, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 105,
    }),
  );
  await assertFails(claim(ANA, { earned: 5, coins: 105, last: 'tsumiki' }));
});

test('las monedas no suben sin un premio fresco', async () => {
  await giveMinesweeper(ANA);
  await assertFails(set(ref(db(ANA), `/users/${ANA}/coins`), 105));
  // Un puntero fresco sin premio detras tampoco.
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/earnings/last`]: { game: 'minesweeper', at: serverTimestamp() },
      [`users/${ANA}/coins`]: 150,
    }),
  );
});

test('el tope es de 20 al dia en cada juego, y se puede llegar justo a el', async () => {
  await giveMinesweeper(ANA);
  await earnedBefore(ANA, 'minesweeper', { earned: 16 });
  // 16 + 8 pasaria de 20.
  await assertFails(claim(ANA, { earned: 24, coins: 108 }));
  // Completar hasta 20 si que vale.
  await assertSucceeds(claim(ANA, { earned: 20, coins: 104 }));
});

test('el tope de un juego no cuenta para otro', async () => {
  await giveMinesweeper(ANA);
  await giveGame(ANA, 'tsumiki');
  await earnedBefore(ANA, 'minesweeper', { earned: 20 });
  await assertSucceeds(claim(ANA, { game: 'tsumiki', earned: 8, coins: 108 }));
});

test('un dia nuevo empieza de cero', async () => {
  await giveMinesweeper(ANA);
  await earnedBefore(ANA, 'minesweeper', { day: today() - 1, earned: 20 });
  await assertSucceeds(claim(ANA, { earned: 8, coins: 108 }));
});

test('no se puede cobrar con un dia que no es hoy', async () => {
  await giveMinesweeper(ANA);
  await assertFails(claim(ANA, { earned: 5, coins: 105, day: today() + 1 }));
  await assertFails(claim(ANA, { earned: 5, coins: 105, day: today() - 1 }));
});

test('entre dos cobros tienen que pasar 15 segundos, aunque sean de juegos distintos', async () => {
  await giveMinesweeper(ANA);
  await giveGame(ANA, 'tsumiki');
  await assertSucceeds(claim(ANA, { earned: 5, coins: 105 }));
  await assertFails(claim(ANA, { earned: 10, coins: 110 }));
  await assertFails(claim(ANA, { game: 'tsumiki', earned: 5, coins: 110 }));
});

test('nadie cobra premios en nombre de otra cuenta', async () => {
  await giveMinesweeper(ANA);
  await assertFails(
    update(ref(db(LUIS), '/'), {
      [`users/${ANA}/earnings/minesweeper`]: { day: today(), earned: 5, at: serverTimestamp() },
      [`users/${ANA}/earnings/last`]: { game: 'minesweeper', at: serverTimestamp() },
      [`users/${ANA}/coins`]: 105,
    }),
  );
});

test('lo cobrado no se puede borrar', async () => {
  await giveMinesweeper(ANA);
  await earnedBefore(ANA, 'minesweeper', { earned: 20 });
  await assertFails(set(ref(db(ANA), `/users/${ANA}/earnings/minesweeper`), null));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/earnings/last`), null));
});

test('el nodo de premios de la 0.5.0 ya no se escribe', async () => {
  await giveMinesweeper(ANA);
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/rewards`]: { game: 'minesweeper', day: today(), earned: 5, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 105,
    }),
  );
});

test('una compra sigue funcionando despues de cobrar un premio', async () => {
  await giveMinesweeper(ANA);
  await assertSucceeds(claim(ANA, { earned: 5, coins: 105 }));
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`users/${ANA}/shop/last`]: { item: 'food_cookie', qty: 1, at: serverTimestamp() },
      [`users/${ANA}/coins`]: 102,
      [`users/${ANA}/pantry/cookie`]: 6,
    }),
  );
});

// --- Bono diario (0.5.1) -----------------------------------------------------

// La misma cuenta que `loginBonusFor` en lib/state/login_bonus.dart.
// La semana del 21 al 24 de septiembre de 2026, de lunes a jueves.
const WEEK_OF_2026_09_21 = [7, 5, 3, 6];

function bonusFor(day) {
  const weekday = (day + 3) % 7; // 0 = lunes
  if (weekday === 4) return 10;
  if (weekday >= 5) return 15;
  const x = (day * 2654435761) % 4294967296;
  return 3 + Math.floor((x * 5) / 4294967296);
}

const collect = (uid, { coins, day = today(), key = String(day) }) =>
  update(ref(db(uid), '/'), {
    [`users/${uid}/login/last`]: { day, at: serverTimestamp() },
    [`users/${uid}/login/days/${key}`]: true,
    [`users/${uid}/coins`]: coins,
  });

test('la cuenta del bono: viernes 10, fin de semana 15 y entre 3 y 7 el resto', () => {
  // 2026-09-18 fue viernes; 19 y 20, fin de semana; 21, lunes.
  const fri = Date.UTC(2026, 8, 18) / DAY;
  assert.equal(bonusFor(fri), 10);
  assert.equal(bonusFor(fri + 1), 15);
  assert.equal(bonusFor(fri + 2), 15);
  const weekdays = [3, 4, 5, 6].map((d) => bonusFor(fri + d));
  for (const v of weekdays) assert.ok(v >= 3 && v <= 7);
  // Los mismos valores que da la app para esa semana (test/login_bonus_test.dart).
  assert.deepEqual(weekdays, WEEK_OF_2026_09_21);
});

test('el bono de hoy se cobra una vez y suma lo que toca', async () => {
  const d = today();
  await assertSucceeds(collect(ANA, { coins: 100 + bonusFor(d) }));
  let back;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    back = (await get(ref(context.database(), `/users/${ANA}/login`))).val();
  });
  assert.equal(back.days[String(d)], true);
  // Otra vez el mismo dia, no.
  await assertFails(collect(ANA, { coins: 100 + 2 * bonusFor(d) }));
});

test('el bono tiene que sumar justo lo del dia', async () => {
  const d = today();
  await assertFails(collect(ANA, { coins: 100 + bonusFor(d) + 1 }));
  await assertFails(collect(ANA, { coins: 100 + bonusFor(d) - 1 }));
});

test('no se cobra el bono de otro dia', async () => {
  const d = today();
  await assertFails(collect(ANA, { day: d - 1, coins: 100 + bonusFor(d - 1) }));
  await assertFails(collect(ANA, { day: d + 1, coins: 100 + bonusFor(d + 1) }));
});

test('el historial solo se apunta con el cobro de ese mismo dia', async () => {
  const d = today();
  await assertFails(collect(ANA, { key: String(d - 1), coins: 100 + bonusFor(d) }));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/login/days/${d}`), true));
});

test('ayer cobrado no impide cobrar hoy', async () => {
  const d = today();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${ANA}/login`), {
      last: { day: d - 1, at: now - DAY },
      days: { [String(d - 1)]: true },
    });
  });
  await assertSucceeds(collect(ANA, { coins: 100 + bonusFor(d) }));
});

test('nadie cobra el bono de otra cuenta, y el bono no se borra', async () => {
  const d = today();
  await assertFails(
    update(ref(db(LUIS), '/'), {
      [`users/${ANA}/login/last`]: { day: d, at: serverTimestamp() },
      [`users/${ANA}/login/days/${d}`]: true,
      [`users/${ANA}/coins`]: 100 + bonusFor(d),
    }),
  );
  await assertSucceeds(collect(ANA, { coins: 100 + bonusFor(d) }));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/login`), null));
});

test('un admin puede borrar su propio bono para probarlo otra vez, y solo el suyo', async () => {
  const d = today();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${ADMIN}/login`), {
      last: { day: d, at: now - 1000 },
      days: { [String(d)]: true },
    });
    await set(ref(context.database(), `/users/${ANA}/login`), {
      last: { day: d, at: now - 1000 },
      days: { [String(d)]: true },
    });
  });
  await assertSucceeds(set(ref(db(ADMIN), `/users/${ADMIN}/login`), null));
  await assertFails(set(ref(db(ADMIN), `/users/${ANA}/login`), null));
});
