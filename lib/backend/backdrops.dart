// Ibasho — los fondos del gacha: colores y temas para el menu de inicio.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Un fondo no se pone en un Tama (ver `prizes.dart`): se equipa en Ajustes y
// se pinta detras de los paneles del menu de inicio (`ShellScreen`). El
// dibujo de cada uno vive en `lib/ui/widgets/backdrop_art.dart`; aqui solo el
// catalogo y la rareza.

import 'gacha.dart';

/// Un fondo del gacha. La clave que se guarda en `/users/{uid}/prizes` es
/// `bg_<id>`, hasta 16 letras en total (lo exigen las reglas del gacha).
class Backdrop {
  const Backdrop(this.id, this.rarity);

  final String id;
  final Rarity rarity;

  String get key => 'bg_$id';
}

/// Todos los fondos, de menos a mas raros. Reparto de rareza como los
/// premios que se ponen: 4 N, 4 R, 3 SR, 2 SSR, 2 UR y uno solo ∞.
const List<Backdrop> backdrops = <Backdrop>[
  Backdrop('sky', Rarity.n),
  Backdrop('coral', Rarity.n),
  Backdrop('mint', Rarity.n),
  Backdrop('peach', Rarity.n),
  Backdrop('lavender', Rarity.r),
  Backdrop('dusk', Rarity.r),
  Backdrop('sunrise', Rarity.r),
  Backdrop('lagoon', Rarity.r),
  Backdrop('aurora', Rarity.sr),
  Backdrop('candy', Rarity.sr),
  Backdrop('forest', Rarity.sr),
  Backdrop('sunset', Rarity.ssr),
  Backdrop('glacier', Rarity.ssr),
  Backdrop('phoenix', Rarity.ur),
  Backdrop('borealis', Rarity.ur),
  Backdrop('starfield', Rarity.mu),
];

final Map<String, Backdrop> _byKey = <String, Backdrop>{
  for (final b in backdrops) b.key: b,
};

final Map<String, Backdrop> _byId = <String, Backdrop>{
  for (final b in backdrops) b.id: b,
};

/// El fondo con clave [key] (`bg_sky`), o `null` si esta version de la app no
/// lo conoce.
Backdrop? backdropByKey(String? key) => key == null ? null : _byKey[key];

/// El fondo con `id` (`sky`, sin el prefijo), o `null` si no existe.
Backdrop? backdropById(String? id) =>
    id == null || id.isEmpty ? null : _byId[id];

/// Los fondos de [rarity], en el orden del catalogo.
List<Backdrop> backdropsOf(Rarity rarity) =>
    backdrops.where((b) => b.rarity == rarity).toList(growable: false);
