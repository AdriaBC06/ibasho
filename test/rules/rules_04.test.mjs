// Ibasho — tests de las reglas de la 0.4.0: claves, mensajes, grupos,
// noticias, sugerencias y monedas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Se lanzan con:   ./tool/test_rules.sh
//
// Va aparte de rules.test.mjs porque el estado de partida es otro: aqui hacen
// falta amistades ya hechas, claves publicadas y un grupo creado, y montar eso
// en el seed comun encarecia los ciento y pico tests que ya habia.

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
import { get, ref, set, update } from 'firebase/database';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', '..', 'database.rules.json'), 'utf8');

const ADMIN = 'uid-admin';
const ANA = 'uid-ana';
const LUIS = 'uid-luis';
const PAU = 'uid-pau';
const BANNED = 'uid-banned';

const testEnv = await initializeTestEnvironment({
  projectId: process.env.GCLOUD_PROJECT ?? 'demo-ibasho',
  database: {
    rules,
    host: process.env.IBASHO_EMULATOR_HOST ?? '127.0.0.1',
    port: Number(process.env.IBASHO_EMULATOR_DB_PORT ?? 9000),
  },
});

const now = Date.now();

/// Una clave publica de mentira con la longitud real: las reglas solo miran el
/// tamaño, no que sea un punto de la curva. Eso lo comprueba el cliente.
const pub = (seed) => `${seed}`.padEnd(88, 'A');

const entry = (username, extra = {}) => ({
  accountId: `uid-${username}`,
  username,
  createdAt: now,
  createdBy: ADMIN,
  disabled: false,
  ...extra,
});

const keys = (who) => ({
  pub: pub(who),
  backup: { v: 1, s: 'c2Fs', d: 'ZGF0b3M=' },
  at: now,
});

/// Un sobre con la forma que exigen las reglas. Su contenido da igual: las
/// reglas no pueden mirar dentro, y ese es justamente el punto.
const envelope = (from, recipients) => ({
  at: now,
  from,
  kind: 'text',
  e: pub('efimera'),
  c: 'Y2lmcmFkbw==',
  k: Object.fromEntries(recipients.map((r) => [r, 'ZW52dWVsdG8='])),
});

const pairId = (a, b) => (a < b ? `${a}_${b}` : `${b}_${a}`);
const pairEnds = (a, b) => (a < b ? { a, b } : { a: b, b: a });

const MSG = 'AAAAAAAAAAAAAAAAAAAA';
const MSG2 = 'BBBBBBBBBBBBBBBBBBBB';
const NEWS = 'NNNNNNNNNNNNNNNNNNNN';

