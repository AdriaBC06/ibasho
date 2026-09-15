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
import { get, ref, set, update } from 'firebase/database';

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

// 10. El nodo del Tama esta reservado para el checkpoint 2.
test('nadie escribe todavia en el nodo del Tama', async () => {
  const member = db(MEMBER);
  await assertFails(set(ref(member, `/users/${MEMBER}/tama`), { especie: 'x' }));
  await assertFails(
    set(ref(db(ADMIN), `/users/${MEMBER}/tama`), { especie: 'x' }),
  );
});

// 11. La presencia valida su forma.
test('la presencia valida estado y marca de tiempo', async () => {
  const member = db(MEMBER);
  const base = `/users/${MEMBER}/presence`;
  await assertSucceeds(set(ref(member, base), { state: 'online', lastSeen: now }));
  await assertFails(set(ref(member, base), { state: 'inventado', lastSeen: now }));
  await assertFails(set(ref(member, base), { state: 'online' }));
});

// 12. Un miembro lee el anuncio del sistema pero no lo escribe.
test('el anuncio del sistema lo escribe solo el administrador', async () => {
  const member = db(MEMBER);
  await assertSucceeds(get(ref(member, '/system/announcement')));
  await assertFails(
    set(ref(member, '/system/announcement'), { text: 'no', updatedAt: now }),
  );
  const snapshot = await get(ref(member, '/system/announcement'));
  assert.equal(snapshot.val().text, 'hola');
});

// 13. Musica del menu: las canciones se desbloquean y solo se elige lo que se
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
