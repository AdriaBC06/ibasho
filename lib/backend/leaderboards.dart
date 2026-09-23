// Ibasho — el catalogo de clasificaciones: una tabla por juego, con premio en
// tickets del gacha para el top 3.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'gacha.dart';

/// Una tabla de clasificacion: una por juego (o por nivel, en el buscaminas).
///
/// El sorteo de quien gana lo hace la app, igual que el gacha: las reglas
/// solo comprueban la forma. Cada cuenta manda su propia puntuacion (solo si
/// mejora la que ya tenia y solo del periodo en curso) y cualquier cliente,
/// cuando el periodo ya ha cerrado, calcula el top 3 leyendo las
/// puntuaciones publicas de ese periodo y lo escribe una sola vez.
enum LeaderboardGame {
  minesweeperEasy,
  minesweeperMedium,
  minesweeperHard,
  tsumiki,
  nihongo;

  /// La clave del juego en `/leaderboards/{clave}` y en las reglas.
  String get key => switch (this) {
        LeaderboardGame.minesweeperEasy => 'minesweeper_easy',
        LeaderboardGame.minesweeperMedium => 'minesweeper_medium',
        LeaderboardGame.minesweeperHard => 'minesweeper_hard',
        LeaderboardGame.tsumiki => 'tsumiki',
        LeaderboardGame.nihongo => 'nihongo',
      };

  /// Buscaminas es por tiempo: menor es mejor. Tsumiki y Nihongo son por
  /// puntos: mayor es mejor.
  bool get lowerIsBetter => switch (this) {
        LeaderboardGame.minesweeperEasy ||
        LeaderboardGame.minesweeperMedium ||
        LeaderboardGame.minesweeperHard =>
          true,
        LeaderboardGame.tsumiki || LeaderboardGame.nihongo => false,
      };

  /// El tope que las reglas dejan escribir para este juego: milisegundos para
  /// el buscaminas, puntos para los demas.
  int get maxScore => lowerIsBetter ? 3600000 : 999999;

  static LeaderboardGame? byKey(String key) {
    for (final g in values) {
      if (g.key == key) return g;
    }
    return null;
  }
}

/// Cuantos tickets da cada puesto del top 3, por tabla diaria o semanal. Las
/// reglas exigen exactamente esto.
Map<TicketKind, int>? leaderboardReward({required bool weekly, required int rank}) {
  if (weekly) {
    return switch (rank) {
      1 => {TicketKind.kinken: 1},
      2 => {TicketKind.gachaken: 3},
      3 => {TicketKind.gachaken: 2},
      _ => null,
    };
  }
  return switch (rank) {
    1 => {TicketKind.gachaken: 2},
    2 => {TicketKind.gachaken: 1},
    3 => {TicketKind.gachaken: 1},
    _ => null,
  };
}
