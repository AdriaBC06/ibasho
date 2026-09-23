// Ibasho — pruebas del catalogo de misiones.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/missions.dart';

void main() {
  group('dailyMissionsFor', () {
    test('elige siempre tres de las cuatro, sin repetir', () {
      for (var day = 0; day < 60; day++) {
        final picked = dailyMissionsFor(day);
        expect(picked.length, 3);
        expect(picked.toSet().length, 3);
      }
    });

    test('es determinista: el mismo dia da siempre la misma lista', () {
      expect(dailyMissionsFor(20719), dailyMissionsFor(20719));
    });

    test('no siempre elige las mismas tres', () {
      final lists = {for (var d = 0; d < 30; d++) dailyMissionsFor(d).join(',')};
      expect(lists.length, greaterThan(1));
    });
  });

  group('WeeklyMission', () {
    test('cada mision semanal tiene su recompensa', () {
      for (final m in WeeklyMission.values) {
        expect(weeklyMissionReward.containsKey(m), isTrue);
        expect(weeklyMissionReward[m]!.$2, greaterThan(0));
      }
    });

    test('el evento de cada mision semanal es el que corresponde', () {
      expect(WeeklyMission.pull.event, MissionEvent.pull);
      expect(WeeklyMission.buy.event, MissionEvent.buy);
    });
  });
}
