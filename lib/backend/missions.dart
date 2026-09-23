// Ibasho — las misiones: que hay que hacer y que da.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Cada mision es "haz X hoy" o "haz X esta semana", donde X ya deja una señal
// en `/users/{cuenta}/missions/signal/{evento}` (o ya tenia una en otro sitio,
// como el bono diario) en el momento en que pasa. Cobrar una mision escribe
// un recibo que las reglas comprueban contra esa señal y sube los tickets en
// la misma escritura.

import 'gacha.dart';

/// Lo que cuenta una mision: una accion que ya deja una señal propia.
enum MissionEvent { feed, play, pull, buy }

/// Las cuatro son validas para cobrar en cualquier momento (lo dicen las
/// reglas); el reparto diario solo decide cuales tres se enseñan hoy, para
/// que no sea siempre la misma lista.
List<MissionEvent> dailyMissionsFor(int day) {
  final order = List<MissionEvent>.from(MissionEvent.values);
  // Fisher-Yates con el mismo hash multiplicativo de Knuth que usa
  // `loginBonusFor`: determinista y bien repartido.
  var seed = day;
  int shuffled() {
    seed = seed * 2654435761 % 4294967296;
    return seed;
  }

  for (var i = order.length - 1; i > 0; i--) {
    final j = shuffled() % (i + 1);
    final tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }
  return order.take(3).toList(growable: false);
}

/// Lo que da una mision diaria cobrada.
const int dailyMissionReward = 1;

/// Las dos misiones semanales, fijas: no roban ninguna a la diaria (hacen la
/// misma señal, pero valen para la semana entera).
enum WeeklyMission { pull, buy }

/// Lo que da cada mision semanal.
const Map<WeeklyMission, (TicketKind, int)> weeklyMissionReward = {
  WeeklyMission.pull: (TicketKind.kinken, 1),
  WeeklyMission.buy: (TicketKind.gachaken, 3),
};

MissionEvent _eventOf(WeeklyMission m) => switch (m) {
      WeeklyMission.pull => MissionEvent.pull,
      WeeklyMission.buy => MissionEvent.buy,
    };

extension WeeklyMissionEvent on WeeklyMission {
  MissionEvent get event => _eventOf(this);
}
