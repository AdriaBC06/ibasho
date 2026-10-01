// Ibasho — piezas del canal de Hebi: las pantallas de salida, pausa y final.
// Los mandos (cruceta y botones) son los de Tsumiki.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../game_stage.dart';
import 'hebi.dart';
import 'hebi_store.dart';

/// Lo que se enseña antes de empezar: como se juega, lo que se gana y el
/// boton de jugar.
class HebiReadyCard extends StatelessWidget {
  const HebiReadyCard({
    super.key,
    required this.onStart,
    required this.records,
    this.showKeys = false,
  });

  final VoidCallback onStart;
  final HebiRecords records;
  final bool showKeys;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: GlossSurface(
          key: const ValueKey<String>('hebi.ready'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ArtIconView(ArtIcon.hebi, size: 64),
              const SizedBox(height: 6),
              Text(l.hebiReadyTitle, textAlign: TextAlign.center, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 4),
              Text(l.hebiReadyHint, textAlign: TextAlign.center, style: Ty.caption),
              const SizedBox(height: 12),
              const _RewardLadder(),
              const SizedBox(height: 8),
              const DailyCoinsMeter(game: 'hebi', height: 40),
              if (records.bestLength > 0) ...[
                const SizedBox(height: 10),
                Text('${l.gameBest}: ${l.hebiLengthCount(records.bestLength)}', style: Ty.caption),
              ],
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('hebi.start'),
                label: l.hebiStart,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onStart,
              ),
              if (showKeys) ...[
                const SizedBox(height: 10),
                Text(l.hebiKeys, textAlign: TextAlign.center, style: Ty.micro),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// «15 de largo → 3, 30 → 5, 50 → 8», con monedas pintadas.
class _RewardLadder extends StatelessWidget {
  const _RewardLadder();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    Widget step(int length, int coins) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ArtIconView(ArtIcon.coin, size: 18),
                const SizedBox(width: 3),
                Text('+$coins', style: Ty.numeral(15, color: Art.goldDark, weight: FontWeight.w700)),
              ],
            ),
            Text(l.hebiLengthCount(length), style: Ty.micro),
          ],
        );
    return GlossSurface(
      radius: 18,
      recessed: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [step(15, 3), step(30, 5), step(50, 8)],
      ),
    );
  }
}

/// La pausa.
class HebiPauseCard extends StatelessWidget {
  const HebiPauseCard({super.key, required this.onResume, required this.onRestart});

  final VoidCallback onResume;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: GlossSurface(
          key: const ValueKey<String>('hebi.paused'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.tsumikiPause, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('hebi.resume'),
                label: l.tsumikiResume,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onResume,
              ),
              const SizedBox(height: 6),
              IbashoButton(
                label: l.tsumikiNewGame,
                glyph: Glyph.refresh,
                tone: ButtonTone.quiet,
                expand: true,
                onPressed: onRestart,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HebiResultsCard extends StatelessWidget {
  const HebiResultsCard({
    super.key,
    required this.report,
    required this.reward,
    required this.rewardPending,
    required this.onAgain,
    required this.onDismiss,
  });

  final HebiReport report;
  final RewardOutcome? reward;
  final bool rewardPending;
  final VoidCallback onAgain;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final earns = hebiRewardFor(report.length) > 0;
    final coinText = earns ? rewardText(l, reward, rewardPending) : l.hebiCoinsHint(15 - report.length);
    final secs = report.seconds.round();
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';

    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: Ty.numeral(22, color: skin.accentDeep, weight: FontWeight.w700)),
              Text(label, style: Ty.micro),
            ],
          ),
        );

    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GlossSurface(
          key: const ValueKey<String>('hebi.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(report.won ? l.hebiWon : l.tsumikiGameOver,
                  style: Ty.title.copyWith(color: skin.accentDeep), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              // La longitud sube contando, como en los resultados de DS.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: report.length.toDouble()),
                duration: skin.motion(Duration(milliseconds: math.min(1400, 400 + report.length * 12))),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  '${v.round()}',
                  style: Ty.numeral(42, color: Ty.ink, weight: FontWeight.w700),
                ),
              ),
              Text('${l.hebiLength} · ${l.gameBest} ${report.best}', style: Ty.caption),
              const SizedBox(height: 10),
              GlossSurface(
                radius: 18,
                recessed: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    stat('${report.eaten}', l.hebiEaten),
                    stat('${report.speed}', l.hebiSpeed),
                    stat(time, l.hebiTime),
                  ],
                ),
              ),
              if (report.newRecord) ...[
                const SizedBox(height: 10),
                ResultChip(text: l.gameNewRecord, accent: true),
              ],
              const SizedBox(height: 10),
              CoinLine(text: coinText, granted: reward?.status == RewardStatus.granted),
              const SizedBox(height: 16),
              IbashoButton(
                key: const ValueKey<String>('hebi.again'),
                label: l.tsumikiNewGame,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onAgain,
              ),
              const SizedBox(height: 4),
              IbashoButton(
                label: l.hebiSeeBoard,
                tone: ButtonTone.quiet,
                height: 40,
                cue: Sfx.back,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
