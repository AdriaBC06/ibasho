// Ibasho — tests de las reglas de seguridad de la Realtime Database.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Se lanzan con:   ./tool/test_rules.sh
// que levanta el emulador de Firebase y ejecuta este archivo.

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
import {
  equalTo,
  get,
  orderByChild,
  query,
  ref,
  set,
  update,
} from 'firebase/database';

const here = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(here, '..', '..', 'database.rules.json'), 'utf8');

// En la primera identidad de cada cuenta, uid y accountId coinciden.
const ADMIN = 'uid-admin';
const MEMBER = 'uid-member';
const OTHER = 'uid-other';
const BANNED = 'uid-banned';
const ORPHAN = 'uid-orphan';

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
  mustChangePassword: false,
  generation: 1,
  ...extra,
});

const profile = (username, extra = {}) => ({
  username,
  displayName: username,
  statusMessage: '',
  birthday: '',
  timezone: 'Europe/Madrid',
  locale: 'es',
  accentColor: '#5BC8F5',
  createdAt: now,
  ...extra,
});

/// Estado de partida, escrito saltandose las reglas.
async function seed() {
  await testEnv.clearDatabase();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.database();
    await set(ref(db, '/'), {
      admins: { [ADMIN]: true },
      allowlist: {
        [ADMIN]: entry('admin'),
        [MEMBER]: entry('member'),
        [OTHER]: entry('other'),
        [BANNED]: entry('banned', { disabled: true }),
      },
      usernames: {
        admin: ADMIN,
        member: MEMBER,
        other: OTHER,
        banned: BANNED,
      },
      users: {
        [MEMBER]: { profile: profile('member') },
        [OTHER]: { profile: profile('other') },
      },
      system: { announcement: { text: 'hola', updatedAt: now } },
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

// 1. Sin autenticar no se puede tocar nada.
test('un visitante sin autenticar no lee ni escribe nada', async () => {
  const anon = db(null);
  for (const path of [
    '/',
    '/allowlist',
    `/allowlist/${MEMBER}`,
    '/admins',
    `/admins/${ADMIN}`,
    '/usernames',
    '/usernames/member',
    `/users/${MEMBER}`,
    `/users/${MEMBER}/profile`,
    '/system/announcement',
  ]) {
    await assertFails(get(ref(anon, path)));
    await assertFails(set(ref(anon, path), { intruso: true }));
  }
});

// 2. El criterio de aceptacion numero cuatro: una cuenta creada por fuera de
//    la app, con la misma API key, no puede leer ni escribir absolutamente
//    nada.
test('una cuenta fuera de la allowlist no lee ni escribe nada', async () => {
  const orphan = db(ORPHAN);
  for (const path of [
    '/',
    '/allowlist',
    `/allowlist/${ORPHAN}`,
    `/allowlist/${MEMBER}`,
    '/admins',
    `/admins/${ORPHAN}`,
    '/usernames',
    '/usernames/member',
    `/users/${MEMBER}`,
    `/users/${MEMBER}/profile`,
    `/users/${ORPHAN}`,
    '/system/announcement',
  ]) {
    await assertFails(get(ref(orphan, path)));
  }
  await assertFails(set(ref(orphan, `/users/${ORPHAN}/profile`), profile('orphan')));
  await assertFails(set(ref(orphan, `/allowlist/${ORPHAN}`), entry('orphan')));
  await assertFails(set(ref(orphan, `/admins/${ORPHAN}`), true));
  await assertFails(set(ref(orphan, '/usernames/orphan'), ORPHAN));
});

// 3. Una cuenta deshabilitada queda igual de fuera que una huerfana.
test('una cuenta deshabilitada pierde el acceso', async () => {
  const banned = db(BANNED);
  await assertFails(get(ref(banned, `/users/${BANNED}`)));
  await assertFails(get(ref(banned, '/system/announcement')));
  await assertFails(
    set(ref(banned, `/users/${BANNED}/profile`), profile('banned')),
  );
  await assertFails(set(ref(banned, `/allowlist/${BANNED}/disabled`), false));
  // Solo puede leer su propia entrada, para que la app le diga que esta
  // deshabilitada en vez de un "sin acceso" generico. La de otros, no.
  await assertSucceeds(get(ref(banned, `/allowlist/${BANNED}`)));
  await assertFails(get(ref(banned, `/allowlist/${MEMBER}`)));
});

// 4. Un usuario normal solo escribe bajo su propio nodo.
test('un usuario no escribe en el nodo de otro', async () => {
  const member = db(MEMBER);
  await assertSucceeds(
    set(ref(member, `/users/${MEMBER}/profile`), profile('member')),
  );
  await assertFails(
    set(ref(member, `/users/${OTHER}/profile`), profile('other')),
  );
  await assertFails(
    set(ref(member, `/users/${OTHER}/profile/displayName`), 'secuestrado'),
  );
  // Leer el perfil ajeno si esta permitido: hace falta para los amigos.
  await assertSucceeds(get(ref(member, `/users/${OTHER}/profile`)));
});

// 5. Un usuario normal no toca la allowlist ni la lista de administradores.
test('un usuario no se da permisos a si mismo', async () => {
  const member = db(MEMBER);
  await assertFails(set(ref(member, `/admins/${MEMBER}`), true));
  await assertFails(set(ref(member, `/allowlist/${MEMBER}/disabled`), false));
  await assertFails(set(ref(member, `/allowlist/${OTHER}/disabled`), true));
  await assertFails(set(ref(member, `/allowlist/${MEMBER}`), entry('member')));
  await assertFails(set(ref(member, '/usernames/member'), OTHER));
  await assertFails(get(ref(member, '/allowlist')));
  // Su propia entrada si la puede leer: de ahi sale si tiene que cambiar la
  // contrasena.
  await assertSucceeds(get(ref(member, `/allowlist/${MEMBER}`)));
});

// 6. La unica excepcion: apagar su propia marca de cambio de contrasena.
test('un usuario solo puede apagar su mustChangePassword', async () => {
  const member = db(MEMBER);
  await assertSucceeds(
    set(ref(member, `/allowlist/${MEMBER}/mustChangePassword`), false),
  );
  await assertFails(
    set(ref(member, `/allowlist/${MEMBER}/mustChangePassword`), true),
  );
  await assertFails(
    set(ref(member, `/allowlist/${OTHER}/mustChangePassword`), false),
  );
});

// 7. El administrador hace su trabajo.
test('el administrador da de alta, deshabilita y rehabilita', async () => {
  const admin = db(ADMIN);
  const uid = 'uid-nuevo';

  await assertSucceeds(get(ref(admin, '/allowlist')));
  await assertSucceeds(
    set(ref(admin, `/allowlist/${uid}`), entry('nuevo', {
      mustChangePassword: true,
    })),
  );
  await assertSucceeds(set(ref(admin, '/usernames/nuevo'), uid));
  await assertSucceeds(set(ref(admin, `/allowlist/${uid}/disabled`), true));
  await assertSucceeds(set(ref(admin, `/allowlist/${uid}/disabled`), false));
  await assertSucceeds(set(ref(admin, `/admins/${uid}`), true));
  await assertSucceeds(
    set(ref(admin, '/system/announcement'), { text: 'aviso', updatedAt: now }),
  );

  // Ni siquiera el administrador escribe bajo /users de otro.
  await assertFails(set(ref(admin, `/users/${uid}/profile`), profile('nuevo')));
});

// 8. El indice de nombres es unico: una vez creado no se sobrescribe.
test('el indice de nombres no se sobrescribe', async () => {
  const admin = db(ADMIN);
  await assertFails(set(ref(admin, '/usernames/member'), OTHER));
  await assertSucceeds(
    set(ref(admin, '/allowlist/uid-nuevo'), entry('nuevo', { accountId: 'uid-nuevo' })),
  );
  await assertSucceeds(set(ref(admin, '/usernames/nuevo'), 'uid-nuevo'));
  await assertFails(set(ref(admin, '/usernames/nuevo'), 'uid-nuevo'));
  // Y nunca puede apuntar a una cuenta que no este en la allowlist.
  await assertFails(set(ref(admin, '/usernames/fantasma'), 'uid-inexistente'));
});

// 8-bis. Regenerar una credencial no pierde datos: la identidad nueva escribe
//        en la misma cuenta y la vieja queda retirada para siempre.
test('una credencial regenerada conserva la cuenta y retira la vieja', async () => {
  const admin = db(ADMIN);
  const fresh = 'uid-member-gen2';

  await assertSucceeds(
    set(ref(admin, `/allowlist/${fresh}`), entry('member', {
      accountId: MEMBER,
      generation: 2,
      mustChangePassword: true,
    })),
  );
  await assertSucceeds(
    update(ref(admin, `/allowlist/${MEMBER}`), { disabled: true, retired: true }),
  );

  // La identidad nueva lee y escribe los datos de siempre.
  const renewed = db(fresh);
  const snapshot = await assertSucceeds(get(ref(renewed, `/users/${MEMBER}/profile`)));
  assert.equal(snapshot.val().username, 'member');
  await assertSucceeds(
    set(ref(renewed, `/users/${MEMBER}/profile/displayName`), 'sigo aqui'),
  );
  // Pero no puede usar la regeneracion para escribir en otra cuenta.
  await assertFails(set(ref(renewed, `/users/${OTHER}/profile/displayName`), 'x'));

  // La vieja ya no escribe nada.
  await assertFails(
    set(ref(db(MEMBER), `/users/${MEMBER}/profile/displayName`), 'x'),
  );

  // Nadie puede des-retirarla ni rehabilitarla.
  await assertFails(set(ref(admin, `/allowlist/${MEMBER}/retired`), false));
  await assertFails(set(ref(admin, `/allowlist/${MEMBER}/disabled`), false));

  // Y el accountId de una identidad es inmutable, ni siquiera el admin lo mueve.
  await assertFails(set(ref(admin, `/allowlist/${fresh}/accountId`), OTHER));
});

// 9. Validacion de campos del perfil.
test('el perfil valida tipos y longitudes', async () => {
  const member = db(MEMBER);
  const base = `/users/${MEMBER}/profile`;

  await assertFails(set(ref(member, `${base}/displayName`), ''));
  await assertFails(set(ref(member, `${base}/displayName`), 'x'.repeat(25)));
  await assertSucceeds(set(ref(member, `${base}/displayName`), 'x'.repeat(24)));

  await assertFails(set(ref(member, `${base}/statusMessage`), 'y'.repeat(101)));
  await assertSucceeds(set(ref(member, `${base}/statusMessage`), 'y'.repeat(100)));

  await assertFails(set(ref(member, `${base}/accentColor`), 'azul'));
  await assertFails(set(ref(member, `${base}/accentColor`), '#5BC8F'));
  await assertSucceeds(set(ref(member, `${base}/accentColor`), '#1B8FD0'));

  await assertFails(set(ref(member, `${base}/locale`), 'fr'));
  await assertSucceeds(set(ref(member, `${base}/locale`), 'en'));

  await assertFails(set(ref(member, `${base}/birthday`), '14-09-1998'));
  await assertSucceeds(set(ref(member, `${base}/birthday`), '1998-09-14'));
  await assertSucceeds(set(ref(member, `${base}/birthday`), ''));

  // El nombre de usuario del perfil tiene que coincidir con el de la allowlist.
  await assertFails(set(ref(member, `${base}/username`), 'otro'));

  // Y no cuela un campo inventado.
  await assertFails(set(ref(member, `${base}/monedas`), 9999));
});

// 10. Tamas: el contador. Crear o borrar un Tama va en la misma operacion
//     multi-ruta que el contador y que el marcador del cambio.
const tamaId = (n) => `-Tama${String(n).padStart(15, '0')}`;

const tamaLook = (extra = {}) => ({
  body: 0, eyes: 1, mouth: 0, crown: 1, cheeks: 1, pattern: 1, arms: 0, feet: 0,
  bodyWidth: 50, bodyHeight: 50, eyeSize: 50, eyeSpacing: 50, eyeHeight: 50,
  mouthSize: 50, mouthHeight: 50, crownSize: 50, cheekIntensity: 60, patternTone: 25,
  color: '#5BC8F5', colorMode: 'palette',
  ...extra,
});

const tamaRecord = (owner, extra = {}) => ({
  schema: 1,
  creator: owner,
  keeper: owner,
  name: 'Tommy',
  personality: 'playful',
  voice: { pitch: 50, tempo: 50, timbre: 0 },
  look: tamaLook(),
  createdAt: now,
  updatedAt: now,
  ...extra,
});

const createTama = (database, owner, id, count, extra = {}) =>
  update(ref(database, '/'), {
    [`tamas/${id}`]: tamaRecord(owner, extra),
    [`users/${owner}/tamaCount`]: count,
    [`users/${owner}/tamaLastChange`]: id,
  });

const deleteTama = (database, owner, id, count) =>
  update(ref(database, '/'), {
    [`tamas/${id}`]: null,
    [`users/${owner}/tamaCount`]: count,
    [`users/${owner}/tamaLastChange`]: id,
  });

test('crear un Tama exige mover el contador en la misma operacion', async () => {
  const member = db(MEMBER);

  await assertSucceeds(createTama(member, MEMBER, tamaId(1), 1));

  // Sin contador, con un salto de dos o con el marcador equivocado: no.
  await assertFails(set(ref(member, `/tamas/${tamaId(2)}`), tamaRecord(MEMBER)));
  await assertFails(createTama(member, MEMBER, tamaId(2), 3));
  await assertFails(
    update(ref(member, '/'), {
      [`tamas/${tamaId(2)}`]: tamaRecord(MEMBER),
      [`users/${MEMBER}/tamaCount`]: 2,
      [`users/${MEMBER}/tamaLastChange`]: tamaId(1),
    }),
  );

  // Dos Tamas con un solo incremento: no.
  await assertFails(
    update(ref(member, '/'), {
      [`tamas/${tamaId(2)}`]: tamaRecord(MEMBER),
      [`tamas/${tamaId(3)}`]: tamaRecord(MEMBER),
      [`users/${MEMBER}/tamaCount`]: 2,
      [`users/${MEMBER}/tamaLastChange`]: tamaId(2),
    }),
  );

  // Subir o bajar el contador sin crear ni borrar nada: no. Es lo que dejaria
  // resetearlo y crear Tamas sin fin.
  await assertFails(
    update(ref(member, `/users/${MEMBER}`), { tamaCount: 2, tamaLastChange: tamaId(9) }),
  );
  await assertFails(
    update(ref(member, `/users/${MEMBER}`), { tamaCount: 0, tamaLastChange: tamaId(1) }),
  );
  await assertFails(set(ref(member, `/users/${MEMBER}/tamaCount`), 0));

  // Ni borrarlo entero, ni borrar la cuenta para empezar de cero.
  await assertFails(set(ref(member, `/users/${MEMBER}/tamaCount`), null));
  await assertFails(set(ref(member, `/users/${MEMBER}/tamaLastChange`), null));
  await assertFails(set(ref(member, `/users/${MEMBER}`), null));

  // Un Tama nace siendo de quien lo crea, y del contador de quien lo crea.
  await assertFails(createTama(member, MEMBER, tamaId(2), 2, { keeper: OTHER }));
  await assertFails(createTama(member, MEMBER, tamaId(2), 2, { creator: OTHER }));
  await assertFails(createTama(member, OTHER, tamaId(2), 1));

  const count = await get(ref(member, `/users/${MEMBER}/tamaCount`));
  assert.equal(count.val(), 1);
});

// 11. Criterio de aceptacion 4: el Tama numero 100 no se puede crear, aunque
//     se llame a la API directamente.
test('las reglas impiden crear el Tama numero 100', async () => {
  const member = db(MEMBER);
  for (let n = 1; n <= 99; n++) {
    await assertSucceeds(createTama(member, MEMBER, tamaId(n), n));
  }
  await assertFails(createTama(member, MEMBER, tamaId(100), 100));
  // Tampoco saltandose el contador o reutilizando el ultimo marcador.
  await assertFails(set(ref(member, `/tamas/${tamaId(100)}`), tamaRecord(MEMBER)));
  await assertFails(createTama(member, MEMBER, tamaId(100), 99));

  // Al borrar uno baja exactamente en uno, y vuelve a haber sitio.
  await assertFails(deleteTama(member, MEMBER, tamaId(99), 97));
  await assertSucceeds(deleteTama(member, MEMBER, tamaId(99), 98));
  await assertSucceeds(createTama(member, MEMBER, tamaId(100), 99));
  await assertFails(createTama(member, MEMBER, tamaId(101), 100));
});

// 12. Criterio de aceptacion 5: solo el creador edita el aspecto. El cuidador
//     (que en el futuro podra ser un amigo) solo escribe los cuidados.
async function seedTamas() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const root = context.database();
    await update(ref(root, '/'), {
      // Creado por member y ya traspasado a other: el caso del checkpoint 3.
      [`tamas/${tamaId(1)}`]: tamaRecord(MEMBER, { keeper: OTHER, name: 'Viajero' }),
      [`tamas/${tamaId(2)}`]: tamaRecord(MEMBER, { name: 'Casero' }),
      [`users/${MEMBER}/tamaCount`]: 2,
      [`users/${MEMBER}/tamaLastChange`]: tamaId(2),
    });
  });
}

