// Ibasho — Tama Kōen: fichas del parque y encuentros del día.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'tama.dart';

/// Huecos del parque por cuenta (`koen/park/0`, `1` y `2`).
const int koenSlots = 3;

/// Probabilidad (sobre 100) de que dos Tamas se encuentren un día.
const int koenMeetChance = 45;

/// Encuentros forzados (arrastrando) por pareja de Tamas y día.
const int koenDragsPerPair = 3;

/// Las zonas del parque. Cada encuentro pasa en una.
enum KoenZone { swings, slide, sandbox, pond, picnic, tree }

enum KoenSeason { spring, summer, autumn, winter }

/// La estación de [local]. En el hemisferio sur ([south]) va seis meses
/// cambiada: diciembre es verano y junio, invierno.
KoenSeason koenSeason(DateTime local, {bool south = false}) {
  final month = south ? (local.month + 5) % 12 + 1 : local.month;
  return switch (month) {
    3 || 4 || 5 => KoenSeason.spring,
    6 || 7 || 8 => KoenSeason.summer,
    9 || 10 || 11 => KoenSeason.autumn,
    _ => KoenSeason.winter,
  };
}

/// Los países del hemisferio sur (o con casi toda la gente en él), por su
/// código ISO. Se mira el país del idioma del dispositivo: no pide ubicación.
const koenSouthCountries = {
  'AR', 'AU', 'BO', 'BR', 'BW', 'CL', 'FJ', 'ID', 'LS', 'MG', 'MU', 'MW', 'MZ', 'NA', 'NZ', //
  'PE', 'PG', 'PY', 'SZ', 'TO', 'UY', 'WS', 'ZA', 'ZM', 'ZW', 'AO', 'SB', 'VU', 'NC', 'PF',
};

/// Si el país [countryCode] (ISO, como el del idioma del dispositivo) está
/// en el hemisferio sur. Sin país, norte.
bool koenSouthern(String? countryCode) => koenSouthCountries.contains(countryCode?.toUpperCase());

/// Luz del día de 0 (noche cerrada) a 1 (pleno día), con amanecer de 6 a 8 y
/// atardecer de 19 a 21.
double koenDaylight(DateTime local) {
  final h = local.hour + local.minute / 60;
  if (h < 6 || h >= 21) return 0;
  if (h < 8) return (h - 6) / 2;
  if (h < 19) return 1;
  return 1 - (h - 19) / 2;
}

