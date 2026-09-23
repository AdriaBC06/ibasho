// Ibasho — dobles de prueba del backend y del almacenamiento.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:ibasho/state/system_status.dart';
import 'package:ibasho/backend/errors.dart';
import 'package:ibasho/backend/ibasho_backend.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/rtdb_socket.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/core/friend_code.dart';
import 'package:ibasho/storage/secure_store.dart';
import 'package:ibasho/storage/settings_store.dart';

const String kAdminUid = 'uid-admin';
const String kAdminUsername = 'adria';

/// Backend en memoria. Sirve para el recorrido visual y para los tests de
/// interfaz: responde igual que el de verdad sin tocar la red.
/// Un equipo sin bateria, o con la que se le diga.
class FakeBatteryWatch implements BatteryWatch {
  FakeBatteryWatch([this.info]);

  BatteryInfo? info;

  @override
  Future<BatteryInfo?> read() async => info;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

class FakeIbashoBackend implements IbashoBackend {
  FakeIbashoBackend({
    this.uid = kAdminUid,
    this.username = kAdminUsername,
    this.isAdmin = true,
    this.mustChangePassword = false,
    this.hasProfile = true,
    this.link = LinkQuality.strong,
    this.locale = 'es',
    this.tamas = const <Tama>[],
    this.profileTamaId,
  });

  final String uid;
  final String username;
  final bool isAdmin;
  final bool mustChangePassword;
  final bool hasProfile;
  final LinkQuality link;
  final String locale;

  /// Tamas con los que arranca la base. Deben tener `keeper` = [uid].
  final List<Tama> tamas;

  /// Cual de ellos esta en el perfil.
  final String? profileTamaId;

  /// Escrituras recibidas, por si un test quiere comprobarlas.
  final List<(String path, Object? value)> writes = <(String, Object?)>[];

  /// Rutas que se comportan como si las reglas negaran la lectura.
  ///
  /// El backend falso no aplica reglas, y hay casos en los que eso esconde
  /// fallos reales: una conversacion que aun no existe no se puede leer, y el
  /// cliente tiene que apañarselas igual. Con esto un test puede reproducirlo.
  bool Function(String path)? denyRead;

  AuthTokens get tokens => AuthTokens(
        uid: uid,
        idToken: 'id-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  Map<String, Object?> get _entry => AllowlistEntry(
        uid: uid,
        accountId: uid,
        username: username,
        createdAt: DateTime(2026, 9, 1),
        createdBy: 'bootstrap',
        disabled: false,
        mustChangePassword: mustChangePassword,
        generation: 1,
      ).toJson();

  Map<String, Object?> get _profile => UserProfile(
        username: username,
        displayName: 'Adrià',
        statusMessage: 'montando el CP2 a las tantas',
        birthday: '1998-09-14',
        timezone: 'Europe/Madrid',
        locale: locale,
        createdAt: DateTime(2026, 9, 1),
      ).toJson();

