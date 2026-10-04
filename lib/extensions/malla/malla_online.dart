// Malla — cliente del protocolo de salas compartido con la web.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'malla_game.dart';

class MallaApiException implements Exception {
  const MallaApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MallaSession {
  const MallaSession({
    required this.code,
    required this.token,
    required this.seat,
  });

  final String code;
  final String token;
  final int seat;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'token': token,
    'seat': seat,
  };

  static MallaSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final code = map['code'];
    final token = map['token'];
    final seat = map['seat'];
    if (code is! String ||
        !RegExp(r'^[A-Z0-9]{6}$').hasMatch(code) ||
        token is! String ||
        token.isEmpty ||
        seat is! num ||
        seat.toInt() < 0 ||
        seat.toInt() > 5) {
      return null;
    }
    return MallaSession(code: code, token: token, seat: seat.toInt());
  }
}

class MallaRoomState {
  const MallaRoomState({
    required this.code,
    required this.size,
    required this.playerCount,
    required this.joinedCount,
    required this.seat,
    required this.started,
    required this.markers,
    required this.colors,
    required this.moves,
    required this.turn,
    required this.startSeat,
    required this.score,
    required this.over,
    required this.endedReason,
    required this.abandonedBy,
    required this.rematch,
    required this.series,
    required this.draws,
    required this.version,
    required this.round,
    required this.chain,
  });

  final String code;
  final int size;
  final int playerCount;
  final int joinedCount;
  final int seat;
  final bool started;
  final List<String?> markers;
  final List<String> colors;
  final List<MallaMove> moves;
  final int turn;
  final int startSeat;
  final List<int> score;
  final bool over;
  final String endedReason;
  final int? abandonedBy;
  final List<bool> rematch;
  final List<int> series;
  final int draws;
  final int version;
  final int round;
  final bool chain;

  bool get joined => joinedCount == playerCount;
  bool get naturalEnd => over && endedReason.isEmpty;

  MallaGame toGame() {
    final game = MallaGame.replay(
      size: size,
      playerCount: playerCount,
      startSeat: startSeat,
      chain: chain,
      moves: moves,
    );
    // El servidor es autoridad. Un desajuste no se oculta: impediría que web
    // e Ibasho jugasen realmente la misma partida.
    if (game.currentPlayer != turn ||
        (endedReason.isEmpty && game.finished != over) ||
        !_sameInts(game.scores, score)) {
      throw const FormatException(
        'El estado remoto de Malla no coincide con el protocolo canónico',
      );
    }
    return game;
  }

  static MallaRoomState fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('state debe ser un objeto');
    final map = Map<String, Object?>.from(raw);
    final playerCount = _int(map['playerCount'], 'playerCount');
    final markersRaw = _list(map['markers'], 'markers');
    final colorsRaw = _list(map['colors'], 'colors');
    final scoreRaw = _list(map['score'], 'score');
    final rematchRaw = _list(map['rematch'], 'rematch');
    final seriesRaw = _list(map['series'], 'series');
    final movesRaw = _list(map['moves'], 'moves');

    if (playerCount < 2 || playerCount > 6) {
      throw const FormatException('playerCount fuera de rango');
    }
    if (markersRaw.length != playerCount ||
        colorsRaw.length != playerCount ||
        scoreRaw.length != playerCount ||
        rematchRaw.length != playerCount ||
        seriesRaw.length != playerCount) {
      throw const FormatException('listas de jugadores con longitud inválida');
    }

