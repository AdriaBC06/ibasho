// Ibasho — piezas del canal de Tsumiki: los mandos de DS, los huecos de la
// siguiente y la guardada, los carteles y las pantallas de salida y final.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../game_stage.dart';
import 'tsumiki.dart';
import 'tsumiki_board.dart';
import 'tsumiki_store.dart';

// --- Mandos -------------------------------------------------------------------

/// Un boton de mando que se mantiene: avisa al bajar y al subir el dedo, no
/// al soltar como un boton normal, para que mover y bajar se repitan
/// mientras se tiene pulsado.
class PadButton extends StatefulWidget {
  const PadButton({
    super.key,
    required this.onDown,
    this.onUp,
    required this.semanticLabel,
    this.letter,
    this.glyph,
    this.size = 60,
    this.accent = false,
  });

  final VoidCallback onDown;
  final VoidCallback? onUp;
  final String semanticLabel;
  final String? letter;
  final Glyph? glyph;
  final double size;

  /// El boton principal (girar), tintado con el acento.
  final bool accent;

  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
    down ? widget.onDown() : widget.onUp?.call();
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final s = widget.size;
    final ink = widget.accent ? T.onAccent : skin.accentDeep;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: () {
        widget.onDown();
        widget.onUp?.call();
      },
      child: Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? .92 : 1,
          duration: skin.motion(const Duration(milliseconds: 90)),
          child: SizedBox(
            width: s,
            height: s,
            child: GlossSurface(
              radius: s / 2,
              tint: widget.accent ? skin.accent : null,
              elevation: _down ? .4 : 1.6,
              sink: _down ? 1 : 0,
              child: Center(
                child: widget.letter != null
                    ? Text(widget.letter!, style: Ty.numeral(s * .4, color: ink, weight: FontWeight.w700))
                    : GlyphIcon(widget.glyph!, size: s * .46, color: ink, strokeWidth: 2.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum PadDir { left, right, up, down }

/// La cruceta: una cruz de plastico con cuatro flechas. Se puede deslizar el
/// dedo de un brazo a otro sin levantarlo, como en una DS.
class DPad extends StatefulWidget {
  const DPad({super.key, required this.onDown, required this.onUp, this.size = 140, required this.semanticLabel});

  final ValueChanged<PadDir> onDown;
  final ValueChanged<PadDir> onUp;
  final double size;
  final String semanticLabel;

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  PadDir? _dir;

  PadDir? _hit(Offset p) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final d = p - c;
    if (d.distance < widget.size * .1) return _dir;
    if (d.dx.abs() > d.dy.abs()) return d.dx < 0 ? PadDir.left : PadDir.right;
    return d.dy < 0 ? PadDir.up : PadDir.down;
  }

  void _to(PadDir? dir) {
    if (dir == _dir) return;
    final old = _dir;
    setState(() => _dir = dir);
    if (old != null) widget.onUp(old);
    if (dir != null) widget.onDown(dir);
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Semantics(
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: (e) => _to(_hit(e.localPosition)),
        onPointerMove: (e) => _to(_hit(e.localPosition)),
        onPointerUp: (_) => _to(null),
        onPointerCancel: (_) => _to(null),
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _DPadPainter(_dir, skin.accent, skin.accentDeep),
        ),
      ),
    );
  }
}

class _DPadPainter extends CustomPainter {
  const _DPadPainter(this.dir, this.accent, this.accentDeep);

  final PadDir? dir;
  final Color accent;
  final Color accentDeep;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final arm = s * .36;
    final c = Offset(s / 2, s / 2);
    // El hueco donde encaja la cruz.
    canvas.drawCircle(
      c,
      s * .5,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.wellTop, T.wellBottom],
        ).createShader(Offset.zero & size),
    );
    final union = Path.combine(
      PathOperation.union,
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * .92, height: arm), Radius.circular(arm * .28))),
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: arm, height: s * .92), Radius.circular(arm * .28))),
    );
    canvas.drawPath(
      union.shift(const Offset(0, 3)),
      Paint()
        ..color = T.shadowDeep
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    paintPlastic(canvas, union, T.shellBottom, edge: 1.6);
    // El brazo pulsado se hunde y se tiñe.
    final d = dir;
    if (d != null) {
      final r = switch (d) {
        PadDir.left => Rect.fromLTWH(s * .04, c.dy - arm / 2, s * .32, arm),
        PadDir.right => Rect.fromLTWH(s * .64, c.dy - arm / 2, s * .32, arm),
        PadDir.up => Rect.fromLTWH(c.dx - arm / 2, s * .04, arm, s * .32),
        PadDir.down => Rect.fromLTWH(c.dx - arm / 2, s * .64, arm, s * .32),
      };
      canvas.save();
      canvas.clipPath(union);
      canvas.drawRect(r, Paint()..color = accent.withValues(alpha: .35));
      canvas.restore();
    }
    // Hoyuelo del centro y flechas.
    canvas.drawCircle(c, arm * .22, Paint()..color = T.dusk.withValues(alpha: .08));
    for (final dd in PadDir.values) {
      final (dx, dy) = switch (dd) {
        PadDir.left => (-1.0, 0.0),
        PadDir.right => (1.0, 0.0),
        PadDir.up => (0.0, -1.0),
        PadDir.down => (0.0, 1.0),
      };
      final tip = c + Offset(dx, dy) * s * .37;
      final back = c + Offset(dx, dy) * s * .27;
      final side = Offset(-dy, dx) * s * .06;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(back.dx + side.dx, back.dy + side.dy)
          ..lineTo(back.dx - side.dx, back.dy - side.dy)
          ..close(),
        Paint()..color = (dd == d ? accentDeep : T.inkSoft).withValues(alpha: .85),
      );
    }
  }

  @override
  bool shouldRepaint(_DPadPainter old) => old.dir != dir || old.accent != accent;
}

