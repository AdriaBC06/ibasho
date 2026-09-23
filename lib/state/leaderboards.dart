// Ibasho — clasificaciones: leer un periodo, mandar la puntuacion propia,
// cerrar el periodo con el top 3 y cobrar el premio en tickets.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/gacha.dart';
import '../backend/ibasho_backend.dart';
import '../backend/leaderboards.dart';
import '../backend/models.dart';
import 'login_bonus.dart' show bonusDay;
import 'session.dart';

const int _dayMs = 86400000;
const int _weekMs = 604800000;

/// Una cuenta y su puntuacion.
@immutable
class LeaderboardEntry {
  const LeaderboardEntry({required this.accountId, required this.score});

  final String accountId;
  final int score;
}

/// Lo que hay en `/leaderboards/{juego}/{daily|weekly}/{periodo}`.
@immutable
class LeaderboardPeriod {
  const LeaderboardPeriod({this.scores = const <String, int>{}, this.results});

  final Map<String, int> scores;

  /// El top 3 (o top 2 si aun no hay tres cuentas con puntuacion), ya
  /// cerrado. `null` mientras el periodo sigue abierto o nadie lo ha
  /// calculado todavia.
  final List<String>? results;

  bool get closed => results != null;

  /// Las puntuaciones ordenadas de mejor a peor segun [game].
  List<LeaderboardEntry> ranked(LeaderboardGame game) {
    final entries = [
      for (final e in scores.entries) LeaderboardEntry(accountId: e.key, score: e.value),
    ];
    entries.sort(
      (a, b) => game.lowerIsBetter ? a.score.compareTo(b.score) : b.score.compareTo(a.score),
    );
    return entries;
  }

  /// El puesto (1 en adelante) de [accountId] en esta tabla, o `null` si no
  /// tiene puntuacion.
  int? rankOf(LeaderboardGame game, String accountId) {
    final list = ranked(game);
    final i = list.indexWhere((e) => e.accountId == accountId);
    return i < 0 ? null : i + 1;
  }

  static LeaderboardPeriod fromJson(Object? raw) {
    if (raw is! Map) return const LeaderboardPeriod();
    final scoresRaw = raw['scores'];
    final scores = <String, int>{
      if (scoresRaw is Map)
        for (final e in scoresRaw.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    };
    final resultsRaw = raw['results'];
    final results = resultsRaw is Map ? _ranksFromMap(resultsRaw) : null;
    return LeaderboardPeriod(scores: scores, results: results);
  }
}

List<String> _ranksFromMap(Map raw) => [
      for (final rank in const ['1', '2', '3'])
        if (raw[rank] is String) raw[rank] as String,
    ];

String _periodKey(LeaderboardGame game, bool weekly, int key) =>
    '${game.key}|${weekly ? 'weekly' : 'daily'}|$key';

/// Estado del canal de clasificaciones: lo que se ha leido de cada periodo
/// mirado, y los cobros ya hechos.
@immutable
class LeaderboardsState {
  const LeaderboardsState({
    this.periods = const <String, LeaderboardPeriod>{},
    this.claims = const <String>{},
    this.busy = false,
  });

  final Map<String, LeaderboardPeriod> periods;

  /// `juego|daily|dia|kind` o `juego|weekly|semana|kind`, para los premios ya
  /// cobrados.
  final Set<String> claims;

  final bool busy;

  LeaderboardPeriod periodOf(LeaderboardGame game, bool weekly, int key) =>
      periods[_periodKey(game, weekly, key)] ?? const LeaderboardPeriod();

  bool claimed(LeaderboardGame game, bool weekly, int key, TicketKind kind) =>
      claims.contains('${_periodKey(game, weekly, key)}|${kind.name}');

