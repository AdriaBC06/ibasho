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
// Crea las cuentas (contraseña `ibasho-dev`) con su codigo de amigo, su
// perfil, su ficha y su Tama de perfil:
//   - adria (admin) y mireia son amigos; hoy es el cumpleaños de mireia en su
//     zona (Asia/Tokyo) y pau ya le ha dejado un mensaje, este año y el pasado;
//   - laia le ha mandado una solicitud a adria;
//   - adria le ha mandado una a pau;
//   - admin2 (también admin) es amigo de adria y los dos tienen Tsumiki
//     abierto, para probar el versus en dos ventanas.
// Y Tama Kōen con todo desbloqueado para adria (ver `_koen`): tres amigos
// más (kenji, sora y hana) con Tamas en el parque, un amigo en cada nivel de
// amistad, un dúo con mireia en racha de 29 días y la casita a nivel 5, el
// álbum entero y una oferta de cuidar a medias de sora.
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
      _Person('kenji', 'Kenji', 'Asia/Tokyo', '1996-05-05', '#F2994A', 'Taro', '#F4B183', 4),
      _Person('sora', 'Sora', 'Europe/Madrid', '2001-07-20', '#56CCF2', 'Fuu', '#A8E6F0', 5),
      _Person('hana', 'Hana', 'Europe/Madrid', '1999-04-01', '#F78FB3', 'Ichigo', '#F7B2C4', 6),
      // La segunda cuenta para probar el versus de Tsumiki contra adria.
      _Person('admin2', 'Admin 2', 'Europe/Madrid', '1995-06-15', '#F2C94C', 'Kiri', '#F9E79F', 7, admin: true),
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
        'personality': ['playful', 'calm', 'cheeky', 'shy'][person.variant % 4],
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
        'music': {'profileTrack': ['aurora', 'noche', 'brisa', 'calma'][person.variant % 4]},
      };
      stdout.writeln('  ${person.username.padRight(7)} ${FriendCode.format(code)}');
    }
    tree['system/friendCodeCounter'] = counter;
    tree['system/announcement'] = {'text': 'datos de prueba del checkpoint 3', 'updatedAt': ms};
    // Precios del Yatai, los mismos que carga tool/seed_shop.dart en produccion.
    tree['shop/prices'] = {
      'game_minesweeper': 0,
      'game_tsumiki': 10,
      'game_hebi': 10,
      'game_nihongo': 50,
      'food_cookie': 3,
      'food_candy': 3,
    };

    final adria = people[0], mireia = people[1], pau = people[2], laia = people[3];
    final friendCount = <_Person, int>{};
    void friends(_Person a, _Person b) {
      tree['users/${a.uid}/friends/${b.uid}'] = {'since': ms - 86400000 * 400};
      tree['users/${b.uid}/friends/${a.uid}'] = {'since': ms - 86400000 * 400};
      friendCount[a] = (friendCount[a] ?? 0) + 1;
      friendCount[b] = (friendCount[b] ?? 0) + 1;
    }

    friends(adria, mireia);
    friends(pau, mireia);
    // adria y admin2, amigos y con Tsumiki ya abierto, para jugar el versus.
    final admin2 = people.firstWhere((p) => p.username == 'admin2');
    friends(adria, admin2);
    for (final p in [adria, admin2]) {
      tree['users/${p.uid}/games/tsumiki'] = {'state': 'open', 'at': ms};
    }
    _koen(tree, people, friends, now);
    friendCount.forEach((p, count) => tree['users/${p.uid}/friendCount'] = count);
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

