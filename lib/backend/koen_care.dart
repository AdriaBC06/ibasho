// Ibasho — Tama Kōen: cuidar un Tama a medias con un amigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'koen.dart';
import 'tama.dart';

/// Las monedas de cuidar a medias van por `earnings/koen_care`: [koenCareCoins]
/// de una vez, una sola vez al día por cuenta, cuando uno de los Tamas
/// compartidos ya ha comido y le han hecho un mimo hoy.
const String koenCareGame = 'koen_care';
const int koenCareCoins = 10;

const int _dayMs = 86400000;

/// Si a [tama] ya le han dado de comer y le han hecho un mimo hoy (día UTC),
/// lo haya hecho quien lo haya hecho. Las reglas miran lo mismo.
bool koenCareDone(Tama tama, int day) {
  bool today(DateTime? at) => at != null && at.millisecondsSinceEpoch >= day * _dayMs;
  return today(tama.care.lastFed) && today(tama.care.lastPetted);
}

/// Una oferta de cuidar a medias: la ficha del Tama, como la del parque, en
/// `/users/{amigo}/koenInbox/{dueño}`. Como mucho una por amigo.
@immutable
class KoenOffer {
  const KoenOffer({required this.from, required this.card});

  /// Quien la manda: el creador del Tama.
  final String from;
  final KoenCard card;

  String get tamaId => card.tamaId;

  static List<KoenOffer> listFrom(Object? raw) => [
    if (raw is Map)
      for (final e in raw.entries)
        if (KoenCard.fromJson('${e.key}', 0, e.value) case final card?)
          if (card.owner == '${e.key}') KoenOffer(from: '${e.key}', card: card),
  ]..sort((a, b) => a.card.at.compareTo(b.card.at));
}
