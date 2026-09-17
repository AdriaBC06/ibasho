// Ibasho — el canal de mensajes: avisos, grupos y conversaciones.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/messaging.dart';
import '../backend/models.dart';
import 'identity.dart';
import 'session.dart';

/// Lo que sabe el canal sin abrir ninguna conversacion: de quien hay mensajes
/// nuevos y como esta el grupo. Son cuatro nodos minusculos y cuatro flujos,
/// no uno por amigo: el aviso de mensaje nuevo lo escribe quien manda en
/// `/users/{yo}/inbox`, y con eso basta para encender la chapa del canal.
@immutable
class MessagesState {
  const MessagesState({
    this.inbox = const <String, DateTime>{},
    this.readDirect = const <String, DateTime>{},
    this.global,
    this.globalMembers = const <GroupMember>[],
    this.globalLastAt,
    this.globalRead,
    this.inGlobal = false,
    this.loaded = false,
  });

  /// accountId → cuando llego su ultimo mensaje.
  final Map<String, DateTime> inbox;

  /// accountId → hasta cuando he leido lo suyo.
  final Map<String, DateTime> readDirect;

  final GroupInfo? global;
  final List<GroupMember> globalMembers;
  final DateTime? globalLastAt;
  final DateTime? globalRead;

  /// Si esta cuenta esta dentro del grupo. Sin estar dentro no se lee nada.
  final bool inGlobal;

  final bool loaded;

  bool unreadFrom(String accountId) {
    final last = inbox[accountId];
    if (last == null) return false;
    final read = readDirect[accountId];
    return read == null || last.isAfter(read);
  }

  bool get unreadInGlobal {
    if (!inGlobal || globalLastAt == null) return false;
    return globalRead == null || globalLastAt!.isAfter(globalRead!);
  }

  /// Cuantas conversaciones tienen algo sin leer. Es lo que pinta la chapa del
  /// icono del canal, con el mismo mecanismo que las solicitudes de amistad.
  int get unreadCount {
    var total = inbox.keys.where(unreadFrom).length;
    if (unreadInGlobal) total++;
    return total;
  }

  bool get globalFull => globalMembers.length >= maxGroupMembers;

  /// Cuando se movio por ultima vez la conversacion con alguien.
  ///
  /// Sale de lo mas reciente entre el ultimo mensaje suyo y la ultima vez que
  /// se leyo lo suyo. Lo segundo hace de rastro de lo propio: el aviso del
  /// buzon solo lo deja quien escribe, asi que sin eso una conversacion en la
  /// que solo se ha hablado no contaria como reciente.
  DateTime? activityWith(String accountId) {
    final last = inbox[accountId];
    final read = readDirect[accountId];
    if (last == null) return read;
    if (read == null) return last;
    return last.isAfter(read) ? last : read;
  }

