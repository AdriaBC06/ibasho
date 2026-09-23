// Ibasho — una sola conexion de la cuenta repartida entre todos sus nodos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/user_mux.dart';

void main() {
  test('una sola suscripcion sirve a todos los hijos', () async {
    var opened = 0;
    final source = StreamController<DatabaseEvent>.broadcast();
    final mux = UserNodeMux(source: () {
      opened++;
      return source.stream;
    });

    final coins = <Object?>[];
    final tickets = <Object?>[];
    final a = mux.child('/coins').listen((e) => coins.add(e.data));
    final b = mux.child('/tickets').listen((e) => tickets.add(e.data));
    await Future<void>.delayed(Duration.zero);

    expect(opened, 1, reason: 'dos nodos, una conexion');

    // El primer `put` de la cuenta entera llega a los dos.
    source.add(DatabaseEvent(
      path: '/',
      data: <String, Object?>{
        'coins': 40,
        'tickets': <String, Object?>{'gachaken': 3},
      },
      isPatch: false,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(coins, <Object?>[40]);
    expect(tickets, <Object?>[
      <String, Object?>{'gachaken': 3}
    ]);

    // Un cambio en un hijo solo despierta a quien mira esa rama.
    source.add(DatabaseEvent(path: '/tickets/gachaken', data: 2, isPatch: false));
    await Future<void>.delayed(Duration.zero);
    expect(coins.length, 1, reason: 'las monedas no se han tocado');
    expect(tickets.last, <String, Object?>{'gachaken': 2});

    await a.cancel();
    await b.cancel();
    await source.close();
  });

  test('un hijo que llega tarde recibe lo que ya hay', () async {
    final source = StreamController<DatabaseEvent>.broadcast();
    final mux = UserNodeMux(source: () => source.stream);

    final first = mux.child('/coins').listen((_) {});
    await Future<void>.delayed(Duration.zero);
    source.add(DatabaseEvent(
      path: '/',
      data: <String, Object?>{'coins': 7, 'pantry': <String, Object?>{'cookie': 5}},
      isPatch: false,
    ));
    await Future<void>.delayed(Duration.zero);

    final pantry = <Object?>[];
    final late = mux.child('/pantry').listen((e) => pantry.add(e.data));
    await Future<void>.delayed(Duration.zero);
    expect(pantry, <Object?>[
      <String, Object?>{'cookie': 5}
    ]);

    await first.cancel();
    await late.cancel();
    await source.close();
  });
}
