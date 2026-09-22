// Ibasho — catalogo de canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../backend/shop.dart';
import '../../../games/minesweeper/minesweeper_channel.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../widgets/channel_art.dart';
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
import 'yatai_channel.dart';

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
    this.gift = false,
    this.gameId,
    this.art,
  });

  final String id;
  final Glyph glyph;

  /// Icono ilustrado a color. Lo llevan lo que se compra o se juega (el
  /// Yatai y los juegos); los canales del sistema se quedan con [glyph].
  final ArtIcon? art;
  final String Function(L) label;
  final WidgetBuilder builder;

  /// Una ranura libre: se ve hundida y lleva a la pantalla de proximamente.
  final bool empty;

  /// Numero que se pinta sobre el icono (solicitudes pendientes). Nada si es 0.
  final ProviderListenable<int>? badge;

  /// Un juego recien comprado: la ranura se ensena como un regalo envuelto y
  /// tocarla lo desenvuelve en vez de abrir el canal.
  final bool gift;

  /// Id del juego en `/users/{cuenta}/games/{gameId}`. Solo los canales de
  /// juegos lo llevan, y hace falta para desenvolver.
  final String? gameId;
}

/// Un juego comprable: con esto y una entrada aqui, el juego ya sale en la
/// rejilla en cuanto se compra. `channelsFor` hace el resto.
class GameChannelEntry {
  const GameChannelEntry({
    required this.glyph,
    required this.art,
    required this.label,
    required this.builder,
  });

  final Glyph glyph;
  final ArtIcon art;
  final String Function(L) label;
  final WidgetBuilder builder;
}

/// Registro de juegos: la clave es el `gameId` del catalogo del Yatai
/// (`lib/backend/shop.dart`) y de `/users/{cuenta}/games/{gameId}`.
final Map<String, GameChannelEntry> gameChannelRegistry = <String, GameChannelEntry>{
  'minesweeper': GameChannelEntry(
    glyph: Glyph.mine,
    art: ArtIcon.minesweeper,
    label: (l) => l.channelMinesweeper,
    builder: (_) => const MinesweeperChannel(),
  ),
};

/// Cuantas ranuras libres ensena el entorno mientras no haya apps propias.
///
/// Una, no dos: el Yatai ya deja la rejilla de una cuenta nueva justa en la
/// primera pagina en horizontal (ocho canales fijos). Con dos, el entorno
/// pasaba a una pagina de mas solo para enseñar un segundo hueco vacio.
const int emptySlotCount = 1;

/// Canales por pagina: rejilla de 4x2 en horizontal, de 3x3 en vertical.
int channelsPerPage({required bool tall}) => tall ? 9 : 8;

List<ChannelSpec> channelsFor({
  required bool isAdmin,
  Map<String, GameInstall> installedGames = const <String, GameInstall>{},
}) {
  // Los juegos comprados, en el orden en que se compraron. Solo entran los
  // que el registro conoce: si el backend trae un id que la app aun no sabe
  // pintar, se ignora en vez de reventar la rejilla.
  final games = installedGames.entries
      .where((e) => gameChannelRegistry.containsKey(e.key))
      .toList()
    ..sort((a, b) => a.value.at.compareTo(b.value.at));

  return <ChannelSpec>[
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
      ChannelSpec(
        id: 'yatai',
        glyph: Glyph.yatai,
        art: ArtIcon.yatai,
        label: (l) => l.channelYatai,
        builder: (_) => const YataiChannel(),
      ),
      for (final entry in games)
        ChannelSpec(
          id: 'game-${entry.key}',
          glyph: gameChannelRegistry[entry.key]!.glyph,
          art: gameChannelRegistry[entry.key]!.art,
          label: gameChannelRegistry[entry.key]!.label,
          builder: gameChannelRegistry[entry.key]!.builder,
          gift: entry.value.isGift,
          gameId: entry.key,
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
}
