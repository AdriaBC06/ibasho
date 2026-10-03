// Ibasho — Tsumiki versus: lo que se guarda de la sala, las invitaciones y el
// historial entre dos amigos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import '../games/tsumiki/tsumiki_versus.dart';

/// Lo que dura una invitación sin responder.
const Duration tsumikiInviteTtl = Duration(minutes: 10);

/// Sin señales del otro durante esto, gana quien se ha quedado.
const Duration tsumikiQuitAfter = Duration(seconds: 20);

/// El id de la sala de dos amigos: sus cuentas ordenadas, como en `/koen`.
String tsumikiPairId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

String tsumikiRoomPath(String a, String b) => '/tsumiki/${tsumikiPairId(a, b)}';

int? _int(Object? v) => v is num ? v.toInt() : null;

/// Una invitación en `users/{yo}/tsumikiInbox/{quien}`.
@immutable
class TsumikiInvite {
  const TsumikiInvite({required this.from, required this.id, required this.at});

  final String from;

  /// El id de la partida en la sala.
  final String id;
  final DateTime at;

  bool freshAt(DateTime now) => now.difference(at) < tsumikiInviteTtl;

  /// Las del buzón, la más vieja primero. Con [now], solo las que no han
  /// caducado.
  static List<TsumikiInvite> listFrom(Object? raw, {DateTime? now}) => [
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is Map)
              if ((_int((e.value as Map)['at']), (e.value as Map)['id']) case (final int at, final String id))
                if (now == null || TsumikiInvite(from: '${e.key}', id: id, at: DateTime.fromMillisecondsSinceEpoch(at)).freshAt(now))
                  TsumikiInvite(from: '${e.key}', id: id, at: DateTime.fromMillisecondsSinceEpoch(at)),
      ]..sort((a, b) => a.at.compareTo(b.at));
}

enum TsumikiRoomState { wait, play, done, no, gone }

/// Por qué se acaba: se ha llenado (`top`), se ha ido (`leave`) o ha dejado
/// de dar señales (`quit`).
enum TsumikiEnd { top, leave, quit }

/// Lo que publica cada jugador en `live/p/{cuenta}`.
@immutable
class TsumikiSeat {
  const TsumikiSeat({
    this.board = '',
    this.ping,
    this.lines = 0,
    this.sent = 0,
    this.meter = 0,
    this.over = false,
    this.fx = const <TsumikiSabotage>{},
  });

  /// El tablero visible, como `TsumikiGame.encodeBoard`.
  final String board;

  /// La última señal, con la hora del servidor.
  final int? ping;
  final int lines;
  final int sent;
  final double meter;
  final bool over;

  /// Los sabotajes que está sufriendo ahora.
  final Set<TsumikiSabotage> fx;

  static TsumikiSeat fromJson(Object? raw) {
    if (raw is! Map) return const TsumikiSeat();
    final fx = raw['fx'];
    return TsumikiSeat(
      board: raw['board'] is String ? raw['board'] as String : '',
      ping: _int(raw['ping']),
      lines: _int(raw['lines']) ?? 0,
      sent: _int(raw['sent']) ?? 0,
      meter: (raw['meter'] is num) ? (raw['meter'] as num).toDouble() : 0,
      over: raw['over'] == true,
      fx: {
        if (fx is Map)
          for (final k in fx.keys)
            if (TsumikiSabotage.values.where((s) => s.name == '$k').firstOrNull case final s?)
              if (fx[k] == true) s,
      },
    );
  }

  /// Altura del montón (0–20), contando desde abajo.
  int get height {
    const w = 10;
    for (var i = 0; i < board.length; i++) {
      if (board[i] != '.') return 20 - i ~/ w;
    }
    return 0;
  }
}

/// Lo que manda uno al otro: filas grises o un sabotaje.
@immutable
class TsumikiVsEvent {
  const TsumikiVsEvent.attack(TsumikiAttack this.attack) : sabotage = null;
  const TsumikiVsEvent.sabotage(TsumikiSabotage this.sabotage) : attack = null;

  final TsumikiAttack? attack;
  final TsumikiSabotage? sabotage;

  static TsumikiVsEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['sab'] case final String sab) {
      final s = TsumikiSabotage.values.where((x) => x.name == sab).firstOrNull;
      return s == null ? null : TsumikiVsEvent.sabotage(s);
    }
    final rows = _int(raw['rows']);
    final hole = _int(raw['hole']);
    if (rows == null || hole == null || rows <= 0) return null;
    return TsumikiVsEvent.attack(TsumikiAttack(rows, hole));
  }

  Map<String, Object?> toJson() =>
      sabotage != null ? {'sab': sabotage!.name} : {'rows': attack!.rows, 'hole': attack!.hole};
}