  /// Los amigos ordenados por conversacion mas reciente. Quien no tiene nada
  /// se queda al final, en el orden en que venga.
  List<T> byRecency<T>(List<T> friends, String Function(T) accountOf) {
    final out = List<T>.of(friends);
    out.sort((a, b) {
      final x = activityWith(accountOf(a));
      final y = activityWith(accountOf(b));
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return out;
  }

  MessagesState copyWith({
    Map<String, DateTime>? inbox,
    Map<String, DateTime>? readDirect,
    GroupInfo? global,
    List<GroupMember>? globalMembers,
    DateTime? globalLastAt,
    DateTime? globalRead,
    bool? inGlobal,
    bool? loaded,
  }) =>
      MessagesState(
        inbox: inbox ?? this.inbox,
        readDirect: readDirect ?? this.readDirect,
        global: global ?? this.global,
        globalMembers: globalMembers ?? this.globalMembers,
        globalLastAt: globalLastAt ?? this.globalLastAt,
        globalRead: globalRead ?? this.globalRead,
        inGlobal: inGlobal ?? this.inGlobal,
        loaded: loaded ?? this.loaded,
      );
}

/// Por que no se ha podido entrar en un grupo.
enum JoinFailure { full, closed, noKeys, network }

class MessagesController extends StateNotifier<MessagesState> {
  MessagesController({
    required IbashoBackend backend,
    required SessionController session,
    required IdentityState identity,
  })  : _backend = backend,
        _session = session,
        _identity = identity,
        super(const MessagesState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final IdentityState _identity;

  final List<StreamSubscription<DatabaseEvent>> _watches = [];
  Object? _inboxTree;
  Object? _readsTree;
  Object? _membersTree;

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    for (final w in _watches) {
      unawaited(w.cancel());
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final results = await Future.wait([
        _backend.read('/users/$_me/inbox', idToken: token),
        _backend.read('/users/$_me/reads', idToken: token),
        _backend.read('/groups/$globalGroupId/meta', idToken: token),
        _backend.read('/users/$_me/groups', idToken: token),
      ]);
      if (!mounted) return;
      _inboxTree = results[0];
      _readsTree = results[1];
      final mine = results[3];
      final inGlobal = mine is Map && mine[globalGroupId] != null;

      state = MessagesState(
        inbox: _parseInbox(_inboxTree),
        readDirect: _parseReadsDirect(_readsTree),
        global: GroupInfo.fromJson(globalGroupId, results[2]),
        globalRead: _parseGroupRead(_readsTree),
        inGlobal: inGlobal,
        loaded: true,
      );
      if (inGlobal) await _loadMembers(token);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el canal de mensajes ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    if (!mounted) return;
    _listen();
  }

  void _listen() {
    _watches.add(
      _backend.watch('/users/$_me/inbox', token: _session.freshToken).listen((e) {
        _inboxTree = applyDatabaseEvent(_inboxTree, e);
        if (mounted) state = state.copyWith(inbox: _parseInbox(_inboxTree));
      }, onError: (Object e) => debugPrint('Ibasho: stream del buzon ($e)')),
    );

    _watches.add(
      _backend.watch('/users/$_me/reads', token: _session.freshToken).listen((e) {
        _readsTree = applyDatabaseEvent(_readsTree, e);
        if (mounted) {
          state = state.copyWith(
            readDirect: _parseReadsDirect(_readsTree),
            globalRead: _parseGroupRead(_readsTree),
          );
        }
      }, onError: (Object e) => debugPrint('Ibasho: stream de lecturas ($e)')),
    );

    // La marca del ultimo mensaje del grupo la lee cualquiera: enciende la
    // chapa sin tener que traerse la conversacion.
    _watches.add(
      _backend
          .watch('/groups/$globalGroupId/lastAt', token: _session.freshToken)
          .listen((e) {
        if (!mounted || e.path != '/' || e.data is! num) return;
        state = state.copyWith(
          globalLastAt:
              DateTime.fromMillisecondsSinceEpoch((e.data! as num).toInt()),
        );
      }, onError: (Object e) => debugPrint('Ibasho: stream del grupo ($e)')),
    );
  }

  Future<void> _loadMembers(String token) async {
    try {
      _membersTree =
          await _backend.read('/groups/$globalGroupId/members', idToken: token);
      if (!mounted) return;
      state = state.copyWith(globalMembers: _parseMembers(_membersTree));
      _watches.add(
        _backend
            .watch('/groups/$globalGroupId/members', token: _session.freshToken)
            .listen((e) {
          _membersTree = applyDatabaseEvent(_membersTree, e);
          if (mounted) {
            state = state.copyWith(globalMembers: _parseMembers(_membersTree));
          }
        }, onError: (Object e) => debugPrint('Ibasho: stream de miembros ($e)')),
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los miembros del grupo ($e)');
    }
  }

  /// Entrar en el grupo. Hasta hacerlo no se lee ni se escribe nada de el.
  ///
  /// La entrada lleva copiada la clave publica: es lo que deja mandar un
  /// mensaje al grupo con una sola lectura en vez de una por miembro.
  Future<JoinFailure?> joinGlobal() async {
    final group = state.global;
    final keys = _identity.keys;
    if (keys == null) return JoinFailure.noKeys;
    if (group == null || !group.open) return JoinFailure.closed;
    if (state.globalFull) return JoinFailure.full;

    try {
      final token = await _session.freshToken();
      await _backend.merge('/', <String, Object?>{
        'groups/$globalGroupId/members/$_me': <String, Object?>{
          'at': serverTimestamp,
          'pub': keys.public.encoded,
        },
        'users/$_me/groups/$globalGroupId': serverTimestamp,
      }, idToken: token);
      if (!mounted) return null;
      state = state.copyWith(inGlobal: true);
      await _loadMembers(token);
      return null;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido entrar en el grupo ($e)');
      return JoinFailure.network;
    }
  }

  /// Salir del grupo. Lo que ya se mando sigue ahi para los demas: esto no
  /// borra la conversacion, solo deja de verla.
  Future<bool> leaveGlobal() async {
    try {
      final token = await _session.freshToken();
      await _backend.merge('/', <String, Object?>{
        'groups/$globalGroupId/members/$_me': null,
        'users/$_me/groups/$globalGroupId': null,
      }, idToken: token);
      if (mounted) {
        state = state.copyWith(inGlobal: false, globalMembers: const []);
      }
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido salir del grupo ($e)');
      return false;
    }
  }

  /// Apunta hasta donde se ha leido. No sale del arbol propio: en Ibasho nadie
  /// ve si has leido lo suyo.
  Future<void> markRead(ConversationTarget target, DateTime at) async {
    final path = switch (target) {
      DirectTarget(:final accountId) => 'reads/dm/$accountId',
      GroupTarget(:final groupId) => 'reads/group/$groupId',
    };
    final already = switch (target) {
      DirectTarget(:final accountId) => state.readDirect[accountId],
      GroupTarget() => state.globalRead,
    };
    if (already != null && !at.isAfter(already)) return;

    try {
      final token = await _session.freshToken();
      await _backend.write(
        '/users/$_me/$path',
        at.millisecondsSinceEpoch,
        idToken: token,
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido apuntar la lectura ($e)');
    }
  }

  static Map<String, DateTime> _parseInbox(Object? raw) {
    if (raw is! Map) return const <String, DateTime>{};
    final out = <String, DateTime>{};
    for (final entry in raw.entries) {
      final parsed = InboxEntry.fromJson('${entry.key}', entry.value);
      if (parsed != null) out[parsed.accountId] = parsed.at;
    }
    return out;
  }

  static Map<String, DateTime> _parseReadsDirect(Object? raw) {
    final dm = raw is Map ? raw['dm'] : null;
    if (dm is! Map) return const <String, DateTime>{};
    return <String, DateTime>{
      for (final e in dm.entries)
        if (e.value is num)
          '${e.key}': DateTime.fromMillisecondsSinceEpoch((e.value as num).toInt()),
    };
  }

  static DateTime? _parseGroupRead(Object? raw) {
    final group = raw is Map ? raw['group'] : null;
    final value = group is Map ? group[globalGroupId] : null;
    return value is num
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
        : null;
  }

  static List<GroupMember> _parseMembers(Object? raw) {
    if (raw is! Map) return const <GroupMember>[];
    final out = <GroupMember>[];
    for (final e in raw.entries) {
      final member = GroupMember.fromJson('${e.key}', e.value);
      if (member != null) out.add(member);
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return List<GroupMember>.unmodifiable(out);
  }
}

/// Con quien se habla.
@immutable
sealed class ConversationTarget {
  const ConversationTarget();

  /// Clave estable, para la familia de providers y para las claves de widget.
  String get key;
}

@immutable
class DirectTarget extends ConversationTarget {
  const DirectTarget(this.accountId);

  final String accountId;

  @override
  String get key => 'dm:$accountId';

  @override
  bool operator ==(Object other) =>
      other is DirectTarget && other.accountId == accountId;

  @override
  int get hashCode => key.hashCode;
}

@immutable
class GroupTarget extends ConversationTarget {
  const GroupTarget(this.groupId);

  final String groupId;

  @override
  String get key => 'gr:$groupId';

  @override
  bool operator ==(Object other) =>
      other is GroupTarget && other.groupId == groupId;

  @override
  int get hashCode => key.hashCode;
}