// --- Huecos -------------------------------------------------------------------

/// Un hueco de cristal con su etiqueta: la pieza guardada o las siguientes.
class PiecePocket extends StatelessWidget {
  const PiecePocket({
    super.key,
    required this.label,
    required this.pieces,
    this.width = 96,
    this.muted = false,
  });

  final String label;
  final List<TsumikiPiece?> pieces;
  final double width;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        GlossSurface(
          radius: width * .22,
          recessed: true,
          padding: EdgeInsets.symmetric(horizontal: width * .1, vertical: width * .1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < pieces.length; i++) ...[
                if (i > 0) SizedBox(height: width * .06),
                // La primera de las siguientes, grande; las demas, menores.
                AnimatedSwitcher(
                  duration: IbashoSkin.of(context).motion(const Duration(milliseconds: 220)),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, .5), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: PiecePreview(
                    key: ValueKey<String>('$i.${pieces[i]}'),
                    piece: pieces[i],
                    size: width * (i == 0 ? .8 : .6),
                    muted: muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// --- Carteles -----------------------------------------------------------------

/// Cartel que salta sobre el tablero: «¡tsumiki!», «combo ×3», «nivel 4»,
/// la cuenta atras. Entra con rebote y se va solo.
class PopBanner extends StatelessWidget {
  const PopBanner({super.key, required this.text, this.big = false});

  final String? text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final t = text;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: skin.motion(const Duration(milliseconds: 280)),
        switchInCurve: skin.curve(Curves.easeOutBack),
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween<double>(begin: .5, end: 1).animate(a), child: child),
        ),
        child: t == null
            ? const SizedBox.shrink(key: ValueKey<String>('banner.none'))
            : GlossSurface(
                key: ValueKey<String>('banner.$t'),
                radius: 22,
                tint: skin.accent,
                elevation: 2.4,
                padding: EdgeInsets.symmetric(horizontal: big ? 26 : 18, vertical: big ? 10 : 6),
                child: Text(
                  t,
                  style: (big ? Ty.numeral(44, color: T.onAccent, weight: FontWeight.w700) : Ty.title.copyWith(color: T.onAccent, fontWeight: FontWeight.w700)),
                ),
              ),
      ),
    );
  }
}

/// Lo que se enseña antes de empezar: el nivel de salida, lo que se gana y
/// el boton de jugar.
class TsumikiReadyCard extends StatelessWidget {
  const TsumikiReadyCard({
    super.key,
    required this.startLevel,
    required this.onLevel,
    required this.onStart,
    required this.records,
    this.showKeys = false,
  });

  final int startLevel;
  final ValueChanged<int> onLevel;
  final VoidCallback onStart;
  final TsumikiRecords records;
  final bool showKeys;

