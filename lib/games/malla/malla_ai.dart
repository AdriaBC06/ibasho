// Malla — IA portada desde public/app.js.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'malla_game.dart';

enum MallaDifficulty { easy, normal, hard }

abstract final class MallaAi {
  static String? choose(
    MallaGame game, {
    required MallaDifficulty difficulty,
    required int player,
    math.Random? random,
  }) {
    final rng = random ?? math.Random();
    return switch (difficulty) {
      MallaDifficulty.easy => _easy(game, player, rng),
      MallaDifficulty.normal => _normal(game, player, rng),
      MallaDifficulty.hard => _hard(game, player, rng),
    };
  }

  static double _evaluate(MallaGame game, int player) {
    final others = <int>[
      for (var i = 0; i < game.scores.length; i++)
        if (i != player) game.scores[i],
    ];
    final bestOther = others.isEmpty ? 0 : others.reduce(math.max);
    var value = (game.scores[player] - bestOther) * 145.0;
    var deadEdges = 0;

    for (final hex in game.hexes) {
      if (hex.owner == player) {
        value += 22;
        continue;
      }
      if (hex.owner != null) {
        value -= 11;
        continue;
      }
      final me = hex.sidesByPlayer[player];
      var opponentMax = 0;
      for (var i = 0; i < hex.sidesByPlayer.length; i++) {
        if (i != player) {
          opponentMax = math.max(opponentMax, hex.sidesByPlayer[i]);
        }
      }
      final free = 6 - hex.drawnSides;
      value += (me - opponentMax) * 3.2;
      if (me == 3 && free > 0) value += 11;
      if (opponentMax >= 3 && me < 4) value -= 10;
      if (hex.drawnSides == 5) value += game.currentPlayer == player ? 10 : -5;
    }

    for (final edge in game.edges.values) {
      if (edge.owner == null &&
          edge.hexes.every((i) => game.hexes[i].owner != null)) {
        deadEdges++;
      }
    }
    if (deadEdges.isOdd) value += game.currentPlayer == player ? 1.8 : -1.2;
    return value;
  }

  static double _priority(MallaGame game, MallaEdge edge, int player) {
    var priority = 0.0;
    for (final index in edge.hexes) {
      final hex = game.hexes[index];
      if (hex.owner != null) {
        priority += .35;
        continue;
      }
      var opponentMax = 0;
      for (var i = 0; i < hex.sidesByPlayer.length; i++) {
        if (i != player) {
          opponentMax = math.max(opponentMax, hex.sidesByPlayer[i]);
        }
      }
      final captures =
          hex.sidesByPlayer[player] + 1 >= 4 || hex.drawnSides == 5;
      if (captures) priority += 56 + (game.chain ? 16 : 0);
      if (opponentMax >= 3) priority += 12;
      priority += hex.sidesByPlayer[player] * 2.2 - opponentMax;
    }
    return priority;
  }

  static String? _easy(MallaGame game, int player, math.Random rng) {
    final free = game.legalEdges;
    if (free.isEmpty) return null;
    final captures = <MallaEdge>[
      for (final edge in free)
        if (game.potentialCaptures(edge, player) > 0) edge,
    ];
    if (captures.isNotEmpty && rng.nextDouble() < .72) {
      return captures[rng.nextInt(captures.length)].key;
    }
    return free[rng.nextInt(free.length)].key;
  }

  static String? _normal(MallaGame game, int player, math.Random rng) {
    final free = game.legalEdges;
    if (free.isEmpty) return null;
    var best = double.negativeInfinity;
    final picks = <String>[];
    for (final edge in free) {
      final sim = game.clone();
      final candidate = sim.edges[edge.key]!;
      final priority = _priority(sim, candidate, player);
      sim.applyMove(edge.key, player);
      final value = _evaluate(sim, player) + priority * 1.15;
      if (value > best + .001) {
        best = value;
        picks
          ..clear()
          ..add(edge.key);
      } else if ((value - best).abs() < .001) {
        picks.add(edge.key);
      }
    }
    return picks[rng.nextInt(picks.length)];
  }

  static String? _hard(MallaGame game, int player, math.Random rng) {
    var candidates = List<MallaEdge>.from(game.legalEdges)
      ..sort(
        (a, b) =>
            _priority(game, b, player).compareTo(_priority(game, a, player)),
      );
    final candidateLimit = switch (game.size) {
      3 => 28,
      4 => 21,
      5 => 16,
      _ => 12,
    };
    if (candidates.length > candidateLimit) {
      candidates = candidates.sublist(0, candidateLimit);
    }

    var best = double.negativeInfinity;
    final picks = <String>[];
    for (final edge in candidates) {
      final sim = game.clone();
      sim.applyMove(edge.key, player);
      var value =
          _evaluate(sim, player) +
          _priority(sim, sim.edges[edge.key]!, player) * .72;
      if (!sim.finished) {
        final actor = sim.currentPlayer;
        var replies = List<MallaEdge>.from(sim.legalEdges)
          ..sort(
            (a, b) =>
                _priority(sim, b, actor).compareTo(_priority(sim, a, actor)),
          );
        final replyLimit = switch (game.size) {
          3 => 20,
          4 => 14,
          _ => 10,
        };
        if (replies.length > replyLimit) {
          replies = replies.sublist(0, replyLimit);
        }

        if (actor == player) {
          var follow = double.negativeInfinity;
          for (final reply in replies) {
            final next = sim.clone();
            next.applyMove(reply.key, actor);
            follow = math.max(follow, _evaluate(next, player));
          }
          if (follow.isFinite) value = .35 * value + .65 * follow;
        } else {
          var worst = double.infinity;
          for (final reply in replies) {
            final next = sim.clone();
            next.applyMove(reply.key, actor);
            worst = math.min(worst, _evaluate(next, player));
          }
          if (worst.isFinite) value = .35 * value + .65 * worst;
        }
      }

      if (value > best + .001) {
        best = value;
        picks
          ..clear()
          ..add(edge.key);
      } else if ((value - best).abs() < .001) {
        picks.add(edge.key);
      }
    }
    if (picks.isEmpty) return _normal(game, player, rng);
    return picks[rng.nextInt(picks.length)];
  }
}
