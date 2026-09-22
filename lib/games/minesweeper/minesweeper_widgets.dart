// Ibasho — piezas del canal del buscaminas: escenario, marcadores, niveles y
// resultados.
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
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/slot_tile.dart';
import '../game_stage.dart';
import 'minesweeper.dart';
import 'minesweeper_store.dart';

export '../game_stage.dart';

String formatDuration(Duration d) {
  final seconds = d.inSeconds;
  final mm = (seconds ~/ 60).toString().padLeft(2, '0');
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

String levelName(L l, MinesweeperLevel level) => switch (level) {
      MinesweeperLevel.easy => l.minesweeperEasy,
      MinesweeperLevel.medium => l.minesweeperMedium,
      MinesweeperLevel.hard => l.minesweeperHard,
    };

ArtIcon medalArt(Medal m) => switch (m) {
      Medal.gold => ArtIcon.medalGold,
      Medal.silver => ArtIcon.medalSilver,
      Medal.bronze => ArtIcon.medalBronze,
    };


/// Mina pequeña para los marcadores.
class BombIcon extends StatelessWidget {
  const BombIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BombIconPainter());
}

class _BombIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintBomb(canvas, size.center(Offset.zero).translate(-size.width * .04, size.height * .06), size.shortestSide * .3, spark: 1);

  @override
  bool shouldRepaint(_BombIconPainter old) => false;
}

/// Bandera pequeña para el interruptor.
class FlagIcon extends StatelessWidget {
  const FlagIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FlagIconPainter());
}

class _FlagIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintFlag(canvas, Offset(size.width * .46, size.height * .9), size.height * .84);

  @override
  bool shouldRepaint(_FlagIconPainter old) => false;
}

/// Una casilla tapada con una flecha de pulsar: el modo de destapar.
class DigIcon extends StatelessWidget {
  const DigIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DigIconPainter(IbashoSkin.of(context).accent));
}

class _DigIconPainter extends CustomPainter {
  _DigIconPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final r = Rect.fromCenter(center: size.center(Offset(0, s * .1)), width: s * .7, height: s * .56);
    paintPlastic(canvas, Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(s * .14))),
        Color.lerp(T.shellBottom, accent, .3)!, edge: s * .04);
    // Un dedo que toca: circulo con ondas.
    final c = Offset(r.center.dx, r.top + s * .02);
    canvas.drawCircle(c, s * .1, Paint()..color = accent);
    canvas.drawCircle(c, s * .1, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .035
      ..color = T.shellTop);
    for (final k in [.2, .3]) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: s * k), math.pi * 1.15, math.pi * .7, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .035
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: .6));
    }
  }

  @override
  bool shouldRepaint(_DigIconPainter old) => old.accent != accent;
}

// --- Interruptor destapar / bandera ----------------------------------------------