test('solo el creador edita el aspecto de un Tama', async () => {
  await seedTamas();
  const member = db(MEMBER);
  const other = db(OTHER);
  const traveller = `/tamas/${tamaId(1)}`;
  const home = `/tamas/${tamaId(2)}`;

  // Alguien que no lo ha creado no toca ni aspecto, ni nombre, ni voz.
  await assertFails(set(ref(other, `${home}/look/color`), '#000000'));
  await assertFails(set(ref(other, `${home}/look`), tamaLook({ body: 3 })));
  await assertFails(set(ref(other, `${traveller}/look/color`), '#000000'));
  await assertFails(set(ref(other, `${traveller}/name`), 'Mio'));
  await assertFails(set(ref(other, `${traveller}/personality`), 'shy'));
  await assertFails(set(ref(other, `${traveller}/voice/pitch`), 90));
  await assertFails(set(ref(other, traveller), tamaRecord(OTHER)));
  await assertFails(set(ref(other, `${traveller}/creator`), OTHER));

  // Pero si lo cuida, si le da de comer y lo mima.
  await assertSucceeds(set(ref(other, `${traveller}/care/lastFed`), now));
  await assertSucceeds(set(ref(other, `${traveller}/care/lastPetted`), now));

  // El creador edita el aspecto aunque ya no lo cuide, y no los cuidados.
  await assertSucceeds(set(ref(member, `${traveller}/look/color`), '#E8A33D'));
  await assertSucceeds(
    update(ref(member, traveller), {
      name: 'Viajera',
      personality: 'shy',
      voice: { pitch: 80, tempo: 20, timbre: 2 },
      look: tamaLook({ body: 5, colorMode: 'hex', color: '#123456' }),
      updatedAt: now,
    }),
  );
  await assertFails(set(ref(member, `${traveller}/care/lastFed`), now));

  // Nadie cambia quien lo creo, quien lo cuida ni cuando nacio.
  await assertFails(set(ref(member, `${home}/creator`), OTHER));
  await assertFails(set(ref(member, `${home}/keeper`), OTHER));
  await assertFails(set(ref(member, `${home}/createdAt`), now - 1000));
  await assertFails(set(ref(member, `${home}/schema`), 2));
});

