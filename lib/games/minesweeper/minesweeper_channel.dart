// Ibasho — canal del buscaminas: dos pantallas, estilo DS.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/tamas.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/panel.dart';
import 'minesweeper.dart';
import 'minesweeper_store.dart';

/// El canal del buscaminas, montado como el propio entorno: dos pantallas.
///
/// Arriba, tu Tama hace de carita del juego —nervioso al destapar, contento
/// al ganar, KO al perder— junto al contador de minas, el cronometro, el
/// mejor tiempo y un minimapa en vivo del tablero. Abajo, el tablero tactil.
class MinesweeperChannel extends ConsumerStatefulWidget {
  const MinesweeperChannel({super.key});

  @override
  ConsumerState<MinesweeperChannel> createState() => _MinesweeperChannelState();
}

class _MinesweeperChannelState extends ConsumerState<MinesweeperChannel> {
  MinesweeperLevel _level = MinesweeperLevel.easy;
  late MinesweeperGame _game = MinesweeperGame(_level);

  /// -1 (KO) a 1 (encantado). En reposo se queda un poco por encima de
  /// neutro: el Tama esta a gusto viendo jugar.
  double _joy = .1;
  Timer? _joyReset;

  Stopwatch? _stopwatch;
  Timer? _ticker;

  MinesweeperStore? _store;
  Map<MinesweeperLevel, Duration> _bestTimes = const <MinesweeperLevel, Duration>{};

  bool _flagMode = false;

  /// Solo se usa en dificil sobre un lienzo vertical: el tablero no cabe
  /// entero y se desplaza y amplia con el dedo.
  final TransformationController _viewController = TransformationController();
  Size? _viewportSize;

  @override
  void initState() {
    super.initState();
    _viewController.addListener(_onViewChanged);
    unawaited(_loadStore());
  }

  Future<void> _loadStore() async {
    final store = await MinesweeperStore.open();
    final best = await store.loadBestTimes();
    if (!mounted) return;
    setState(() {
      _store = store;
      _bestTimes = best;
    });
  }

  @override
  void dispose() {
    _joyReset?.cancel();
    _ticker?.cancel();
    _viewController.removeListener(_onViewChanged);
    _viewController.dispose();
    super.dispose();
  }

  void _onViewChanged() {
    if (mounted) setState(() {});
  }

