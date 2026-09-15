// Ibasho — catalogo de canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../widgets/glyphs.dart';
import 'admin_channel.dart';
import 'coming_soon_channel.dart';
import 'debug_channel.dart';
import 'profile_channel.dart';
import 'settings_channel.dart';

/// Un hueco de la rejilla.
@immutable
class ChannelSpec {
  const ChannelSpec({
    required this.id,
    required this.glyph,
    required this.label,
    required this.builder,
    this.empty = false,
  });

  final String id;
  final Glyph glyph;
  final String Function(L) label;
  final WidgetBuilder builder;

  /// Una ranura libre: se ve hundida y lleva a la pantalla de proximamente.
  final bool empty;
}

/// Cuantas ranuras libres ensena el entorno mientras no haya apps.
const int emptySlotCount = 4;

/// Canales por pagina: rejilla de 4x2.
const int channelsPerPage = 8;

List<ChannelSpec> channelsFor({required bool isAdmin}) => <ChannelSpec>[
      ChannelSpec(
        id: 'settings',
        glyph: Glyph.gear,
        label: (l) => l.channelSettings,
        builder: (_) => const SettingsChannel(),
      ),
      ChannelSpec(
        id: 'profile',
        glyph: Glyph.person,
        label: (l) => l.channelProfile,
        builder: (_) => const ProfileChannel(),
      ),
      if (isAdmin)
        ChannelSpec(
          id: 'admin',
          glyph: Glyph.keycard,
          label: (l) => l.channelAdmin,
          builder: (_) => const AdminChannel(),
        ),
      if (isAdmin)
        ChannelSpec(
          id: 'debug',
          glyph: Glyph.bug,
          label: (l) => l.channelDebug,
          builder: (_) => const DebugChannel(),
        ),
      for (var i = 0; i < emptySlotCount; i++)
        ChannelSpec(
          id: 'slot-$i',
          glyph: Glyph.slot,
          label: (l) => l.channelEmpty,
          empty: true,
          builder: (_) => const ComingSoonChannel(),
        ),
    ];