    final code = _string(map['code'], 'code').toUpperCase();
    final size = _int(map['size'], 'size');
    final joinedCount = _int(map['joinedCount'], 'joinedCount');
    final seat = _int(map['seat'], 'seat');
    final turn = _int(map['turn'], 'turn');
    final startSeat = _int(map['startSeat'], 'startSeat');
    final draws = _int(map['draws'], 'draws');
    final version = _int(map['version'], 'version');
    final round = _int(map['round'], 'round');
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      throw const FormatException('code inválido');
    }
    if (size < 3 || size > 7)
      throw const FormatException('size fuera de rango');
    if (joinedCount < 0 || joinedCount > playerCount) {
      throw const FormatException('joinedCount fuera de rango');
    }
    if (seat < 0 ||
        seat >= playerCount ||
        turn < 0 ||
        turn >= playerCount ||
        startSeat < 0 ||
        startSeat >= playerCount) {
      throw const FormatException('asiento/turno fuera de rango');
    }
    if (map['started'] is! bool ||
        map['over'] is! bool ||
        map['chain'] is! bool) {
      throw const FormatException('booleanos de estado inválidos');
    }
    if (draws < 0 || version < 1 || round < 1) {
      throw const FormatException('contadores remotos inválidos');
    }

    final markers = <String?>[];
    for (final marker in markersRaw) {
      if (marker != null && marker is! String)
        throw const FormatException('marker inválido');
      final value = marker as String?;
      if (value != null && (value.isEmpty || value.length > 64)) {
        throw const FormatException('marker fuera de rango');
      }
      markers.add(value);
    }
    final colors = <String>[];
    for (final rawColor in colorsRaw) {
      if (rawColor is! String ||
          !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(rawColor)) {
        throw const FormatException('color remoto inválido');
      }
      colors.add(rawColor.toLowerCase());
    }
    final score = <int>[for (final value in scoreRaw) _int(value, 'score')];
    final series = <int>[for (final value in seriesRaw) _int(value, 'series')];
    if (score.any((v) => v < 0) || series.any((v) => v < 0)) {
      throw const FormatException('puntuación/serie inválida');
    }
    if (rematchRaw.any((v) => v is! bool)) {
      throw const FormatException('rematch inválido');
    }

    final moves = <MallaMove>[];
    for (final rawMove in movesRaw) {
      if (rawMove is! List || rawMove.length != 2) {
        throw const FormatException('movimiento remoto inválido');
      }
      final key = rawMove[0];
      final who = rawMove[1];
      if (key is! String || key.length < 5 || key.length > 80 || who is! num) {
        throw const FormatException('movimiento remoto inválido');
      }
      final player = who.toInt();
      if (player < 0 || player >= playerCount) {
        throw const FormatException('jugador remoto inválido');
      }
      moves.add(MallaMove(key, player));
    }

    final endedReasonRaw = map['endedReason'];
    if (endedReasonRaw != null && endedReasonRaw is! String) {
      throw const FormatException('endedReason inválido');
    }
    final endedReason = endedReasonRaw?.toString() ?? '';
    if (endedReason.isNotEmpty && endedReason != 'abandon') {
      throw const FormatException('endedReason desconocido');
    }
    final abandonedRaw = map['abandonedBy'];
    final int? abandonedBy;
    if (abandonedRaw == null) {
      abandonedBy = null;
    } else if (abandonedRaw is num &&
        abandonedRaw.toInt() >= 0 &&
        abandonedRaw.toInt() < playerCount) {
      abandonedBy = abandonedRaw.toInt();
    } else {
      throw const FormatException('abandonedBy inválido');
    }

    return MallaRoomState(
      code: code,
      size: size,
      playerCount: playerCount,
      joinedCount: joinedCount,
      seat: seat,
      started: map['started'] as bool,
      markers: List<String?>.unmodifiable(markers),
      colors: List<String>.unmodifiable(colors),
      moves: List<MallaMove>.unmodifiable(moves),
      turn: turn,
      startSeat: startSeat,
      score: List<int>.unmodifiable(score),
      over: map['over'] as bool,
      endedReason: endedReason,
      abandonedBy: abandonedBy,
      rematch: <bool>[for (final value in rematchRaw) value as bool],
      series: List<int>.unmodifiable(series),
      draws: draws,
      version: version,
      round: round,
      chain: map['chain'] as bool,
    );
  }
}

class MallaPollResult {
  const MallaPollResult(this.state, this.presence);

  final MallaRoomState state;
  final List<int?> presence;
}

class MallaOnlineClient {
  MallaOnlineClient({http.Client? client}) : _client = client ?? http.Client();

