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
  });

  /// Los Tamas que cuida la cuenta, del mas antiguo al mas nuevo.
  final List<Tama> tamas;

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

  bool get full => tamas.length >= maxTamasPerAccount;

  TamasState copyWith({
    List<Tama>? tamas,
    String? profileTamaId,
    bool clearProfile = false,
    bool? loaded,
  }) =>
      TamasState(
        tamas: tamas ?? this.tamas,
        profileTamaId: clearProfile ? null : (profileTamaId ?? this.profileTamaId),
        loaded: loaded ?? this.loaded,
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
  })  : _backend = backend,
        _session = session,
        _cardOf = cardOf,
        super(const TamasState()) {
    unawaited(_start());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  /// La ficha publica apunta al Tama de perfil: cualquier escritura que lo
  /// cambie la lleva en la misma operacion, o las reglas la rechazan.
  final Future<UserCard> Function(String? tamaId, String? tamaColor) _cardOf;

  StreamSubscription<DatabaseEvent>? _listWatch;
  StreamSubscription<DatabaseEvent>? _profileWatch;
  Object? _tree;

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

  /// Un mimo. La marca solo se escribe si ha pasado un rato desde la ultima.
  Future<void> pet(String id) => _care(id, 'lastPetted', _lastPetWrite, petWriteGap,
      (care, at) => care.copyWith(lastPetted: at));

  /// Una chuche.
  Future<void> feed(String id) => _care(id, 'lastFed', _lastFeedWrite, feedWriteGap,
      (care, at) => care.copyWith(lastFed: at));

  Future<void> _care(
    String id,
    String field,
    Map<String, DateTime> last,
    Duration gap,
    TamaCare Function(TamaCare, DateTime) apply,
  ) async {
    final tama = state.byId(id);
    if (tama == null) return;
    final now = DateTime.now();
    final previous = last[id];
    // El humor se ve cambiar al momento aunque no se escriba nada.
    _putLocal(tama.copyWith(care: apply(tama.care, now)));
    if (previous != null && now.difference(previous) < gap) return;
    last[id] = now;
    try {
      await _backend.write('/tamas/$id/care/$field', serverTimestamp,
          idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar el cuidado ($e)');
      last.remove(id);
    }
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
}
