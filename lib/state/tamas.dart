// Ibasho — los Tamas de la cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/errors.dart';
import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart';
import '../backend/koen.dart';
import '../backend/push_id.dart';
import '../backend/social.dart';
import '../backend/tama.dart';
import 'session.dart';

@immutable
class TamasState {
  const TamasState({
    this.tamas = const <Tama>[],
    this.profileTamaId,
    this.loaded = false,
    this.cared = const <Tama>[],
  });

  /// Los Tamas que cuida la cuenta, del mas antiguo al mas nuevo.
  final List<Tama> tamas;

  /// Los Tamas de amigos que la cuenta cuida a medias (Tama Kōen). No cuentan
  /// para el tope ni pueden ir al perfil.
  final List<Tama> cared;

  /// El que se ensena en el panel superior y en el perfil.
  final String? profileTamaId;

  final bool loaded;

  Tama? byId(String? id) {
    if (id == null) return null;
    for (final tama in tamas) {
      if (tama.id == id) return tama;
    }
    return null;
  }

  Tama? get profileTama => byId(profileTamaId);

  /// Uno propio o uno que se cuida a medias.
  Tama? find(String? id) {
    if (id == null) return null;
    return byId(id) ?? cared.where((t) => t.id == id).firstOrNull;
  }

  /// Los que pueden acompañar en los minijuegos: los propios y los que se
  /// cuidan a medias.
  List<Tama> get companions => cared.isEmpty ? tamas : [...tamas, ...cared];

  /// Si la cuenta cuida a medias algún Tama con [friend], en un sentido u
  /// otro.
  bool sharesWith(String friend) =>
      tamas.any((t) => t.carer == friend) || cared.any((t) => t.creator == friend);

  bool get full => tamas.length >= maxTamasPerAccount;

  TamasState copyWith({
    List<Tama>? tamas,
    String? profileTamaId,
    bool clearProfile = false,
    bool? loaded,
    List<Tama>? cared,
  }) =>
      TamasState(
        tamas: tamas ?? this.tamas,
        profileTamaId: clearProfile ? null : (profileTamaId ?? this.profileTamaId),
        loaded: loaded ?? this.loaded,
        cared: cared ?? this.cared,
      );
}

/// Por que no se ha podido crear un Tama.
enum TamaCreateFailure { full, invalidName, rejected, network }

