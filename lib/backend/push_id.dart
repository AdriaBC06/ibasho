// Ibasho — identificadores cronologicos para registros nuevos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

const String _alphabet =
    '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

final math.Random _random = math.Random.secure();
int _lastTime = -1;
final List<int> _lastRandom = List<int>.filled(12, 0);

/// Un id de 20 caracteres como los de `push()` de Firebase: los 8 primeros
/// codifican la hora y los 12 ultimos son azar. Ordenados como texto quedan en
/// orden de creacion, y dos ids del mismo milisegundo tampoco chocan.
///
/// Las reglas solo aceptan ids con esta forma: `^[-0-9A-Za-z_]{20}$`.
String generatePushId([DateTime? at]) {
  var time = (at ?? DateTime.now()).millisecondsSinceEpoch;
  final sameMoment = time == _lastTime;
  _lastTime = time;

  final head = List<String>.filled(8, '');
  for (var i = 7; i >= 0; i--) {
    head[i] = _alphabet[time % 64];
    time ~/= 64;
  }

  if (!sameMoment) {
    for (var i = 0; i < 12; i++) {
      _lastRandom[i] = _random.nextInt(64);
    }
  } else {
    // Mismo milisegundo: se incrementa el azar anterior para mantener el orden.
    var i = 11;
    while (i >= 0 && _lastRandom[i] == 63) {
      _lastRandom[i] = 0;
      i--;
    }
    if (i >= 0) _lastRandom[i]++;
  }
  return head.join() + _lastRandom.map((v) => _alphabet[v]).join();
}
