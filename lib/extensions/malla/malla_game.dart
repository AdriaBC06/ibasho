// Malla — reglas y protocolo geométrico compartidos con la versión web.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

class MallaPoint {
  const MallaPoint(this.x, this.y);

  final double x;
  final double y;

  String get wireKey => '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
}

class MallaMove {
  const MallaMove(this.key, this.player);

  final String key;
  final int player;

  List<Object> toWire() => <Object>[key, player];
}

class MallaHex {
  MallaHex({
    required this.cx,
    required this.cy,
    required this.vertices,
    required this.playerCount,
  }) : sidesByPlayer = List<int>.filled(playerCount, 0);

  final double cx;
  final double cy;
  final List<MallaPoint> vertices;
  final int playerCount;
  final List<String> edgeKeys = <String>[];
  final List<int> sidesByPlayer;

  int drawnSides = 0;
  int? owner;
}

class MallaEdge {
  MallaEdge({required this.key, required this.p, required this.q});

  final String key;
  final MallaPoint p;
  final MallaPoint q;
  final List<int> hexes = <int>[];
  int? owner;
}

class MallaMoveResult {
  const MallaMoveResult({
    required this.accepted,
    required this.player,
    required this.capturedHexes,
    required this.nextPlayer,
    required this.finished,
  });

  final bool accepted;
  final int player;
  final List<int> capturedHexes;
  final int nextPlayer;
  final bool finished;

  int get captured => capturedHexes.length;
}

/// Estado canónico de Malla.
///
/// La geometría y las claves de arista replican literalmente el algoritmo de
/// `public/app.js` y `netlify/functions/room.mjs`: S=30, PAD=16, vértices a
/// 30+60*k grados y coordenadas redondeadas con una decimal. Eso permite que
/// una partida creada en web acepte movimientos de Ibasho y viceversa.
class MallaGame {
  MallaGame({
    required this.size,
    required this.playerCount,
    required this.startSeat,
    required this.chain,
  }) : assert(size >= 1),
       assert(playerCount >= 2 && playerCount <= 6),
       assert(startSeat >= 0 && startSeat < playerCount),
       currentPlayer = startSeat,
       scores = List<int>.filled(playerCount, 0) {
    _buildBoard();
  }

  static const double cellRadius = 30;
  static const double pad = 16;
  static final double root3 = math.sqrt(3);

  final int size;
  final int playerCount;
  final int startSeat;
  final bool chain;
  int currentPlayer;
  final List<int> scores;
  final List<MallaHex> hexes = <MallaHex>[];
  final Map<String, MallaEdge> edges = <String, MallaEdge>{};
  final List<MallaMove> moves = <MallaMove>[];
  String lastMoveKey = '';

  bool get finished => scores.fold<int>(0, (a, b) => a + b) == hexes.length;

  List<MallaEdge> get legalEdges => <MallaEdge>[
    for (final edge in edges.values)
      if (edge.owner == null) edge,
  ];

  List<int> get winners {
    if (!finished) return const <int>[];
    final best = scores.reduce(math.max);
    return <int>[
      for (var i = 0; i < scores.length; i++)
        if (scores[i] == best) i,
    ];
  }

  MallaGame clone() {
    final copy = MallaGame(
      size: size,
      playerCount: playerCount,
      startSeat: startSeat,
      chain: chain,
    );
    copy.currentPlayer = currentPlayer;
    copy.lastMoveKey = lastMoveKey;
    copy.moves.addAll(moves);
    for (var i = 0; i < scores.length; i++) {
      copy.scores[i] = scores[i];
    }
    for (final entry in edges.entries) {
      copy.edges[entry.key]!.owner = entry.value.owner;
    }
    for (var i = 0; i < hexes.length; i++) {
      final source = hexes[i];
      final target = copy.hexes[i];
      target.drawnSides = source.drawnSides;
      target.owner = source.owner;
      for (var player = 0; player < playerCount; player++) {
        target.sidesByPlayer[player] = source.sidesByPlayer[player];
      }
    }
    return copy;
  }

