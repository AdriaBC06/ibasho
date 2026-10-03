// Malla — pruebas del motor nativo y su compatibilidad con la web.
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/game_host_registry.dart';
import 'package:ibasho/extensions/malla/malla_ai.dart';
import 'package:ibasho/extensions/malla/malla_game.dart';

void main() {
  test('Kōbō expone Malla pero no motores arbitrarios', () {
    expect(KoboGameHostRegistry.supports('malla'), isTrue);
    expect(KoboGameHostRegistry.supports('javascript'), isFalse);
    expect(KoboGameHostRegistry.supports('dart'), isFalse);
  });

  test(
    'la geometría genera exactamente las mismas cantidades de aristas que la web',
    () {
      const expected = <int, int>{
        1: 6,
        2: 19,
        3: 38,
        4: 63,
        5: 94,
        6: 131,
        7: 174,
      };
      for (final entry in expected.entries) {
        final game = MallaGame(
          size: entry.key,
          playerCount: 2,
          startSeat: 0,
          chain: false,
        );
        expect(
          game.edges,
          hasLength(entry.value),
          reason: '${entry.key}x${entry.key}',
        );
      }
    },
  );

  test('las primeras claves 3x3 son byte a byte las de app.js/room.mjs', () {
    final game = MallaGame(size: 3, playerCount: 2, startSeat: 0, chain: false);
    expect(game.edges.keys.take(6).toList(), <String>[
      '42.0,76.0|68.0,61.0',
      '16.0,61.0|42.0,76.0',
      '16.0,31.0|16.0,61.0',
      '16.0,31.0|42.0,16.0',
      '42.0,16.0|68.0,31.0',
      '68.0,31.0|68.0,61.0',
    ]);
  });

  test(
    'cuatro lados del mismo jugador conquistan antes de cerrar el hexágono',
    () {
      final game = MallaGame(
        size: 2,
        playerCount: 2,
        startSeat: 0,
        chain: false,
      );
      final target = game.hexes.first;
      final targetEdges = target.edgeKeys.map((k) => game.edges[k]!).toList();
      final fillers = game.edges.values
          .where((edge) => edge.hexes.every((index) => index != 0))
          .take(3)
          .toList();
      expect(fillers, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(game.applyMove(targetEdges[i].key, 0).accepted, isTrue);
        expect(game.applyMove(fillers[i].key, 1).accepted, isTrue);
      }
      expect(target.owner, isNull);
      final result = game.applyMove(targetEdges[3].key, 0);
      expect(result.accepted, isTrue);
      expect(result.capturedHexes, contains(0));
      expect(target.owner, 0);
      expect(target.drawnSides, 4);
    },
  );

  test(
    'si llega la sexta arista sin cuatro lados, conquista quien pone la sexta',
    () {
      final game = MallaGame(
        size: 1,
        playerCount: 2,
        startSeat: 0,
        chain: false,
      );
      final keys = game.edges.keys.toList();
      for (var i = 0; i < 6; i++) {
        expect(game.applyMove(keys[i], i.isEven ? 0 : 1).accepted, isTrue);
      }
      expect(game.finished, isTrue);
      expect(game.hexes.single.owner, 1);
      expect(game.scores, <int>[0, 1]);
    },
  );

  test('Cadena conserva el turno después de una conquista', () {
    final game = MallaGame(size: 2, playerCount: 2, startSeat: 0, chain: true);
    final target = game.hexes.first;
    final targetEdges = target.edgeKeys.map((k) => game.edges[k]!).toList();
    final fillers = game.edges.values
        .where((edge) => edge.hexes.every((index) => index != 0))
        .take(3)
        .toList();
    for (var i = 0; i < 3; i++) {
      game.applyMove(targetEdges[i].key, 0);
      game.applyMove(fillers[i].key, 1);
    }
    final result = game.applyMove(targetEdges[3].key, 0);
    expect(result.captured, 1);
    expect(result.nextPlayer, 0);
  });

  test('las tres dificultades de IA solo devuelven aristas legales', () {
    for (final difficulty in MallaDifficulty.values) {
      final game = MallaGame(
        size: 3,
        playerCount: 2,
        startSeat: 0,
        chain: false,
      );
      final key = MallaAi.choose(
        game,
        difficulty: difficulty,
        player: 0,
        random: math.Random(7),
      );
      expect(key, isNotNull);
      expect(game.edges[key]!.owner, isNull);
    }
  });

  test(
    'vector dorado de room.mjs: 3 jugadores produce el mismo turno y score',
    () {
      final game = MallaGame(
        size: 3,
        playerCount: 3,
        startSeat: 1,
        chain: false,
      );
      final keys = game.edges.keys.toList();
      for (var i = 0; i < 12; i++) {
        final player = game.currentPlayer;
        final result = game.applyMove(keys[i], player);
        expect(result.accepted, isTrue, reason: 'move ${i + 1}');
      }
      // Calculado ejecutando computeGame() del room.mjs original suministrado.
      expect(game.currentPlayer, 1);
      expect(game.scores, <int>[1, 0, 1]);
      expect(game.finished, isFalse);
    },
  );

  test(
    'vector dorado de room.mjs: Cadena conserva turno en la sexta arista',
    () {
      final game = MallaGame(
        size: 2,
        playerCount: 2,
        startSeat: 0,
        chain: true,
      );
      final keys = game.edges.keys.toList();
      for (var i = 0; i < 6; i++) {
        final result = game.applyMove(keys[i], game.currentPlayer);
        expect(result.accepted, isTrue, reason: 'move ${i + 1}');
      }
      // room.mjs da score [0,1] y turno 1 tras el sexto movimiento.
      expect(game.scores, <int>[0, 1]);
      expect(game.currentPlayer, 1);
      expect(game.finished, isFalse);
    },
  );

  test('replay reproduce turno, puntuación y propiedad', () {
    final original = MallaGame(
      size: 3,
      playerCount: 3,
      startSeat: 1,
      chain: false,
    );
    for (var i = 0; i < 9; i++) {
      final edge = original.legalEdges.first;
      original.applyMove(edge.key, original.currentPlayer);
    }
    final replay = MallaGame.replay(
      size: 3,
      playerCount: 3,
      startSeat: 1,
      chain: false,
      moves: original.moves,
    );
    expect(replay.currentPlayer, original.currentPlayer);
    expect(replay.scores, original.scores);
    expect(replay.moves.map((m) => m.key), original.moves.map((m) => m.key));
  });
}
