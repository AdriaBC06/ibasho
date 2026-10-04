// Ibasho — Malla online: la sala, las invitaciones y el historial.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../games/malla/malla_game.dart';
import 'tama.dart';

/// Lo que dura una invitación sin responder.
const Duration mallaInviteTtl = Duration(minutes: 10);

/// Sin señales de un jugador durante esto, se le salta. Las reglas exigen 20 s
/// con la hora del servidor; la app espera un poco más con la suya.
const Duration mallaGoneAfter = Duration(seconds: 25);

/// Cada cuánto da señal de vida cada jugador, en la sala y en partida.
const Duration mallaPingEvery = Duration(seconds: 5);

/// Partidas que se guardan en el historial de cada cuenta.
const int mallaHistoryKeep = 30;

/// Las letras de los códigos: sin 0/O ni 1/I, que se confunden al dictarlos.
const String mallaCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

final RegExp mallaCodePattern = RegExp('^[$mallaCodeAlphabet]{6}\$');

String generateMallaCode([math.Random? random]) {
  final rng = random ?? math.Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 6; i++) mallaCodeAlphabet.codeUnitAt(rng.nextInt(mallaCodeAlphabet.length)),
  ]);
}

/// Deja un código como lo escribiría la app: mayúsculas y sin lo que no puede
/// ir en él (las O y las I se leen como 0 y 1, que tampoco valen).
String cleanMallaCode(String raw) {
  final out = StringBuffer();
  for (final ch in raw.toUpperCase().split('')) {
    if (mallaCodeAlphabet.contains(ch)) out.write(ch);
    if (out.length == 6) break;
  }
  return out.toString();
}

String mallaRoomPath(String code) => '/malla/$code';

int? _int(Object? v) => v is num ? v.toInt() : null;

/// Lo que llega de una lista de la base: un `List` si las claves son 0, 1,
/// 2… seguidas, o un `Map` con claves de texto si no.
Map<int, Object?> _indexed(Object? raw) {
  if (raw is List) return {for (var i = 0; i < raw.length; i++) if (raw[i] != null) i: raw[i]};
  if (raw is Map) {
    return {
      for (final e in raw.entries)
        if (int.tryParse('${e.key}') case final int i) i: e.value,
    };
  }
  return const {};
}

/// El Tama de un jugador, copiado en la sala para que lo vean también quienes
/// no son sus amigos y para el historial.
@immutable
class MallaTama {
  const MallaTama({required this.name, required this.personality, required this.look});

  factory MallaTama.of(Tama tama) => MallaTama(name: tama.name, personality: tama.personality, look: tama.look);

  final String name;
  final TamaPersonality personality;
  final TamaLook look;

  Map<String, Object?> toJson() => {'name': name, 'personality': personality.name, 'look': look.toJson()};

  static MallaTama? fromJson(Object? raw) {
    if (raw is! Map || raw['name'] is! String) return null;
    return MallaTama(
      name: raw['name'] as String,
      personality: TamaPersonality.byName(raw['personality']),
      look: TamaLook.fromJson(raw['look']),
    );
  }
}

/// Quien está en la sala, en `members/{cuenta}`.
@immutable
class MallaMember {
  const MallaMember({
    required this.account,
    required this.name,
    required this.marker,
    required this.color,
    required this.at,
    this.tama,
    this.ping,
  });

  final String account;
  final String name;
  final MallaTama? tama;

  /// La marca de Malla: una letra o un emoji.
  final String marker;

  /// `#rrggbb`.
  final String color;

  /// Cuándo entró: decide el asiento.
  final int at;

  /// La última señal de vida, con la hora del servidor.
  final int? ping;

  static MallaMember? fromJson(String account, Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final marker = raw['marker'];
    final color = raw['color'];
    if (name is! String || marker is! String || color is! String) return null;
    return MallaMember(
      account: account,
      name: name,
      tama: MallaTama.fromJson(raw['tama']),
      marker: marker,
      color: color,
      at: _int(raw['at']) ?? 0,
      ping: _int(raw['ping']),
    );
  }
}

enum MallaRoomPhase { wait, play, done, gone }

