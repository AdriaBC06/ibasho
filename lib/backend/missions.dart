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
///
/// `pet`, `gift`, `koen` y `chat` llegaron en la 0.9.0: acariciar a un Tama,
/// abrir el regalo del Yatai, mandar un Tama al parque y mandar un mensaje.
enum MissionEvent { feed, play, pull, buy, pet, gift, koen, chat }

/// Cuantas misiones diarias se enseñan cada dia.
const int dailyMissionCount = 4;

/// Todas son validas para cobrar en cualquier momento (lo dicen las reglas);
/// el reparto diario solo decide cuales [dailyMissionCount] se enseñan hoy,
/// para que no sea siempre la misma lista.
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
  return order.take(dailyMissionCount).toList(growable: false);
}

/// Lo que da una mision diaria cobrada.
const int dailyMissionReward = 1;

/// Las misiones semanales de una vez, fijas: no roban ninguna a la diaria
/// (hacen la misma señal, pero valen para la semana entera).
enum WeeklyMission { pull, buy, koen, chat }

/// Lo que da cada mision semanal.
const Map<WeeklyMission, (TicketKind, int)> weeklyMissionReward = {
  WeeklyMission.pull: (TicketKind.kinken, 1),
  WeeklyMission.buy: (TicketKind.gachaken, 3),
  WeeklyMission.koen: (TicketKind.gachaken, 2),
  WeeklyMission.chat: (TicketKind.gachaken, 2),
};

MissionEvent _eventOf(WeeklyMission m) => switch (m) {
      WeeklyMission.pull => MissionEvent.pull,
      WeeklyMission.buy => MissionEvent.buy,
      WeeklyMission.koen => MissionEvent.koen,
      WeeklyMission.chat => MissionEvent.chat,
    };

extension WeeklyMissionEvent on WeeklyMission {
  MissionEvent get event => _eventOf(this);
}

/// Las semanales que se repiten: cada [RepeatMission.step] veces que pasa su
/// señal en la semana se puede cobrar una vez, hasta [repeatMissionTimes].
/// Las cuentan los `missions/tally/{evento}` de la semana.
enum RepeatMission {
  play(MissionEvent.play, 5),
  feed(MissionEvent.feed, 5),
  pet(MissionEvent.pet, 5);

  const RepeatMission(this.event, this.step);

  final MissionEvent event;

  /// Veces que tiene que pasar la señal para cada cobro.
  final int step;
}

/// Veces que se puede cobrar cada repetible por semana.
const int repeatMissionTimes = 3;

/// Lo que da cada cobro de una repetible.
const int repeatMissionReward = 1;