  @override
  Future<SignIn> signIn({
    required String username,
    required String password,
    int knownGeneration = 1,
  }) async {
    if (password == 'mal') {
      throw const IbashoException(IbashoFailure.invalidCredentials);
    }
    return SignIn(tokens: tokens, generation: 1);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async => tokens;

  @override
  Future<AuthTokens> changePassword({
    required AuthTokens session,
    required String newPassword,
  }) async =>
      tokens;

  @override
  Future<ProvisionedAccount> provisionAccount({
    required String username,
    required String password,
    int generation = 1,
  }) async =>
      ProvisionedAccount(uid: 'uid-$username', username: username, password: password);

  // --- Base en memoria -------------------------------------------------------
  //
  // Un arbol JSON con lo mismo que tendria la base de verdad. Las lecturas, las
  // escrituras multi-ruta, las consultas por hijo y los streams trabajan sobre
  // el, asi que dos controladores sobre el mismo doble se ven los cambios como
  // se los verian dos equipos.

  /// La base es compartida: [sharing] crea otra cuenta sobre el mismo arbol,
  /// como dos personas en dos equipos.
  late _FakeDatabase _db = _FakeDatabase(_seedTree());

  Map<String, Object?> get _root => _db.root;
  set _root(Map<String, Object?> value) => _db.root = value;

  List<(String, DatabaseQuery?, StreamController<DatabaseEvent>)> get _watchers => _db.watchers;

  /// Otra cuenta que ve la misma base que esta.
  FakeIbashoBackend sharing({required String uid, required String username, bool isAdmin = false}) {
    final other = FakeIbashoBackend(uid: uid, username: username, isAdmin: isAdmin, link: link);
    other._db = _db;
    return other;
  }

  /// Lecturas recibidas, en orden.
  List<String> get reads => _db.reads;

  Map<String, Object?> _seedTree() => <String, Object?>{
        'allowlist': <String, Object?>{
          uid: _entry,
          'uid-mireia': AllowlistEntry(
            uid: 'uid-mireia',
            accountId: 'uid-mireia',
            username: 'mireia',
            createdAt: DateTime(2026, 9, 10),
            createdBy: uid,
            disabled: false,
            mustChangePassword: true,
            generation: 1,
          ).toJson(),
          'uid-pau': AllowlistEntry(
            uid: 'uid-pau',
            accountId: 'uid-pau',
            username: 'pau',
            createdAt: DateTime(2026, 9, 12),
            createdBy: uid,
            disabled: true,
            mustChangePassword: false,
            generation: 2,
          ).toJson(),
        },
        'admins': <String, Object?>{if (isAdmin) uid: true},
        'users': <String, Object?>{
          uid: <String, Object?>{
            if (hasProfile) 'profile': _profile,
            if (profileTamaId != null) 'tama': profileTamaId,
            if (tamas.isNotEmpty) 'tamaCount': tamas.length,
          },
        },
        if (tamas.isNotEmpty)
          'tamas': <String, Object?>{for (final t in tamas) t.id: t.toJson()},
        'system': <String, Object?>{
          'announcement': <String, Object?>{'text': 'el CP2 trae los Tamas', 'updatedAt': 0},
        },
      };


  /// Escribe saltandose todo, como haria otro equipo o la consola de Firebase.
  void seed(String path, Object? value) {
    _setAt(path, _resolve(value));
    _notify();
  }

  /// Lo que hay ahora mismo en una ruta.
  Object? peek(String path) => _getAt(path);

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList(growable: false);

  Object? _getAt(String path) {
    Object? node = _root;
    for (final segment in _segments(path)) {
      if (node is! Map) return null;
      node = node[segment];
    }
    return node;
  }

  void _setAt(String path, Object? value) {
    final segments = _segments(path);
    if (segments.isEmpty) {
      _root = value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
      return;
    }
    var node = _root;
    for (final segment in segments.take(segments.length - 1)) {
      final next = node[segment];
      if (next is Map<String, Object?>) {
        node = next;
      } else {
        final created = <String, Object?>{};
        node[segment] = created;
        node = created;
      }
    }
    if (value == null) {
      node.remove(segments.last);
      _prune(_root, segments);
    } else {
      node[segments.last] = value;
    }
  }

  /// Como la base de verdad: un nodo que se queda sin hijos deja de existir.
  static void _prune(Map<String, Object?> node, List<String> path) {
    if (path.length < 2) return;
    final child = node[path.first];
    if (child is! Map<String, Object?>) return;
    _prune(child, path.sublist(1));
    if (child.isEmpty) node.remove(path.first);
  }

  /// Copia profunda con las marcas de tiempo del servidor ya resueltas.
  Object? _resolve(Object? value) {
    if (value is Map) {
      if (value.length == 1 && value['.sv'] == 'timestamp') {
        return DateTime.now().millisecondsSinceEpoch;
      }
      return <String, Object?>{
        for (final e in value.entries) '${e.key}': _resolve(e.value),
      };
    }
    return value;
  }

  Object? _snapshot(String path, DatabaseQuery? query) {
    final node = _resolve(_getAt(path));
    if (query == null) return node;
    if (node is! Map) return null;
    final matching = <String, Object?>{
      for (final e in node.entries)
        if (e.value is Map && (e.value as Map)[query.orderByChild] == query.equalTo)
          '${e.key}': e.value,
    };
    return matching.isEmpty ? null : matching;
  }

  void _notify() {
    for (final (path, query, controller) in _watchers) {
      if (!controller.isClosed) {
        controller.add(DatabaseEvent(path: '/', data: _snapshot(path, query), isPatch: false));
      }
    }
  }

  @override
  Future<Object?> read(
    String path, {
    required String idToken,
    bool shallow = false,
    DatabaseQuery? query,
  }) async {
    _db.reads.add(path);
    if (denyRead?.call(path) ?? false) {
      throw const IbashoException(IbashoFailure.permissionDenied);
    }
    return _snapshot(path, query);
  }

  @override
  Future<void> write(String path, Object? value, {required String idToken}) async {
    writes.add((path, value));
    _setAt(path, _resolve(value));
    _notify();
  }

  @override
  Future<void> merge(String path, Map<String, Object?> value,
      {required String idToken}) async {
    writes.add((path, value));
    final base = path.endsWith('/') ? path : '$path/';
    value.forEach((key, child) => _setAt('$base$key', _resolve(child)));
    _notify();
  }

  @override
  Future<void> remove(String path, {required String idToken}) async {
    writes.add((path, null));
    _setAt(path, null);
    _notify();
  }

  @override
  Stream<DatabaseEvent> watch(
    String path, {
    required Future<String> Function() token,
    DatabaseQuery? query,
  }) {
    late final StreamController<DatabaseEvent> controller;
    controller = StreamController<DatabaseEvent>(
      onListen: () {
        if (denyRead?.call(path) ?? false) {
          controller.addError(const IbashoException(IbashoFailure.permissionDenied));
          return;
        }
        _watchers.add((path, query, controller));
        controller.add(DatabaseEvent(path: '/', data: _snapshot(path, query), isPatch: false));
      },
      onCancel: () => _watchers.removeWhere((w) => w.$3 == controller),
    );
    return controller.stream;
  }

  /// Conexiones de presencia abiertas, la ultima al final.
  final List<FakePresenceLink> presenceLinks = <FakePresenceLink>[];

  @override
  PresenceLink openPresenceLink({required Future<String> Function() token}) {
    final created = FakePresenceLink(this);
    presenceLinks.add(created);
    return created;
  }

  @override
  Future<LinkQuality> probe() async => link;

  /// Ultimo aviso de segundo plano recibido.
  bool background = false;

  @override
  void setBackground(bool background) => this.background = background;

  @override
  void setOwnAccount(String? accountId) {}

  @override
  void dispose() {
    for (final (_, _, controller) in _watchers.toList()) {
      unawaited(controller.close());
    }
  }
}

class _FakeDatabase {
  _FakeDatabase(this.root);