  void _restart([MinesweeperLevel? level]) {
    _joyReset?.cancel();
    _ticker?.cancel();
    _stopwatch = null;
    _viewController.value = Matrix4.identity();
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _level = level ?? _level;
      _game = MinesweeperGame(_level);
      _joy = .1;
      _flagMode = false;
    });
  }

  void _startTimerIfNeeded() {
    if (_stopwatch != null) return;
    _stopwatch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch?.stop();
  }

  void _bumpJoy(double value, {required bool sticky}) {
    _joyReset?.cancel();
    _joy = value;
    if (sticky) return;
    _joyReset = Timer(const Duration(milliseconds: 480), () {
      if (mounted) setState(() => _joy = .1);
    });
  }

  Future<void> _recordBestIfNeeded() async {
    final store = _store;
    final elapsed = _stopwatch?.elapsed;
    if (store == null || elapsed == null) return;
    final next = await store.recordTime(_bestTimes, _level, elapsed);
    if (mounted) setState(() => _bestTimes = next);
  }

  void _afterMove({required bool wasReady}) {
    if (wasReady && _game.status == MinesweeperStatus.playing) _startTimerIfNeeded();
    switch (_game.status) {
      case MinesweeperStatus.won:
        _stopTimer();
        AudioService.instance.play(Sfx.chime);
        _bumpJoy(1, sticky: true);
        unawaited(_recordBestIfNeeded());
      case MinesweeperStatus.lost:
        _stopTimer();
        AudioService.instance.play(Sfx.error);
        _bumpJoy(-1, sticky: true);
      case MinesweeperStatus.playing:
        AudioService.instance.play(Sfx.tick);
        _bumpJoy(-.35, sticky: false);
      case MinesweeperStatus.ready:
        break;
    }
    setState(() {});
  }

  void _reveal(int x, int y) {
    if (_game.isOver) return;
    final wasReady = _game.status == MinesweeperStatus.ready;
    _game.reveal(x, y);
    _afterMove(wasReady: wasReady);
  }

  void _toggleFlag(int x, int y) {
    if (_game.isOver) return;
    final wasReady = _game.status == MinesweeperStatus.ready;
    _game.toggleFlag(x, y);
    if (wasReady && _game.status != MinesweeperStatus.ready) _startTimerIfNeeded();
    AudioService.instance.play(Sfx.tick);
    setState(() {});
  }

  void _cellTap(int x, int y) => _flagMode ? _toggleFlag(x, y) : _reveal(x, y);

  Tama? _favouriteTama(TamasState state) =>
      state.profileTama ?? (state.tamas.isEmpty ? null : state.tamas.first);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tamas = ref.watch(tamasProvider);
    final tama = _favouriteTama(tamas);

    return ChannelScaffold(
      title: l.minesweeperTitle,
      glyph: Glyph.mine,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: LayoutBuilder(builder: (context, box) {
          final showcase = layout.tall
              ? math.max(200.0, math.min(300.0, box.maxHeight * .38))
              : 280.0;
          return Column(
            children: [
              const SizedBox(height: 14),
              SizedBox(
                height: showcase,
                child: ScreenPanel(
                  child: _TopPanel(
                    tama: tama,
                    joy: _joy,
                    level: _level,
                    status: _game.status,
                    minesLeft: _game.minesLeft,
                    elapsed: _stopwatch?.elapsed ?? Duration.zero,
                    best: _bestTimes[_level],
                    onSelectLevel: _restart,
                    minimap: _MinimapData(
                      game: _game,
                      visible: _visibleBoardRect(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ScreenPanel(
                  child: _BottomPanel(
                    game: _game,
                    flagMode: _flagMode,
                    onFlagModeChanged: (v) => setState(() => _flagMode = v),
                    onRestart: () => _restart(),
                    onCellTap: _cellTap,
                    onCellFlag: _toggleFlag,
                    viewController: _viewController,
                    onViewportSize: (size) {
                      if (_viewportSize == size) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _viewportSize = size);
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        }),
      ),
    );
  }

  Rect? _visibleBoardRect() {
    final viewportSize = _viewportSize;
    if (viewportSize == null) return null;
    final inverse = _tryInvert(_viewController.value);
    if (inverse == null) return null;
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight =
        MatrixUtils.transformPoint(inverse, Offset(viewportSize.width, viewportSize.height));
    return Rect.fromPoints(topLeft, bottomRight);
  }
}

/// La matriz inversa de la transformacion en curso, o `null` si no se puede
/// invertir (por ejemplo, con escala cero en un primer frame).
Matrix4? _tryInvert(Matrix4 m) {
  final copy = m.clone();
  final det = copy.invert();
  if (det == 0) return null;
  return copy;
}

// --- Pantalla de arriba -------------------------------------------------------

/// Lo que necesita el minimapa: el tablero y, si el de abajo esta ampliado,
/// la zona que se ve.
class _MinimapData {
  const _MinimapData({required this.game, required this.visible});

  final MinesweeperGame game;

  /// En coordenadas del tablero (unidad = una casilla). `null` cuando se ve
  /// entero.
  final Rect? visible;
}

class _TopPanel extends StatelessWidget {
  const _TopPanel({
    required this.tama,
    required this.joy,
    required this.level,
    required this.status,
    required this.minesLeft,
    required this.elapsed,
    required this.best,
    required this.onSelectLevel,
    required this.minimap,
  });

  final Tama? tama;
  final double joy;
  final MinesweeperLevel level;
  final MinesweeperStatus status;
  final int minesLeft;
  final Duration elapsed;
  final Duration? best;
  final ValueChanged<MinesweeperLevel> onSelectLevel;
  final _MinimapData minimap;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tall = layout.tall;
    final skin = IbashoSkin.of(context);

    final face = SizedBox(
      width: tall ? 120 : 170,
      height: tall ? 120 : 170,
      child: Center(
        child: tama == null
            ? _SimpleFace(joy: joy, size: tall ? 96 : 140)
            : TamaOnStand(tama: tama!, size: tall ? 96 : 140, joy: joy),
      ),
    );

    final stats = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: _StatChip(glyph: Glyph.mine, value: '$minesLeft')),
            const SizedBox(width: 10),
            Expanded(child: _StatChip(glyph: Glyph.clock, value: _formatDuration(elapsed))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(l.minesweeperBest, style: Ty.caption),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                best == null ? '--:--' : _formatDuration(best!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ty.numeral(16, color: skin.accentDeep),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DifficultyRow(level: level, onSelect: onSelectLevel),
        if (status == MinesweeperStatus.won || status == MinesweeperStatus.lost) ...[
          const SizedBox(height: 10),
          Text(
            status == MinesweeperStatus.won ? l.minesweeperWin : l.minesweeperLose,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ty.lead.copyWith(
              color: status == MinesweeperStatus.won ? skin.accentDeep : T.warn,
            ),
          ),
        ],
      ],
    );

    final map = SizedBox(
      width: tall ? double.infinity : 150,
      height: tall ? 84 : 150,
      child: _Minimap(data: minimap),
    );

    if (tall) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                face,
                const SizedBox(width: 12),
                Expanded(child: stats),
              ],
            ),
            const SizedBox(height: 10),
            map,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 20, 30, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          face,
          const SizedBox(width: 24),
          Expanded(child: stats),
          const SizedBox(width: 24),
          map,
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final seconds = d.inSeconds;
  final mm = (seconds ~/ 60).toString().padLeft(2, '0');
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.glyph, required this.value});

  final Glyph glyph;
  final String value;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 14,
      recessed: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(glyph, size: 16, color: skin.accentDeep),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ty.numeral(16),
            ),
          ),
        ],
      ),
    );
  }
}

