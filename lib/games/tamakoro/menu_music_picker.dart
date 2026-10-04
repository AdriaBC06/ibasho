// Ibasho — el selector de la musica del menu, en la configuracion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/gacha_music.dart';
import '../../extensions/content_models.dart';
import '../../extensions/content_registry.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/koro.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/track_text.dart';
import '../../ui/widgets/track_tile.dart';
import 'koro_widgets.dart';

/// Lo que puede sonar en el menu de inicio: las canciones propias de
/// Tamakoro y las pistas descubiertas en las apps o ganadas en el gacha.
/// Desde la 0.7.0 vuelve a la configuracion; entre la 0.6.2 y la 0.6.3
/// vivio en una pestaña de Tamakoro.
class MenuMusicPicker extends ConsumerWidget {
  const MenuMusicPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final library = ref.watch(musicLibraryProvider);
    final gacha = ref.watch(gachaProvider);
    final koro = ref.watch(koroProvider);
    final profile = ref.watch(profileProvider.select((p) => p.profile));
    final owner = profile == null
        ? ''
        : profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.username;
    final localMusic = ref.watch(
      preferencesProvider.select((p) => p.musicTrack),
    );
    final current = localMusic.startsWith('ext:')
        ? localMusic
        : (library.menuTrack ?? localMusic);
    final extensionMusic =
        ref.watch(extensionContentProvider).asData?.value.music ??
        const <ExtensionMusicTrack>[];
    final koroSlot = koroSlotOfTrack(current);

    // Una pista tambien esta desbloqueada si es un premio del gacha ya ganado
    // (`mu_<id>`), ademas de las de serie y las que se escuchan jugando.
    bool unlocked(MusicTrack track) {
      if (library.isUnlocked(track)) return true;
      final prize = gachaMusicById(track.id);
      return prize != null && gacha.owns(prize.key);
    }

    final tracks = MusicTrack.values.where(unlocked).toList(growable: false);
    final pending = MusicTrack.values.length - tracks.length;
    final songs = koro.songs.entries.where((e) => !e.value.isBlank).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final playing = Text(
      l.musicPlaying,
      style: Ty.caption.copyWith(
        color: T.onAccent,
        fontWeight: FontWeight.w500,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 10),
          child: Text(l.settingsMenuMusicHint, style: Ty.caption),
        ),
        for (final entry in songs)
          TrackTile(
            title: koroTitle(l, entry.value, owner),
            subtitle: l.koroSongFacts(
              entry.value.tempo,
              koroScaleName(l, entry.value.scale),
            ),
            selected: koroSlot == entry.key,
            onPressed: () => unawaited(
              ref.read(musicLibraryProvider.notifier).selectKoro(entry.key),
            ),
            trailing: koroSlot == entry.key ? playing : null,
          ),
        if (songs.isNotEmpty) const SizedBox(height: 12),
        for (final track in tracks)
          TrackTile(
            title: track.id,
            subtitle: describeTrack(l, track),
            selected: koroSlot == null && track.id == current,
            onPressed: () async {
              final notifier = ref.read(musicLibraryProvider.notifier);
              // Una pista ganada en el gacha pero nunca escuchada aun no
              // cuenta para `select`: se marca al elegirla la primera vez.
              if (!library.isUnlocked(track)) await notifier.markHeard(track);
              await notifier.select(track);
            },
            trailing: koroSlot == null && track.id == current ? playing : null,
          ),
        if (extensionMusic.isNotEmpty) const SizedBox(height: 12),
        for (final track in extensionMusic)
          TrackTile(
            title: track.label(Localizations.localeOf(context).languageCode),
            subtitle: '${track.author} · ${track.license}',
            selected: track.preferenceId == current,
            onPressed: () => ref
                .read(preferencesProvider.notifier)
                .setExtensionMusicTrack(track.preferenceId, track.filePath),
            trailing: track.preferenceId == current ? playing : null,
          ),
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 10),
          child: Text(l.settingsMenuMusicPending(pending), style: Ty.micro),
        ),
      ],
    );
  }
}