/// `live`: la partida en curso de una pareja.
@immutable
class TsumikiRoom {
  const TsumikiRoom({
    required this.id,
    required this.seed,
    required this.host,
    required this.guest,
    required this.state,
    required this.at,
    this.start,
    this.seats = const <String, TsumikiSeat>{},
    this.events = const <String, List<(String, TsumikiVsEvent)>>{},
    this.winner,
    this.end,
  });

  final String id;
  final int seed;
  final String host;
  final String guest;
  final TsumikiRoomState state;

  /// Cuándo se mandó la invitación (hora del servidor, ms).
  final int at;

  /// Cuándo se aceptó.
  final int? start;
  final Map<String, TsumikiSeat> seats;

  /// Lo que ha mandado cada uno, en orden (con su clave).
  final Map<String, List<(String, TsumikiVsEvent)>> events;
  final String? winner;
  final TsumikiEnd? end;

  String other(String me) => me == host ? guest : host;
  TsumikiSeat seat(String who) => seats[who] ?? const TsumikiSeat();

  /// Lado del jugador (0 quien invita, 1 el otro): separa los huecos.
  int side(String who) => who == host ? 0 : 1;

  static TsumikiRoom? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final host = raw['host'];
    final guest = raw['guest'];
    final state = TsumikiRoomState.values.where((s) => s.name == raw['state']).firstOrNull;
    if (id is! String || host is! String || guest is! String || state == null) return null;
    final p = raw['p'];
    final atk = raw['atk'];
    final result = raw['result'];
    return TsumikiRoom(
      id: id,
      seed: _int(raw['seed']) ?? 0,
      host: host,
      guest: guest,
      state: state,
      at: _int(raw['at']) ?? 0,
      start: _int(raw['start']),
      seats: {
        if (p is Map)
          for (final e in p.entries) '${e.key}': TsumikiSeat.fromJson(e.value),
      },
      events: {
        if (atk is Map)
          for (final e in atk.entries)
            if (e.value is Map)
              '${e.key}': [
                for (final k in ((e.value as Map).keys.map((k) => '$k').toList()..sort()))
                  if (TsumikiVsEvent.fromJson((e.value as Map)[k]) case final ev?) (k, ev),
              ],
      },
      winner: result is Map && result['w'] is String ? result['w'] as String : null,
      end: result is Map ? TsumikiEnd.values.where((x) => x.name == result['why']).firstOrNull : null,
    );
  }
}

/// Una partida acabada, en `history/{id}`.
@immutable
class TsumikiMatchRecord {
  const TsumikiMatchRecord({
    required this.id,
    required this.at,
    required this.winner,
    required this.end,
    required this.seconds,
    this.sent = const <String, int>{},
    this.lines = const <String, int>{},
  });

  final String id;
  final DateTime at;
  final String winner;
  final TsumikiEnd end;
  final int seconds;

  /// Filas grises que mandó cada uno.
  final Map<String, int> sent;

  /// Filas que borró cada uno.
  final Map<String, int> lines;

  Map<String, Object?> toJson() => {
        'w': winner,
        'why': end.name,
        'at': at.millisecondsSinceEpoch,
        'dur': seconds,
        's': sent,
        'l': lines,
      };

  static Map<String, int> _counts(Object? raw) => {
        if (raw is Map)
          for (final e in raw.entries) '${e.key}': ?_int(e.value),
      };

  /// El historial, la más nueva primero.
  static List<TsumikiMatchRecord> listFrom(Object? raw) => [
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is Map)
              if (((e.value as Map)['w'], _int((e.value as Map)['at']),
                  TsumikiEnd.values.where((x) => x.name == (e.value as Map)['why']).firstOrNull)
                  case (final String w, final int at, final TsumikiEnd end))
                TsumikiMatchRecord(
                  id: '${e.key}',
                  at: DateTime.fromMillisecondsSinceEpoch(at),
                  winner: w,
                  end: end,
                  seconds: _int((e.value as Map)['dur']) ?? 0,
                  sent: _counts((e.value as Map)['s']),
                  lines: _counts((e.value as Map)['l']),
                ),
      ]..sort((a, b) => b.at.compareTo(a.at));
}

/// Victorias de cada uno contra el otro (`score/{cuenta}`).
@immutable
class TsumikiScore {
  const TsumikiScore({this.mine = 0, this.theirs = 0});

  final int mine;
  final int theirs;

  bool get isEmpty => mine == 0 && theirs == 0;

  static TsumikiScore fromJson(Object? raw, {required String me, required String friend}) => raw is Map
      ? TsumikiScore(mine: _int(raw[me]) ?? 0, theirs: _int(raw[friend]) ?? 0)
      : const TsumikiScore();
}
