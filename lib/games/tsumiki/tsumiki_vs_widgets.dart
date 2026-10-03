// Ibasho — piezas del versus de Tsumiki: el tablero pequeño del otro, la
// barra de filas grises, el medidor de trabas, la niebla y el resultado.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../backend/tsumiki_versus.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/menu_theme.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/pressable.dart';
import '../game_stage.dart';
import 'tsumiki.dart';
import 'tsumiki_board.dart';
import 'tsumiki_versus.dart';

String sabotageName(L l, TsumikiSabotage s) => switch (s) {
      TsumikiSabotage.rush => l.tsumikiSabRush,
      TsumikiSabotage.blind => l.tsumikiSabBlind,
      TsumikiSabotage.lock => l.tsumikiSabLock,
      TsumikiSabotage.fog => l.tsumikiSabFog,
    };

Glyph sabotageGlyph(TsumikiSabotage s) => switch (s) {
      TsumikiSabotage.rush => Glyph.flame,
      TsumikiSabotage.blind => Glyph.eyeOff,
      TsumikiSabotage.lock => Glyph.lock,
      TsumikiSabotage.fog => Glyph.wave,
    };

/// El tablero del otro, pequeño, tal como lo publica (`encodeBoard`).
class TsumikiMiniBoard extends StatelessWidget {
  const TsumikiMiniBoard({super.key, required this.board, required this.cell, this.over = false});

  final String board;
  final double cell;
  final bool over;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: cell * TsumikiGame.width,
        height: cell * TsumikiGame.visibleRows,
        child: RepaintBoundary(
          child: CustomPaint(painter: _MiniBoardPainter(board, IbashoSkin.of(context).surfaces, over)),
        ),
      );
}

class _MiniBoardPainter extends CustomPainter {
  _MiniBoardPainter(this.board, this.surfaces, this.over);

  final String board;
  final Surfaces surfaces;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / TsumikiGame.width;
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * .8));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surfaces.wellTop, surfaces.wellBottom],
        ).createShader(Offset.zero & size),
    );
    final cells = TsumikiGame.decodeBoard(board);
    for (var i = 0; i < cells.length; i++) {
      final p = cells[i];
      if (p == null) continue;
      final x = i % TsumikiGame.width;
      final y = i ~/ TsumikiGame.width;
      final color = over ? Color.lerp(pieceColor(p), T.inkSoft, .7)! : pieceColor(p);
      BlockStamp.paint(canvas, Rect.fromLTWH(x * c, y * c, c, c), color);
    }
  }

  @override
  bool shouldRepaint(_MiniBoardPainter old) => old.board != board || old.surfaces != surfaces || old.over != over;
}

/// La barra roja junto al pozo: filas grises que subirán al asentar la
/// siguiente pieza que no borre.
class GarbageGauge extends StatelessWidget {
  const GarbageGauge({super.key, required this.rows, required this.cell, this.width = 8});

  final int rows;
  final double cell;
  final double width;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final h = cell * TsumikiGame.visibleRows;
    final shown = rows.clamp(0, TsumikiGame.visibleRows);
    return Semantics(
      label: L.of(context)!.tsumikiVsIncoming(rows),
      child: SizedBox(
        width: width,
        height: h,
        child: GlossSurface(
          radius: width / 2,
          recessed: true,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: skin.motion(const Duration(milliseconds: 180)),
              width: width,
              height: shown * cell,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width / 2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(T.wrong, T.shellTop, .25)!, T.wrong],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Niebla sobre las filas de arriba del pozo propio.
class TsumikiFog extends StatelessWidget {
  const TsumikiFog({super.key, required this.cell, required this.on});

  final double cell;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: skin.motion(const Duration(milliseconds: 400)),
        child: Container(
          height: cell * (TsumikiDuel.fogRows + 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                skin.surfaces.wellBottom,
                skin.surfaces.wellBottom.withValues(alpha: .97),
                skin.surfaces.wellBottom.withValues(alpha: 0),
              ],
              stops: const [0, .78, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// El medidor de trabas y los cuatro botones para lanzarlas. Con el
/// medidor lleno se encienden.
class SabotageBar extends StatelessWidget {
  const SabotageBar({
    super.key,
    required this.meter,
    required this.ready,
    required this.onThrow,
    this.button = 46,
    this.vertical = false,
  });

  /// De 0 a 1.
  final double meter;
  final bool ready;
  final ValueChanged<TsumikiSabotage> onThrow;
  final double button;

  /// En dos filas de dos (columna estrecha) en vez de una fila de cuatro.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    Widget bar() => SizedBox(
          height: 12,
          child: GlossSurface(
            radius: 6,
            recessed: true,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: meter.clamp(0.0, 1.0),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: ready ? skin.accent : skin.accent.withValues(alpha: .55),
                  ),
                ),
              ),
            ),
          ),
        );
    Widget btn(TsumikiSabotage s) => _SabotageButton(
          key: ValueKey<String>('tsumiki.vs.sab.${s.name}'),
          sabotage: s,
          size: button,
          ready: ready,
          label: sabotageName(l, s),
          onPressed: () => onThrow(s),
        );
    final title = Text(
      ready ? l.tsumikiVsMeterReady : l.tsumikiVsMeter,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Ty.micro.copyWith(fontWeight: FontWeight.w600, color: ready ? skin.accentDeep : null),
    );
    const s = TsumikiSabotage.values;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 4),
        bar(),
        const SizedBox(height: 6),
        if (vertical) ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [btn(s[0]), btn(s[1])]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [btn(s[2]), btn(s[3])]),
        ] else
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final x in s) btn(x)]),
      ],
    );
  }
}