/// Los Tamas de la cuenta en curso.
///
/// La lista llega por la consulta de "Tamas que cuido" y se sigue en tiempo
/// real, asi que una edicion hecha en otro equipo aparece aqui en cuanto el
/// servidor la acepta. El humor no se guarda nunca: lo calcula quien lo pinta.
class TamasController extends StateNotifier<TamasState> {
  TamasController({
    required IbashoBackend backend,
    required SessionController session,
    required Future<UserCard> Function(String? tamaId, String? tamaColor) cardOf,
    required Future<bool> Function(TamaFood food) consumeFood,
  })  : _backend = backend,
        _session = session,
        _cardOf = cardOf,
        _consumeFood = consumeFood,
        super(const TamasState()) {
    unawaited(_start());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  /// La ficha publica apunta al Tama de perfil: cualquier escritura que lo
  /// cambie la lleva en la misma operacion, o las reglas la rechazan.
  final Future<UserCard> Function(String? tamaId, String? tamaColor) _cardOf;

  /// Gasta una unidad de la despensa. `false` si no quedaba ninguna.
  final Future<bool> Function(TamaFood food) _consumeFood;

  StreamSubscription<DatabaseEvent>? _listWatch;
  StreamSubscription<DatabaseEvent>? _profileWatch;
  StreamSubscription<DatabaseEvent>? _caringWatch;
  Object? _tree;

  /// `koen/caring`: los Tamas que se cuidan a medias, con su creador.
  Object? _caring;

  /// Ultima escritura de cada cuidado por Tama. Mimar frotando dispara muchos
  /// gestos seguidos; al servidor le basta con uno de vez en cuando.
  final Map<String, DateTime> _lastPetWrite = <String, DateTime>{};
  final Map<String, DateTime> _lastFeedWrite = <String, DateTime>{};
  static const Duration petWriteGap = Duration(seconds: 30);
  static const Duration feedWriteGap = Duration(seconds: 5);

  String get _account => _session.state.accountId;

  DatabaseQuery get _mine =>
      DatabaseQuery(orderByChild: 'keeper', equalTo: _account);

  @override
  void dispose() {
    unawaited(_listWatch?.cancel());
    unawaited(_profileWatch?.cancel());
    unawaited(_caringWatch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    if (_account.isEmpty || _session.state.tokens == null) return;
    try {
      final token = await _session.freshToken();
      final results = await Future.wait([
        _backend.read('/tamas', idToken: token, query: _mine),
        _backend.read('/users/$_account/tama', idToken: token),
      ]);
      if (!mounted) return;
      _tree = results[0];
      final pointer = results[1];
      state = TamasState(
        tamas: _parse(_tree),
        profileTamaId: pointer is String ? pointer : null,
        loaded: true,
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los Tamas ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    if (!mounted) return;

    _listWatch = _backend
        .watch('/tamas', token: _session.freshToken, query: _mine)
        .listen((event) {
      _tree = applyDatabaseEvent(_tree, event);
      if (mounted) state = state.copyWith(tamas: _parse(_tree), loaded: true);
    }, onError: (Object e) => debugPrint('Ibasho: stream de Tamas ($e)'));

    _profileWatch = _backend
        .watch('/users/$_account/tama', token: _session.freshToken)
        .listen((event) {
      if (!mounted || event.path != '/') return;
      final id = event.data;
      state = id is String
          ? state.copyWith(profileTamaId: id)
          : state.copyWith(clearProfile: true);
    }, onError: (Object e) => debugPrint('Ibasho: stream del Tama de perfil ($e)'));

    // Sale de la conexion de la cuenta: no abre otra.
    _caringWatch = _backend
        .watch('/users/$_account/koen/caring', token: _session.freshToken)
        .listen((event) {
      _caring = applyDatabaseEvent(_caring, event);
      unawaited(refreshCared());
    }, onError: (Object e) => debugPrint('Ibasho: stream de los cuidados a medias ($e)'));
  }

  /// Vuelve a leer los Tamas que se cuidan a medias. No se siguen en vivo
  /// (cada uno seria una conexion): se leen al cambiar la lista y al abrir el
  /// parque o la habitacion. Los que ya no se pueden leer o ya no tienen a la
  /// cuenta de cuidadora se quitan de la lista.
  Future<void> refreshCared() async {
    final ids = _caring is Map ? [for (final k in (_caring! as Map).keys) '$k'] : const <String>[];
    final demo = state.cared.where((t) => _isDemo(t.id)).toList();
    if (ids.isEmpty) {
      if (mounted && state.cared.length != demo.length) state = state.copyWith(cared: demo);
      return;
    }
    try {
      final token = await _session.freshToken();
      final raws = await Future.wait([
        for (final id in ids)
          _backend.read('/tamas/$id', idToken: token).then<Object?>((v) => v, onError: (Object _) => null),
      ]);
      if (!mounted) return;
      final cared = <Tama>[...demo];
      final gone = <String, Object?>{};
      for (var i = 0; i < ids.length; i++) {
        final raw = raws[i];
        final tama = raw is Map ? Tama.fromJson(ids[i], raw) : null;
        if (tama != null && tama.carer == _account) {
          cared.add(tama);
        } else {
          gone[ids[i]] = null;
        }
      }
      cared.sort((a, b) => a.id.compareTo(b.id));
      state = state.copyWith(cared: List<Tama>.unmodifiable(cared));
      if (gone.isNotEmpty) {
        await _backend.merge('/users/$_account/koen/caring', gone, idToken: token);
      }
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los Tamas a medias ($e)');
    }
  }

  static List<Tama> _parse(Object? tree) {
    if (tree is! Map) return const <Tama>[];
    final list = <Tama>[
      for (final entry in tree.entries)
        if (entry.value is Map) Tama.fromJson('${entry.key}', entry.value as Map),
    ]..sort((a, b) => a.id.compareTo(b.id));
    return List<Tama>.unmodifiable(list);
  }

  /// Aplica un cambio en local sin esperar al servidor. Tambien va al arbol,
  /// para que el siguiente evento del stream no lo deshaga antes de tiempo.
  void _putLocal(Tama tama) {
    if (state.byId(tama.id) == null && state.cared.any((t) => t.id == tama.id)) {
      state = state.copyWith(cared: [for (final t in state.cared) t.id == tama.id ? tama : t]);
      return;
    }
    _tree = applyDatabaseEvent(
      _tree,
      DatabaseEvent(path: '/${tama.id}', data: tama.toJson(), isPatch: false),
    );
    state = state.copyWith(tamas: _parse(_tree));
  }

  Future<int> _currentCount(String token) async {
    final raw = await _backend.read('/users/$_account/tamaCount', idToken: token);
    return raw is num ? raw.toInt() : 0;
  }

  /// Crea un Tama. Devuelve su id, o el motivo por el que no se ha podido.
  ///
  /// El Tama, el contador y el marcador del cambio van en una sola escritura
  /// multi-ruta: es lo que exigen las reglas para aplicar el tope de 99. Si la
  /// cuenta aun no tiene Tama de perfil, este pasa a serlo en la misma
  /// operacion.
  Future<(String?, TamaCreateFailure?)> create({
    required String name,
    required TamaPersonality personality,
    required TamaVoice voice,
    required TamaLook look,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > tamaNameMax) {
      return (null, TamaCreateFailure.invalidName);
    }
    if (state.full) return (null, TamaCreateFailure.full);

    final id = generatePushId();
    final now = DateTime.now();
    final draft = Tama(
      id: id,
      creator: _account,
      keeper: _account,
      name: clean,
      personality: personality,
      voice: voice,
      look: look,
      createdAt: now,
      updatedAt: now,
    );
    final becomesProfile = state.profileTamaId == null;

    // Dos intentos: si otro equipo ha creado un Tama a la vez, el contador
    // leido ya no vale y las reglas rechazan el primero.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await _session.freshToken();
        final count = await _currentCount(token);
        if (count >= maxTamasPerAccount) return (null, TamaCreateFailure.full);
        await _backend.merge('/', {
          'tamas/$id': {
            'schema': tamaSchema,
            'creator': _account,
            'keeper': _account,
            ...draft.identityJson(),
            'createdAt': serverTimestamp,
            'updatedAt': serverTimestamp,
          },
          'users/$_account/tamaCount': count + 1,
          'users/$_account/tamaLastChange': id,
          if (becomesProfile) 'users/$_account/tama': id,
          if (becomesProfile)
            'users/$_account/card': (await _cardOf(id, look.color)).toJson(),
        }, idToken: token);
        if (!mounted) return (id, null);
        _putLocal(draft);
        if (becomesProfile) state = state.copyWith(profileTamaId: id);
        return (id, null);
      } on IbashoException catch (e) {
        debugPrint('Ibasho: no se ha podido crear el Tama ($e)');
        if (e.failure == IbashoFailure.network) {
          return (null, TamaCreateFailure.network);
        }
        if (attempt == 1) return (null, TamaCreateFailure.rejected);
      }
    }
    return (null, TamaCreateFailure.rejected);
  }

  /// Guarda nombre, personalidad, voz y aspecto. Solo lo acepta el servidor si
  /// la cuenta es la creadora.
  Future<bool> saveIdentity(Tama tama) async {
    final previous = state.byId(tama.id);
    try {
      await _backend.merge('/tamas/${tama.id}', {
        ...tama.identityJson(),
        'updatedAt': serverTimestamp,
      }, idToken: await _session.freshToken());
      if (mounted) _putLocal(tama.copyWith(updatedAt: DateTime.now()));
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar el Tama ($e)');
      if (mounted && previous != null) _putLocal(previous);
      return false;
    }
  }

  /// Un mimo. La marca solo se escribe si ha pasado un rato desde la ultima;
  /// `true` si se ha escrito (es lo que cuenta para las misiones).
  Future<bool> pet(String id) => _care(id, 'lastPetted', _lastPetWrite, petWriteGap,
      (care, at) => care.copyWith(lastPetted: at));

  /// Una chuche. Gasta primero una unidad de esa comida en la despensa; si no
  /// quedaba ninguna, no se llega a dar de comer y devuelve `false`.
  Future<bool> feed(String id, TamaFood food) async {
    // Los del parque de prueba no gastan la despensa de verdad.
    if (!_isDemo(id) && !await _consumeFood(food)) return false;
    await _care(id, 'lastFed', _lastFeedWrite, feedWriteGap,
        (care, at) => care.copyWith(lastFed: at));
    return true;
  }

  /// Una comida hecha en Hatarakitama: cuenta como comer, pero no sale de
  /// la despensa (la ha gastado el almacén del juego).
  Future<bool> feedMeal(String id) => _care(id, 'lastFed', _lastFeedWrite, feedWriteGap,
      (care, at) => care.copyWith(lastFed: at));

  Future<bool> _care(
    String id,
    String field,
    Map<String, DateTime> last,
    Duration gap,
    TamaCare Function(TamaCare, DateTime) apply,
  ) async {
    final tama = state.find(id);
    if (tama == null) return false;
    final now = DateTime.now();
    final previous = last[id];
    // El humor se ve cambiar al momento aunque no se escriba nada.
    _putLocal(tama.copyWith(care: apply(tama.care, now)));
    if (_isDemo(id) || (previous != null && now.difference(previous) < gap)) return false;
    last[id] = now;
    try {
      await _backend.write('/tamas/$id/care/$field', serverTimestamp,
          idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar el cuidado ($e)');
      last.remove(id);
      return false;
    }
    return true;
  }

  /// Pone un Tama en el perfil.
  Future<bool> setProfile(String id) async {
    if (state.byId(id) == null) return false;
    final before = state.profileTamaId;
    state = state.copyWith(profileTamaId: id);
    try {
      final card = await _cardOf(id, state.byId(id)?.look.color);
      await _backend.merge('/users/$_account', {
        'tama': id,
        'card': card.toJson(),
      }, idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cambiar el Tama de perfil ($e)');
      if (mounted) {
        state = before == null
            ? state.copyWith(clearProfile: true)
            : state.copyWith(profileTamaId: before);
      }
      return false;
    }
  }

  /// Borra un Tama. Si era el de perfil, el perfil pasa al mas antiguo que
  /// quede, en la misma operacion.
  Future<bool> delete(String id) async {
    final tama = state.byId(id);
    if (tama == null || !tama.createdBy(_account)) return false;
    final wasProfile = state.profileTamaId == id;
    final successor = wasProfile
        ? state.tamas.where((t) => t.id != id).firstOrNull?.id
        : state.profileTamaId;
    try {
      final token = await _session.freshToken();
      final count = await _currentCount(token);
      await _backend.merge('/', {
        'tamas/$id': null,
        'users/$_account/tamaCount': count - 1,
        'users/$_account/tamaLastChange': id,
        if (wasProfile) 'users/$_account/tama': successor,
        if (wasProfile)
          'users/$_account/card':
              (await _cardOf(successor, state.byId(successor)?.look.color)).toJson(),
      }, idToken: token);
      if (!mounted) return true;
      _tree = applyDatabaseEvent(
          _tree, DatabaseEvent(path: '/$id', data: null, isPatch: false));
      state = TamasState(
        tamas: _parse(_tree),
        profileTamaId: successor,
        loaded: true,
      );
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido borrar el Tama ($e)');
      return false;
    }
  }

  // --- Cuidar a medias (Tama Kōen) -------------------------------------------------

  /// Los Tamas inventados del parque de prueba (`-demo…`): no se escriben.
  static bool _isDemo(String id) => id.startsWith('-demo');

  /// Solo para probar en una build de depuración: [tama] (de un amigo
  /// inventado) pasa a cuidarse a medias, sin escribir nada.
  void debugCare(Tama tama) {
    if (state.cared.any((t) => t.id == tama.id)) return;
    state = state.copyWith(cared: [...state.cared, tama]);
  }

  /// Ofrece a [friend] cuidar a medias [tama]: le deja la ficha del Tama en
  /// su buzon (`koenInbox/{yo}`), que pisa la oferta anterior si la habia.
  Future<bool> offerCare(Tama tama, String friend) async {
    if (!tama.createdBy(_account) || tama.shared) return false;
    final card = KoenCard.ofTama(tama, holder: _account, slot: 0, at: 0).toJson()..['at'] = serverTimestamp;
    try {
      await _backend.write('/users/$friend/koenInbox/$_account', card, idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido mandar la oferta de cuidar a medias ($e)');
      return false;
    }
  }

  /// Acepta la oferta de [from]: la cuenta pasa a ser la cuidadora de
  /// [tamaId]. La oferta se borra en la misma escritura, y el Tama se apunta
  /// en `koen/caring` para encontrarlo.
  Future<bool> acceptCare(String from, String tamaId) async {
    try {
      await _backend.merge('/', {
        'tamas/$tamaId/carer': _account,
        'users/$_account/koenInbox/$from': null,
        'users/$_account/koen/caring/$tamaId': from,
      }, idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido aceptar la oferta de cuidar a medias ($e)');
      return false;
    }
  }

  /// Rechaza (o tira) la oferta de [from].
  Future<bool> declineCare(String from) async {
    try {
      await _backend.remove('/users/$_account/koenInbox/$from', idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido rechazar la oferta ($e)');
      return false;
    }
  }

  /// Deja de cuidar [tama] a medias. Lo puede hacer cualquiera de los dos.
  Future<bool> endCare(Tama tama) async {
    final mine = tama.createdBy(_account);
    if (!mine && tama.carer != _account) return false;
    if (_isDemo(tama.id)) {
      state = state.copyWith(cared: [...state.cared.where((t) => t.id != tama.id)]);
      return true;
    }
    try {
      await _backend.merge('/', {
        'tamas/${tama.id}/carer': null,
        if (!mine) 'users/$_account/koen/caring/${tama.id}': null,
      }, idToken: await _session.freshToken());
      if (!mounted) return true;
      if (mine) {
        _putLocal(tama.copyWith(clearCarer: true));
      } else {
        state = state.copyWith(cared: [...state.cared.where((t) => t.id != tama.id)]);
      }
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido dejar de cuidar a medias ($e)');
      return false;
    }
  }

  /// Lo que hay que borrar al dejar de ser amigo de [friend]: los cuidados a
  /// medias con el, en los dos sentidos. Va en la misma escritura.
  Map<String, Object?> unsharePaths(String friend) => {
    for (final t in state.tamas)
      if (t.carer == friend) 'tamas/${t.id}/carer': null,
    for (final t in state.cared)
      if (t.creator == friend) ...{
        'tamas/${t.id}/carer': null,
        'users/$_account/koen/caring/${t.id}': null,
      },
  };

  /// Al abrir: quita los cuidados a medias con quien ya no es amigo (si lo
  /// dejaron desde el otro lado, las reglas ya le han cerrado el acceso).
  Future<void> tidyShares(Set<String> friends) async {
    Map<String, Object?> stale(Set<String> friends) => {
      for (final t in state.tamas)
        if (t.carer != null && !friends.contains(t.carer)) 'tamas/${t.id}/carer': null,
      for (final t in state.cared)
        if (!_isDemo(t.id) && !friends.contains(t.creator)) ...{
          'tamas/${t.id}/carer': null,
          'users/$_account/koen/caring/${t.id}': null,
        },
    };
    if (stale(friends).isEmpty) return;
    try {
      // Antes de quitar nada, la lista de amigos de verdad: la de memoria
      // puede haber salido vacia por no tener red.
      final token = await _session.freshToken();
      final raw = await _backend.read('/users/$_account/friends', idToken: token);
      final patch = stale({if (raw is Map) for (final k in raw.keys) '$k'});
      if (patch.isEmpty || !mounted) return;
      await _backend.merge('/', patch, idToken: token);
    } catch (e) {
      debugPrint('Ibasho: no se han podido limpiar los cuidados a medias ($e)');
    }
  }
}
