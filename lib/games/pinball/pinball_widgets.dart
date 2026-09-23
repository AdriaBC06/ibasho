// Ibasho — las tarjetas del pinball: cargar bolas, premio, bola perdida,
// pausa y resultados.
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
import '../../ui/screens/channels/gacha_channel.dart' show categoryName;
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gacha_art.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/prize_view.dart';
import '../game_stage.dart';
import 'pinball.dart';
import 'pinball_catalog.dart';

/// Una bola con lo que la hace especial: el icono de su categoria si es
/// dirigida y un corazon si la cuida el Tama.
class QueueBall extends StatelessWidget {
  const QueueBall(this.ball, {super.key, this.size = 40, this.faded = false});

  final GachaBall ball;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final category = ball.category;
    return Opacity(
      opacity: faded ? .35 : 1,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GachaBallView(ball.rarity, size: size, shadow: false),
            if (category != null)
              Positioned(right: -size * .12, bottom: -size * .1, child: CategoryArtView(category, size: size * .5)),
            if (isGuarded(ball))
              Positioned(
                left: -size * .08,
                top: -size * .08,
                child: GlyphIcon(Glyph.heart, size: size * .34, color: skin.accentDeep, strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

/// Antes de jugar: el deposito y la cola. Tocar una bola del deposito la
/// pone al final de la cola; tocar una de la cola la devuelve. Salen en ese
/// orden.
class PinballLoadCard extends StatelessWidget {
  const PinballLoadCard({
    super.key,
    required this.gacha,
    required this.queue,
    required this.best,
    required this.busy,
    required this.error,
    required this.showKeys,
    required this.onAdd,
    required this.onRemove,
    required this.onPlay,
    required this.onCatalog,
  });

  final GachaState gacha;
  final List<GachaBall> queue;
  final int best;
  final bool busy;
  final String? error;
  final bool showKeys;
  final ValueChanged<GachaBall> onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onPlay;
  final VoidCallback onCatalog;

  int _queued(GachaBall b) => queue.where((q) => q.rarity == b.rarity && q.category == b.category).length;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final stock = <(GachaBall, int)>[
      for (final rarity in Rarity.values)
        if (gacha.ballsOf(rarity) > 0) (GachaBall(rarity), gacha.ballsOf(rarity)),
      for (final category in GachaCategory.values)
        for (final rarity in Rarity.values)
          if (gacha.markedOf(category, rarity) > 0)
            (GachaBall(rarity, category: category), gacha.markedOf(category, rarity)),
    ];
    final full = queue.length >= pinballQueueMax;

    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GlossSurface(
          key: const ValueKey<String>('pinball.load'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pinballLoadTitle, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 2),
              Text(l.pinballLoadHint, textAlign: TextAlign.center, style: Ty.caption),
              const SizedBox(height: 10),
              PinballWishBar(wish: gacha.wish, onPressed: onCatalog),
              const SizedBox(height: 10),
              // La cola: cinco huecos.
              GlossSurface(
                radius: 20,
                recessed: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < pinballQueueMax; i++)
                      i < queue.length
                          ? GestureDetector(
                              key: ValueKey<String>('pinball.queue.$i'),
                              onTap: busy
                                  ? null
                                  : () {
                                      AudioService.instance.play(Sfx.back);
                                      onRemove(i);
                                    },
                              child: QueueBall(queue[i], size: 40),
                            )
                          : SizedBox(
                              width: 40,
                              height: 40,
                              child: GlossSurface(
                                radius: 20,
                                recessed: true,
                                child: Center(child: Text('${i + 1}', style: Ty.micro)),
                              ),
                            ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(queue.isEmpty ? l.pinballQueueEmpty : l.pinballGuarded, style: Ty.micro),
              const SizedBox(height: 10),
              if (stock.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l.pinballNoBalls, textAlign: TextAlign.center, style: Ty.body.copyWith(color: T.inkSoft)),
                )
              else
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (ball, count) in stock)
                      _StockBall(
                        ball: ball,
                        left: count - _queued(ball),
                        enabled: !busy && !full && count - _queued(ball) > 0,
                        onTap: () {
                          AudioService.instance.play(Sfx.tick);
                          onAdd(ball);
                        },
                      ),
                  ],
                ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, textAlign: TextAlign.center, style: Ty.caption.copyWith(color: T.wrong)),
              ],
              if (best > 0) ...[
                const SizedBox(height: 10),
                Text('${l.gameBest}: $best', style: Ty.caption),
              ],
              const SizedBox(height: 12),
              IbashoButton(
                key: const ValueKey<String>('pinball.play'),
                label: l.pinballPlay,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                cue: Sfx.open,
                onPressed: queue.isEmpty || busy ? null : onPlay,
              ),
              const SizedBox(height: 8),
              Text(showKeys ? l.pinballKeys : l.pinballTouchHint, textAlign: TextAlign.center, style: Ty.micro),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockBall extends StatelessWidget {
  const _StockBall({required this.ball, required this.left, required this.enabled, required this.onTap});

  final GachaBall ball;
  final int left;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: ValueKey<String>('pinball.stock.${ball.rarity.name}.${ball.category?.name ?? '-'}'),
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QueueBall(ball, size: 38, faded: left <= 0),
            const SizedBox(height: 2),
            Text('×$left', style: Ty.numeral(13, weight: FontWeight.w700)),
          ],
        ),
      );
}

/// El premio de una bola: la pieza que ha tocado, con su nombre, su rareza
/// y si es nueva o cuantas hay ya. Vale para las cuatro categorias: gorros,
/// accesorios, fondos y musicas.
class PinballPrizeCard extends StatelessWidget {
  const PinballPrizeCard({
    super.key,
    required this.outcome,
    required this.copies,
    required this.last,
    required this.onNext,
  });