  static MallaGame replay({
    required int size,
    required int playerCount,
    required int startSeat,
    required bool chain,
    required Iterable<MallaMove> moves,
  }) {
    final game = MallaGame(
      size: size,
      playerCount: playerCount,
      startSeat: startSeat,
      chain: chain,
    );
    for (final move in moves) {
      final result = game.applyMove(move.key, move.player);
      if (!result.accepted) {
        throw FormatException('Secuencia de Malla inválida en ${move.key}');
      }
    }
    return game;
  }

  MallaMoveResult applyMove(String key, int who) {
    final edge = edges[key];
    if (finished ||
        edge == null ||
        edge.owner != null ||
        who != currentPlayer) {
      return MallaMoveResult(
        accepted: false,
        player: who,
        capturedHexes: const <int>[],
        nextPlayer: currentPlayer,
        finished: finished,
      );
    }

    edge.owner = who;
    moves.add(MallaMove(key, who));
    lastMoveKey = key;
    final captured = <int>[];

    for (final index in edge.hexes) {
      final hex = hexes[index];
      hex.drawnSides += 1;
      hex.sidesByPlayer[who] += 1;
      // Regla canónica de Malla: cuatro lados del mismo jugador conquistan.
      // Si llega la sexta arista sin que nadie haya alcanzado cuatro, la
      // conquista quien dibujó esa sexta arista.
      if (hex.owner == null &&
          (hex.sidesByPlayer[who] >= 4 || hex.drawnSides == 6)) {
        hex.owner = who;
        scores[who] += 1;
        captured.add(index);
      }
    }

    if (!finished && !(chain && captured.isNotEmpty)) {
      currentPlayer = (currentPlayer + 1) % playerCount;
    }

    return MallaMoveResult(
      accepted: true,
      player: who,
      capturedHexes: List<int>.unmodifiable(captured),
      nextPlayer: currentPlayer,
      finished: finished,
    );
  }

  /// Cuántos hexágonos conquistaría [player] con esta arista.
  int potentialCaptures(MallaEdge edge, int player) {
    if (edge.owner != null) return -1;
    var captures = 0;
    for (final index in edge.hexes) {
      final hex = hexes[index];
      if (hex.owner != null) continue;
      if (hex.sidesByPlayer[player] + 1 >= 4 || hex.drawnSides == 5) {
        captures++;
      }
    }
    return captures;
  }

  /// Caso especial del logro «Último toque» del juego web.
  int lastTouchCapturesFor(MallaEdge edge, int player) {
    if (edge.owner != null) return 0;
    var count = 0;
    for (final index in edge.hexes) {
      final hex = hexes[index];
      if (hex.owner == null &&
          hex.drawnSides == 5 &&
          hex.sidesByPlayer[player] <= 2) {
        count++;
      }
    }
    return count;
  }

  void _buildBoard() {
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        final cx =
            pad +
            root3 * cellRadius / 2 +
            root3 * cellRadius * (col + .5 * (row & 1));
        final cy = pad + cellRadius + 1.5 * cellRadius * row;
        final vertices = <MallaPoint>[];
        for (var k = 0; k < 6; k++) {
          final angle = math.pi / 180 * (30 + 60 * k);
          vertices.add(
            MallaPoint(
              cx + cellRadius * math.cos(angle),
              cy + cellRadius * math.sin(angle),
            ),
          );
        }
        final hex = MallaHex(
          cx: cx,
          cy: cy,
          vertices: vertices,
          playerCount: playerCount,
        );
        final hexIndex = hexes.length;
        hexes.add(hex);

        for (var k = 0; k < 6; k++) {
          final p = vertices[k];
          final q = vertices[(k + 1) % 6];
          final a = p.wireKey;
          final b = q.wireKey;
          final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
          final edge = edges.putIfAbsent(
            key,
            () => MallaEdge(key: key, p: p, q: q),
          );
          edge.hexes.add(hexIndex);
          hex.edgeKeys.add(key);
        }
      }
    }
  }
}
