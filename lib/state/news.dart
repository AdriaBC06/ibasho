// Ibasho — el canal de noticias y el recuento de las encuestas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart';
import '../backend/news.dart';
import '../backend/push_id.dart';
import 'session.dart';

@immutable
class NewsState {
  const NewsState({
    this.items = const <NewsItem>[],
    this.myVotes = const <String, int>{},
    this.lastRead,
    this.loaded = false,
  });

  /// De la mas nueva a la mas vieja.
  final List<NewsItem> items;

  /// Que he votado en cada encuesta. Sale de mi arbol, no del de la encuesta:
  /// ahi no esta y por eso el voto es anonimo.
  final Map<String, int> myVotes;

  final DateTime? lastRead;
  final bool loaded;

  /// Entradas nuevas desde la ultima visita. Es lo que enciende la chapa.
  int get unreadCount {
    final read = lastRead;
    if (read == null) return items.length;
    return items.where((i) => i.at.isAfter(read)).length;
  }

  int? voteOn(String newsId) => myVotes[newsId];

  NewsState copyWith({
    List<NewsItem>? items,
    Map<String, int>? myVotes,
    DateTime? lastRead,
    bool? loaded,
  }) =>
      NewsState(
        items: items ?? this.items,
        myVotes: myVotes ?? this.myVotes,
        lastRead: lastRead ?? this.lastRead,
        loaded: loaded ?? this.loaded,
      );
}

/// El tablon: novedades de version, avisos y encuestas.
///
/// Publicar es cosa del admin. Votar lo puede hacer cualquiera, y el voto es
/// anonimo de verdad: en la encuesta solo queda cuantos votos lleva cada
/// opcion y quien ya ha votado; a que voto cada cual esta unicamente en su
/// propio arbol, que no lee nadie mas.
class NewsController extends StateNotifier<NewsState> {
  NewsController({required IbashoBackend backend, required SessionController session})
      : _backend = backend,
        _session = session,
        super(const NewsState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;

  StreamSubscription<DatabaseEvent>? _newsWatch;
  Object? _tree;

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    unawaited(_newsWatch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final results = await Future.wait([
        _backend.read('/news', idToken: token),
        _backend.read('/users/$_me/votes', idToken: token),
        _backend.read('/users/$_me/reads/news', idToken: token),
      ]);
      if (!mounted) return;
      _tree = results[0];
      final read = results[2];
      state = NewsState(
        items: _parse(_tree),
        myVotes: _parseVotes(results[1]),
        lastRead: read is num
            ? DateTime.fromMillisecondsSinceEpoch(read.toInt())
            : null,
        loaded: true,
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer las noticias ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    if (!mounted) return;

    _newsWatch = _backend.watch('/news', token: _session.freshToken).listen((e) {
      _tree = applyDatabaseEvent(_tree, e);
      if (mounted) state = state.copyWith(items: _parse(_tree), loaded: true);
    }, onError: (Object e) => debugPrint('Ibasho: stream de noticias ($e)'));
  }

  /// Marca el tablon como visto hasta la entrada mas nueva.
  Future<void> markRead() async {
    if (state.items.isEmpty) return;
    final newest = state.items.first.at;
    if (state.lastRead != null && !newest.isAfter(state.lastRead!)) return;
    state = state.copyWith(lastRead: newest);
    try {
      final token = await _session.freshToken();
      await _backend.write(
        '/users/$_me/reads/news',
        newest.millisecondsSinceEpoch,
        idToken: token,
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido apuntar la visita al tablon ($e)');
    }
  }

  /// Vota, o cambia el voto mientras la encuesta siga abierta.
  ///
  /// Es una sola escritura multi-ruta: el recuento de la opcion nueva sube, el
  /// de la vieja baja, se apunta que esta cuenta ya voto y se guarda en el
  /// arbol propio que fue lo votado. Las reglas comprueban que cada recuento
  /// se mueva de uno en uno.
  Future<bool> vote(String newsId, int option) async {
    final item = state.items.where((i) => i.id == newsId).firstOrNull;
    if (item == null || !item.isOpenAt(DateTime.now())) return false;
    if (option < 0 || option >= item.options.length) return false;

    final previous = state.myVotes[newsId];
    if (previous == option) return true;

    final writes = <String, Object?>{
      'news/$newsId/voters/$_me': true,
      'news/$newsId/tally/$option': _countOf(item, option) + 1,
      'users/$_me/votes/$newsId': option,
    };
    if (previous != null && previous < item.options.length) {
      writes['news/$newsId/tally/$previous'] = _countOf(item, previous) - 1;
    }

    try {
      final token = await _session.freshToken();
      await _backend.merge('/', writes, idToken: token);
      if (mounted) {
        state = state.copyWith(
          myVotes: <String, int>{...state.myVotes, newsId: option},
        );
      }
      return true;
    } catch (e) {
      debugPrint('Ibasho: el voto no ha entrado ($e)');
      return false;
    }
  }

  // --- Solo admin --------------------------------------------------------

  /// Publica una entrada. `options` la convierte en encuesta.
  Future<String?> publish({
    required NewsKind kind,
    required String title,
    String body = '',
    String? version,
    List<String> options = const <String>[],
    DateTime? closesAt,
    required String by,
  }) async {
    final id = generatePushId();
    final node = <String, Object?>{
      'kind': kind.name,
      'title': title,
      if (body.isNotEmpty) 'body': body,
      'version': ?version,
      'at': serverTimestamp,
      'by': by,
      if (options.isNotEmpty)
        'options': <String, Object?>{
          for (var i = 0; i < options.length; i++) '$i': options[i],
        },
      if (closesAt != null) 'closesAt': closesAt.millisecondsSinceEpoch,
    };
    try {
      final token = await _session.freshToken();
      await _backend.write('/news/$id', node, idToken: token);
      return id;
    } catch (e) {
      debugPrint('Ibasho: la entrada no se ha publicado ($e)');
      return null;
    }
  }

  /// Cierra una encuesta a mano.
  Future<bool> closePoll(String newsId) async {
    try {
      final token = await _session.freshToken();
      await _backend.write('/news/$newsId/closed', true, idToken: token);
      return true;
    } catch (e) {
      debugPrint('Ibasho: la encuesta no se ha cerrado ($e)');
      return false;
    }
  }

  Future<bool> remove(String newsId) async {
    try {
      final token = await _session.freshToken();
      await _backend.remove('/news/$newsId', idToken: token);
      return true;
    } catch (e) {
      debugPrint('Ibasho: la entrada no se ha borrado ($e)');
      return false;
    }
  }

  static int _countOf(NewsItem item, int option) =>
      option >= 0 && option < item.tally.length ? item.tally[option] : 0;

  static List<NewsItem> _parse(Object? raw) {
    if (raw is! Map) return const <NewsItem>[];
    final out = <NewsItem>[];
    for (final e in raw.entries) {
      final item = NewsItem.fromJson('${e.key}', e.value);
      if (item != null) out.add(item);
    }
    out.sort((a, b) => b.id.compareTo(a.id));
    return List<NewsItem>.unmodifiable(out);
  }

  static Map<String, int> _parseVotes(Object? raw) {
    if (raw is! Map) return const <String, int>{};
    return <String, int>{
      for (final e in raw.entries)
        if (e.value is num) '${e.key}': (e.value as num).toInt(),
    };
  }
}