/// FNV-1a de 32 bits: el mismo número en todos los móviles, a diferencia de
/// `String.hashCode`.
int koenHash(String text) {
  var h = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// La ficha de un Tama en el parque: lo que ven los amigos, sin abrirles
/// `tamas`. Vive en `/users/{holder}/koen/park/{slot}`.
@immutable
class KoenCard {
  const KoenCard({
    required this.holder,
    required this.slot,
    required this.tamaId,
    required this.owner,
    required this.name,
    required this.personality,
    required this.voice,
    required this.look,
    required this.at,
    this.duo,
  });

  /// La cuenta que lo ha traído al parque (en cuyo `koen/park` está).
  final String holder;
  final int slot;
  final String tamaId;

  /// Quien lo creó. Hoy coincide con [holder]; con los cuidados a medias
  /// puede traerlo el cuidador.
  final String owner;
  final String name;
  final TamaPersonality personality;
  final TamaVoice voice;
  final TamaLook look;

  /// Cuándo llegó al parque, en milisegundos.
  final int at;

  /// El otro Tama de su dúo (fase 5): los dos van juntos y se encuentran
  /// todos los días. Lo pone quien lo trae.
  final String? duo;

  /// Si [a] y [b] son los dos Tamas de un dúo.
  static bool duoPair(KoenCard a, KoenCard b) => a.duo == b.tamaId || b.duo == a.tamaId;

  factory KoenCard.ofTama(Tama tama, {required String holder, required int slot, required int at, String? duo}) =>
      KoenCard(
        holder: holder,
        slot: slot,
        tamaId: tama.id,
        owner: tama.creator,
        name: tama.name,
        personality: tama.personality,
        voice: tama.voice,
        look: tama.look,
        at: at,
        duo: duo,
      );

  static KoenCard? fromJson(String holder, int slot, Object? raw) {
    if (raw is! Map) return null;
    final id = raw['tamaId'];
    final owner = raw['owner'];
    if (id is! String || owner is! String) return null;
    return KoenCard(
      holder: holder,
      slot: slot,
      tamaId: id,
      owner: owner,
      name: (raw['name'] as String?) ?? '',
      personality: TamaPersonality.byName(raw['personality']),
      voice: TamaVoice.fromJson(raw['voice']),
      look: TamaLook.fromJson(raw['look']),
      at: (raw['at'] as num?)?.toInt() ?? 0,
      duo: raw['duo'] is String ? raw['duo'] as String : null,
    );
  }

  /// Los huecos de `koen/park`, tal como llegan (mapa o lista).
  static List<KoenCard> parkFromJson(String holder, Object? raw) {
    Object? at(int i) => switch (raw) {
      Map() => raw['$i'] ?? raw[i],
      List() => i < raw.length ? raw[i] : null,
      _ => null,
    };
    return [
      for (var i = 0; i < koenSlots; i++) ?KoenCard.fromJson(holder, i, at(i)),
    ];
  }

  Map<String, Object?> toJson() => {
    'tamaId': tamaId,
    'owner': owner,
    'name': name,
    'personality': personality.name,
    'voice': voice.toJson(),
    'look': look.toJson(),
    'at': at,
    'duo': ?duo,
  };

  /// Si la ficha ya no refleja a [tama] (le han cambiado el nombre, la ropa…)
  /// o su dúo ya no es [duo].
  bool staleFor(Tama tama, {String? duo}) =>
      duo != this.duo ||
      tama.name != name ||
      tama.personality != personality ||
      tama.voice != voice ||
      tama.look != look;

  /// Un Tama para dibujarlo (sin cuidados).
  Tama toTama() {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return Tama(
      id: tamaId,
      creator: owner,
      keeper: holder,
      name: name,
      personality: personality,
      voice: voice,
      look: look,
      createdAt: epoch,
      updatedAt: epoch,
    );
  }
}

/// Un encuentro entre dos Tamas un día.
@immutable
class KoenEncounter {
  const KoenEncounter({
    required this.a,
    required this.b,
    required this.zone,
    required this.hour,
    required this.variant,
    this.inPlace = false,
  });

  /// Los dos Tamas, con `a.tamaId < b.tamaId`.
  final KoenCard a;
  final KoenCard b;
  final KoenZone zone;

  /// Hora del día (local, de 8 a 21) a la que pasa.
  final double hour;

  /// Qué hacen en la zona, para variar la animación (0–3).
  final int variant;

  /// Si se encuentran donde estén, paseando, en vez de ir a [zone].
  final bool inPlace;

  String get pairKey => koenPairKey(a.tamaId, b.tamaId);

  /// Si los dueños son cuentas distintas: solo así da monedas y amistad
  /// entre jugadores.
  bool get crossAccount => a.holder != b.holder;

  /// Los dos Tamas de un dúo.
  bool get duo => KoenCard.duoPair(a, b);

  bool involves(String tamaId) => a.tamaId == tamaId || b.tamaId == tamaId;

  KoenCard other(String tamaId) => a.tamaId == tamaId ? b : a;
}

/// La clave de una pareja: los dos ids ordenados.
String koenPairKey(String x, String y) => x.compareTo(y) < 0 ? '${x}_$y' : '${y}_$x';

/// Los encuentros del día [day] (UTC, como `bonusDay`) entre [cards].
///
/// Cada pareja se decide sola con `hash(día, pareja)`, así que el resultado
/// no depende de quién mire ni de qué otros Tamas vea: A y B ven lo mismo de
/// sus Tamas aunque cada uno tenga amigos distintos. Solo se juntan Tamas
/// de la misma cuenta o de cuentas amigas ([friends] dice si dos cuentas lo
/// son). Los dos Tamas de un dúo se encuentran todos los días.
List<KoenEncounter> koenEncounters({
  required int day,
  required List<KoenCard> cards,
  required bool Function(String accountA, String accountB) friends,
}) {
  final sorted = [...cards]..sort((x, y) => x.tamaId.compareTo(y.tamaId));
  final out = <KoenEncounter>[];
  for (var i = 0; i < sorted.length; i++) {
    for (var j = i + 1; j < sorted.length; j++) {
      final a = sorted[i];
      final b = sorted[j];
      if (a.tamaId == b.tamaId) continue;
      if (a.holder != b.holder && !friends(a.holder, b.holder)) continue;
      final h = koenHash('$day:${a.tamaId}:${b.tamaId}');
      if (h % 100 >= koenMeetChance && !KoenCard.duoPair(a, b)) continue;
      final r = koenHash('$h:zone');
      out.add(KoenEncounter(
        a: a,
        b: b,
        zone: KoenZone.values[r % KoenZone.values.length],
        hour: 8 + (r >> 8) % 1300 / 100,
        variant: (r >> 20) % 4,
        inPlace: (r >> 24) % 5 < 2,
      ));
    }
  }
  out.sort((x, y) => x.hour.compareTo(y.hour));
  return out;
}

/// Lo bien que se conocen dos Tamas, de 0 (nada) a 1 (muy amigos).
///
/// Hasta que haya amistad de verdad (fase 3) sale de cuántos de los últimos
/// 30 días les ha tocado encontrarse: por azar son unos 13, así que se estira
/// de 8 a 19. Los de la misma cuenta ya se conocen de casa.
double koenCloseness(int day, KoenCard a, KoenCard b) {
  final pair = [a.tamaId, b.tamaId]..sort();
  var days = 0;
  for (var d = day - 29; d <= day; d++) {
    if (koenHash('$d:${pair[0]}:${pair[1]}') % 100 < koenMeetChance) days++;
  }
  final c = ((days - 8) / 11).clamp(0.0, 1.0);
  return a.holder == b.holder ? math.max(c, .6) : c;
}