test('cada campo del Tama valida tipo, rango y lista cerrada', async () => {
  await seedTamas();
  const member = db(MEMBER);
  const home = `/tamas/${tamaId(2)}`;
  const ok = (path, value) => assertSucceeds(set(ref(member, `${home}/${path}`), value));
  const bad = (path, value) => assertFails(set(ref(member, `${home}/${path}`), value));

  await ok('look/body', 5);
  await bad('look/body', 6);
  await bad('look/body', -1);
  await bad('look/mouth', 5);
  await ok('look/cheeks', 3);
  await bad('look/cheeks', 4);
  await ok('look/arms', 3);
  await bad('look/arms', 4);
  await ok('look/feet', 3);
  await bad('look/feet', 4);
  await ok('look/bodyWidth', 100);
  await bad('look/bodyWidth', 101);
  await bad('look/eyeSize', 50.5);
  await bad('look/eyeSize', '50');
  await ok('look/color', '#abcdef');
  await bad('look/color', 'rojo');
  await bad('look/color', '#12345');
  await ok('look/colorMode', 'hex');
  await bad('look/colorMode', 'rgb');
  await bad('look/sombrero', 1);
  await bad('look', { body: 1 });

  await ok('name', 'x'.repeat(16));
  await bad('name', 'x'.repeat(17));
  await bad('name', '');
  await ok('personality', 'sleepy');
  await bad('personality', 'grumpy');
  await ok('voice/timbre', 5);
  await bad('voice/timbre', 6);
  await bad('voice/pitch', 101);
  await bad('voice/volumen', 3);
  await bad('updatedAt', now + 3600 * 1000);
  await bad('monedas', 9999);

  // Cuidados: marcas de tiempo del pasado, nada mas.
  await ok('care/lastPetted', now);
  await bad('care/lastPetted', now + 3600 * 1000);
  await bad('care/lastPetted', 'ayer');
  await bad('care/humor', 80);
});

