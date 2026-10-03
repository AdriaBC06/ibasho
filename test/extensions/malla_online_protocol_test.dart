// Malla — pruebas del contrato HTTP compartido Web ↔ Ibasho.
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/malla/malla_online.dart';

void main() {
  test('el host usa exclusivamente el endpoint oficial de Malla', () {
    expect(
      MallaOnlineClient.endpoint.toString(),
      'https://mallagame.netlify.app/.netlify/functions/room',
    );
    expect(
      MallaOnlineClient().inviteUri('ABC123').toString(),
      'https://mallagame.netlify.app/?sala=ABC123',
    );
  });

  test('parsea el estado sanitizado de room.mjs y lo reproduce', () {
    final state = MallaRoomState.fromJson(<String, Object?>{
      'code': 'ABC123',
      'size': 3,
      'playerCount': 2,
      'joinedCount': 2,
      'seat': 0,
      'started': true,
      'markers': <Object?>['A', 'B'],
      'colors': <Object?>['#397d79', '#bd6f57'],
      'moves': <Object?>[],
      'turn': 0,
      'startSeat': 0,
      'score': <Object?>[0, 0],
      'over': false,
      'endedReason': '',
      'abandonedBy': null,
      'rematch': <Object?>[false, false],
      'series': <Object?>[0, 0],
      'draws': 0,
      'version': 2,
      'round': 1,
      'chain': false,
    });
    final game = state.toGame();
    expect(game.size, 3);
    expect(game.playerCount, 2);
    expect(game.currentPlayer, 0);
    expect(game.edges, hasLength(38));
  });

  test(
    'un abandono puede cerrar la sala sin afirmar que el tablero terminó naturalmente',
    () {
      final state = MallaRoomState.fromJson(<String, Object?>{
        'code': 'XYZ789',
        'size': 3,
        'playerCount': 2,
        'joinedCount': 2,
        'seat': 1,
        'started': true,
        'markers': <Object?>['A', 'B'],
        'colors': <Object?>['#397d79', '#bd6f57'],
        'moves': <Object?>[],
        'turn': 0,
        'startSeat': 0,
        'score': <Object?>[0, 0],
        'over': true,
        'endedReason': 'abandon',
        'abandonedBy': 0,
        'rematch': <Object?>[false, false],
        'series': <Object?>[0, 0],
        'draws': 0,
        'version': 3,
        'round': 1,
        'chain': false,
      });
      expect(state.naturalEnd, isFalse);
      expect(() => state.toGame(), returnsNormally);
    },
  );

  test('rechaza listas de jugador incompatibles con el protocolo', () {
    expect(
      () => MallaRoomState.fromJson(<String, Object?>{
        'code': 'ABC123',
        'size': 3,
        'playerCount': 3,
        'joinedCount': 1,
        'seat': 0,
        'started': false,
        'markers': <Object?>['A'],
        'colors': <Object?>['#397d79'],
        'moves': <Object?>[],
        'turn': 0,
        'startSeat': 0,
        'score': <Object?>[0],
        'over': false,
        'rematch': <Object?>[false],
        'series': <Object?>[0],
        'draws': 0,
        'version': 1,
        'round': 1,
        'chain': false,
      }),
      throwsFormatException,
    );
  });
}
