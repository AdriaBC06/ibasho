// Ibasho — canal de depuracion (solo administracion).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/debug.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../track_text.dart';
import '../../widgets/panel.dart';
import '../../widgets/track_tile.dart';
import '../../layout.dart';
import '../channel_route.dart';

class DebugChannel extends ConsumerWidget {
  const DebugChannel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final isAdmin = ref.watch(sessionProvider.select((s) => s.isAdmin));
    if (!isAdmin) {
      return ChannelScaffold(
        title: l.channelDebug,
        glyph: Glyph.bug,
        child: Center(child: Text(l.adminNotAdmin, style: Ty.lead)),
      );
    }

    final flags = ref.watch(debugProvider);
    final debug = ref.read(debugProvider.notifier);
    final trackId = ref.watch(preferencesProvider.select((p) => p.musicTrack));
    final current = MusicTrack.byId(trackId);
    final session = ref.watch(sessionProvider);
    final link = ref.watch(systemStatusProvider.select((s) => s.link));

    final library = ref.watch(musicLibraryProvider);
    final layout = Layout.of(context);

    final effects = <(Sfx, String)>[
      (Sfx.tick, l.debugSfxTick),
      (Sfx.open, l.debugSfxOpen),
      (Sfx.back, l.debugSfxBack),
      (Sfx.error, l.debugSfxError),
      (Sfx.chime, l.debugSfxChime),
    ];

    return ChannelScaffold(
      title: l.channelDebug,
      glyph: Glyph.bug,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.pick(24, 18), layout.gutter, 44),
        child: Center(
          child: SizedBox(
            width: layout.pick(860, layout.column),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.debugIntro, style: Ty.body.copyWith(color: T.inkSoft)),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.debugMusic,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 4),
                        child: Text(l.debugMusicPreviewHint, style: Ty.caption),
                      ),
                      for (final track in MusicTrack.values) ...[
                        if (track == MusicTrack.plaza || track == MusicTrack.calma)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 12, 0, 4),
                            child: Text(
                              track == MusicTrack.plaza
                                  ? l.debugRhythmic
                                  : l.debugAmbient,
                              style: Ty.label,
                            ),
                          ),
                        TrackTile(
                          title: track.id,
                          subtitle:
                              '${describeTrack(l, track)} · ${track.author} · ${track.license}',
                          selected: track == current,
                          onPressed: () => ref
                              .read(preferencesProvider.notifier)
                              .setMusicTrack(track.id),
                          trailing: library.isUnlocked(track)
                              ? Text(
                                  track.unlockedByDefault ? '' : l.debugUnlocked,
                                  style: Ty.micro.copyWith(
                                    color: track == current ? T.onAccent : T.inkSoft,
                                  ),
                                )
                              : IbashoButton(
                                  label: l.debugMarkHeard,
                                  glyph: Glyph.check,
                                  height: 34,
                                  onPressed: () => ref
                                      .read(musicLibraryProvider.notifier)
                                      .markHeard(track),
                                ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IbashoButton(
                          label: l.debugResetUnlocks,
                          glyph: Glyph.refresh,
                          tone: ButtonTone.quiet,
                          height: 38,
                          onPressed: library.unlocked.isEmpty
                              ? null
                              : () => ref
                                  .read(musicLibraryProvider.notifier)
                                  .resetUnlocks(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.debugEffects,
                  // En horizontal, una fila (Wrap estiraria cada boton a todo
                  // el ancho); en vertical, dos filas que se reparten.
                  child: layout.tall
                      ? Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final (sfx, label) in effects)
                              IbashoButton(
                                label: label,
                                glyph: Glyph.play,
                                height: 44,
                                cue: sfx,
                                onPressed: () {},
                              ),
                          ],
                        )
                      : Row(
                    children: [
                      for (final (i, (sfx, label)) in effects.indexed) ...[
                        if (i > 0) const SizedBox(width: 12),
                        IbashoButton(
                          label: label,
                          glyph: Glyph.play,
                          height: 44,
                          cue: sfx,
                          onPressed: () {},
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.debugMotion,
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 6),
                  child: Column(
                    children: [
                      SettingRow(
                        label: l.debugSlowMotion,
                        hint: l.debugSlowMotionHint,
                        control: IbashoToggle(
                          value: flags.slowMotion,
                          onChanged: debug.setSlowMotion,
                        ),
                      ),
                      SettingRow(
                        label: l.debugPerformance,
                        hint: l.debugPerformanceHint,
                        divider: false,
                        control: IbashoToggle(
                          value: flags.performanceOverlay,
                          onChanged: debug.setPerformanceOverlay,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.debugSession,
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 6),
                  child: Column(
                    children: [
                      _InfoRow(label: l.debugUid, value: session.uid),
                      _InfoRow(label: l.debugAccount, value: session.accountId),
                      _InfoRow(
                        label: l.debugStore,
                        value: ref.read(secureStoreProvider).backendName,
                      ),
                      SettingRow(
                        label: l.debugLink,
                        divider: false,
                        control: SignalArcs(
                          bars: switch (link) {
                            LinkQuality.offline => 0,
                            LinkQuality.weak => 1,
                            LinkQuality.fair => 2,
                            LinkQuality.strong => 3,
                          },
                          color: IbashoSkin.of(context).accentDeep,
                          dim: T.hairline,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SettingRow(
        label: label,
        control: Text(value, style: Ty.numeral(14, color: T.inkSoft)),
      );
}
