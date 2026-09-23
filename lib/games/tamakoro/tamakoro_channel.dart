// Ibasho — canal de Tamakoro: pintar canciones que canta tu coro de Tamas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/gacha_music.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/koro.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/track_text.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/panel.dart';
import '../../ui/widgets/slot_tile.dart';
import '../../ui/widgets/track_tile.dart';
import '../game_stage.dart';
import 'koro_editor.dart';
import 'koro_piano.dart';
import 'koro_song.dart';
import 'koro_widgets.dart';

enum _Tab { songs, piano, menu }

/// El canal de Tamakoro.
///
/// Tres pestañas: las canciones (una rejilla de huecos, como el HOME Menu,
/// y el editor al abrir una), el Tamapiano y la musica del menu, que desde
/// la 0.6.2 se elige aqui y no en la configuracion.
///
/// Es el unico canal sin musica: mientras esta abierto el menu calla, porque
/// lo que suena es el coro.
class TamakoroChannel extends ConsumerStatefulWidget {
  const TamakoroChannel({super.key});

  @override
  ConsumerState<TamakoroChannel> createState() => _TamakoroChannelState();
}

class _TamakoroChannelState extends ConsumerState<TamakoroChannel> {
  _Tab _tab = _Tab.songs;
  int _page = 0;
  int _selected = 0;

  /// Hueco abierto en el editor, si hay.
  int? _editing;

  @override
  void initState() {
    super.initState();
    unawaited(AudioService.instance.hushMusic());
  }

  @override
  void dispose() {
    unawaited(AudioService.instance.stopKoro());
    unawaited(AudioService.instance.unhushMusic());
    super.dispose();
  }