test('la lista de Tamas solo se lee con la consulta de cuidador propio', async () => {
  await seedTamas();
  const member = db(MEMBER);
  const other = db(OTHER);

  await assertSucceeds(
    get(query(ref(member, '/tamas'), orderByChild('keeper'), equalTo(MEMBER))),
  );
  const mine = await get(
    query(ref(other, '/tamas'), orderByChild('keeper'), equalTo(OTHER)),
  );
  assert.deepEqual(Object.keys(mine.val()), [tamaId(1)]);

  // Ni la coleccion entera ni la lista de otro.
  await assertFails(get(ref(member, '/tamas')));
  await assertFails(
    get(query(ref(member, '/tamas'), orderByChild('keeper'), equalTo(OTHER))),
  );
  await assertFails(
    get(query(ref(member, '/tamas'), orderByChild('creator'), equalTo(MEMBER))),
  );

  // Un Tama suelto: su creador y su cuidador, nadie mas (hasta el CP3).
  await assertSucceeds(get(ref(member, `/tamas/${tamaId(1)}`)));
  await assertSucceeds(get(ref(other, `/tamas/${tamaId(1)}`)));
  await assertFails(get(ref(other, `/tamas/${tamaId(2)}`)));
  await assertFails(get(ref(db(ORPHAN), `/tamas/${tamaId(2)}`)));
  await assertFails(get(ref(db(BANNED), `/tamas/${tamaId(2)}`)));
});

