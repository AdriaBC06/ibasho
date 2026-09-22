// Ibasho — datos de prueba para usar la app contra los emuladores de Firebase.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uso, con los emuladores ya levantados:
//   firebase emulators:start --project demo-ibasho --only auth,database
//   dart run tool/dev_seed.dart
//   flutter run -d linux --dart-define-from-file=.env \
//     --dart-define=IBASHO_USE_EMULATOR=true --dart-define=IBASHO_PROJECT_ID=demo-ibasho
//
// Crea cuatro cuentas (contraseña `ibasho-dev`) con su codigo de amigo, su
// perfil, su ficha y su Tama de perfil:
//   - adria (admin) y mireia son amigos; hoy es el cumpleaños de mireia en su
//     zona (Asia/Tokyo) y pau ya le ha dejado un mensaje, este año y el pasado;
//   - laia le ha mandado una solicitud a adria;
//   - adria le ha mandado una a pau.
// Solo habla con 127.0.0.1: nunca toca el proyecto real.

import 'dart:convert';
import 'dart:io';

import 'package:ibasho/core/friend_code.dart';

const String _auth = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const String _db = 'http://127.0.0.1:9000';
const String _ns = 'demo-ibasho-default-rtdb';
const String _password = 'ibasho-dev';

Future<int> main() async {
  final client = HttpClient();
  try {
    final now = DateTime.now();
    final ms = now.millisecondsSinceEpoch;
    final tokyo = now.toUtc().add(const Duration(hours: 9));

    final people = <_Person>[
      _Person('adria', 'Adrià', 'Europe/Madrid', '1998-09-14', '#5BC8F5', 'Tommy', '#F6A8D0', 0,
          status: 'probando el checkpoint 3', admin: true),
      _Person('mireia', 'Mireia', 'Asia/Tokyo',
          '1999-${_two(tokyo.month)}-${_two(tokyo.day)}', '#EE7C96', 'Mochi', '#9FE0C6', 1,
          status: 'desde Tokio 🗼'),
      _Person('pau', 'Pau', 'America/Mexico_City', '1997-03-02', '#8CC96A', 'Bolo', '#F6CF4E', 2),
      _Person('laia', 'Laia', 'Europe/London', '2000-12-24', '#B08BE0', 'Nube', '#C6A8F0', 3),
    ];

    for (final person in people) {
      person.uid = await _signUp(client, '${person.username}@ibasho.top');
    }

    final tree = <String, Object?>{};
    var counter = 1;
    for (final person in people) {
      final code = FriendCode.forCounter(counter++);
      final tamaId = '-DevTama${person.username.padRight(12, '0')}';
      tree['allowlist/${person.uid}'] = {
        'accountId': person.uid,
        'username': person.username,
        'createdAt': ms,
        'createdBy': 'dev_seed',
        'disabled': false,
        'mustChangePassword': false,
        'generation': 1,
      };
      if (person.admin) tree['admins/${person.uid}'] = true;
      tree['usernames/${person.username}'] = person.uid;
      tree['friendCodes/$code'] = person.uid;
      tree['tamas/$tamaId'] = {
        'schema': 1,
        'creator': person.uid,
        'keeper': person.uid,
        'name': person.tamaName,
        'personality': ['playful', 'calm', 'cheeky', 'shy'][person.variant],
        'voice': {'pitch': 40 + person.variant * 12, 'tempo': 50, 'timbre': person.variant},
        'look': {
          'body': person.variant,
          'eyes': (person.variant + 1) % 6,
          'mouth': person.variant % 5,
          'crown': (person.variant + 1) % 6,
          'cheeks': 1,
          'pattern': (person.variant + 1) % 5,
          'arms': person.variant % 4,
          'feet': person.variant % 4,
          'bodyWidth': 50, 'bodyHeight': 50, 'eyeSize': 55, 'eyeSpacing': 50,
          'eyeHeight': 50, 'mouthSize': 50, 'mouthHeight': 50, 'crownSize': 55,
          'cheekIntensity': 60, 'patternTone': 25,
          'color': person.tamaColor,
          'colorMode': 'palette',
        },
        'care': {'lastPetted': ms - 3600000, 'lastFed': ms - 7200000},
        'createdAt': ms,
        'updatedAt': ms,
      };
      tree['users/${person.uid}'] = {
        'profile': {
          'username': person.username,
          'displayName': person.displayName,
          'statusMessage': person.status,
          'birthday': person.birthday,
          'timezone': person.timezone,
          'locale': 'es',
          'accentColor': person.accent,
          'accentFollowsTama': false,
          'createdAt': ms,
        },
        'card': {'displayName': person.displayName, 'accentColor': person.accent, 'tamaId': tamaId},
        'friendCode': code,
        'tama': tamaId,
        'tamaCount': 1,
        'tamaLastChange': tamaId,
        'presence': {'state': person.variant == 1 ? 'online' : 'offline', 'lastSeen': ms - 5400000},
        'music': {'profileTrack': ['aurora', 'noche', 'brisa', 'calma'][person.variant]},
      };
      stdout.writeln('  ${person.username.padRight(7)} ${FriendCode.format(code)}');
    }
    tree['system/friendCodeCounter'] = counter;
    tree['system/announcement'] = {'text': 'datos de prueba del checkpoint 3', 'updatedAt': ms};
    // Precios del Yatai, los mismos que carga tool/seed_shop.dart en produccion.
    tree['shop/prices'] = {
      'game_minesweeper': 0,
      'game_tsumiki': 10,
      'game_nihongo': 150,
      'food_cookie': 3,
      'food_candy': 3,
    };

    final adria = people[0], mireia = people[1], pau = people[2], laia = people[3];
    void friends(_Person a, _Person b) {
      tree['users/${a.uid}/friends/${b.uid}'] = {'since': ms - 86400000 * 400};
      tree['users/${b.uid}/friends/${a.uid}'] = {'since': ms - 86400000 * 400};
    }

    friends(adria, mireia);
    friends(pau, mireia);
    for (final p in people) {
      final count = [adria, pau].contains(p) ? 1 : (p == mireia ? 2 : 0);
      if (count > 0) {
        tree['users/${p.uid}/friendCount'] = count;
      }
    }
    tree['users/${laia.uid}/requests/out/${adria.uid}'] = {'at': ms - 600000};
    tree['users/${adria.uid}/requests/in/${laia.uid}'] = {'at': ms - 600000};
    tree['users/${adria.uid}/requests/out/${pau.uid}'] = {'at': ms - 1200000};
    tree['users/${pau.uid}/requests/in/${adria.uid}'] = {'at': ms - 1200000};
    tree['users/${mireia.uid}/wall/${tokyo.year}/${pau.uid}'] = {
      'text': '¡Feliz cumple, Mireia! Que Mochi te traiga muchas chuches 🎂',
      'at': ms - 3600000,
    };
    tree['users/${mireia.uid}/wall/${tokyo.year - 1}/${pau.uid}'] = {
      'text': 'felicidades desde el otro lado del charco',
      'at': ms - 86400000 * 365,
    };

    // Todo de golpe, saltandose las reglas como hace la CLI en produccion. Las
    // rutas se anidan antes: una fusion multi-ruta no admite una ruta dentro
    // de otra.
    final nested = <String, Object?>{};
    tree.forEach((path, value) {
      final segments = path.split('/');
      var node = nested;
      for (final segment in segments.take(segments.length - 1)) {
        node = (node[segment] ??= <String, Object?>{}) as Map<String, Object?>;
      }
      final last = segments.last;
      final existing = node[last];
      if (existing is Map<String, Object?> && value is Map) {
        existing.addAll(value.cast<String, Object?>());
      } else {
        node[last] = value;
      }
    });
    await _patch(client, '/', nested);
    stdout.writeln('\nListo. Contraseña de todas: $_password');
    return 0;
  } on HttpException catch (e) {
    stderr.writeln('No responde el emulador (${e.message}). ¿Esta levantado?');
    return 70;
  } finally {
    client.close();
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

class _Person {
  _Person(this.username, this.displayName, this.timezone, this.birthday, this.accent,
      this.tamaName, this.tamaColor, this.variant,
      {this.status = '', this.admin = false});

  final String username;
  final String displayName;
  final String timezone;
  final String birthday;
  final String accent;
  final String tamaName;
  final String tamaColor;
  final int variant;
  final String status;
  final bool admin;
  late String uid;
}

Future<String> _signUp(HttpClient client, String email) async {
  final body = {'email': email, 'password': _password, 'returnSecureToken': true};
  var reply = await _post(client, '$_auth/accounts:signUp?key=demo-key', body);
  if (reply['localId'] == null) {
    reply = await _post(client, '$_auth/accounts:signInWithPassword?key=demo-key', body);
  }
  final uid = reply['localId'];
  if (uid is! String) throw HttpException('auth: $reply');
  return uid;
}

Future<Map<String, Object?>> _post(HttpClient client, String url, Object body) async {
  final request = await client.postUrl(Uri.parse(url));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  return jsonDecode(text) as Map<String, Object?>;
}

Future<void> _patch(HttpClient client, String path, Map<String, Object?> value) async {
  final request = await client.patchUrl(Uri.parse('$_db$path.json?ns=$_ns'));
  request.headers
    ..contentType = ContentType.json
    ..set('Authorization', 'Bearer owner');
  request.write(jsonEncode(value));
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode >= 300) throw HttpException('database: $text');
}
