// Ibasho — las tarjetas del pachinko: llenar la bandeja, la bandeja de
// rarezas mientras se juega, pausa y resultados.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../backend/gacha.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/gacha.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gacha_art.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../game_stage.dart';
import 'pachinko.dart';
import 'pachinko_board.dart';

/// Antes de jugar: cuantas bolas de cada rareza entran (hasta 50 en total).
class PachinkoLoadCard extends StatelessWidget {
  const PachinkoLoadCard({
    super.key,
    required this.gacha,
    required this.picked,
    required this.busy,
    required this.error,
    required this.showKeys,
    required this.onChange,
    required this.onPlay,
  });

  final GachaState gacha;
  final Map<Rarity, int> picked;
  final bool busy;
  final String? error;
  final bool showKeys;
  final void Function(Rarity rarity, int count) onChange;
  final VoidCallback onPlay;

  int get _total => picked.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final owned = pachinkoRarities.where((r) => gacha.ballsOf(r) > 0).toList();
    final room = pachinkoMaxBalls - _total;

    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GlossSurface(
          key: const ValueKey<String>('pachinko.load'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pachinkoLoadTitle, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 2),
              Text(l.pachinkoLoadHint, textAlign: TextAlign.center, style: Ty.caption),
              const SizedBox(height: 10),
              const _PocketLegend(),
              const SizedBox(height: 10),
              if (owned.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l.pachinkoNoBalls, textAlign: TextAlign.center, style: Ty.body.copyWith(color: Ty.inkSoft)),
                )
              else
                GlossSurface(
                  radius: 20,
                  recessed: true,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    children: [
                      for (final rarity in owned)
                        _Stepper(
                          rarity: rarity,
                          count: picked[rarity] ?? 0,
                          owned: gacha.ballsOf(rarity),
                          room: room,
                          enabled: !busy,
                          onChange: (n) => onChange(rarity, n),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(l.pachinkoOdds, textAlign: TextAlign.center, style: Ty.micro),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, textAlign: TextAlign.center, style: Ty.caption.copyWith(color: T.wrong)),
              ],
              const SizedBox(height: 12),
              IbashoButton(
                key: const ValueKey<String>('pachinko.play'),
                label: _total == 0 ? l.pachinkoPlayEmpty : l.pachinkoPlay(_total),
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                cue: Sfx.open,
                onPressed: _total == 0 || busy ? null : onPlay,
              ),
              const SizedBox(height: 8),
              Text(showKeys ? l.pachinkoKeys : l.pachinkoDropHint, textAlign: TextAlign.center, style: Ty.micro),
            ],
          ),
        ),
      ),
    );
  }
}

/// Que hace cada bolsillo, con su color.
class _PocketLegend extends StatelessWidget {
  const _PocketLegend();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    Widget chip(PocketKind kind, String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: pocketColor(kind).withValues(alpha: .25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  pocketLabel(kind),
                  style: Ty.numeral(12, weight: FontWeight.w800, color: Art.deep(pocketColor(kind), .55)),
                ),
              ),
              const SizedBox(width: 4),
              Text(text, style: Ty.micro),
            ],
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        chip(PocketKind.same, l.pachinkoPocketSame),
        chip(PocketKind.up1, l.pachinkoPocketUp1),
        chip(PocketKind.up2, l.pachinkoPocketUp2),
        chip(PocketKind.out, l.pachinkoPocketOut),
      ],
    );
  }
}