class _DifficultyRow extends StatelessWidget {
  const _DifficultyRow({required this.level, required this.onSelect});

  final MinesweeperLevel level;
  final ValueChanged<MinesweeperLevel> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    String label(MinesweeperLevel lvl) => switch (lvl) {
          MinesweeperLevel.easy => l.minesweeperEasy,
          MinesweeperLevel.medium => l.minesweeperMedium,
          MinesweeperLevel.hard => l.minesweeperHard,
        };
    return Row(
      children: [
        for (final lvl in MinesweeperLevel.values) ...[
          if (lvl != MinesweeperLevel.easy) const SizedBox(width: 8),
          Expanded(
            child: IbashoButton(
              key: ValueKey<String>('minesweeper.level.${lvl.name}'),
              label: label(lvl),
              tone: lvl == level ? ButtonTone.accent : ButtonTone.plain,
              height: 40,
              expand: true,
              cue: null,
              onPressed: lvl == level ? null : () => onSelect(lvl),
            ),
          ),
        ],
      ],
    );
  }
}

/// Cara sencilla dibujada a mano, para cuando la cuenta no tiene ningun Tama.
class _SimpleFace extends StatelessWidget {
  const _SimpleFace({required this.joy, required this.size});

  final double joy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SimpleFacePainter(joy: joy, accent: skin.accent)),
    );
  }
}

class _SimpleFacePainter extends CustomPainter {
  _SimpleFacePainter({required this.joy, required this.accent});

  final double joy;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(accent, T.shellTop, .5)!, accent],
        ).createShader(Offset.zero & size),
    );

    final eyeY = centre.dy - radius * .12;
    final eyeDx = radius * .34;
    final eyeR = radius * (joy < -.5 ? .05 : .09);
    final eyePaint = Paint()..color = T.tamaInk;
    if (joy < -.5) {
      // Ojos en X: fuera de combate.
      for (final dx in [-eyeDx, eyeDx]) {
        final c = Offset(centre.dx + dx, eyeY);
        canvas.drawLine(c + const Offset(-3, -3), c + const Offset(3, 3),
            Paint()..color = T.tamaInk..strokeWidth = 2);
        canvas.drawLine(c + const Offset(-3, 3), c + const Offset(3, -3),
            Paint()..color = T.tamaInk..strokeWidth = 2);
      }
    } else {
      canvas.drawCircle(Offset(centre.dx - eyeDx, eyeY), eyeR, eyePaint);
      canvas.drawCircle(Offset(centre.dx + eyeDx, eyeY), eyeR, eyePaint);
    }

    final mouthY = centre.dy + radius * .32;
    final mouthWidth = radius * .5;
    final curve = (joy.clamp(-1.0, 1.0)) * radius * .22;
    final path = Path()
      ..moveTo(centre.dx - mouthWidth, mouthY)
      ..quadraticBezierTo(centre.dx, mouthY + curve, centre.dx + mouthWidth, mouthY);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = T.tamaInk,
    );
  }

  @override
  bool shouldRepaint(_SimpleFacePainter old) => old.joy != joy || old.accent != accent;
}

class _Minimap extends StatelessWidget {
  const _Minimap({required this.data});

  final _MinimapData data;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 14,
      recessed: true,
      padding: const EdgeInsets.all(6),
      child: CustomPaint(
        painter: _MinimapPainter(game: data.game, visible: data.visible, accent: skin.accent),
        size: Size.infinite,
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({required this.game, required this.visible, required this.accent});

  final MinesweeperGame game;
  final Rect? visible;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cellW = size.width / game.width;
    final cellH = size.height / game.height;

    for (var y = 0; y < game.height; y++) {
      for (var x = 0; x < game.width; x++) {
        final cell = game.cellAt(x, y);
        final rect = Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);
        final Color color;
        if (cell.mine && cell.revealed) {
          color = T.warn;
        } else if (cell.flagged) {
          color = accent;
        } else if (cell.revealed) {
          color = T.wellBottom;
        } else {
          color = T.shellBottom;
        }
        canvas.drawRect(rect, Paint()..color = color);
      }
    }