/// La sala `/malla/{código}`. Ver docs/MALLA-0.9.1.md.
@immutable
class MallaRoom {
  const MallaRoom({
    required this.code,
    required this.host,
    required this.at,
    required this.size,
    required this.max,
    required this.chain,
    required this.phase,
    this.members = const {},
    this.order = const [],
    this.start = 0,
    this.turn = 0,
    this.n = 0,
    this.moves = const [],
    this.next,
  });

  final String code;
  final String host;
  final int at;
  final int size;

  /// Cuántos caben (2–6).
  final int max;
  final bool chain;
  final MallaRoomPhase phase;
  final Map<String, MallaMember> members;

  /// Las cuentas por asiento, desde que empieza.
  final List<String> order;

  /// El asiento que abre la partida.
  final int start;

  /// El asiento al que le toca, según la última escritura.
  final int turn;

  /// Jugadas escritas (aristas y salidas).
  final int n;
  final List<MallaMove> moves;

  /// El código de la revancha.
  final String? next;

  bool get started => phase == MallaRoomPhase.play || phase == MallaRoomPhase.done;

  /// Los de la sala en orden de llegada: los asientos antes de empezar.
  List<MallaMember> get lobby => members.values.toList()
    ..sort((a, b) {
      final byAt = a.at.compareTo(b.at);
      return byAt != 0 ? byAt : a.account.compareTo(b.account);
    });

  /// Los que juegan, por asiento; antes de empezar, los primeros [max] en
  /// llegar.
  List<MallaMember> get seats => started
      ? [for (final a in order) members[a] ?? MallaMember(account: a, name: '?', marker: '?', color: '#888888', at: 0)]
      : lobby.take(max).toList();

  int seatOf(String account) => seats.indexWhere((m) => m.account == account);

  bool get full => members.length >= max;

  /// La partida tal y como está, rejugando todo. Una jugada que no encaja
  /// (otra versión, o alguien que ha hecho trampas) lanza `FormatException`.
  MallaGame toGame() => MallaGame.replay(
        size: size,
        playerCount: order.length,
        startSeat: start,
        chain: chain,
        moves: moves,
      );

  static MallaRoom? fromJson(String code, Object? raw) {
    if (raw is! Map) return null;
    final host = raw['host'];
    final size = _int(raw['size']);
    final max = _int(raw['max']);
    final phase = MallaRoomPhase.values.where((p) => p.name == raw['state']).firstOrNull;
    if (host is! String || size == null || max == null || phase == null) return null;
    final members = <String, MallaMember>{};
    if (raw['members'] case final Map m) {
      for (final e in m.entries) {
        final member = MallaMember.fromJson('${e.key}', e.value);
        if (member != null) members[member.account] = member;
      }
    }
    final orderMap = _indexed(raw['order']);
    final order = <String>[
      for (var i = 0; orderMap[i] is String; i++) orderMap[i] as String,
    ];
    final moveMap = _indexed(raw['moves']);
    final moves = <MallaMove>[];
    for (var i = 0; moveMap[i] is Map; i++) {
      final m = moveMap[i] as Map;
      final out = _int(m['o']);
      final p = _int(m['p']);
      if (out != null) {
        moves.add(MallaMove.out(out));
      } else if (m['k'] is String && p != null) {
        moves.add(MallaMove(m['k'] as String, p));
      } else {
        break;
      }
    }
    final next = raw['next'];
    return MallaRoom(
      code: code,
      host: host,
      at: _int(raw['at']) ?? 0,
      size: size,
      max: max,
      chain: raw['chain'] == true,
      phase: phase,
      members: members,
      order: order,
      start: _int(raw['start']) ?? 0,
      turn: _int(raw['turn']) ?? 0,
      n: _int(raw['n']) ?? 0,
      moves: moves,
      next: next is String && mallaCodePattern.hasMatch(next) ? next : null,
    );
  }
}

/// Una invitación en `users/{yo}/mallaInbox/{quien}`.
@immutable
class MallaInvite {
  const MallaInvite({required this.from, required this.code, required this.at});

  final String from;
  final String code;
  final DateTime at;