  final PinballOutcome outcome;

  /// Copias de la pieza en la coleccion, contando esta.
  final int copies;
  final bool last;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final category = outcome.category!;
    final key = outcome.prize;
    final rarity = outcome.ball.rarity;
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: GlossSurface(
          key: const ValueKey<String>('pinball.prize'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pinballPrizeTitle, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 8),
              if (key != null)
                GlossSurface(
                  radius: 24,
                  recessed: true,
                  tint: RarityArt.of(rarity),
                  padding: const EdgeInsets.all(10),
                  child: GachaPrizeView(key, size: 96),
                )
              else
                CategoryArtView(category, size: 96),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      key != null ? gachaPrizeName(l, key) : categoryName(l, category),
                      key: const ValueKey<String>('pinball.prize.name'),
                      style: Ty.body.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  RarityBadge(rarity, height: 22),
                ],
              ),
              const SizedBox(height: 8),
              if (key == null)
                const SizedBox.shrink()
              else if (copies <= 1)
                ResultChip(text: l.pinballPrizeNew, accent: true)
              else
                Text(l.pinballPrizeCopies(copies), textAlign: TextAlign.center, style: Ty.micro),
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('pinball.next'),
                label: last ? l.pinballSeeResults : l.pinballNext,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La bola se ha ido: se consuela, no se castiga.
class PinballLostCard extends StatelessWidget {
  const PinballLostCard({super.key, required this.ball, required this.last, required this.onNext});

  final GachaBall ball;
  final bool last;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: GlossSurface(
          key: const ValueKey<String>('pinball.lost'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pinballLostTitle, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 10),
              QueueBall(ball, size: 56, faded: true),
              const SizedBox(height: 10),
              Text(l.pinballLostBody, textAlign: TextAlign.center, style: Ty.caption),
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('pinball.next'),
                label: last ? l.pinballSeeResults : l.pinballNext,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PinballPauseCard extends StatelessWidget {
  const PinballPauseCard({
    super.key,
    required this.onResume,
    this.returnable = 0,
    this.onCancel,
    this.busy = false,
    this.error,
  });

  final VoidCallback onResume;

  /// Cuantas bolas vuelven al cancelar; 0 si ya no se puede.
  final int returnable;
  final VoidCallback? onCancel;
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
          key: const ValueKey<String>('pinball.paused'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pinballPause, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 6),
              Text(l.pinballResumeHint, textAlign: TextAlign.center, style: Ty.caption),
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('pinball.resume'),
                label: l.pinballResume,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: busy ? null : onResume,
              ),
              if (returnable > 0 && onCancel != null) ...[
                const SizedBox(height: 14),
                Text(l.pinballCancelHint, textAlign: TextAlign.center, style: Ty.caption),
                const SizedBox(height: 8),
                IbashoButton(
                  key: const ValueKey<String>('pinball.cancel'),
                  label: l.pinballCancel(returnable),
                  glyph: Glyph.undo,
                  expand: true,
                  cue: Sfx.back,
                  onPressed: busy ? null : onCancel,
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

class PinballResultsCard extends StatelessWidget {
  const PinballResultsCard({
    super.key,
    required this.outcomes,
    required this.score,
    required this.best,
    required this.newRecord,
    required this.onAgain,
    this.unsaved = false,
  });

  final List<PinballOutcome> outcomes;
  final int score;
  final int best;
  final bool newRecord;
  final VoidCallback onAgain;

  /// Hay bolas jugadas que no se han podido guardar: se reintenta al volver
  /// a jugar.
  final bool unsaved;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GlossSurface(
          key: const ValueKey<String>('pinball.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.pinballResults, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: score.toDouble()),
                duration: skin.motion(const Duration(milliseconds: 1200)),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text('${v.round()}', style: Ty.numeral(40, color: T.ink, weight: FontWeight.w700)),
              ),
              Text('${l.gameBest} $best', style: Ty.caption),
              if (newRecord) ...[
                const SizedBox(height: 6),
                ResultChip(text: l.gameNewRecord, accent: true),
              ],
              const SizedBox(height: 12),
              GlossSurface(
                radius: 18,
                recessed: true,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Column(
                  children: [
                    for (final o in outcomes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            QueueBall(o.ball, size: 30),
                            const SizedBox(width: 10),
                            if (o.won) ...[
                              if (o.prize case final key?)
                                GachaPrizeView(key, size: 30)
                              else
                                CategoryArtView(o.category!, size: 30),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  o.prize != null ? gachaPrizeName(l, o.prize!) : categoryName(l, o.category!),
                                  style: Ty.body,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              RarityBadge(o.ball.rarity, height: 18),
                            ] else
                              Expanded(child: Text(l.pinballLostTitle, style: Ty.body.copyWith(color: T.inkSoft))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (unsaved) ...[
                const SizedBox(height: 8),
                Text(
                  l.pinballUnsaved,
                  key: const ValueKey<String>('pinball.unsaved'),
                  textAlign: TextAlign.center,
                  style: Ty.caption.copyWith(color: T.wrong),
                ),
              ],
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('pinball.again'),
                label: l.pinballAgain,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onAgain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sin Tamas no se juega: son quienes cuidan las bolas.
class PinballNeedTamaCard extends StatelessWidget {
  const PinballNeedTamaCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: GlossSurface(
          key: const ValueKey<String>('pinball.needTama'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlossyFace(joy: -.2, size: 72),
              const SizedBox(height: 8),
              Text(l.pinballNeedTama, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 6),
              Text(l.pinballNeedTamaBody, textAlign: TextAlign.center, style: Ty.caption),
            ],
          ),
        ),
      ),
    );
  }
}