    final rect = visible;
    if (rect != null) {
      final scaled = Rect.fromLTRB(
        rect.left / game.width * size.width,
        rect.top / game.height * size.height,
        rect.right / game.width * size.width,
        rect.bottom / game.height * size.height,
      ).intersect(Offset.zero & size);
      canvas.drawRect(
        scaled,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => true;
}

// --- Pantalla de abajo ---------------------------------------------------------

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.game,
    required this.flagMode,
    required this.onFlagModeChanged,
    required this.onRestart,
    required this.onCellTap,
    required this.onCellFlag,
    required this.viewController,
    required this.onViewportSize,
  });

  final MinesweeperGame game;
  final bool flagMode;
  final ValueChanged<bool> onFlagModeChanged;
  final VoidCallback onRestart;
  final void Function(int x, int y) onCellTap;
  final void Function(int x, int y) onCellFlag;
  final TransformationController viewController;
  final ValueChanged<Size> onViewportSize;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final l = L.of(context)!;

    return Column(
      children: [
        SizedBox(
          height: layout.pick(52, 58),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.pick(16, 12), vertical: 8),
            child: Row(
              children: [
                _ModeToggle(
                  flagMode: flagMode,
                  onChanged: onFlagModeChanged,
                  digLabel: l.minesweeperDig,
                  flagLabel: l.minesweeperFlag,
                ),
                const Spacer(),
                IconPill(
                  key: const ValueKey<String>('minesweeper.restart'),
                  glyph: Glyph.refresh,
                  semanticLabel: l.minesweeperRestart,
                  diameter: layout.pill,
                  onPressed: onRestart,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(layout.pick(10, 8)),
            child: LayoutBuilder(builder: (context, box) {
              final available = box.biggest;
              final cellFromWidth = available.width / game.width;
              final cellFromHeight = available.height / game.height;
              final naturalCell =
                  math.min(cellFromWidth, cellFromHeight).clamp(20.0, 56.0);

              // Solo en vertical, y solo si el tablero no cabria comodo: se
              // fija un tamaño tactil de verdad y se deja que se desplace y
              // amplie.
              final needsViewer = layout.tall && naturalCell < layout.touch;
              final cellSize = needsViewer ? layout.touch : naturalCell;

              final board = _Board(
                game: game,
                cellSize: cellSize,
                onCellTap: onCellTap,
                onCellFlag: onCellFlag,
              );

              if (!needsViewer) {
                return Center(child: board);
              }

              return LayoutBuilder(builder: (context, viewerBox) {
                onViewportSize(viewerBox.biggest);
                return InteractiveViewer(
                  transformationController: viewController,
                  minScale: 1,
                  maxScale: 3,
                  boundaryMargin: const EdgeInsets.all(24),
                  child: board,
                );
              });
            }),
          ),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.flagMode,
    required this.onChanged,
    required this.digLabel,
    required this.flagLabel,
  });

  final bool flagMode;
  final ValueChanged<bool> onChanged;
  final String digLabel;
  final String flagLabel;

  @override
  Widget build(BuildContext context) {
    final tall = Layout.of(context).tall;
    // En vertical el carril es estrecho: el modo se reduce a dos pastillas
    // de icono, sin etiqueta.
    if (tall) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconPill(
            key: const ValueKey<String>('minesweeper.mode.dig'),
            glyph: Glyph.magnify,
            tone: flagMode ? ButtonTone.plain : ButtonTone.accent,
            semanticLabel: digLabel,
            cue: null,
            onPressed: flagMode ? () => onChanged(false) : null,
          ),
          const SizedBox(width: 8),
          IconPill(
            key: const ValueKey<String>('minesweeper.mode.flag'),
            glyph: Glyph.mine,
            tone: flagMode ? ButtonTone.accent : ButtonTone.plain,
            semanticLabel: flagLabel,
            cue: null,
            onPressed: flagMode ? null : () => onChanged(true),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IbashoButton(
          key: const ValueKey<String>('minesweeper.mode.dig'),
          label: digLabel,
          glyph: Glyph.magnify,
          tone: flagMode ? ButtonTone.plain : ButtonTone.accent,
          height: 40,
          cue: null,
          onPressed: flagMode ? () => onChanged(false) : null,
        ),
        const SizedBox(width: 8),
        IbashoButton(
          key: const ValueKey<String>('minesweeper.mode.flag'),
          label: flagLabel,
          glyph: Glyph.mine,
          tone: flagMode ? ButtonTone.accent : ButtonTone.plain,
          height: 40,
          cue: null,
          onPressed: flagMode ? null : () => onChanged(true),
        ),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.game,
    required this.cellSize,
    required this.onCellTap,
    required this.onCellFlag,
  });

  final MinesweeperGame game;
  final double cellSize;
  final void Function(int x, int y) onCellTap;
  final void Function(int x, int y) onCellFlag;

  (int, int)? _cellAt(Offset local) {
    final x = (local.dx / cellSize).floor();
    final y = (local.dy / cellSize).floor();
    if (x < 0 || y < 0 || x >= game.width || y >= game.height) return null;
    return (x, y);
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(game.width * cellSize, game.height * cellSize);
    return GestureDetector(
      key: const ValueKey<String>('minesweeper.board'),
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final cell = _cellAt(details.localPosition);
        if (cell != null) onCellTap(cell.$1, cell.$2);
      },
      onLongPressStart: (details) {
        final cell = _cellAt(details.localPosition);
        if (cell != null) onCellFlag(cell.$1, cell.$2);
      },
      onSecondaryTapUp: (details) {
        final cell = _cellAt(details.localPosition);
        if (cell != null) onCellFlag(cell.$1, cell.$2);
      },
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CustomPaint(painter: _BoardPainter(game: game)),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.game});

  final MinesweeperGame game;

  static const List<Color> _numberColors = T.accentPalette;

  @override
  void paint(Canvas canvas, Size size) {
    if (game.width == 0 || game.height == 0) return;
    final cellW = size.width / game.width;
    final cellH = size.height / game.height;

    canvas.drawRect(Offset.zero & size, Paint()..color = T.hairline);

    for (var y = 0; y < game.height; y++) {
      for (var x = 0; x < game.width; x++) {
        final cell = game.cellAt(x, y);
        final rect = Rect.fromLTWH(x * cellW + .5, y * cellH + .5, cellW - 1, cellH - 1);
        final exploded = game.losingX == x && game.losingY == y;
        _paintCell(canvas, rect, cell, exploded, math.min(cellW, cellH));
      }
    }
  }

  void _paintCell(Canvas canvas, Rect rect, MinesweeperCell cell, bool exploded, double unit) {
    if (!cell.revealed) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [T.shellTop, T.shellBottom],
          ).createShader(rect),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = T.hairline,
      );
      if (cell.flagged) _paintFlag(canvas, rect, unit, wrong: cell.wrongFlag);
      return;
    }

    canvas.drawRect(
      rect,
      Paint()..color = exploded ? const Color(0xFFF3B7B7) : T.wellBottom,
    );

    if (cell.mine) {
      _paintMine(canvas, rect, unit);
      return;
    }

    if (cell.adjacent > 0) {
      final color = _numberColors[(cell.adjacent - 1).clamp(0, _numberColors.length - 1)];
      final painter = TextPainter(
        text: TextSpan(
          text: '${cell.adjacent}',
          style: Ty.numeral(unit * .52, color: color, weight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        rect.center - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  void _paintFlag(Canvas canvas, Rect rect, double unit, {required bool wrong}) {
    final base = rect.center;
    final pole = Offset(base.dx - unit * .08, base.dy - unit * .26);
    canvas.drawLine(
      pole,
      Offset(pole.dx, base.dy + unit * .26),
      Paint()
        ..color = T.ink
        ..strokeWidth = math.max(1, unit * .06),
    );
    final flag = Path()
      ..moveTo(pole.dx, pole.dy)
      ..lineTo(pole.dx + unit * .32, pole.dy + unit * .1)
      ..lineTo(pole.dx, pole.dy + unit * .2)
      ..close();
    canvas.drawPath(flag, Paint()..color = T.warn);
    if (wrong) {
      final centre = base;
      final r = unit * .3;
      canvas.drawLine(centre + Offset(-r, -r), centre + Offset(r, r),
          Paint()..color = T.foodCherry..strokeWidth = math.max(1, unit * .08));
      canvas.drawLine(centre + Offset(-r, r), centre + Offset(r, -r),
          Paint()..color = T.foodCherry..strokeWidth = math.max(1, unit * .08));
    }
  }

  void _paintMine(Canvas canvas, Rect rect, double unit) {
    final centre = rect.center;
    final radius = unit * .24;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, unit * .07)
      ..strokeCap = StrokeCap.round
      ..color = T.ink;
    canvas.drawCircle(centre, radius, Paint()..color = T.ink);
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(centre + dir * radius, centre + dir * (radius + unit * .12), stroke);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
