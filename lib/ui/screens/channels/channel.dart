// Ibasho — catalogo de canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/shop.dart';
import '../../../games/game_music.dart';
import '../../../games/minesweeper/minesweeper_channel.dart';
import '../../../games/nihongo/nihongo_channel.dart';
import '../../../games/tsumiki/tsumiki_channel.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../widgets/channel_art.dart';
import '../../widgets/glyphs.dart';
import 'admin_channel.dart';
import 'coming_soon_channel.dart';
import 'debug_channel.dart';
import 'friends_channel.dart';
import '../../../games/pachinko/pachinko_channel.dart';
import '../../../games/pinball/pinball_channel.dart';
import 'gacha_channel.dart';
import 'leaderboards_channel.dart';
import 'messages_channel.dart';
import 'missions_channel.dart';
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
    this.onUnwrap,
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

  /// Que hacer al desenvolver, cuando no es un juego del Yatai (el gachapon
  /// se abre solo, al conseguir el primer ticket).
  final void Function(WidgetRef ref)? onUnwrap;
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
    builder: (_) => const GameMusic(track: MusicTrack.plaza, child: MinesweeperChannel()),
  ),
  'tsumiki': GameChannelEntry(
    glyph: Glyph.blocks,
    art: ArtIcon.tsumiki,
    label: (l) => l.channelTsumiki,
    builder: (_) => const GameMusic(track: MusicTrack.bossa, child: TsumikiChannel()),
  ),
  'nihongo': GameChannelEntry(
    glyph: Glyph.kana,
    art: ArtIcon.nihongo,
    label: (l) => l.channelNihongo,
    // Nihongo cambia de cancion segun este en el menu o jugando: la pone el.
    builder: (_) => const NihongoChannel(),
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
  bool gachaUnlocked = false,
  bool gachaGift = false,
  bool pinballUnlocked = false,
  bool pinballGift = false,
  bool pachinkoUnlocked = false,
  bool pachinkoGift = false,
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
      // Se juega y se gana algo (tickets del gacha): icono ilustrado, como el
      // Yatai y los juegos, no el glifo blanco de los canales del sistema.
      ChannelSpec(
        id: 'leaderboards',
        glyph: Glyph.trophy,
        art: ArtIcon.leaderboards,
        label: (l) => l.channelLeaderboards,
        builder: (_) => const LeaderboardsChannel(),
      ),
      ChannelSpec(
        id: 'missions',
        glyph: Glyph.flag,
        label: (l) => l.channelMissions,
        builder: (_) => const MissionsChannel(),
      ),
      // El gachapon aparece al tener el primer ticket, envuelto como un
      // regalo. Los tickets se siguen comprando en el Yatai.
      if (gachaUnlocked)
        ChannelSpec(
          id: 'gacha',
          glyph: Glyph.gift,
          art: ArtIcon.gacha,
          label: (l) => l.channelGacha,
          builder: (_) => const GachaChannel(),
          gift: gachaGift,
          onUnwrap: (ref) => unawaited(ref.read(preferencesProvider.notifier).openGacha()),
        ),
      // El pinball llega igual, envuelto, con la primera bola: es donde se
      // abren.
      if (pinballUnlocked)
        ChannelSpec(
          id: 'pinball',
          glyph: Glyph.star,
          art: ArtIcon.pinball,
          label: (l) => l.channelPinball,
          builder: (_) => const PinballChannel(),
          gift: pinballGift,
          onUnwrap: (ref) => unawaited(ref.read(preferencesProvider.notifier).openPinball()),
        ),
      // El pachinko llega tras jugar la primera bola en el pinball: ahi se
      // arriesgan bolas para subirlas de rareza.
      if (pachinkoUnlocked)
        ChannelSpec(
          id: 'pachinko',
          glyph: Glyph.star,
          art: ArtIcon.pachinko,
          label: (l) => l.channelPachinko,
          builder: (_) => const PachinkoChannel(),
          gift: pachinkoGift,
          onUnwrap: (ref) => unawaited(ref.read(preferencesProvider.notifier).openPachinko()),
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