  Map<String, Object?> root;
  final List<(String, DatabaseQuery?, StreamController<DatabaseEvent>)> watchers =
      <(String, DatabaseQuery?, StreamController<DatabaseEvent>)>[];
  final List<String> reads = <String>[];
}

/// Conexion de presencia en memoria: escribe en la base del doble y guarda lo
/// encargado para la desconexion, que se aplica con [drop] o al cerrar.
class FakePresenceLink implements PresenceLink {
  FakePresenceLink(this._backend) {
    scheduleMicrotask(() {
      if (_closed) return;
      _connected = true;
      _connection.add(true);
    });
  }

  final FakeIbashoBackend _backend;
  final StreamController<bool> _connection = StreamController<bool>.broadcast();
  bool _connected = false;
  bool _closed = false;

  /// Lo encargado para cuando se pierda la conexion, por ruta.
  final Map<String, Object?> onDisconnect = <String, Object?>{};

  @override
  Stream<bool> get connection => _connection.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> set(String path, Object? value) => _backend.write(path, value, idToken: 'socket');

  @override
  Future<void> setOnDisconnect(String path, Object? value) async => onDisconnect[path] = value;

  @override
  Future<void> cancelOnDisconnect(String path) async => onDisconnect.remove(path);

  /// El servidor nota que la conexion se ha caido: ejecuta lo encargado.
  Future<void> drop({bool reconnect = false}) async {
    _connected = false;
    if (!_connection.isClosed) _connection.add(false);
    for (final entry in Map.of(onDisconnect).entries) {
      await _backend.write(entry.key, entry.value, idToken: 'servidor');
    }
    onDisconnect.clear();
    if (reconnect && !_closed) {
      _connected = true;
      _connection.add(true);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await drop();
    await _connection.close();
  }
}

/// Almacen de secretos en memoria.
class FakeSecureStore implements SecureStore {
  FakeSecureStore({AuthTokens? session}) {
    if (session != null) {
      _values['ibasho.session.tokens'] = jsonEncode(session.toJson());
    }
  }

  final Map<String, String> _values = <String, String>{};

  @override
  String get backendName => 'memoria';

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Preferencias que no tocan el disco.
class FakeSettingsStore implements SettingsStore {
  Preferences saved = const Preferences();

  @override
  Future<Preferences> load() async => saved;