test('el Tama de perfil es uno que se cuida y no se puede borrar sin soltarlo', async () => {
  await seedTamas();
  const member = db(MEMBER);
  const other = db(OTHER);

  await assertSucceeds(set(ref(member, `/users/${MEMBER}/tama`), tamaId(2)));
  // Uno que ya no cuida, uno inexistente o un id raro: no.
  await assertFails(set(ref(member, `/users/${MEMBER}/tama`), tamaId(1)));
  await assertFails(set(ref(member, `/users/${MEMBER}/tama`), tamaId(7)));
  await assertFails(set(ref(member, `/users/${MEMBER}/tama`), 'hola'));
  await assertSucceeds(set(ref(other, `/users/${OTHER}/tama`), tamaId(1)));

  // Borrar el Tama de perfil sin soltarlo deja el perfil apuntando a la nada.
  await assertFails(deleteTama(member, MEMBER, tamaId(2), 1));
  await assertSucceeds(
    update(ref(member, '/'), {
      [`tamas/${tamaId(2)}`]: null,
      [`users/${MEMBER}/tamaCount`]: 1,
      [`users/${MEMBER}/tamaLastChange`]: tamaId(2),
      [`users/${MEMBER}/tama`]: null,
    }),
  );

  // Borra quien lo creo y lo cuida a la vez: ni el creador de uno traspasado
  // ni su cuidador.
  await assertFails(deleteTama(member, MEMBER, tamaId(1), 0));
  await assertFails(deleteTama(other, OTHER, tamaId(1), 0));
  await assertFails(deleteTama(other, MEMBER, tamaId(1), 0));
});