/// Una fila de la bandeja: la bola, − cuantas + y las que tienes.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.rarity,
    required this.count,
    required this.owned,
    required this.room,
    required this.enabled,
    required this.onChange,
  });

  final Rarity rarity;
  final int count;
  final int owned;
  final int room;
  final bool enabled;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final canAdd = enabled && count < owned && room > 0;
    final canAddTen = enabled && count < owned && room > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          GachaBallView(rarity, size: 30, shadow: false),
          const SizedBox(width: 6),
          Text('/$owned', style: Ty.numeral(13, color: Ty.inkSoft)),
          const Spacer(),
          IconPill(
            key: ValueKey<String>('pachinko.less.${rarity.name}'),
            glyph: Glyph.minus,
            diameter: 32,
            semanticLabel: l.pachinkoLess,
            onPressed: enabled && count > 0 ? () => onChange(count - 1) : null,
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$count',
              key: ValueKey<String>('pachinko.count.${rarity.name}'),
              textAlign: TextAlign.center,
              style: Ty.numeral(18, weight: FontWeight.w700, color: Ty.ink),
            ),
          ),
          IconPill(
            key: ValueKey<String>('pachinko.more.${rarity.name}'),
            glyph: Glyph.plus,
            diameter: 32,
            semanticLabel: l.pachinkoMore,
            onPressed: canAdd ? () => onChange(count + 1) : null,
          ),
          const SizedBox(width: 4),
          GestureDetector(
            key: ValueKey<String>('pachinko.ten.${rarity.name}'),
            onTap: canAddTen
                ? () {
                    AudioService.instance.play(Sfx.tick);
                    onChange(count + [10, owned - count, room].reduce((a, b) => a < b ? a : b));
                  }
                : null,
            child: Opacity(
              opacity: canAddTen ? 1 : .35,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text('+10', style: Ty.numeral(13, weight: FontWeight.w800, color: Ty.inkSoft)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mientras se juega: las bolas que quedan de cada rareza. La elegida es la
/// que sale al tocar el tablero.
class PachinkoTray extends StatelessWidget {
  const PachinkoTray({
    super.key,
    required this.game,
    required this.selected,
    required this.onSelect,
    this.axis = Axis.horizontal,
    this.ball = 34,
  });

  final PachinkoGame game;
  final Rarity? selected;
  final ValueChanged<Rarity> onSelect;
  final Axis axis;
  final double ball;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final items = <Widget>[
      for (final rarity in pachinkoRarities)
        if (game.loaded[rarity]! > 0)
          GestureDetector(
            key: ValueKey<String>('pachinko.tray.${rarity.name}'),
            onTap: game.stockOf(rarity) > 0
                ? () {
                    AudioService.instance.play(Sfx.tick);
                    onSelect(rarity);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Opacity(
                opacity: game.stockOf(rarity) > 0 ? 1 : .35,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (rarity == selected)
                            BoxShadow(color: skin.accent.withValues(alpha: .7), blurRadius: 10, spreadRadius: 2),
                        ],
                      ),
                      child: GachaBallView(rarity, size: ball, shadow: false),
                    ),
                    const SizedBox(height: 2),
                    Text('×${game.stockOf(rarity)}', style: Ty.numeral(12, weight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
    ];
    return GlossSurface(
      radius: 20,
      recessed: true,
      padding: const EdgeInsets.all(5),
      child: axis == Axis.horizontal
          ? Row(mainAxisSize: MainAxisSize.min, children: items)
          : Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

class PachinkoPauseCard extends StatelessWidget {
  const PachinkoPauseCard({
    super.key,
    required this.onResume,
    required this.left,
    required this.falling,
    required this.onFinish,
    this.busy = false,
    this.error,
  });

  final VoidCallback onResume;

  /// Bolas sin soltar, que vuelven tal cual al terminar.
  final int left;

  /// Si hay bolas cayendo: entonces no se puede terminar todavia.
  final bool falling;
  final VoidCallback onFinish;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: GlossSurface(
          key: const ValueKey<String>('pachinko.paused'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pachinkoPause, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 6),
              Text(l.pachinkoResumeHint, textAlign: TextAlign.center, style: Ty.caption),
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('pachinko.resume'),
                label: l.pachinkoResume,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: busy ? null : onResume,
              ),
              if (left > 0) ...[
                const SizedBox(height: 14),
                Text(falling ? l.pachinkoFinishWait : l.pachinkoFinishHint, textAlign: TextAlign.center, style: Ty.caption),
                const SizedBox(height: 8),
                IbashoButton(
                  key: const ValueKey<String>('pachinko.finish'),
                  label: l.pachinkoFinish(left),
                  glyph: Glyph.undo,
                  expand: true,
                  cue: Sfx.back,
                  onPressed: busy || falling ? null : onFinish,
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, textAlign: TextAlign.center, style: Ty.caption.copyWith(color: T.wrong)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// El final de la tanda: lo que entro y lo que vuelve al deposito. Mientras
/// se guarda, espera; si falla, deja reintentar (la tanda sigue guardada en
/// el dispositivo hasta que se cobra).
class PachinkoResultsCard extends StatelessWidget {
  const PachinkoResultsCard({
    super.key,
    required this.game,
    required this.settled,
    required this.busy,
    required this.error,
    required this.onRetry,
    required this.onAgain,
  });

  final PachinkoGame game;
  final bool settled;
  final bool busy;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final payout = game.payout;
    final lost = game.results.where((r) => r.kind == PocketKind.out).length;
    final ups = game.results.where((r) => r.kind == PocketKind.up1 || r.kind == PocketKind.up2).length;

    Widget row(String label, Map<Rarity, int> balls) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(label, style: Ty.caption),
              )),
              Expanded(
                child: balls.values.every((n) => n == 0)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('—', style: Ty.caption.copyWith(color: Ty.inkSoft)),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final r in Rarity.values)
                            if ((balls[r] ?? 0) > 0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GachaBallView(r, size: 26, shadow: false),
                                  const SizedBox(width: 2),
                                  Text('×${balls[r]}', style: Ty.numeral(13, weight: FontWeight.w700)),
                                ],
                              ),
                        ],
                      ),
              ),
            ],
          ),
        );

    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GlossSurface(
          key: const ValueKey<String>('pachinko.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pachinkoResults, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  if (ups > 0) ResultChip(text: l.pachinkoUps(ups), accent: true),
                  ResultChip(text: l.pachinkoLost(lost)),
                ],
              ),
              const SizedBox(height: 10),
              GlossSurface(
                radius: 18,
                recessed: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    row(l.pachinkoIn, game.loaded),
                    row(l.pachinkoOut, payout),
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, textAlign: TextAlign.center, style: Ty.caption.copyWith(color: T.wrong)),
              ],
              const SizedBox(height: 14),
              if (settled)
                IbashoButton(
                  key: const ValueKey<String>('pachinko.again'),
                  label: l.pachinkoAgain,
                  glyph: Glyph.refresh,
                  tone: ButtonTone.accent,
                  expand: true,
                  onPressed: onAgain,
                )
              else
                IbashoButton(
                  key: const ValueKey<String>('pachinko.retry'),
                  label: busy ? l.pachinkoSaving : l.pachinkoRetry,
                  glyph: Glyph.refresh,
                  tone: ButtonTone.accent,
                  expand: true,
                  onPressed: busy ? null : onRetry,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
