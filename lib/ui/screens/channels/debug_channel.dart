// Ibasho — canal de depuracion (solo administracion).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/gacha.dart';
import '../../../backend/gacha_prizes.dart';
import '../../../backend/models.dart';
import '../../../backend/shop.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/debug.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../track_text.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/track_tile.dart';
import '../../layout.dart';
import '../channel_route.dart';
import '../login_bonus_panel.dart';
import 'channel.dart';

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
                const _BonusSection(),
                const _GachaSection(),
                const SizedBox(height: 22),
                const _PrizesSection(),
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
                const _AppsSection(),
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

/// Probar el bono diario: verlo sin cobrar, abrir el de verdad u olvidar el
/// de la cuenta propia para cobrarlo otra vez (las reglas solo dejan a un
/// admin borrar el suyo).
class _BonusSection extends ConsumerWidget {
  const _BonusSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final bonus = ref.watch(loginBonusProvider);
    return SectionCard(
      title: l.debugBonus,
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.debugBonusHint, style: Ty.caption),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              IbashoButton(
                key: const Key('debug.bonus.preview'),
                label: l.debugBonusPreview,
                glyph: Glyph.play,
                height: 40,
                onPressed: () => showLoginBonus(context, preview: true),
              ),
              IbashoButton(
                key: const Key('debug.bonus.open'),
                label: l.debugBonusOpen,
                glyph: Glyph.coin,
                height: 40,
                onPressed: bonus.loaded ? () => showLoginBonus(context) : null,
              ),
              IbashoButton(
                key: const Key('debug.bonus.reset'),
                label: l.debugBonusReset,
                glyph: Glyph.refresh,
                tone: ButtonTone.quiet,
                height: 40,
                onPressed: bonus.claimedToday
                    ? () async {
                        final ok = await ref.read(loginBonusProvider.notifier).debugReset();
                        if (!ok && context.mounted) {
                          showIbashoToast(context, l.debugBonusResetFailed, isError: true);
                        }
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Darse tickets del gacha sin pasar por el Yatai. Las reglas solo lo
/// aceptan de un admin y en su propia cuenta.
class _GachaSection extends ConsumerWidget {
  const _GachaSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final gacha = ref.watch(gachaProvider);
    Future<void> give(TicketKind kind, int amount) async {
      final ok = await ref.read(gachaProvider.notifier).debugGiveTickets(kind, amount);
      if (!ok && context.mounted) showIbashoToast(context, l.debugGachaFailed, isError: true);
    }

    return SectionCard(
      title: l.debugGacha,
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.debugGachaHint, style: Ty.caption),
          const SizedBox(height: 12),
          _InfoRow(
            label: l.gachaTicketGachaken,
            value: '${gacha.ticketsOf(TicketKind.gachaken)}',
          ),
          _InfoRow(
            label: l.gachaTicketKinken,
            value: '${gacha.ticketsOf(TicketKind.kinken)}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              IbashoButton(
                key: const Key('debug.gacha.give'),
                label: l.debugGachaGive,
                glyph: Glyph.gift,
                height: 40,
                onPressed: () => unawaited(give(TicketKind.gachaken, 10)),
              ),
              IbashoButton(
                key: const Key('debug.gacha.giveGold'),
                label: l.debugGachaGiveGold,
                glyph: Glyph.star,
                height: 40,
                onPressed: () => unawaited(give(TicketKind.kinken, 1)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Darse o quitarse de golpe todo el contenido: los premios del gacha de las
/// cuatro categorias y todas las canciones. Las reglas solo lo aceptan de un
/// admin y en su propia cuenta.
class _PrizesSection extends ConsumerStatefulWidget {
  const _PrizesSection();

  @override
  ConsumerState<_PrizesSection> createState() => _PrizesSectionState();
}

class _PrizesSectionState extends ConsumerState<_PrizesSection> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) showIbashoToast(context, L.of(context)!.debugPrizesFailed, isError: true);
  }

  Future<bool> _give() async {
    final ok = await ref.read(gachaProvider.notifier).debugGiveAllPrizes();
    if (ok) await ref.read(musicLibraryProvider.notifier).unlockAll();
    return ok;
  }

  Future<bool> _remove() async {
    final ok = await ref.read(gachaProvider.notifier).debugRemoveAllPrizes();
    if (!ok) return false;
    await ref.read(musicLibraryProvider.notifier).resetUnlocks();
    await ref.read(preferencesProvider.notifier).setBackdrop('');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final gacha = ref.watch(gachaProvider);
    final all = allGachaPrizeKeys;
    return SectionCard(
      title: l.debugPrizes,
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.debugPrizesHint, style: Ty.caption),
          const SizedBox(height: 12),
          _InfoRow(
            label: l.debugPrizesOwned,
            value: '${all.where(gacha.owns).length}/${all.length}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              IbashoButton(
                key: const Key('debug.prizes.give'),
                label: l.debugPrizesGive,
                glyph: Glyph.gift,
                height: 40,
                onPressed: _busy ? null : () => unawaited(_run(_give)),
              ),
              IbashoButton(
                key: const Key('debug.prizes.remove'),
                label: l.debugPrizesRemove,
                glyph: Glyph.cross,
                height: 40,
                onPressed: _busy ? null : () => unawaited(_run(_remove)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dar o quitar juegos a la cuenta propia sin pasar por el Yatai. Las reglas
/// solo lo aceptan de un admin y en su propia cuenta.
class _AppsSection extends ConsumerStatefulWidget {
  const _AppsSection();

  @override
  ConsumerState<_AppsSection> createState() => _AppsSectionState();
}

class _AppsSectionState extends ConsumerState<_AppsSection> {
  String? _failed;

  Future<void> _set(String gameId, GameState? to) async {
    setState(() => _failed = null);
    final ok = await ref.read(shopProvider.notifier).debugSetGame(gameId, to);
    if (!ok && mounted) setState(() => _failed = gameId);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final games = ref.watch(installedGamesProvider);
    final busy = ref.watch(shopProvider.select((s) => s.busy));
    final entries = gameChannelRegistry.entries.toList();

    return SectionCard(
      title: l.debugApps,
      padding: const EdgeInsets.fromLTRB(26, 6, 26, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(l.debugAppsHint, style: Ty.caption),
          ),
          for (final (i, entry) in entries.indexed)
            SettingRow(
              label: entry.value.label(l),
              hint: _failed == entry.key
                  ? l.debugAppFailed
                  : switch (games[entry.key]?.state) {
                      null => l.debugAppMissing,
                      GameState.gift => l.debugAppGift,
                      GameState.open => l.debugAppOpen,
                    },
              divider: i < entries.length - 1,
              control: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  IbashoButton(
                    key: Key('debug.app.${entry.key}.gift'),
                    label: l.debugAppGiveGift,
                    glyph: Glyph.gift,
                    height: 38,
                    onPressed: busy || games[entry.key]?.state == GameState.gift
                        ? null
                        : () => _set(entry.key, GameState.gift),
                  ),
                  IbashoButton(
                    key: Key('debug.app.${entry.key}.open'),
                    label: l.debugAppGiveOpen,
                    glyph: Glyph.check,
                    height: 38,
                    onPressed: busy || games[entry.key]?.state == GameState.open
                        ? null
                        : () => _set(entry.key, GameState.open),
                  ),
                  IbashoButton(
                    key: Key('debug.app.${entry.key}.remove'),
                    label: l.debugAppRemove,
                    glyph: Glyph.trash,
                    tone: ButtonTone.quiet,
                    height: 38,
                    onPressed: busy || !games.containsKey(entry.key)
                        ? null
                        : () => _set(entry.key, null),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