/// Tama Kōen con todo desbloqueado para adria. Los premios que se cobran
/// (monedas por nivel de amistad, el fondo y el gorro de los Tamas más
/// amigos, el día 30 de la racha) se dejan sin cobrar: los cobra la app al
/// abrir el parque, contra las reglas del emulador.
void _koen(
  Map<String, Object?> tree,
  List<_Person> people,
  void Function(_Person, _Person) friends,
  DateTime now,
) {
  final ms = now.millisecondsSinceEpoch;
  final today = now.toUtc().millisecondsSinceEpoch ~/ 86400000;
  final byName = {for (final p in people) p.username: p};
  final adria = byName['adria']!, mireia = byName['mireia']!;
  final kenji = byName['kenji']!, sora = byName['sora']!, hana = byName['hana']!;

  // Los Tamas de perfil ya están; se añaden otros para llenar el parque.
  String tamaOf(_Person p) => '-DevTama${p.username.padRight(12, '0')}';
  var extra = 0;
  String addTama(_Person p, String name, String color) {
    final id = '-DevKoen${name.toLowerCase().padRight(12, '0')}';
    final v = 7 + extra++;
    tree['tamas/$id'] = {
      'schema': 1,
      'creator': p.uid,
      'keeper': p.uid,
      'name': name,
      'personality': ['playful', 'calm', 'cheeky', 'shy', 'sleepy'][v % 5],
      'voice': {'pitch': 30 + v * 7 % 60, 'tempo': 40 + v * 3 % 30, 'timbre': v % 4},
      'look': {
        'body': v % 6,
        'eyes': (v + 2) % 6,
        'mouth': v % 5,
        'crown': (v + 3) % 6,
        'cheeks': v % 2,
        'pattern': v % 5,
        'arms': v % 4,
        'feet': (v + 1) % 4,
        'bodyWidth': 40 + v * 5 % 30, 'bodyHeight': 50, 'eyeSize': 55, 'eyeSpacing': 50,
        'eyeHeight': 50, 'mouthSize': 50, 'mouthHeight': 50, 'crownSize': 55,
        'cheekIntensity': 60, 'patternTone': 25,
        'color': color,
        'colorMode': 'palette',
      },
      'care': {'lastPetted': ms - 3600000, 'lastFed': ms - 7200000},
      'createdAt': ms,
      'updatedAt': ms,
    };
    // Se anidan dentro de users/{cuenta} al final, como el resto.
    tree['users/${p.uid}/tamaCount'] = ((tree['users/${p.uid}/tamaCount'] as int?) ?? 1) + 1;
    tree['users/${p.uid}/tamaLastChange'] = id;
    return id;
  }

  final tommy = tamaOf(adria), mochi = tamaOf(mireia);
  final kumo = addTama(adria, 'Kumo', '#B8C4F0');
  final hoshi = addTama(adria, 'Hoshi', '#F6E27A');
  final ame = addTama(mireia, 'Ame', '#9EC9F5');
  final pon = addTama(kenji, 'Pon', '#C9A27E');
  final riku = addTama(kenji, 'Riku', '#8FD19E');
  final nori = addTama(sora, 'Nori', '#6FCF97');
  final momo = addTama(hana, 'Momo', '#FFB7A8');
  final sumi = addTama(hana, 'Sumi', '#9B9B9B');

  // Amigos de adria, y entre ellos (para los amigos de amigos).
  friends(adria, kenji);
  friends(adria, sora);
  friends(adria, hana);
  friends(mireia, kenji);
  friends(kenji, sora);
  friends(sora, hana);

  // Cuidados a medias: Tommy y Mochi, el dúo de adria y mireia.
  (tree['tamas/$tommy']! as Map<String, Object?>)['carer'] = mireia.uid;
  (tree['tamas/$mochi']! as Map<String, Object?>)['carer'] = adria.uid;
  tree['users/${mireia.uid}/koen/caring/$tommy'] = adria.uid;
  tree['users/${adria.uid}/koen/caring/$mochi'] = mireia.uid;

  Map<String, Object?> card(String id, {String? duo, int ago = 3600000}) {
    final t = tree['tamas/$id']! as Map<String, Object?>;
    return {
      'tamaId': id,
      'owner': t['creator'],
      'name': t['name'],
      'personality': t['personality'],
      'voice': t['voice'],
      'look': t['look'],
      'at': ms - ago,
      'duo': ?duo,
    };
  }

  void park(_Person p, List<Map<String, Object?>> cards) {
    for (var i = 0; i < cards.length; i++) {
      tree['users/${p.uid}/koen/park/$i'] = cards[i];
    }
  }

  park(adria, [card(tommy, duo: mochi), card(kumo), card(hoshi)]);
  park(mireia, [card(mochi, duo: tommy), card(ame)]);
  park(kenji, [card(tamaOf(kenji)), card(pon), card(riku)]);
  park(sora, [card(tamaOf(sora)), card(nori)]);
  park(hana, [card(tamaOf(hana)), card(momo), card(sumi)]);

  // Un amigo en cada nivel: mireia inseparables (150), kenji buenos amigos
  // (60), sora amigos (20) y hana conocidos (1). Sin `l`: la app avisa de
  // cada nivel y cobra sus monedas.
  void points(_Person a, _Person b, int each, {int? other}) {
    tree['users/${a.uid}/koen/friends/${b.uid}'] = {'p': each, 'd': today - 1, 'n': 0};
    tree['users/${b.uid}/koen/friends/${a.uid}'] = {'p': other ?? each, 'd': today - 1, 'n': 0};
  }

  points(adria, mireia, 75);
  points(adria, kenji, 30);
  points(adria, sora, 10);
  points(adria, hana, 1, other: 0);

  // Amistad entre Tamas: Tommy y Mochi al máximo (5), Kumo y Taro en el 4,
  // Hoshi e Ichigo en el 3.
  String pair(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';
  void bond(_Person a, String ta, _Person b, String tb, int p) {
    final value = {'p': p, 'd': today - 1, 'n': 0};
    tree['users/${a.uid}/koen/bonds/${pair(ta, tb)}'] = value;
    tree['users/${b.uid}/koen/bonds/${pair(ta, tb)}'] = value;
  }

  bond(adria, tommy, mireia, mochi, 25);
  bond(adria, kumo, kenji, tamaOf(kenji), 15);
  bond(adria, hoshi, hana, tamaOf(hana), 8);

  // El álbum entero, de días pasados.
  const memories = [
    'first', 'swings', 'slide', 'sandbox', 'pond', 'picnic', 'tree', 'stroll',
    'spring', 'summer', 'autumn', 'winter', 'hanami', 'splash', 'momiji', 'snowman',
    'morning', 'dusk', 'fireflies', 'siblings', 'friendsOfFriends', 'dragged', 'besties',
    'busyDay', 'duo',
  ];
  for (var i = 0; i < memories.length; i++) {
    tree['users/${adria.uid}/koen/album/${memories[i]}'] = today - 60 + i * 2;
  }

  // El dúo: 29 días de racha (con Tommy y Mochi cuidados hoy, al abrir el
  // parque llega a 30 y cobra el gato de la suerte), mejor racha 30 para
  // que la casita esté ya a nivel 5, y los premios de 3, 7 y 14 cobrados.
  final duo = pair(adria.uid, mireia.uid);
  final (a, b) = adria.uid.compareTo(mireia.uid) < 0 ? (adria, mireia) : (mireia, adria);
  tree['koen/$duo'] = {
    'a': a.uid,
    'b': b.uid,
    'slots': {'left': tommy, 'right': mochi},
    'streak': {'count': 29, 'day': today - 1, 'best': 30},
    'house': {
      'decor': {'0': 'zabuton', '1': 'andon', '2': 'kotatsu', '3': 'bonsai', '4': 'tansu'},
    },
  };
  for (final p in [adria, mireia]) {
    for (final days in [3, 7, 14]) {
      tree['users/${p.uid}/koen/duos/$duo/$days'] = true;
    }
  }

  // sora le ofrece a adria cuidar a medias a Nori.
  tree['users/${adria.uid}/koenInbox/${sora.uid}'] = card(nori, ago: 1800000);
}

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