  /// Endpoint fijo del Malla web. Un paquete `.ibasho` no puede cambiarlo ni
  /// convertir el host en un proxy HTTP arbitrario.
  static final Uri endpoint = Uri.parse(
    'https://mallagame.netlify.app/.netlify/functions/room',
  );
  static final Uri webBase = Uri.parse('https://mallagame.netlify.app/');

  final http.Client _client;

  Uri inviteUri(String code) => webBase.replace(
    queryParameters: <String, String>{'sala': code.toUpperCase()},
  );

  Future<(MallaSession, MallaRoomState)> create({
    required int size,
    required int playerCount,
    required String marker,
    required String color,
    required bool chain,
  }) async {
    final data = await _call(<String, Object?>{
      'action': 'create',
      'size': size,
      'playerCount': playerCount,
      'marker': marker,
      'color': color,
      'chain': chain,
    });
    return _sessionResponse(data);
  }

  Future<(MallaSession, MallaRoomState)> join({
    required String code,
    required String marker,
    required String color,
  }) async {
    final data = await _call(<String, Object?>{
      'action': 'join',
      'code': code,
      'marker': marker,
      'color': color,
    });
    return _sessionResponse(data);
  }

  Future<MallaRoomState> start(MallaSession session) async =>
      _stateResponse(await _call(_auth('start', session)));

  Future<MallaPollResult> poll(MallaSession session) async {
    final data = await _call(_auth('poll', session));
    final state = MallaRoomState.fromJson(data['state']);
    final raw = data['presence'];
    final presence = raw is List
        ? <int?>[for (final value in raw) value is num ? value.toInt() : null]
        : List<int?>.filled(state.playerCount, null);
    return MallaPollResult(state, presence);
  }

  Future<void> heartbeat(MallaSession session) async {
    await _call(_auth('heartbeat', session));
  }

  Future<MallaRoomState> move(MallaSession session, String edgeKey) async =>
      _stateResponse(
        await _call(<String, Object?>{
          ..._auth('move', session),
          'key': edgeKey,
        }),
      );

  Future<MallaRoomState> rematch(MallaSession session) async =>
      _stateResponse(await _call(_auth('rematch', session)));

  Future<MallaRoomState?> leave(MallaSession session) async {
    final data = await _call(_auth('leave', session));
    final state = data['state'];
    return state == null ? null : MallaRoomState.fromJson(state);
  }

  void close() => _client.close();

  Map<String, Object?> _auth(String action, MallaSession session) =>
      <String, Object?>{
        'action': action,
        'code': session.code,
        'token': session.token,
      };

  Future<Map<String, Object?>> _call(Map<String, Object?> payload) async {
    http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const MallaApiException(
        'La conexión tardó demasiado. Inténtalo otra vez.',
      );
    } catch (error) {
      throw MallaApiException('No se pudo conectar con Malla: $error');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw MallaApiException(
        'Respuesta inválida del servidor de Malla.',
        response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw MallaApiException(
        'Respuesta inválida del servidor de Malla.',
        response.statusCode,
      );
    }
    final data = Map<String, Object?>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MallaApiException(
        data['error']?.toString() ?? 'Error ${response.statusCode}',
        response.statusCode,
      );
    }
    return data;
  }

  (MallaSession, MallaRoomState) _sessionResponse(Map<String, Object?> data) {
    final token = data['token'];
    final state = MallaRoomState.fromJson(data['state']);
    if (token is! String || token.isEmpty) {
      throw const FormatException('El servidor no devolvió token de sala');
    }
    return (
      MallaSession(code: state.code, token: token, seat: state.seat),
      state,
    );
  }

  MallaRoomState _stateResponse(Map<String, Object?> data) =>
      MallaRoomState.fromJson(data['state']);
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<Object?> _list(Object? raw, String name) {
  if (raw is! List) throw FormatException('$name debe ser una lista');
  return List<Object?>.from(raw);
}

int _int(Object? raw, String name) {
  if (raw is! num) throw FormatException('$name debe ser número');
  return raw.toInt();
}

String _string(Object? raw, String name) {
  if (raw is! String || raw.isEmpty)
    throw FormatException('$name debe ser texto');
  return raw;
}
