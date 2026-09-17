// Ibasho — catalogo de canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../widgets/glyphs.dart';
import 'admin_channel.dart';
import 'coming_soon_channel.dart';
import 'debug_channel.dart';
import 'friends_channel.dart';
import 'messages_channel.dart';
import 'news_channel.dart';
import 'profile_channel.dart';
import 'settings_channel.dart';
import 'suggestions_channel.dart';
import 'tamas_channel.dart';

/// Un hueco de la rejilla.
@immutable
class ChannelSpec {
  const ChannelSpec({
    required this.id,
    required this.glyph,
    required this.label,
    required this.builder,
    this.empty = false,
    this.badge,
  });

  final String id;
  final Glyph glyph;
  final String Function(L) label;
  final WidgetBuilder builder;

  /// Una ranura libre: se ve hundida y lleva a la pantalla de proximamente.
  final bool empty;

  /// Numero que se pinta sobre el icono (solicitudes pendientes). Nada si es 0.
  final ProviderListenable<int>? badge;
}

/// Cuantas ranuras libres ensena el entorno mientras no haya apps.
///
/// Una, no dos: con los tres canales de la 0.4.0 una cuenta normal tiene siete,
/// y la octava ranura deja la primera pagina justa. Con dos, el entorno pasaba
/// a dos paginas para enseñar un hueco.
const int emptySlotCount = 1;

/// Canales por pagina: rejilla de 4x2 en horizontal, de 3x3 en vertical.
int channelsPerPage({required bool tall}) => tall ? 9 : 8;

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
      ChannelSpec(
        id: 'tamas',
        glyph: Glyph.tama,
        label: (l) => l.channelTamas,
        builder: (_) => const TamasChannel(),
      ),
      ChannelSpec(
        id: 'friends',
        glyph: Glyph.friends,
        label: (l) => l.channelFriends,
        builder: (_) => const FriendsChannel(),
        badge: pendingRequestsProvider,
      ),
      ChannelSpec(
        id: 'messages',
        glyph: Glyph.chat,
        label: (l) => l.channelMessages,
        builder: (_) => const MessagesChannel(),
        badge: unreadMessagesProvider,
      ),
      ChannelSpec(
        id: 'news',
        glyph: Glyph.news,
        label: (l) => l.channelNews,
        builder: (_) => const NewsChannel(),
        badge: unreadNewsProvider,
      ),
      ChannelSpec(
        id: 'suggestions',
        glyph: Glyph.bulb,
        label: (l) => l.channelSuggestions,
        builder: (_) => const SuggestionsChannel(),
        // Solo se enciende al admin: `pending` unicamente se llena si quien
        // mira puede leer el buzon entero.
        badge: pendingSuggestionsProvider,
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
