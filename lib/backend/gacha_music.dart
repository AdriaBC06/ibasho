// Ibasho — la musica del gacha: pistas que se ganan jugando al pinball.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Una pista de este catalogo no se "equipa": una vez ganada, aparece en la
// lista de musica del menu de Ajustes junto a las de serie (ver
// `lib/state/music_library.dart` y `settings_channel.dart`). El audio en si
// vive en `MusicTrack` (`lib/audio/audio_service.dart`); aqui solo la rareza
// y la clave con la que se guarda en `/users/{uid}/prizes`.

import 'gacha.dart';

/// Una pista de musica del gacha. La clave que se guarda en
/// `/users/{uid}/prizes` es `mu_<id>`.
class GachaMusicTrack {
  const GachaMusicTrack(this.id, this.rarity);

  final String id;
  final Rarity rarity;

  String get key => 'mu_$id';
}

/// Las seis pistas del gacha, de menos a mas rara. Con solo seis huecos (no
/// dieciseis, como fondos o premios) el reparto se aprieta: dos N, una R,
/// una SR, una UR y una ∞, la mas elaborada de todas.
const List<GachaMusicTrack> gachaMusicTracks = <GachaMusicTrack>[
  GachaMusicTrack('nana', Rarity.n),
  GachaMusicTrack('carrillon', Rarity.n),
  GachaMusicTrack('lofi', Rarity.r),
  GachaMusicTrack('feria', Rarity.sr),
  GachaMusicTrack('abrigo', Rarity.ur),
  GachaMusicTrack('cenit', Rarity.mu),
];

final Map<String, GachaMusicTrack> _byKey = <String, GachaMusicTrack>{
  for (final m in gachaMusicTracks) m.key: m,
};

final Map<String, GachaMusicTrack> _byId = <String, GachaMusicTrack>{
  for (final m in gachaMusicTracks) m.id: m,
};

/// La pista con clave [key] (`mu_nana`), o `null` si esta version de la app
/// no la conoce.
GachaMusicTrack? gachaMusicByKey(String? key) =>
    key == null ? null : _byKey[key];

/// La pista con `id` (`nana`, sin el prefijo), o `null` si no existe.
GachaMusicTrack? gachaMusicById(String? id) =>
    id == null || id.isEmpty ? null : _byId[id];

/// Las pistas de [rarity], en el orden del catalogo.
List<GachaMusicTrack> gachaMusicOf(Rarity rarity) =>
    gachaMusicTracks.where((m) => m.rarity == rarity).toList(growable: false);