  @override
  Future<void> save(Preferences preferences) async => saved = preferences;
}

/// Un Tama de ejemplo, de la cuenta de pruebas.
Tama sampleTama({
  String id = '-TamaMuestra00000001',
  String name = 'Tommy',
  TamaPersonality personality = TamaPersonality.playful,
  TamaLook look = const TamaLook(
    parts: {
      TamaPart.body: 0,
      TamaPart.eyes: 1,
      TamaPart.mouth: 1,
      TamaPart.crown: 1,
      TamaPart.cheeks: 1,
      TamaPart.pattern: 1,
    },
    color: '#F6A8D0',
  ),
  String creator = kAdminUid,
  String keeper = kAdminUid,
  DateTime? lastPetted,
  DateTime? lastFed,
}) {
  final now = DateTime.now();
  return Tama(
    id: id,
    creator: creator,
    keeper: keeper,
    name: name,
    personality: personality,
    look: look,
    care: TamaCare(
      lastPetted: lastPetted ?? now.subtract(const Duration(hours: 2)),
      lastFed: lastFed ?? now.subtract(const Duration(hours: 5)),
    ),
    createdAt: now.subtract(const Duration(days: 3)),
    updatedAt: now.subtract(const Duration(days: 1)),
  );
}

/// Ids de las cuentas de la escena social de prueba.
const String kMireiaUid = 'uid-mireia';
const String kLaiaUid = 'uid-laia';
const String kPauUid = 'uid-pau';

/// Codigos de amigo de la escena: los tres primeros contadores.
final String kAdminCode = FriendCode.forCounter(1);
final String kMireiaCode = FriendCode.forCounter(2);
final String kLaiaCode = FriendCode.forCounter(3);

/// Tama de perfil de mireia.
Tama mireiaTama() => sampleTama(
      id: '-TamaMireia000000001',
      name: 'Mochi',
      creator: kMireiaUid,
      keeper: kMireiaUid,
      look: const TamaLook(
        parts: {TamaPart.body: 4, TamaPart.eyes: 2, TamaPart.crown: 2, TamaPart.pattern: 2},
        color: '#9FE0C6',
      ),
    );

/// Monta la escena social sobre la base del doble:
/// - la cuenta principal y mireia son amigas desde hace 400 dias;
/// - hoy es el cumpleaños de mireia en su zona (Asia/Tokyo), y suena `noche`
///   en su perfil;
/// - laia (sin ser amiga) le ha mandado una solicitud a la cuenta principal.
void seedSocial(FakeIbashoBackend backend, {bool mireiaBirthdayToday = true}) {
  final me = backend.uid;
  final now = DateTime.now();
  final tokyo = now.toUtc().add(const Duration(hours: 9));
  final since = now.subtract(const Duration(days: 400)).millisecondsSinceEpoch;
  final tama = mireiaTama();
  String two(int n) => n.toString().padLeft(2, '0');

  backend
    ..seed('/allowlist/$kMireiaUid/mustChangePassword', false)
    ..seed('/friendCodes/$kAdminCode', me)
    ..seed('/friendCodes/$kMireiaCode', kMireiaUid)
    ..seed('/friendCodes/$kLaiaCode', kLaiaUid)
    ..seed('/system/friendCodeCounter', 4)
    ..seed('/users/$me/friendCode', kAdminCode)
    ..seed('/users/$me/card', {'displayName': 'Adrià', 'accentColor': '#5BC8F5'})
    ..seed('/users/$me/friends/$kMireiaUid', {'since': since})
    ..seed('/users/$me/friendCount', 1)
    ..seed('/users/$me/requests/in/$kLaiaUid', {'at': now.millisecondsSinceEpoch})
    ..seed('/allowlist/$kLaiaUid', AllowlistEntry(
      uid: kLaiaUid,
      accountId: kLaiaUid,
      username: 'laia',
      createdAt: DateTime(2026, 9, 13),
      createdBy: me,
      disabled: false,
      mustChangePassword: false,
      generation: 1,
    ).toJson())
    ..seed('/tamas/${tama.id}', tama.toJson())
    ..seed('/users/$kMireiaUid', {
      'profile': UserProfile(
        username: 'mireia',
        displayName: 'Mireia',
        statusMessage: 'desde Tokio',
        birthday: mireiaBirthdayToday ? '1999-${two(tokyo.month)}-${two(tokyo.day)}' : '1999-01-01',
        timezone: 'Asia/Tokyo',
        accentColor: '#EE7C96',
        createdAt: DateTime(2026, 9, 10),
      ).toJson(),
      'card': {'displayName': 'Mireia', 'accentColor': '#EE7C96', 'tamaId': tama.id},
      'tama': tama.id,
      'friendCode': kMireiaCode,
      'friends': {me: {'since': since}},
      'friendCount': 1,
      'presence': {'state': 'online', 'lastSeen': now.millisecondsSinceEpoch},
      'music': {'profileTrack': 'noche'},
    })
    ..seed('/users/$kLaiaUid', {
      'card': {'displayName': 'Laia', 'accentColor': '#B08BE0'},
      'friendCode': kLaiaCode,
      'requests': {
        'out': {me: {'at': now.millisecondsSinceEpoch}},
      },
    });
}
