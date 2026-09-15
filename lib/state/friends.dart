// Ibasho — amigos, solicitudes y busqueda por codigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/errors.dart';
import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart';
import '../backend/social.dart';
import '../core/friend_code.dart';
import 'session.dart';

@immutable
class FriendsState {
  const FriendsState({
    this.code,
    this.friends = const <Friendship>[],
    this.incoming = const <FriendRequest>[],
    this.outgoing = const <FriendRequest>[],
    this.loaded = false,
  });

  /// Codigo de amigo propio, sin guiones. `null` hasta que el admin lo da.
  final String? code;

  /// De la amistad mas antigua a la mas nueva.
  final List<Friendship> friends;

  /// Solicitudes recibidas y mandadas, de la mas nueva a la mas antigua.
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;

  final bool loaded;

  bool get full => friends.length >= maxFriendsPerAccount;

  Friendship? friendship(String account) {
    for (final f in friends) {
      if (f.accountId == account) return f;
    }
    return null;
  }

  bool isFriend(String account) => friendship(account) != null;

  bool hasIncoming(String account) => incoming.any((r) => r.accountId == account);

  bool hasOutgoing(String account) => outgoing.any((r) => r.accountId == account);

  FriendsState copyWith({
    String? code,
    List<Friendship>? friends,
    List<FriendRequest>? incoming,
    List<FriendRequest>? outgoing,
    bool? loaded,
  }) =>
      FriendsState(
        code: code ?? this.code,
        friends: friends ?? this.friends,
        incoming: incoming ?? this.incoming,
        outgoing: outgoing ?? this.outgoing,
        loaded: loaded ?? this.loaded,
      );
}

/// Resultado de buscar un codigo.
enum LookupOutcome {
  /// El digito de control no cuadra: esta mal tecleado. No se ha tocado la red.
  invalid,

  /// Esta bien escrito, pero nadie tiene ese codigo.
  notFound,

  /// Es el codigo propio.
  self,

  /// Hay alguien.
  found,

  /// Sin conexion con el servidor.
  network,
}

/// Relacion con la persona encontrada.
enum FriendRelation { none, friend, requested, requestedYou }

@immutable
class FriendLookup {
  const FriendLookup(this.outcome, {this.accountId, this.card, this.relation = FriendRelation.none});

  final LookupOutcome outcome;
  final String? accountId;

  /// La ficha reducida: nombre, Tama de perfil y color. Puede faltar si esa
  /// cuenta aun no ha entrado desde que existen las fichas.
  final UserCard? card;

  final FriendRelation relation;
}

/// Por que no ha salido una accion.
enum FriendFailure { yourListFull, theirListFull, rejected, network }