  LeaderboardsState copyWith({
    Map<String, LeaderboardPeriod>? periods,
    Set<String>? claims,
    bool? busy,
  }) =>
      LeaderboardsState(
        periods: periods ?? this.periods,
        claims: claims ?? this.claims,
        busy: busy ?? this.busy,
      );
}

/// Las clasificaciones.
///
/// El sorteo de quien gana lo hace la app, igual que el gacha: cada cuenta
/// manda su propia puntuacion y cualquier cliente, cuando el periodo ya ha
/// cerrado, calcula el top 3 leyendo las puntuaciones publicas y lo escribe
/// una sola vez.
class LeaderboardsController extends StateNotifier<LeaderboardsState> {
  LeaderboardsController({
    required IbashoBackend backend,
    required SessionController session,
    required int Function(TicketKind) ticketsOf,
  })  : _backend = backend,
        _session = session,
        _ticketsOf = ticketsOf,
        super(const LeaderboardsState());

  final IbashoBackend _backend;
  final SessionController _session;
  final int Function(TicketKind) _ticketsOf;

  String get _me => _session.state.accountId;

  String _path(LeaderboardGame game, bool weekly, int key) =>
      '/leaderboards/${game.key}/${weekly ? 'weekly' : 'daily'}/$key';

  /// Igual que [_path] pero sin la barra inicial: lo que hace falta como
  /// clave de una escritura multi-ruta con base `/`.
  String _relPath(LeaderboardGame game, bool weekly, int key) =>
      'leaderboards/${game.key}/${weekly ? 'weekly' : 'daily'}/$key';