/// Ana y Luis son amigos. Pau no es amigo de nadie. Todos tienen claves.
async function seed() {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/'), {
      admins: { [ADMIN]: true },
      allowlist: {
        [ADMIN]: entry('admin'),
        [ANA]: entry('ana'),
        [LUIS]: entry('luis'),
        [PAU]: entry('pau'),
        [BANNED]: entry('banned', { disabled: true }),
      },
      usernames: { admin: ADMIN, ana: ANA, luis: LUIS, pau: PAU, banned: BANNED },
      users: {
        [ADMIN]: { keys: keys(ADMIN) },
        [ANA]: {
          keys: keys(ANA),
          friends: { [LUIS]: { since: now } },
          coins: 0,
        },
        [LUIS]: {
          keys: keys(LUIS),
          friends: { [ANA]: { since: now } },
          coins: 0,
        },
        [PAU]: { keys: keys(PAU), coins: 0 },
      },
      news: {
        [NEWS]: {
          kind: 'poll',
          title: 'Que viene despues',
          at: now,
          by: 'admin',
          options: { 0: 'Un minijuego', 1: 'Una tienda' },
          tally: { 0: 2, 1: 1 },
          voters: { [LUIS]: true },
        },
      },
      system: { friendCodeCounter: 5 },
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

// --- Claves ---------------------------------------------------------------

test('la clave publica la lee cualquier miembro y el respaldo solo su dueña', async () => {
  // Publica de verdad: sin ella nadie podria mandarle nada a nadie.
  await assertSucceeds(get(ref(db(PAU), `/users/${ANA}/keys/pub`)));
  await assertSucceeds(get(ref(db(ANA), `/users/${ANA}/keys/backup`)));
  // El respaldo es lo unico que, con la frase, abre el historial.
  await assertFails(get(ref(db(LUIS), `/users/${ANA}/keys/backup`)));
  await assertFails(get(ref(db(PAU), `/users/${ANA}/keys/backup`)));
  await assertFails(get(ref(db(ADMIN), `/users/${ANA}/keys/backup`)));
  await assertFails(get(ref(db(BANNED), `/users/${ANA}/keys/pub`)));
});

test('cada cual publica sus claves y nadie las de otro', async () => {
  await assertSucceeds(set(ref(db(ANA), `/users/${ANA}/keys`), keys(ANA)));
  await assertFails(set(ref(db(LUIS), `/users/${ANA}/keys`), keys(LUIS)));
  await assertFails(set(ref(db(ADMIN), `/users/${ANA}/keys`), keys(ADMIN)));
  // Sin `at`, o con una publica de otro tamaño, no cuela.
  await assertFails(set(ref(db(ANA), `/users/${ANA}/keys`), { pub: pub(ANA) }));
  await assertFails(
    set(ref(db(ANA), `/users/${ANA}/keys`), { pub: 'corta', at: now }),
  );
});

// --- Monedas --------------------------------------------------------------

test('las monedas las pone un admin y nadie se las pone a si mismo', async () => {
  await assertSucceeds(set(ref(db(ADMIN), `/users/${ANA}/coins`), 250));
  await assertFails(set(ref(db(ANA), `/users/${ANA}/coins`), 250));
  await assertFails(set(ref(db(LUIS), `/users/${ANA}/coins`), 250));
  await assertFails(set(ref(db(ADMIN), `/users/${ANA}/coins`), -1));
  await assertFails(set(ref(db(ADMIN), `/users/${ANA}/coins`), 1.5));
});

test('las monedas las leen sus amigos y el admin que las reparte', async () => {
  await assertSucceeds(get(ref(db(ANA), `/users/${ANA}/coins`)));
  await assertSucceeds(get(ref(db(LUIS), `/users/${ANA}/coins`)));
  await assertSucceeds(get(ref(db(ADMIN), `/users/${ANA}/coins`)));
  await assertFails(get(ref(db(PAU), `/users/${ANA}/coins`)));
});

// --- Conversaciones privadas ----------------------------------------------

const openPair = (me, other) => {
  const ends = pairEnds(me, other);
  return {
    [`dm/${pairId(me, other)}/a`]: ends.a,
    [`dm/${pairId(me, other)}/b`]: ends.b,
  };
};

test('una conversacion se abre entre amigos y solo en su sitio', async () => {
  await assertSucceeds(update(ref(db(ANA), '/'), openPair(ANA, LUIS)));

  await seed();
  // Con alguien que no es amigo, no.
  await assertFails(update(ref(db(ANA), '/'), openPair(ANA, PAU)));

  await seed();
  // El id tiene que ser los dos accountId ordenados: si no, la misma pareja
  // podria tener conversaciones en sitios distintos.
  const ends = pairEnds(ANA, LUIS);
  await assertFails(
    update(ref(db(ANA), '/'), {
      'dm/inventado/a': ends.a,
      'dm/inventado/b': ends.b,
    }),
  );
});

test('la conversacion solo la leen los dos que hablan', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const ends = pairEnds(ANA, LUIS);
    await set(ref(context.database(), `/dm/${pairId(ANA, LUIS)}`), {
      a: ends.a,
      b: ends.b,
      msgs: { [MSG]: envelope(ANA, [ANA, LUIS]) },
    });
  });

  await assertSucceeds(get(ref(db(ANA), `/dm/${pairId(ANA, LUIS)}/msgs`)));
  await assertSucceeds(get(ref(db(LUIS), `/dm/${pairId(ANA, LUIS)}/msgs`)));
  // Ni un tercero ni el administrador: aqui no hay privilegios que valgan, y
  // aunque los hubiera solo verian ruido.
  await assertFails(get(ref(db(PAU), `/dm/${pairId(ANA, LUIS)}/msgs`)));
  await assertFails(get(ref(db(ADMIN), `/dm/${pairId(ANA, LUIS)}/msgs`)));
});