  bool freshAt(DateTime now) => now.difference(at) < mallaInviteTtl;

  /// Las del buzón, la más vieja primero. Con [now], solo las que no han
  /// caducado.
  static List<MallaInvite> listFrom(Object? raw, {DateTime? now}) => [
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is Map)
              if ((_int((e.value as Map)['at']), (e.value as Map)['code']) case (final int at, final String code))
                if (MallaInvite(from: '${e.key}', code: code, at: DateTime.fromMillisecondsSinceEpoch(at))
                    case final invite when now == null || invite.freshAt(now))
                  invite,
      ]..sort((a, b) => a.at.compareTo(b.at));
}

/// Cómo acabó una partida para quien la guarda.
enum MallaEnd {
  /// Se llenó el tablero.
  board,

  /// Los demás se fueron y quedó uno.
  last,

  /// Se fue (o se quedó sin señal) antes de acabar.
  left,
}

@immutable
class MallaHistoryPlayer {
  const MallaHistoryPlayer({required this.account, required this.name, required this.score, this.tama, this.marker = '', this.color = '#888888'});

  final String account;
  final String name;
  final int score;
  final MallaTama? tama;
  final String marker;
  final String color;

  Map<String, Object?> toJson() => {
        'a': account,
        'name': name,
        's': score,
        if (marker.isNotEmpty) 'marker': marker,
        'color': color,
        if (tama != null) 'tama': tama!.toJson(),
      };

  static MallaHistoryPlayer? fromJson(Object? raw) {
    if (raw is! Map || raw['a'] is! String || raw['name'] is! String) return null;
    return MallaHistoryPlayer(
      account: raw['a'] as String,
      name: raw['name'] as String,
      score: _int(raw['s']) ?? 0,
      tama: MallaTama.fromJson(raw['tama']),
      marker: raw['marker'] is String ? raw['marker'] as String : '',
      color: raw['color'] is String ? raw['color'] as String : '#888888',
    );
  }
}

/// Una partida online en `users/{yo}/mallaHistory/{código}`.
@immutable
class MallaRecord {
  const MallaRecord({
    required this.code,
    required this.at,
    required this.size,
    required this.me,
    required this.end,
    required this.players,
    required this.winners,
  });

  final String code;
  final DateTime at;
  final int size;

  /// Mi asiento.
  final int me;
  final MallaEnd end;
  final List<MallaHistoryPlayer> players;
  final List<int> winners;

  bool get won => end != MallaEnd.left && winners.length == 1 && winners.first == me;
  bool get draw => end != MallaEnd.left && winners.length > 1 && winners.contains(me);

  Map<String, Object?> toJson(Object at) => {
        'at': at,
        'size': size,
        'me': me,
        'why': end.name,
        'p': {for (var i = 0; i < players.length; i++) '$i': players[i].toJson()},
        'w': {for (final w in winners) '$w': true},
      };

  static MallaRecord? fromJson(String code, Object? raw) {
    if (raw is! Map) return null;
    final at = _int(raw['at']);
    final size = _int(raw['size']);
    final me = _int(raw['me']);
    final end = MallaEnd.values.where((e) => e.name == raw['why']).firstOrNull;
    if (at == null || size == null || me == null || end == null) return null;
    final playerMap = _indexed(raw['p']);
    final players = <MallaHistoryPlayer>[];
    for (var i = 0; i < playerMap.length; i++) {
      final p = MallaHistoryPlayer.fromJson(playerMap[i]);
      if (p == null) break;
      players.add(p);
    }
    if (me >= players.length) return null;
    final winners = <int>[
      for (final w in _indexed(raw['w']).keys) w,
    ]..sort();
    return MallaRecord(
      code: code,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      size: size,
      me: me,
      end: end,
      players: players,
      winners: winners,
    );
  }

  /// Las del historial, la más nueva primero.
  static List<MallaRecord> listFrom(Object? raw) => [
        if (raw is Map)
          for (final e in raw.entries) ?MallaRecord.fromJson('${e.key}', e.value),
      ]..sort((a, b) => b.at.compareTo(a.at));
}