/// Dos posiciones en un rail hundido; la elegida la tapa un pomo de plastico
/// que se desliza con rebote.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({
    super.key,
    required this.flagMode,
    required this.onChanged,
    required this.digLabel,
    required this.flagLabel,
    this.height = 52,
    this.showLabels = true,
    this.width,
  });

  /// Ancho total. Sin el, cada mitad mide lo justo para su contenido.
  final double? width;

  final bool flagMode;
  final ValueChanged<bool> onChanged;
  final String digLabel;
  final String flagLabel;
  final double height;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final knob = height - 8;
    final half = width != null ? (width! - 8) / 2 : (showLabels ? height * 2.5 : height * 1.25);

    Widget option(bool flag) {
      final active = flag == flagMode;
      return Pressable(
        key: ValueKey<String>(flag ? 'minesweeper.mode.flag' : 'minesweeper.mode.dig'),
        cue: null,
        semanticLabel: flag ? flagLabel : digLabel,
        onPressed: () {
          if (active) return;
          AudioService.instance.play(Sfx.tick);
          onChanged(flag);
        },
        builder: (context, state) => SizedBox(
          width: half,
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: knob * (showLabels ? .62 : .8),
                height: knob * (showLabels ? .62 : .8),
                child: flag ? const FlagIcon() : const DigIcon(),
              ),
              if (showLabels) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    flag ? flagLabel : digLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? skin.accentDeep : Color.lerp(T.inkSoft, T.ink, state.hover)!,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: half * 2 + 8,
      height: height,
      child: GlossSurface(
        radius: height / 2,
        recessed: true,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: skin.motion(const Duration(milliseconds: 260)),
              curve: skin.curve(Curves.easeOutBack),
              alignment: flagMode ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: half,
                  height: knob,
                  child: GlossSurface(
                    radius: knob / 2,
                    tint: skin.accentWash,
                    borderColor: skin.accentDeep,
                    borderWidth: 1.6,
                    elevation: 1.2,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [option(false), option(true)]),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Niveles ------------------------------------------------------------------

/// Que tablero se juega: un nivel o el del dia.
@immutable
class BoardChoice {
  const BoardChoice.level(MinesweeperLevel this.level) : daily = false;
  const BoardChoice.daily()
      : level = null,
        daily = true;

  final MinesweeperLevel? level;
  final bool daily;

  MinesweeperLevel get effectiveLevel => level ?? MinesweeperLevel.medium;

  String get id => daily ? 'daily' : level!.name;

  static const List<BoardChoice> all = <BoardChoice>[
    BoardChoice.level(MinesweeperLevel.easy),
    BoardChoice.level(MinesweeperLevel.medium),
    BoardChoice.level(MinesweeperLevel.hard),
    BoardChoice.daily(),
  ];

  @override
  bool operator ==(Object other) => other is BoardChoice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Tarjeta de un tablero: un mini tablero dibujado, el nombre, la medida y
/// lo conseguido (medalla, sello o el tiempo de hoy).
class LevelCard extends StatelessWidget {
  const LevelCard({
    super.key,
    required this.choice,
    required this.selected,
    required this.records,
    required this.onPressed,
    required this.width,
    required this.height,
  });

  final BoardChoice choice;
  final bool selected;
  final MinesweeperRecords records;
  final VoidCallback onPressed;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final level = choice.effectiveLevel;
    final today = records.daily[dayKey(DateTime.now())];
    final medal = choice.daily ? null : records.medals[level];
    final stamp = !choice.daily && records.noFlags.contains(level);

    // Ganado hoy, el del dia se cierra hasta manana: se ve el tiempo y el
    // candado, y no se puede volver a jugar.
    final locked = choice.daily && today != null;

    final name = choice.daily ? l.minesweeperDaily : levelName(l, level);
    final sub = choice.daily
        ? (today == null ? l.minesweeperLevelSize(level.width, level.height, level.mines) : l.minesweeperDailyLocked(formatDuration(today)))
        : l.minesweeperLevelSize(level.width, level.height, level.mines);

    return SlotTile(
      key: ValueKey<String>('minesweeper.level.${choice.id}'),
      width: width,
      height: height,
      selected: selected,
      semanticLabel: name,
      onPressed: locked ? null : onPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: height * .14),
        child: Row(
          children: [
            SizedBox(
              width: height * .56,
              height: height * .56,
              child: choice.daily
                  ? const ArtIconView(ArtIcon.calendar)
                  : CustomPaint(painter: _MiniBoardPainter(level, IbashoSkin.of(context).accent)),
            ),
            SizedBox(width: height * .14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Ty.body.copyWith(fontWeight: FontWeight.w600, height: 1.15)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(height: 1.2)),
                ],
              ),
            ),
            if (locked)
              GlyphIcon(Glyph.lock, size: height * .3, color: T.inkSoft, strokeWidth: 2.2)
            else if (medal != null || stamp)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (medal != null) ArtIconView(medalArt(medal), size: height * .42),
                  if (stamp) _StampDot(size: height * .2),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StampDot extends StatelessWidget {
  const _StampDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.6,
        height: size,
        child: Center(child: SizedBox(width: size, height: size, child: const FlagIcon())),
      );
}

/// Un tablero en miniatura: mas casillas cuanto mas dificil.
class _MiniBoardPainter extends CustomPainter {
  _MiniBoardPainter(this.level, this.accent);

  final MinesweeperLevel level;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final n = switch (level) {
      MinesweeperLevel.easy => 3,
      MinesweeperLevel.medium => 4,
      MinesweeperLevel.hard => 5,
    };
    final s = size.shortestSide;
    final u = s / n;
    final rnd = math.Random(n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final r = Rect.fromLTWH(x * u + u * .08, y * u + u * .08, u * .84, u * .84);
        final open = rnd.nextDouble() < .35;
        final rr = RRect.fromRectAndRadius(r, Radius.circular(u * .22));
        if (open) {
          canvas.drawRRect(rr, Paint()..color = T.wellTop);
        } else {
          canvas.drawRRect(
            rr,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [T.shellTop, Color.lerp(T.shellBottom, accent, .35)!],
              ).createShader(r),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MiniBoardPainter old) => old.level != level || old.accent != accent;
}

// --- Resultados -------------------------------------------------------------

/// La pantalla de resultados, como las de los juegos de DS: aparece sobre el
/// tablero con un rebote. La medalla entra girando.
class ResultsCard extends StatelessWidget {
  const ResultsCard({
    super.key,
    required this.report,
    required this.daily,
    required this.reward,
    required this.rewardPending,
    required this.level,
    required this.onAgain,
    required this.onDismiss,
  });

  final WinReport report;
  final bool daily;
  final RewardOutcome? reward;
  final bool rewardPending;
  final MinesweeperLevel level;
  final VoidCallback onAgain;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);

    final medal = report.medal;
    final coinText = rewardPending
        ? l.gameCoinsPending
        : switch (reward?.status) {
            RewardStatus.granted => l.gameCoinsWon(reward!.coins),
            RewardStatus.capped => l.gameCoinsCapped,
            _ => l.gameCoinsFailed,
          };

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: skin.motion(const Duration(milliseconds: 520)),
      curve: skin.curve(Curves.easeOutBack),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: .7 + .3 * t, child: child),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlossSurface(
          key: const ValueKey<String>('minesweeper.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(daily ? l.minesweeperDailyTitle : l.minesweeperCleared,
                  style: Ty.title.copyWith(color: skin.accentDeep), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              if (!daily)
                SizedBox(
                  height: 96,
                  child: medal == null
                      ? Center(
                          child: Text(
                            l.minesweeperNoMedal(medalSeconds[level]!.$3),
                            textAlign: TextAlign.center,
                            style: Ty.caption,
                          ),
                        )
                      : TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: skin.motion(const Duration(milliseconds: 900)),
                          curve: skin.curve(Curves.elasticOut),
                          builder: (context, t, _) => Transform.scale(
                            scale: t.clamp(0.0, 2.0),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, .002)
                                ..rotateY((1 - t) * math.pi * 2),
                              child: ArtIconView(medalArt(medal), size: 96),
                            ),
                          ),
                        ),
                ),
              const SizedBox(height: 6),
              Text(formatDuration(report.time), style: Ty.numeral(40, color: T.ink, weight: FontWeight.w700)),
              Text('${l.gameBest} ${formatDuration(report.best)}', style: Ty.caption),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (report.newRecord) ResultChip(text: l.gameNewRecord, accent: true),
                  if (report.newMedal) ResultChip(text: l.minesweeperNewMedal, accent: true),
                  if (report.noFlags) ResultChip(text: l.minesweeperStampNoFlags, icon: const FlagIcon()),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ArtIconView(ArtIcon.coin, size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      coinText,
                      key: const ValueKey<String>('minesweeper.results.coins'),
                      textAlign: TextAlign.center,
                      style: Ty.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: reward?.status == RewardStatus.granted ? Art.goldDark : T.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              IbashoButton(
                key: const ValueKey<String>('minesweeper.again'),
                label: l.minesweeperNewRound,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onAgain,
              ),
              const SizedBox(height: 4),
              IbashoButton(
                label: l.minesweeperSeeBoard,
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