test('un mensaje va firmado por quien lo manda y cerrado para los dos', async () => {
  const pair = pairId(ANA, LUIS);
  const base = openPair(ANA, LUIS);

  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      ...base,
      [`dm/${pair}/msgs/${MSG}`]: envelope(ANA, [ANA, LUIS]),
      [`users/${LUIS}/inbox/${ANA}`]: { at: now },
    }),
  );

  await seed();
  // Firmar con el nombre de otro, no.
  await assertFails(
    update(ref(db(ANA), '/'), {
      ...base,
      [`dm/${pair}/msgs/${MSG}`]: envelope(LUIS, [ANA, LUIS]),
    }),
  );

  await seed();
  // Un sobre que el otro no puede abrir tampoco: si se guardara, la
  // conversacion tendria huecos ilegibles para siempre.
  await assertFails(
    update(ref(db(ANA), '/'), {
      ...base,
      [`dm/${pair}/msgs/${MSG}`]: envelope(ANA, [ANA]),
    }),
  );

  await seed();
  // Y un tercero no puede colar nada dentro.
  await assertFails(
    update(ref(db(PAU), '/'), {
      ...base,
      [`dm/${pair}/msgs/${MSG}`]: envelope(PAU, [ANA, LUIS]),
    }),
  );
});

test('un mensaje no se edita, y cualquiera de los dos puede podar', async () => {
  const pair = pairId(ANA, LUIS);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const ends = pairEnds(ANA, LUIS);
    await set(ref(context.database(), `/dm/${pair}`), {
      a: ends.a,
      b: ends.b,
      msgs: { [MSG]: envelope(ANA, [ANA, LUIS]) },
    });
  });

  // Reescribir lo dicho no se puede: ni el que lo escribio.
  await assertFails(
    set(ref(db(ANA), `/dm/${pair}/msgs/${MSG}`), envelope(ANA, [ANA, LUIS])),
  );
  // Borrar si, y lo puede hacer el otro: la poda de los 300 mensajes y los 90
  // dias la hace el cliente que escribe, sea de quien sea lo viejo.
  await assertSucceeds(set(ref(db(LUIS), `/dm/${pair}/msgs/${MSG}`), null));
  await assertFails(set(ref(db(PAU), `/dm/${pair}/msgs/${MSG2}`), null));
});

test('el aviso de mensaje nuevo lo deja un amigo y no lleva nada dentro', async () => {
  await assertSucceeds(
    set(ref(db(ANA), `/users/${LUIS}/inbox/${ANA}`), { at: now }),
  );
  // Pau no es amigo de Luis: no puede ni avisarle.
  await assertFails(
    set(ref(db(PAU), `/users/${LUIS}/inbox/${PAU}`), { at: now }),
  );
  // Ni se puede firmar el aviso con el nombre de otro.
  await assertFails(
    set(ref(db(ANA), `/users/${LUIS}/inbox/${PAU}`), { at: now }),
  );
  // Ni colar el texto en el aviso, que no va cifrado.
  await assertFails(
    set(ref(db(ANA), `/users/${LUIS}/inbox/${ANA}`), { at: now, text: 'hola' }),
  );
});

// --- Grupo ----------------------------------------------------------------