/// Amigos y solicitudes de la cuenta en curso.
///
/// Todas las operaciones son una sola escritura multi-ruta que las reglas
/// validan entera: mandar crea las dos mitades de la solicitud, aceptar crea
/// las dos entradas de amistad, mueve los dos contadores y borra las
/// solicitudes, y dejar de ser amigos lo deshace.
class FriendsController extends StateNotifier<FriendsState> {
  FriendsController({required IbashoBackend backend, required SessionController session})
      : _backend = backend,
        _session = session,
        super(const FriendsState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) unawaited(_start());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  StreamSubscription<DatabaseEvent>? _friendsWatch;
  StreamSubscription<DatabaseEvent>? _requestsWatch;
  StreamSubscription<DatabaseEvent>? _codeWatch;
  Object? _friendsTree;
  Object? _requestsTree;

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    unawaited(_friendsWatch?.cancel());
    unawaited(_requestsWatch?.cancel());
    unawaited(_codeWatch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final results = await Future.wait([
        _backend.read('/users/$_me/friendCode', idToken: token),
        _backend.read('/users/$_me/friends', idToken: token),
        _backend.read('/users/$_me/requests', idToken: token),
      ]);
      if (!mounted) return;
      _friendsTree = results[1];
      _requestsTree = results[2];
      state = FriendsState(
        code: results[0] is String ? results[0] as String : null,
        friends: parseFriends(_friendsTree),
        incoming: parseRequests(_requestsIn),
        outgoing: parseRequests(_requestsOut),
        loaded: true,
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los amigos ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    if (!mounted) return;

    _friendsWatch = _backend.watch('/users/$_me/friends', token: _session.freshToken).listen((e) {
      _friendsTree = applyDatabaseEvent(_friendsTree, e);
      if (mounted) state = state.copyWith(friends: parseFriends(_friendsTree), loaded: true);
    }, onError: (Object e) => debugPrint('Ibasho: stream de amigos ($e)'));

    _requestsWatch =
        _backend.watch('/users/$_me/requests', token: _session.freshToken).listen((e) {
      _requestsTree = applyDatabaseEvent(_requestsTree, e);
      if (mounted) {
        state = state.copyWith(
          incoming: parseRequests(_requestsIn),
          outgoing: parseRequests(_requestsOut),
        );
      }
    }, onError: (Object e) => debugPrint('Ibasho: stream de solicitudes ($e)'));

    // El codigo llega a las cuentas antiguas cuando el admin lo reparte.
    if (state.code == null) {
      _codeWatch =
          _backend.watch('/users/$_me/friendCode', token: _session.freshToken).listen((e) {
        if (mounted && e.path == '/' && e.data is String) {
          state = state.copyWith(code: e.data! as String);
        }
      }, onError: (Object e) => debugPrint('Ibasho: stream del codigo ($e)'));
    }
  }

  Object? get _requestsIn => _requestsTree is Map ? (_requestsTree! as Map)['in'] : null;

  Object? get _requestsOut => _requestsTree is Map ? (_requestsTree! as Map)['out'] : null;

  /// Busca a quien tiene un codigo.
  ///
  /// Un codigo mal tecleado se rechaza aqui mismo, antes de cualquier
  /// peticion: "no es valido" y "no existe" son cosas distintas.
  Future<FriendLookup> lookup(String input) async {
    final digits = FriendCode.normalize(input);
    if (digits == null || !FriendCode.isValid(digits)) {
      return const FriendLookup(LookupOutcome.invalid);
    }
    if (digits == state.code) return const FriendLookup(LookupOutcome.self);
    try {
      final token = await _session.freshToken();
      final account = await _backend.read('/friendCodes/$digits', idToken: token);
      if (account is! String) return const FriendLookup(LookupOutcome.notFound);
      if (account == _me) return const FriendLookup(LookupOutcome.self);
      final card = UserCard.fromJson(await _backend.read('/users/$account/card', idToken: token));
      return FriendLookup(
        LookupOutcome.found,
        accountId: account,
        card: card,
        relation: relationWith(account),
      );
    } on IbashoException catch (e) {
      debugPrint('Ibasho: busqueda de codigo fallida ($e)');
      return FriendLookup(
        e.failure == IbashoFailure.network ? LookupOutcome.network : LookupOutcome.notFound,
      );
    }
  }

  FriendRelation relationWith(String account) {
    if (state.isFriend(account)) return FriendRelation.friend;
    if (state.hasIncoming(account)) return FriendRelation.requestedYou;
    if (state.hasOutgoing(account)) return FriendRelation.requested;
    return FriendRelation.none;
  }

  /// Manda una solicitud. Si esa persona ya te habia mandado una, os hace
  /// amigos directamente.
  Future<FriendFailure?> sendRequest(String account) async {
    if (account == _me || state.isFriend(account)) return null;
    if (state.hasIncoming(account)) return accept(account);
    if (state.full) return FriendFailure.yourListFull;
    try {
      final token = await _session.freshToken();
      await _backend.merge('/', {
        'users/$_me/requests/out/$account': {'at': serverTimestamp},
        'users/$account/requests/in/$_me': {'at': serverTimestamp},
      }, idToken: token);
      return null;
    } on IbashoException catch (e) {
      if (e.failure == IbashoFailure.network) return FriendFailure.network;
      // Puede que se hayan cruzado: la suya ha llegado mientras tanto.
      try {
        final incoming = await _backend.read('/users/$_me/requests/in/$account',
            idToken: await _session.freshToken());
        if (incoming != null) return accept(account);
      } catch (_) {}
      debugPrint('Ibasho: solicitud rechazada ($e)');
      return FriendFailure.rejected;
    }
  }

  Future<int> _count(String account, String token) async {
    final raw = await _backend.read('/users/$account/friendCount', idToken: token);
    return raw is num ? raw.toInt() : 0;
  }

  /// Acepta la solicitud de `account`.
  Future<FriendFailure?> accept(String account) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await _session.freshToken();
        final counts = await Future.wait([_count(_me, token), _count(account, token)]);
        if (counts[0] >= maxFriendsPerAccount) return FriendFailure.yourListFull;
        if (counts[1] >= maxFriendsPerAccount) return FriendFailure.theirListFull;
        await _backend.merge('/', {
          'users/$_me/friends/$account': {'since': serverTimestamp},
          'users/$account/friends/$_me': {'since': serverTimestamp},
          'users/$_me/friendCount': counts[0] + 1,
          'users/$_me/friendLastChange': account,
          'users/$account/friendCount': counts[1] + 1,
          'users/$account/friendLastChange': _me,
          'users/$_me/requests/in/$account': null,
          'users/$account/requests/out/$_me': null,
          'users/$_me/requests/out/$account': null,
          'users/$account/requests/in/$_me': null,
        }, idToken: token);
        return null;
      } on IbashoException catch (e) {
        debugPrint('Ibasho: no se ha podido aceptar ($e)');
        if (e.failure == IbashoFailure.network) return FriendFailure.network;
      }
    }
    return FriendFailure.rejected;
  }

  /// Rechaza sin dejar rastro ni avisar.
  Future<FriendFailure?> reject(String account) => _drop({
        'users/$_me/requests/in/$account': null,
        'users/$account/requests/out/$_me': null,
      });

  /// Retira una solicitud mandada.
  Future<FriendFailure?> cancel(String account) => _drop({
        'users/$_me/requests/out/$account': null,
        'users/$account/requests/in/$_me': null,
      });

  Future<FriendFailure?> _drop(Map<String, Object?> paths) async {
    try {
      await _backend.merge('/', paths, idToken: await _session.freshToken());
      return null;
    } on IbashoException catch (e) {
      debugPrint('Ibasho: no se ha podido retirar la solicitud ($e)');
      return e.failure == IbashoFailure.network ? FriendFailure.network : FriendFailure.rejected;
    }
  }

  /// Deja de ser amigo de `account`. Borra las dos entradas y baja los dos
  /// contadores.
  Future<FriendFailure?> unfriend(String account) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await _session.freshToken();
        final counts = await Future.wait([_count(_me, token), _count(account, token)]);
        await _backend.merge('/', {
          'users/$_me/friends/$account': null,
          'users/$account/friends/$_me': null,
          'users/$_me/friendCount': counts[0] - 1,
          'users/$_me/friendLastChange': account,
          'users/$account/friendCount': counts[1] - 1,
          'users/$account/friendLastChange': _me,
        }, idToken: token);
        return null;
      } on IbashoException catch (e) {
        debugPrint('Ibasho: no se ha podido dejar de ser amigos ($e)');
        if (e.failure == IbashoFailure.network) return FriendFailure.network;
      }
    }
    return FriendFailure.rejected;
  }

  /// Deja un mensaje en el muro de un amigo, en el año que toca en su zona.
  Future<bool> postOnWall(String account, int year, String text) async {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > wallMessageMax) return false;
    try {
      await _backend.write(
        '/users/$account/wall/$year/$_me',
        {'text': clean, 'at': serverTimestamp},
        idToken: await _session.freshToken(),
      );
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido dejar el mensaje ($e)');
      return false;
    }
  }

  /// Borra un mensaje del muro propio.
  Future<bool> deleteFromWall(int year, String author) async {
    try {
      await _backend.remove('/users/$_me/wall/$year/$author',
          idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido borrar el mensaje ($e)');
      return false;
    }
  }
}