  /// Lee un periodo (puntuaciones y resultados, si los hay). Si el periodo ya
  /// ha cerrado y nadie ha calculado el top 3 todavia, lo calcula con lo que
  /// hay y lo escribe: las reglas solo dejan hacerlo una vez, asi que si dos
  /// clientes llegan a la vez el segundo simplemente falla y relee.
  Future<LeaderboardPeriod> loadPeriod(
    LeaderboardGame game, {
    required bool weekly,
    required int key,
  }) async {
    Object? raw;
    try {
      raw = await _backend.read(_path(game, weekly, key), idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer la clasificacion (${game.key}, $e)');
      return state.periodOf(game, weekly, key);
    }
    var period = LeaderboardPeriod.fromJson(raw);
    final periodMs = weekly ? _weekMs : _dayMs;
    final closed = (key + 1) * periodMs <= DateTime.now().millisecondsSinceEpoch;
    if (closed && period.results == null && period.scores.isNotEmpty) {
      period = await _closePeriod(game, weekly: weekly, key: key, period: period);
    }
    if (mounted) {
      state = state.copyWith(periods: {...state.periods, _periodKey(game, weekly, key): period});
    }
    return period;
  }

  Future<LeaderboardPeriod> _closePeriod(
    LeaderboardGame game, {
    required bool weekly,
    required int key,
    required LeaderboardPeriod period,
  }) async {
    final ranked = period.ranked(game);
    if (ranked.length < 2) return period;
    final results = <String, Object?>{
      '1': ranked[0].accountId,
      '2': ranked[1].accountId,
      if (ranked.length > 2) '3': ranked[2].accountId,
    };
    try {
      await _backend.merge(
        '/',
        {
          // El numero del periodo va con `results`, por si nadie lo habia
          // escrito ya (un periodo sin puntuaciones no llegaria aqui, pero
          // uno con puntuaciones y sin este numero, en teoria, si).
          '${_relPath(game, weekly, key)}/${weekly ? 'week' : 'day'}': key,
          '${_relPath(game, weekly, key)}/results': results,
        },
        idToken: await _session.freshToken(),
      );
      return LeaderboardPeriod(scores: period.scores, results: _ranksFromMap(results));
    } catch (e) {
      // Ya cerrado por otro cliente, o sin conexion: se relee lo que haya.
      debugPrint('Ibasho: no se ha podido cerrar la clasificacion (${game.key}, $e)');
      try {
        final raw = await _backend.read(
          '${_path(game, weekly, key)}/results',
          idToken: await _session.freshToken(),
        );
        if (raw is Map) return LeaderboardPeriod(scores: period.scores, results: _ranksFromMap(raw));
      } catch (_) {
        // Sin red: se deja el periodo como estaba, se reintentara luego.
      }
      return period;
    }
  }

  /// Manda la puntuacion propia de hoy y de esta semana, si mejora. Van en
  /// dos escrituras separadas: si una no mejora (las reglas la rechazan) no
  /// tiene que arrastrar a la otra. Un fallo no rompe la partida: se
  /// reintenta la proxima vez que se gane.
  Future<void> submitScore(LeaderboardGame game, int score) async {
    if (_me.isEmpty) return;
    final day = bonusDay();
    final week = gachaWeek();
    final token = await _session.freshToken();
    try {
      await _backend.merge(
        '/',
        {
          // `day`/`week` van con cada puntuacion: son el numero de verdad que
          // las reglas necesitan para la aritmetica del periodo (el comodin
          // de la ruta es siempre texto). Reescribir el mismo numero que ya
          // hubiera no molesta a nadie.
          'leaderboards/${game.key}/daily/$day/day': day,
          'leaderboards/${game.key}/daily/$day/scores/$_me': score,
          'leaderboards/${game.key}/daily/$day/at/$_me': serverTimestamp,
        },
        idToken: token,
      );
    } catch (e) {
      debugPrint('Ibasho: puntuacion diaria no admitida (${game.key}, $e)');
    }
    try {
      await _backend.merge(
        '/',
        {
          'leaderboards/${game.key}/weekly/$week/week': week,
          'leaderboards/${game.key}/weekly/$week/scores/$_me': score,
          'leaderboards/${game.key}/weekly/$week/at/$_me': serverTimestamp,
        },
        idToken: token,
      );
    } catch (e) {
      debugPrint('Ibasho: puntuacion semanal no admitida (${game.key}, $e)');
    }
  }

  /// Lee lo ya cobrado de [game]/[weekly]/[key], para pintar el boton bien
  /// desde el principio.
  Future<void> loadClaims(LeaderboardGame game, {required bool weekly, required int key}) async {
    final period = weekly ? 'weekly' : 'daily';
    Object? raw;
    try {
      raw = await _backend.read(
        '/users/$_me/leaderboardClaims/${game.key}/$period/$key',
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los cobros de la clasificacion ($e)');
      return;
    }
    if (raw is! Map || !mounted) return;
    final claimed = <String>{
      for (final entry in raw.entries)
        if (entry.value == true) '${_periodKey(game, weekly, key)}|${entry.key}',
    };
    if (claimed.isEmpty) return;
    state = state.copyWith(claims: {...state.claims, ...claimed});
  }

  /// Cobra el ticket de [kind] por el puesto [rank]. Devuelve `false` sin
  /// tocar nada si ese puesto no da ese ticket, si ya estaba cobrado o si no
  /// hay conexion.
  Future<bool> claim({
    required LeaderboardGame game,
    required bool weekly,
    required int key,
    required int rank,
    required TicketKind kind,
  }) async {
    final amount = leaderboardReward(weekly: weekly, rank: rank)?[kind];
    if (amount == null) return false;
    if (state.claimed(game, weekly, key, kind)) return false;
    final period = weekly ? 'weekly' : 'daily';
    final writes = <String, Object?>{
      'users/$_me/leaderboardClaims/last': {
        'game': game.key,
        'period': period,
        'key': key,
        'kind': kind.name,
        'at': serverTimestamp,
      },
      'users/$_me/leaderboardClaims/${game.key}/$period/$key/${kind.name}': true,
      'users/$_me/tickets/${kind.name}': _ticketsOf(kind) + amount,
    };
    state = state.copyWith(busy: true);
    try {
      await _backend.merge('/', writes, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar el premio de la clasificacion ($e)');
      if (mounted) state = state.copyWith(busy: false);
      return false;
    }
    if (mounted) {
      state = state.copyWith(
        busy: false,
        claims: {...state.claims, '${_periodKey(game, weekly, key)}|${kind.name}'},
      );
    }
    return true;
  }
}