test('el chat general ya no existe: ni se lee ni se escribe', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/groups/global/meta'), {
      name: 'Global',
      open: true,
      createdAt: now,
    });
  });
  for (const path of ['/groups/global/meta', '/groups/global/lastAt', '/groups/global/msgs']) {
    await assertFails(get(ref(db(ANA), path)));
  }
  await assertFails(set(ref(db(ADMIN), '/groups/otro/meta'), { name: 'Otro', open: true, createdAt: now }));
  await assertFails(
    update(ref(db(LUIS), '/'), {
      [`groups/global/members/${LUIS}`]: { at: now, pub: pub(LUIS) },
      [`users/${LUIS}/groups/global`]: now,
    }),
  );
  await assertFails(set(ref(db(LUIS), `/users/${LUIS}/reads/group/global`), now));
});

// --- Noticias -------------------------------------------------------------

test('el tablon lo lee todo el mundo y lo escribe solo el admin', async () => {
  await assertSucceeds(get(ref(db(PAU), '/news')));
  await assertFails(get(ref(db(BANNED), '/news')));

  const nuevo = {
    kind: 'update',
    title: 'Ibasho 0.4.0',
    at: now,
    by: 'admin',
    version: '0.4.0',
    // La entrada puede ir en los dos idiomas.
    titleEn: 'Ibasho 0.4.0',
    bodyEn: 'Encrypted messages, news and ideas.',
  };
  await assertSucceeds(set(ref(db(ADMIN), '/news/UUUUUUUUUUUUUUUUUUUU'), nuevo));
  await assertFails(set(ref(db(ANA), '/news/VVVVVVVVVVVVVVVVVVVV'), nuevo));
  await assertFails(set(ref(db(ADMIN), `/news/${NEWS}/title`), ''));
  await assertFails(set(ref(db(ADMIN), `/news/${NEWS}/titleEn`), ''));
  await assertFails(set(ref(db(ADMIN), `/news/${NEWS}/bodyEn`), 'x'.repeat(601)));
  // Y un campo que las reglas no conocen sigue sin entrar.
  await assertFails(set(ref(db(ADMIN), `/news/${NEWS}/titleFr`), 'Salut'));
});

test('el voto es anonimo: solo cuenta, y de uno en uno', async () => {
  // Votar es subir un recuento en uno y apuntarse como votante. Lo que se ha
  // votado no se escribe aqui: va al arbol de quien vota.
  await assertSucceeds(
    update(ref(db(ANA), '/'), {
      [`news/${NEWS}/voters/${ANA}`]: true,
      [`news/${NEWS}/tally/1`]: 2,
      [`users/${ANA}/votes/${NEWS}`]: 1,
    }),
  );

  await seed();
  // Sin apuntarse como votante, el recuento no se mueve.
  await assertFails(set(ref(db(ANA), `/news/${NEWS}/tally/1`), 2));

  await seed();
  // Ni de dos en dos.
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`news/${NEWS}/voters/${ANA}`]: true,
      [`news/${NEWS}/tally/1`]: 3,
    }),
  );

  await seed();
  // Ni en una opcion que no existe.
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`news/${NEWS}/voters/${ANA}`]: true,
      [`news/${NEWS}/tally/3`]: 1,
    }),
  );

  await seed();
  // Y lo que uno vota no lo lee nadie mas.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/users/${ANA}/votes/${NEWS}`), 1);
  });
  await assertSucceeds(get(ref(db(ANA), `/users/${ANA}/votes/${NEWS}`)));
  await assertFails(get(ref(db(LUIS), `/users/${ANA}/votes/${NEWS}`)));
  await assertFails(get(ref(db(ADMIN), `/users/${ANA}/votes/${NEWS}`)));
});

test('una encuesta cerrada ya no admite votos', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/news/${NEWS}/closed`), true);
  });
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`news/${NEWS}/voters/${ANA}`]: true,
      [`news/${NEWS}/tally/1`]: 2,
    }),
  );

  await seed();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/news/${NEWS}/closesAt`), now - 1000);
  });
  await assertFails(
    update(ref(db(ANA), '/'), {
      [`news/${NEWS}/voters/${ANA}`]: true,
      [`news/${NEWS}/tally/1`]: 2,
    }),
  );
});

// --- Sugerencias ----------------------------------------------------------

