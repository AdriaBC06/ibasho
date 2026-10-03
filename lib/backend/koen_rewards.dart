// Ibasho — Tama Kōen: lo que da el parque (monedas, regalos y recuerdos).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'koen.dart';
import 'tama.dart';

/// El juego del parque en `earnings`. Es gratis, como Odori, con el tope de
/// siempre (20 al día).
const String koenGame = 'koen';

/// Lo que da cada encuentro de un Tama propio con el de un amigo.
const int koenCoinsPerMeet = 5;

const int _weekMs = 604800000;

/// La semana (como la de la tienda): `floor(ms / 604800000)`.
int koenWeek(DateTime now) => now.toUtc().millisecondsSinceEpoch ~/ _weekMs;

/// Cuándo pasa [e] hoy, en hora local.
DateTime koenMeetAt(KoenEncounter e, DateTime now) {
  final minutes = (e.hour * 60).round();
  return DateTime(now.year, now.month, now.day).add(Duration(minutes: minutes));
}

/// Si [e] da monedas a [me]: un Tama suyo con el de otra cuenta.
bool koenPays(KoenEncounter e, String me) => e.crossAccount && (e.a.holder == me || e.b.holder == me);

/// Los encuentros de hoy que ya han pasado a [now] y en los que estaban los
/// dos en el parque, por orden de hora.
List<KoenEncounter> koenDone(List<KoenEncounter> today, DateTime now) {
  final out = [
    for (final e in today)
      if (!koenMeetAt(e, now).isAfter(now) &&
          koenMeetAt(e, now).millisecondsSinceEpoch >= (e.a.at > e.b.at ? e.a.at : e.b.at))
        e,
  ]..sort((x, y) => x.hour.compareTo(y.hour));
  return out;
}

/// La chuche que traen hoy de regalo: sale del día y de la cuenta, así que es
/// la misma aunque se abra desde otro móvil.
TamaFood koenGiftFood(int day, String me) =>
    TamaFood.values[koenHash('$day:$me:gift') % TamaFood.values.length];

/// Los recuerdos del álbum. Cada uno es una postal: una zona del parque
/// ([focus], o el parque entero), con su estación y su luz, y la cara que
/// ponen ([mood], el nombre de un `KoenMood`).
enum KoenMemory {
  first(mood: 'greet'),
  swings(focus: KoenZone.swings, mood: 'laugh'),
  slide(focus: KoenZone.slide, mood: 'surprise'),
  sandbox(focus: KoenZone.sandbox, mood: 'happy'),
  pond(focus: KoenZone.pond, mood: 'curious'),
  picnic(focus: KoenZone.picnic, mood: 'happy'),
  tree(focus: KoenZone.tree, mood: 'sing'),
  stroll(mood: 'greet'),
  spring(season: KoenSeason.spring, mood: 'happy'),
  summer(season: KoenSeason.summer, mood: 'laugh'),
  autumn(season: KoenSeason.autumn, mood: 'curious'),
  winter(season: KoenSeason.winter, mood: 'surprise'),
  hanami(focus: KoenZone.tree, season: KoenSeason.spring, mood: 'love'),
  splash(focus: KoenZone.pond, season: KoenSeason.summer, mood: 'laugh'),
  momiji(focus: KoenZone.picnic, season: KoenSeason.autumn, mood: 'sing'),
  snowman(focus: KoenZone.sandbox, season: KoenSeason.winter, mood: 'happy'),
  morning(daylight: .7, mood: 'sleepy'),
  dusk(daylight: .5, mood: 'sing'),
  fireflies(daylight: .1, mood: 'love'),
  siblings(mood: 'happy'),
  friendsOfFriends(mood: 'curious'),
  dragged(mood: 'surprise'),
  besties(mood: 'love'),
  busyDay(mood: 'laugh'),
  duo(mood: 'love');

  const KoenMemory({this.focus, this.season, this.daylight = 1, required this.mood});

  final KoenZone? focus;
  final KoenSeason? season;
  final double daylight;
  final String mood;

  static KoenMemory? byName(String name) => values.where((m) => m.name == name).firstOrNull;
}

/// Los recuerdos que deja un encuentro.
///
/// - [me]: la cuenta que mira; los encuentros sin Tamas suyos solo dejan el
///   de «amigos de amigos».
/// - [season]: la estación de hoy.
/// - [closeness]: la amistad de la pareja (`koenCloseness`).
/// - [dragged]: si lo ha forzado arrastrando.
/// - [paidToday]: cuántos encuentros con amigos lleva hoy, contando este.
Set<KoenMemory> koenMemoriesOf(
  KoenEncounter e, {
  required String me,
  required KoenSeason season,
  required double closeness,
  bool dragged = false,
  int paidToday = 0,
}) {
  final mine = e.a.holder == me || e.b.holder == me;
  if (!mine) return {if (e.crossAccount) KoenMemory.friendsOfFriends};
  final out = <KoenMemory>{KoenMemory.first};
  final zone = e.inPlace || dragged ? null : e.zone;
  if (zone == null) {
    out.add(KoenMemory.stroll);
  } else {
    out.add(KoenMemory.values.firstWhere((m) => m.focus == zone && m.season == null));
  }
  out.add(KoenMemory.values.firstWhere((m) => m.season == season && m.focus == null));
  for (final m in KoenMemory.values) {
    if (m.focus != null && m.season == season && m.focus == zone) out.add(m);
  }
  if (!dragged) {
    if (e.hour < 9) out.add(KoenMemory.morning);
    if (e.hour >= 19 && e.hour < 20.25) out.add(KoenMemory.dusk);
    if (e.hour >= 20.25) out.add(KoenMemory.fireflies);
  }
  if (!e.crossAccount) out.add(KoenMemory.siblings);
  if (dragged) out.add(KoenMemory.dragged);
  if (closeness >= .7) out.add(KoenMemory.besties);
  if (paidToday >= 3) out.add(KoenMemory.busyDay);
  if (e.duo) out.add(KoenMemory.duo);
  return out;
}