test('el acento sigue al Tama solo si es un booleano', async () => {
  const member = db(MEMBER);
  await assertSucceeds(set(ref(member, `/users/${MEMBER}/profile/accentFollowsTama`), true));
  await assertFails(set(ref(member, `/users/${MEMBER}/profile/accentFollowsTama`), 'si'));
});

// 13. La presencia valida su forma.
test('la presencia valida estado y marca de tiempo', async () => {
  const member = db(MEMBER);
  const base = `/users/${MEMBER}/presence`;
  await assertSucceeds(set(ref(member, base), { state: 'online', lastSeen: now }));
  await assertFails(set(ref(member, base), { state: 'inventado', lastSeen: now }));
  await assertFails(set(ref(member, base), { state: 'online' }));
});

// 14. Un miembro lee el anuncio del sistema pero no lo escribe.
test('el anuncio del sistema lo escribe solo el administrador', async () => {
  const member = db(MEMBER);
  await assertSucceeds(get(ref(member, '/system/announcement')));
  await assertFails(
    set(ref(member, '/system/announcement'), { text: 'no', updatedAt: now }),
  );
  const snapshot = await get(ref(member, '/system/announcement'));
  assert.equal(snapshot.val().text, 'hola');
});

// 15. Musica del menu: las canciones se desbloquean y solo se elige lo que se
//     tiene.
test('la musica del menu solo acepta canciones desbloqueadas', async () => {
  const member = db(MEMBER);
  const base = `/users/${MEMBER}/music`;

  // Las de serie se pueden elegir sin desbloquear nada.
  await assertSucceeds(set(ref(member, `${base}/menuTrack`), 'aurora'));
  // Una de las apps, no hasta que se ha escuchado.
  await assertFails(set(ref(member, `${base}/menuTrack`), 'plaza'));
  await assertSucceeds(set(ref(member, `${base}/unlocked/plaza`), true));
  await assertSucceeds(set(ref(member, `${base}/menuTrack`), 'plaza'));

  // Formato: identificador valido y solo `true`.
  await assertFails(set(ref(member, `${base}/unlocked/plaza`), false));
  await assertFails(set(ref(member, `${base}/unlocked/No-Valido!`), true));
  await assertFails(set(ref(member, `${base}/volumen`), 3));

  // Nadie desbloquea canciones en la cuenta de otro.
  await assertFails(set(ref(member, `/users/${OTHER}/music/unlocked/plaza`), true));
});