const suggestion = (extra = {}) => ({
  title: 'Musica en la habitacion',
  body: 'Que cada Tama tenga una pista suya.',
  at: now,
  status: 'pending',
  ...extra,
});

test('una sugerencia viva por cuenta', async () => {
  await assertSucceeds(set(ref(db(ANA), `/suggestions/${ANA}`), suggestion()));
  // Con la primera esperando respuesta, la segunda no entra.
  await assertFails(
    set(ref(db(ANA), `/suggestions/${ANA}`), suggestion({ title: 'Otra' })),
  );

  // Con veredicto dado, si.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/suggestions/${ANA}/status`), 'rejected');
  });
  await assertSucceeds(
    set(ref(db(ANA), `/suggestions/${ANA}`), suggestion({ title: 'Otra' })),
  );
});

test('nadie manda sugerencias en nombre de otro ni se da el visto bueno', async () => {
  await assertFails(set(ref(db(LUIS), `/suggestions/${ANA}`), suggestion()));
  // Mandarla ya aceptada, o con el motivo puesto, seria firmarse el veredicto.
  await assertFails(
    set(ref(db(ANA), `/suggestions/${ANA}`), suggestion({ status: 'accepted' })),
  );
  await assertFails(
    set(ref(db(ANA), `/suggestions/${ANA}`), suggestion({ note: 'me la apruebo' })),
  );
  // Y los largos son los que son.
  await assertFails(
    set(ref(db(ANA), `/suggestions/${ANA}`), suggestion({ title: 'x'.repeat(31) })),
  );
  await assertFails(
    set(ref(db(ANA), `/suggestions/${ANA}`), suggestion({ body: 'x'.repeat(201) })),
  );
});

test('el buzon se puede cerrar para todos', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), '/system/suggestionsOpen'), false);
  });
  await assertFails(set(ref(db(ANA), `/suggestions/${ANA}`), suggestion()));
  // El admin sigue pudiendo decidir sobre lo que ya habia.
  await assertSucceeds(set(ref(db(ADMIN), '/system/suggestionsOpen'), true));
  await assertFails(set(ref(db(ANA), '/system/suggestionsOpen'), false));
});

test('cada cual ve la suya y el admin las ve todas', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/suggestions/${ANA}`), suggestion());
  });
  await assertSucceeds(get(ref(db(ANA), `/suggestions/${ANA}`)));
  await assertSucceeds(get(ref(db(ADMIN), '/suggestions')));
  await assertFails(get(ref(db(LUIS), `/suggestions/${ANA}`)));
  await assertFails(get(ref(db(ANA), '/suggestions')));
});

test('el veredicto lo da el admin y sale a la lista publica', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), `/suggestions/${ANA}`), suggestion());
  });

  await assertSucceeds(
    update(ref(db(ADMIN), '/'), {
      [`suggestions/${ANA}/status`]: 'accepted',
      [`suggestions/${ANA}/note`]: 'Buena idea.',
      [`suggestions/${ANA}/decidedAt`]: now,
      [`suggestions/${ANA}/decidedBy`]: 'admin',
      'acceptedSuggestions/AAAAAAAAAAAAAAAAAAAA': {
        title: 'Musica en la habitacion',
        by: 'ana',
        at: now,
      },
    }),
  );
  // La lista de aceptadas la lee todo el mundo y la escribe solo el admin.
  await assertSucceeds(get(ref(db(PAU), '/acceptedSuggestions')));
  await assertFails(
    set(ref(db(ANA), '/acceptedSuggestions/BBBBBBBBBBBBBBBBBBBB'), {
      title: 'La mia',
      by: 'ana',
      at: now,
    }),
  );
});

// --- Lo que no cambia -----------------------------------------------------

test('lo que ya era privado sigue siendolo', async () => {
  // La 0.4.0 abre nodos nuevos; ninguno de ellos abre la raiz.
  for (const path of ['/', '/dm', '/groups', '/suggestions']) {
    await assertFails(get(ref(db(ANA), path)));
  }
  assert.ok(true);
});
