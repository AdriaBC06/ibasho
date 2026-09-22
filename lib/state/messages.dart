// Ibasho — el canal de mensajes: avisos y conversaciones.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/messaging.dart';
import '../backend/models.dart';
import 'session.dart';

/// Lo que sabe el canal sin abrir ninguna conversacion: de quien hay mensajes
/// nuevos. Son dos nodos minusculos y dos flujos, no uno por amigo: el aviso
/// de mensaje nuevo lo escribe quien manda en `/users/{yo}/inbox`, y con eso
/// basta para encender la chapa del canal.
@immutable
class MessagesState {
  const MessagesState({
    this.inbox = const <String, DateTime>{},
    this.readDirect = const <String, DateTime>{},
    this.loaded = false,
  });

  /// accountId → cuando llego su ultimo mensaje.
  final Map<String, DateTime> inbox;

  /// accountId → hasta cuando he leido lo suyo.
  final Map<String, DateTime> readDirect;

  final bool loaded;

  bool unreadFrom(String accountId) {
    final last = inbox[accountId];
    if (last == null) return false;
    final read = readDirect[accountId];
    return read == null || last.isAfter(read);
  }

  /// Cuantas conversaciones tienen algo sin leer. Es lo que pinta la chapa del
  /// icono del canal, con el mismo mecanismo que las solicitudes de amistad.
  int get unreadCount => inbox.keys.where(unreadFrom).length;

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
    bool? loaded,
  }) =>
      MessagesState(
        inbox: inbox ?? this.inbox,
        readDirect: readDirect ?? this.readDirect,
        loaded: loaded ?? this.loaded,
      );
}

class MessagesController extends StateNotifier<MessagesState> {
  MessagesController({
    required IbashoBackend backend,
    required SessionController session,
  })  : _backend = backend,
        _session = session,
        super(const MessagesState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;

  final List<StreamSubscription<DatabaseEvent>> _watches = [];
  Object? _inboxTree;
  Object? _readsTree;

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
      ]);
      if (!mounted) return;
      _inboxTree = results[0];
      _readsTree = results[1];

      state = MessagesState(
        inbox: _parseInbox(_inboxTree),
        readDirect: _parseReadsDirect(_readsTree),
        loaded: true,
      );
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
          state = state.copyWith(readDirect: _parseReadsDirect(_readsTree));
        }
      }, onError: (Object e) => debugPrint('Ibasho: stream de lecturas ($e)')),
    );
  }

  /// Apunta hasta donde se ha leido. No sale del arbol propio: en Ibasho nadie
  /// ve si has leido lo suyo.
  Future<void> markRead(ConversationTarget target, DateTime at) async {
    final accountId = switch (target) {
      DirectTarget(:final accountId) => accountId,
    };
    final path = 'reads/dm/$accountId';
    final already = state.readDirect[accountId];
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

