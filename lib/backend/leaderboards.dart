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
  nihongo,
  odori,
  odoriButai,
  ohirune;

  /// La clave del juego en `/leaderboards/{clave}` y en las reglas.
  String get key => switch (this) {
        LeaderboardGame.minesweeperEasy => 'minesweeper_easy',
        LeaderboardGame.minesweeperMedium => 'minesweeper_medium',
        LeaderboardGame.minesweeperHard => 'minesweeper_hard',
        LeaderboardGame.tsumiki => 'tsumiki',
        LeaderboardGame.nihongo => 'nihongo',
        LeaderboardGame.odori => 'odori',
        LeaderboardGame.odoriButai => 'odori_butai',
        LeaderboardGame.ohirune => 'ohirune',
      };

  /// Buscaminas y Ohirune son por tiempo: menor es mejor. Tsumiki, Nihongo
  /// y Odori (Taki y Butai) son por puntos: mayor es mejor.
  bool get lowerIsBetter => switch (this) {
        LeaderboardGame.minesweeperEasy ||
        LeaderboardGame.minesweeperMedium ||
        LeaderboardGame.minesweeperHard ||
        LeaderboardGame.ohirune =>
          true,
        LeaderboardGame.tsumiki ||
        LeaderboardGame.nihongo ||
        LeaderboardGame.odori ||
        LeaderboardGame.odoriButai =>
          false,
      };

  /// El tope que las reglas dejan escribir para este juego: milisegundos para
  /// el buscaminas y Ohirune, puntos para los demas. Odori llega al millon por partida y
  /// lo multiplica hasta ×1,5 segun la dificultad.
  int get maxScore => switch (this) {
        LeaderboardGame.odori || LeaderboardGame.odoriButai => 1500000,
        _ => lowerIsBetter ? 3600000 : 999999,
      };

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