  String _owner() {
    final profile = ref.read(profileProvider).profile;
    if (profile == null) return '';
    return profile.displayName.isNotEmpty ? profile.displayName : profile.username;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final koro = ref.watch(koroProvider);
    final tamas = ref.watch(tamasProvider.select((t) => t.tamas));
    final editing = _editing;

    Widget body;
    if (editing != null) {
      final song = koro.songs[editing] ?? KoroSong(number: koro.nextNumber);
      body = KoroEditor(
        key: ValueKey<int>(editing),
        song: song,
        tamas: tamas,
        title: koroTitle(l, song, _owner()),
        onSave: (song) => unawaited(ref.read(koroProvider.notifier).save(editing, song)),
        onBack: () => setState(() => _editing = null),
      );
    } else {
      body = Column(
        children: [
          _tabs(l),
          SizedBox(height: layout.pick(18, 12)),
          Expanded(
            child: switch (_tab) {
              _Tab.songs => _songs(context, koro, tamas),
              _Tab.piano => KoroPiano(
                  tamas: tamas,
                  initialTamaId: ref.read(tamasProvider).profileTamaId,
                ),
              _Tab.menu => _menuMusic(context),
            },
          ),
        ],
      );
    }

    return ChannelScaffold(
      title: l.channelTamakoro,
      glyph: Glyph.note,
      art: ArtIcon.tamakoro,
      child: Padding(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.pick(18, 12)),
        child: body,
      ),
    );
  }

  Widget _tabs(L l) => SegmentRail(
        children: [
          for (final (tab, label, glyph) in [
            (_Tab.songs, l.koroTabSongs, Glyph.pencil),
            (_Tab.piano, l.koroTabPiano, Glyph.tama),
            (_Tab.menu, l.koroTabMenu, Glyph.note),
          ])
            SegmentPill(
              key: ValueKey<String>('koro.tab.${tab.name}'),
              label: label,
              glyph: glyph,
              selected: _tab == tab,
              onPressed: () => setState(() => _tab = tab),
            ),
        ],
      );

  // --- Canciones -------------------------------------------------------------

  Widget _songs(BuildContext context, KoroState koro, List<Tama> tamas) {
    final layout = Layout.of(context);
    final perPage = layout.tall ? 6 : 10;
    final columns = layout.tall ? 2 : 5;
    final pages = math.max(1, (koro.slots / perPage).ceil());
    final page = _page.clamp(0, pages - 1);
    final info = _songInfo(context, koro, tamas);
    final grid = LayoutBuilder(
      builder: (context, box) {
        final rows = (perPage / columns).ceil();
        const gap = 12.0;
        final w = (box.maxWidth - gap * (columns - 1)) / columns;
        final h = math.min(w * .78, (box.maxHeight - gap * (rows - 1)) / rows);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = page * perPage; i < math.min(koro.slots, (page + 1) * perPage); i++)
              _slot(context, i, koro.songs[i], tamas, w, h),
          ],
        );
      },
    );
    final foot = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pages > 1) KoroPager(page: page, pages: pages, onPage: (p) => setState(() => _page = p)),
        const SizedBox(height: 8),
        Text(
          L.of(context)!.koroSlotsHint(koro.songs.length, koro.slots, koroMaxSlots),
          style: Ty.micro,
          textAlign: TextAlign.center,
        ),
      ],
    );
    if (layout.tall) {
      return Column(
        children: [
          info,
          const SizedBox(height: 14),
          Expanded(child: grid),
          foot,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: [Expanded(child: grid), foot])),
        const SizedBox(width: 24),
        SizedBox(width: 280, child: info),
      ],
    );
  }

  Widget _slot(BuildContext context, int slot, KoroSong? song, List<Tama> tamas, double w, double h) {
    final l = L.of(context)!;
    final selected = slot == _selected;
    return SlotTile(
      key: ValueKey<String>('koro.slot.$slot'),
      width: w,
      height: h,
      selected: selected,
      semanticLabel: song == null ? l.koroEmptySlot : koroTitle(l, song, _owner()),
      // Tocar una vez elige; tocar otra vez entra, como en el HOME Menu.
      onPressed: () => selected ? setState(() => _editing = slot) : setState(() => _selected = slot),
      child: song == null
          ? Center(child: GlyphIcon(Glyph.plus, size: 26, color: Ty.inkSoft))
          : Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ColoredBox(
                        color: T.shellTop,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: KoroCanvasPainter(song: song, inks: koroInks(song, tamas), grid: false),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('#${song.number}', style: Ty.micro),
                ],
              ),
            ),
    );
  }

  Widget _songInfo(BuildContext context, KoroState koro, List<Tama> tamas) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final song = koro.songs[_selected];
    final inMenu = koroSlotOfTrack(ref.watch(musicLibraryProvider.select((m) => m.menuTrack))) == _selected;
    final title = song == null ? l.koroEmptySlot : koroTitle(l, song, _owner());
    final open = IbashoButton(
      key: const ValueKey<String>('koro.open'),
      label: song == null ? l.koroNew : l.koroEdit,
      glyph: song == null ? Glyph.plus : Glyph.pencil,
      tone: ButtonTone.accent,
      expand: true,
      onPressed: () => setState(() => _editing = _selected),
    );
    return SectionCard(
      title: l.koroSlotNumber(_selected + 1),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Ty.lead),
          if (song != null) ...[
            const SizedBox(height: 6),
            Text(
              inMenu ? l.koroInMenu : l.koroSongFacts(song.tempo, _scaleName(l, song.scale)),
              style: Ty.caption.copyWith(color: inMenu ? skin.accentDeep : null),
            ),
          ],
          const SizedBox(height: 16),
          open,
          if (song != null) ...[
            const SizedBox(height: 10),
            IbashoButton(
              key: const ValueKey<String>('koro.menu'),
              label: l.koroSetMenu,
              glyph: Glyph.speaker,
              expand: true,
              onPressed: inMenu || song.isBlank
                  ? null
                  : () => unawaited(ref.read(musicLibraryProvider.notifier).selectKoro(_selected)),
            ),
            const SizedBox(height: 10),
            IbashoButton(
              key: const ValueKey<String>('koro.delete'),
              label: l.koroDelete,
              glyph: Glyph.trash,
              expand: true,
              onPressed: () => unawaited(_delete(song, inMenu)),
            ),
          ],
        ],
      ),
    );
  }

  String _scaleName(L l, KoroScale scale) => switch (scale) {
        KoroScale.major => l.koroScaleMajor,
        KoroScale.minor => l.koroScaleMinor,
        KoroScale.penta => l.koroScalePenta,
      };

  Future<void> _delete(KoroSong song, bool inMenu) async {
    final l = L.of(context)!;
    final slot = _selected;
    final ok = await askConfirmation(
      context,
      title: l.koroDeleteTitle,
      body: l.koroDeleteBody(koroTitle(l, song, _owner())),
      confirmLabel: l.koroDelete,
      cancelLabel: l.actionCancel,
    );
    if (!ok || !mounted) return;
    // Si sonaba en el menu, el menu vuelve a la pista de serie.
    if (inMenu) await ref.read(musicLibraryProvider.notifier).select(MusicTrack.fallback);
    await ref.read(koroProvider.notifier).delete(slot);
  }

  // --- Musica del menu -------------------------------------------------------

  Widget _menuMusic(BuildContext context) {
    final l = L.of(context)!;
    final library = ref.watch(musicLibraryProvider);
    final gacha = ref.watch(gachaProvider);
    final koro = ref.watch(koroProvider);
    final current = library.menuTrack ?? ref.watch(preferencesProvider.select((p) => p.musicTrack));
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
      style: Ty.caption.copyWith(color: T.onAccent, fontWeight: FontWeight.w500),
    );

    return IbashoScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(l.koroMenuHint, style: Ty.caption),
          ),
          for (final entry in songs)
            TrackTile(
              title: koroTitle(l, entry.value, _owner()),
              subtitle: l.koroSongFacts(entry.value.tempo, _scaleName(l, entry.value.scale)),
              selected: koroSlot == entry.key,
              onPressed: () => unawaited(ref.read(musicLibraryProvider.notifier).selectKoro(entry.key)),
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
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 10),
            child: Text(l.settingsMenuMusicPending(pending), style: Ty.micro),
          ),
        ],
      ),
    );
  }
}