  static const List<int> levels = [1, 5, 10, 15];

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: GlossSurface(
          key: const ValueKey<String>('tsumiki.ready'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ArtIconView(ArtIcon.tsumiki, size: 64),
              const SizedBox(height: 6),
              Text(l.tsumikiReadyTitle, textAlign: TextAlign.center, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 4),
              Text(l.tsumikiReadyHint, textAlign: TextAlign.center, style: Ty.caption),
              const SizedBox(height: 12),
              _RewardLadder(),
              const SizedBox(height: 12),
              Text(l.tsumikiStartLevel, style: Ty.micro.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentRail(
                height: 40,
                children: [
                  for (final lv in levels)
                    SegmentPill(
                      key: ValueKey<String>('tsumiki.level.$lv'),
                      label: '$lv',
                      height: 40,
                      selected: lv == startLevel,
                      onPressed: () => onLevel(lv),
                    ),
                ],
              ),
              if (records.bestScore > 0) ...[
                const SizedBox(height: 10),
                Text('${l.gameBest}: ${records.bestScore} · ${l.tsumikiLinesCount(records.bestLines)}', style: Ty.caption),
              ],
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('tsumiki.start'),
                label: l.tsumikiStart,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onStart,
              ),
              if (showKeys) ...[
                const SizedBox(height: 10),
                Text(l.tsumikiKeys, textAlign: TextAlign.center, style: Ty.micro),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// «10 filas → 3, 25 → 5, 50 → 8», con monedas pintadas.
class _RewardLadder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    Widget step(int lines, int coins) => Column(
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
            Text(l.tsumikiLinesCount(lines), style: Ty.micro),
          ],
        );
    return GlossSurface(
      radius: 18,
      recessed: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [step(10, 3), step(25, 5), step(50, 8)],
      ),
    );
  }
}

/// La pausa: la partida queda tapada (sin mirar donde caera la siguiente).
class TsumikiPauseCard extends StatelessWidget {
  const TsumikiPauseCard({super.key, required this.onResume, required this.onRestart});

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
          key: const ValueKey<String>('tsumiki.paused'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.tsumikiPause, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('tsumiki.resume'),
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

// --- Resultados -----------------------------------------------------------------

class TsumikiResultsCard extends StatelessWidget {
  const TsumikiResultsCard({
    super.key,
    required this.report,
    required this.reward,
    required this.rewardPending,
    required this.onAgain,
    required this.onDismiss,
  });

  final TsumikiReport report;
  final RewardOutcome? reward;
  final bool rewardPending;
  final VoidCallback onAgain;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final earns = tsumikiRewardFor(report.lines) > 0;
    final coinText = earns ? rewardText(l, reward, rewardPending) : l.tsumikiCoinsHint(10 - report.lines);

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
          key: const ValueKey<String>('tsumiki.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.tsumikiGameOver, style: Ty.title.copyWith(color: skin.accentDeep), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              // La puntuacion sube contando, como en los resultados de DS.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: report.score.toDouble()),
                duration: skin.motion(Duration(milliseconds: math.min(1400, 400 + report.score ~/ 20))),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  '${v.round()}',
                  style: Ty.numeral(42, color: T.ink, weight: FontWeight.w700),
                ),
              ),
              Text('${l.gameBest} ${report.best}', style: Ty.caption),
              const SizedBox(height: 10),
              GlossSurface(
                radius: 18,
                recessed: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    stat('${report.lines}', l.tsumikiLines),
                    stat('${report.level}', l.tsumikiLevel),
                    stat('${report.tsumikis}', l.tsumikiTitle),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (report.newRecord) ResultChip(text: l.gameNewRecord, accent: true),
                  if (report.newLines) ResultChip(text: l.tsumikiChipLines, accent: !report.newRecord),
                  if (report.maxCombo >= 3) ResultChip(text: l.tsumikiBannerCombo(report.maxCombo)),
                ],
              ),
              const SizedBox(height: 10),
              CoinLine(text: coinText, granted: reward?.status == RewardStatus.granted),
              const SizedBox(height: 16),
              IbashoButton(
                key: const ValueKey<String>('tsumiki.again'),
                label: l.tsumikiNewGame,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onAgain,
              ),
              const SizedBox(height: 4),
              IbashoButton(
                label: l.tsumikiSeeTower,
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
