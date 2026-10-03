// Ibasho — pruebas del catalogo de misiones.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/missions.dart';
import 'package:ibasho/state/missions.dart';

void main() {
  group('dailyMissionsFor', () {
    test('elige siempre cuatro, sin repetir', () {
      for (var day = 0; day < 60; day++) {
        final picked = dailyMissionsFor(day);
        expect(picked.length, dailyMissionCount);
        expect(picked.toSet().length, dailyMissionCount);
      }
    });

    test('con los dias salen todas las misiones', () {
      final seen = {for (var d = 0; d < 60; d++) ...dailyMissionsFor(d)};
      expect(seen, MissionEvent.values.toSet());
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
      expect(WeeklyMission.koen.event, MissionEvent.koen);
      expect(WeeklyMission.chat.event, MissionEvent.chat);
    });
  });

  group('repetibles', () {
    const week = 2900;

    test('cada cobro pide otras step veces, hasta tres', () {
      MissionsState at(int n, int claimed) => MissionsState(
            tallies: {MissionEvent.play: (week, n)},
            repeatClaims: {
              week: {RepeatMission.play: claimed},
            },
            loaded: true,
          );
      expect(at(4, 0).canClaimRepeat(RepeatMission.play, week), isFalse);
      expect(at(5, 0).canClaimRepeat(RepeatMission.play, week), isTrue);
      expect(at(9, 1).canClaimRepeat(RepeatMission.play, week), isFalse);
      expect(at(10, 1).canClaimRepeat(RepeatMission.play, week), isTrue);
      expect(at(15, 2).canClaimRepeat(RepeatMission.play, week), isTrue);
      expect(at(40, 3).canClaimRepeat(RepeatMission.play, week), isFalse);
    });

    test('el recuento de otra semana no cuenta', () {
      const state = MissionsState(tallies: {MissionEvent.feed: (week - 1, 12)}, loaded: true);
      expect(state.tally(MissionEvent.feed, week), 0);
      expect(state.canClaimRepeat(RepeatMission.feed, week), isFalse);
    });
  });
}