class _SabotageButton extends StatelessWidget {
  const _SabotageButton({
    super.key,
    required this.sabotage,
    required this.size,
    required this.ready,
    required this.label,
    required this.onPressed,
  });

  final TsumikiSabotage sabotage;
  final double size;
  final bool ready;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      enabled: ready,
      semanticLabel: label,
      cue: null,
      onPressed: onPressed,
      builder: (context, st) => Opacity(
        opacity: ready ? 1 : .45,
        child: SizedBox(
          width: size,
          height: size,
          child: GlossSurface(
            radius: size / 2,
            tint: ready ? skin.accent : null,
            elevation: ready ? 1.6 - st.press : .4,
            sink: st.press,
            child: Center(
              child: GlyphIcon(
                sabotageGlyph(sabotage),
                size: size * .46,
                color: ready ? T.onAccent : skin.accentDeep,
                strokeWidth: 2.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Las trabas que estoy sufriendo, en pastillas pequeñas con su icono.
class SufferedTricks extends StatelessWidget {
  const SufferedTricks({super.key, required this.active, this.size = 26});

  final Iterable<TsumikiSabotage> active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final s in active)
          Semantics(
            label: sabotageName(l, s),
            child: SizedBox(
              width: size,
              height: size,
              child: GlossSurface(
                radius: size / 2,
                tint: T.wrong,
                elevation: .8,
                child: Center(child: GlyphIcon(sabotageGlyph(s), size: size * .55, color: T.onAccent, strokeWidth: 2.2)),
              ),
            ),
          ),
      ],
    );
  }
}

/// El final del versus: quién gana y por qué, el marcador, lo de cada uno y
/// la revancha.
class TsumikiVsResultCard extends StatelessWidget {
  const TsumikiVsResultCard({
    super.key,
    required this.won,
    required this.end,
    required this.friendName,
    required this.myLines,
    required this.mySent,
    required this.theirLines,
    required this.theirSent,
    required this.score,
    required this.rematchOffered,
    required this.rematchBusy,
    required this.onRematch,
    required this.onExit,
  });

  final bool won;
  final TsumikiEnd? end;
  final String friendName;
  final int myLines;
  final int mySent;
  final int theirLines;
  final int theirSent;
  final TsumikiScore? score;
  final bool rematchOffered;
  final bool rematchBusy;
  final VoidCallback onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final why = switch ((end, won)) {
      (TsumikiEnd.top, true) => l.tsumikiVsWhyTopThem(friendName),
      (TsumikiEnd.top, false) => l.tsumikiVsWhyTopMe,
      (TsumikiEnd.leave, true) => l.tsumikiVsWhyLeaveThem(friendName),
      (TsumikiEnd.leave, false) => l.tsumikiVsWhyLeaveMe,
      (TsumikiEnd.quit, true) => l.tsumikiVsWhyQuitThem(friendName),
      (TsumikiEnd.quit, false) => l.tsumikiVsWhyQuitMe,
      (null, _) => '',
    };
    Widget side(String who, int lines, int sent) => Expanded(
          child: Column(
            children: [
              Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('$lines', style: Ty.numeral(22, color: skin.accentDeep, weight: FontWeight.w700)),
              Text(l.tsumikiLines, style: Ty.micro),
              const SizedBox(height: 4),
              Text('$sent', style: Ty.numeral(18, color: Ty.ink, weight: FontWeight.w700)),
              Text(l.tsumikiVsSent, style: Ty.micro),
            ],
          ),
        );
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GlossSurface(
          key: const ValueKey<String>('tsumiki.vs.result'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won ? l.tsumikiVsWon : l.tsumikiVsLost(friendName),
                textAlign: TextAlign.center,
                style: Ty.title.copyWith(color: won ? skin.accentDeep : Ty.ink),
              ),
              if (why.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(why, textAlign: TextAlign.center, style: Ty.caption),
              ],
              if (score case final s?) ...[
                const SizedBox(height: 10),
                Text(l.tsumikiVsScore, style: Ty.micro.copyWith(fontWeight: FontWeight.w600)),
                Text('${s.mine} – ${s.theirs}', style: Ty.numeral(34, color: Ty.ink, weight: FontWeight.w700)),
              ],
              const SizedBox(height: 10),
              GlossSurface(
                radius: 18,
                recessed: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [side(l.tsumikiVsYou, myLines, mySent), side(friendName, theirLines, theirSent)],
                ),
              ),
              if (rematchOffered) ...[
                const SizedBox(height: 10),
                ResultChip(text: l.tsumikiVsRematchOffered(friendName), accent: true),
              ],
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('tsumiki.vs.rematch'),
                label: rematchOffered ? l.tsumikiVsRematchAccept : l.tsumikiVsRematch,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: rematchBusy ? null : onRematch,
              ),
              const SizedBox(height: 4),
              IbashoButton(
                key: const ValueKey<String>('tsumiki.vs.exit'),
                label: l.tsumikiVsExit,
                tone: ButtonTone.quiet,
                height: 40,
                cue: Sfx.back,
                onPressed: onExit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
