// Ibasho — el editor de Tamakoro: se pinta con el coro y se escucha en bucle.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/glyphs.dart';
import 'koro_song.dart';
import 'koro_synth.dart';
import 'koro_widgets.dart';

class KoroEditor extends StatefulWidget {
  const KoroEditor({
    super.key,
    required this.song,
    required this.tamas,
    required this.title,
    required this.onSave,
    required this.onBack,
  });

  final KoroSong song;
  final List<Tama> tamas;
  final String title;
  final ValueChanged<KoroSong> onSave;
  final VoidCallback onBack;

  @override
  State<KoroEditor> createState() => _KoroEditorState();
}

class _KoroEditorState extends State<KoroEditor> with SingleTickerProviderStateMixin {
  late KoroSong _song = widget.song;

  /// El pincel: el asiento (1 a 6) cuya tinta se pone, o 0 para la goma.
  int _brush = 1;
  final List<Uint8List> _undo = <Uint8List>[];
  final List<Uint8List> _redo = <Uint8List>[];

  /// Celda donde iba el trazo, para rellenar los saltos de un gesto rapido.
  (int, int)? _last;
  bool _stroking = false;

  bool _playing = false;
  final ValueNotifier<double?> _playhead = ValueNotifier<double?>(null);
  late final Ticker _ticker = createTicker((_) => _tick());
  Timer? _rerender;
  Timer? _autosave;
  int _renderToken = 0;

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // El primer asiento con Tama, para empezar a pintar sin tocar nada.
    final first = _song.seats.indexWhere((id) => _tamaOf(id) != null);
    if (first >= 0) _brush = first + 1;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _rerender?.cancel();
    if (_autosave?.isActive ?? false) {
      _autosave!.cancel();
      widget.onSave(_song);
    }
    unawaited(AudioService.instance.stopKoro());
    _playhead.dispose();
    _focus.dispose();
    super.dispose();
  }

  Tama? _tamaOf(String? id) =>
      id == null ? null : widget.tamas.where((t) => t.id == id).firstOrNull;

  List<Color> get _inks => koroInks(_song, widget.tamas);

  // --- Cambios -------------------------------------------------------------

  void _change(KoroSong next) {
    setState(() => _song = next);
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 1200), () => widget.onSave(_song));
    if (_playing) {
      _rerender?.cancel();
      _rerender = Timer(const Duration(milliseconds: 180), () => unawaited(_start()));
    }
  }

  void _snapshot() {
    _undo.add(Uint8List.fromList(_song.cells));
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    _redo.add(Uint8List.fromList(_song.cells));
    _change(_song.copyWith(cells: _undo.removeLast()));
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    _undo.add(Uint8List.fromList(_song.cells));
    _change(_song.copyWith(cells: _redo.removeLast()));
  }

  // --- Pintar --------------------------------------------------------------

  (int, int)? _cellAt(Offset p, Size size) {
    final step = (p.dx / size.width * koroSteps).floor();
    final row = koroRows - 1 - (p.dy / size.height * koroRows).floor();
    if (step < 0 || step >= koroSteps || row < 0 || row >= koroRows) return null;
    return (step, row);
  }

  Future<void> _strokeStart(Offset p, Size size) async {
    if (_brush > 0 && _tamaOf(_song.seats[_brush - 1]) == null) {
      await _pickSeat(_brush - 1);
      return;
    }
    _stroking = true;
    _snapshot();
    _last = null;
    _paintTo(p, size);
  }

  void _paintTo(Offset p, Size size) {
    if (!_stroking) return;
    final cell = _cellAt(p, size);
    if (cell == null) return;
    final cells = Uint8List.fromList(_song.cells);
    // Linea de celdas desde la anterior: un gesto rapido no deja huecos.
    final from = _last ?? cell;
    final n = math.max((cell.$1 - from.$1).abs(), (cell.$2 - from.$2).abs());
    var changed = false;
    for (var i = 0; i <= n; i++) {
      final t = n == 0 ? 0.0 : i / n;
      final s = (from.$1 + (cell.$1 - from.$1) * t).round();
      final r = (from.$2 + (cell.$2 - from.$2) * t).round();
      final k = KoroSong.index(s, r);
      if (cells[k] != _brush) {
        cells[k] = _brush;
        changed = true;
      }
    }
    // Al cambiar de nota, el Tama la canta: se oye lo que se pinta.
    if (_brush > 0 && (_last == null || _last!.$2 != cell.$2) && !_playing) _preview(cell.$2);
    _last = cell;
    if (changed) _change(_song.copyWith(cells: cells));
  }

  void _strokeEnd() {
    _stroking = false;
    _last = null;
  }

  void _preview(int row) {
    final voice = _tamaOf(_song.seats[_brush - 1])?.voice ?? koroFallbackVoice;
    final midi = _song.scale.midiOf(row);
    unawaited(AudioService.instance.playKoroNote(
      '${voice.pitch}.${voice.tempo}.${voice.timbre.index}.$midi',
      () => renderKoroNote(voice: voice, midi: midi, seconds: .22),
    ));
  }

  // --- Coro ----------------------------------------------------------------

  Future<void> _pickSeat(int seat) async {
    final l = L.of(context)!;
    final picked = await pickKoroTama(
      context,
      tamas: widget.tamas,
      title: l.koroPickTama,
      allowClear: _song.seats[seat] != null,
    );
    if (picked == null || !mounted) return;
    final seats = [..._song.seats]..[seat] = picked.isEmpty ? null : picked;
    setState(() => _brush = seat + 1);
    _change(_song.copyWith(seats: seats));
  }

  // --- Sonar ---------------------------------------------------------------

  Future<void> _togglePlay() async {
    if (_playing) {
      _rerender?.cancel();
      setState(() => _playing = false);
      _ticker.stop();
      _playhead.value = null;
      await AudioService.instance.stopKoro();
      return;
    }
    setState(() => _playing = true);
    await _start();
    if (mounted && _playing && !_ticker.isActive) unawaited(_ticker.start());
  }

  /// Renderiza la vuelta y la pone, siguiendo donde iba el cabezal.
  Future<void> _start() async {
    final token = ++_renderToken;
    final song = _song;
    final voices = [for (final id in song.seats) _tamaOf(id)?.voice];
    final wav = await compute(_renderJob, (song, voices));
    if (!mounted || !_playing || token != _renderToken) return;
    final head = _playhead.value;
    // El tempo puede haber cambiado: se sigue en el mismo paso, no segundo.
    final from = head == null ? 0.0 : head * song.stepSeconds;
    await AudioService.instance.playKoro(wav, from: from);
  }

  void _tick() {
    final pos = AudioService.instance.koroPosition;
    _playhead.value = pos == null ? null : (pos / _song.stepSeconds) % koroSteps;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (key == LogicalKeyboardKey.space) {
      unawaited(_togglePlay());
    } else if (ctrl && key == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed ? _redoStep() : _undoStep();
    } else if (ctrl && key == LogicalKeyboardKey.keyY) {
      _redoStep();
    } else if (key == LogicalKeyboardKey.keyE) {
      setState(() => _brush = 0);
    } else if (key.keyLabel.length == 1 && '123456'.contains(key.keyLabel)) {
      setState(() => _brush = int.parse(key.keyLabel));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- Vista ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          if (layout.tall) {
            final side = math.min(box.maxWidth, box.maxHeight - 260);
            return Column(
              children: [
                _header(context),
                const SizedBox(height: 10),
                _canvas(context, side),
                const SizedBox(height: 12),
                _choir(context, size: math.min(52, (box.maxWidth - 50) / 6)),
                const SizedBox(height: 12),
                _tools(context),
              ],
            );
          }
          final side = math.min(box.maxHeight, box.maxWidth - 330);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _canvas(context, side),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const SizedBox(height: 18),
                    _choir(context, size: 60, wrap: true),
                    const SizedBox(height: 18),
                    _tools(context),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l = L.of(context)!;
    return Row(
      children: [
        IconPill(glyph: Glyph.arrowLeft, onPressed: widget.onBack, semanticLabel: l.koroBack),
        const SizedBox(width: 12),
        Expanded(
          child: Text(widget.title, style: Ty.lead, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _canvas(BuildContext context, double side) {
    final skin = IbashoSkin.of(context);
    final inks = _inks;
    return SizedBox.square(
      dimension: side,
      child: GlossSurface(
        radius: 20,
        elevation: 2,
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: T.shellTop,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.biggest;
                return GestureDetector(
                  key: const ValueKey<String>('koro.canvas'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => unawaited(_strokeStart(d.localPosition, size)),
                  onPanUpdate: (d) => _paintTo(d.localPosition, size),
                  onPanEnd: (_) => _strokeEnd(),
                  onTapDown: (d) => unawaited(_strokeStart(d.localPosition, size)),
                  onTapUp: (_) => _strokeEnd(),
                  child: CustomPaint(
                    size: size,
                    painter: KoroCanvasPainter(
                      song: _song,
                      inks: inks,
                      playhead: _playhead,
                      accent: skin.accent,
                      repaint: _playhead,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _choir(BuildContext context, {required double size, bool wrap = false}) {
    final l = L.of(context)!;
    final inks = _inks;
    final seats = [
      for (var i = 0; i < koroSeats; i++)
        KoroSeat(
          key: ValueKey<String>('koro.seat.$i'),
          tama: _tamaOf(_song.seats[i]),
          ink: inks[i],
          size: size,
          selected: _brush == i + 1,
          onPressed: () {
            if (_tamaOf(_song.seats[i]) == null || _brush == i + 1) {
              unawaited(_pickSeat(i));
            } else {
              setState(() => _brush = i + 1);
            }
          },
          onLongPress: () => unawaited(_pickSeat(i)),
        ),
    ];
    final body = wrap
        ? Wrap(spacing: 12, runSpacing: 12, children: seats)
        : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: seats);
    return Column(
      crossAxisAlignment: wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(l.koroChoirHint, style: Ty.caption),
        const SizedBox(height: 8),
        body,
      ],
    );
  }

  Widget _tools(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tempoFraction = (_song.tempo - koroMinTempo) / (koroMaxTempo - koroMinTempo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconPill(
              glyph: Glyph.eraser,
              tone: _brush == 0 ? ButtonTone.accent : ButtonTone.plain,
              onPressed: () => setState(() => _brush = 0),
              semanticLabel: l.koroEraser,
            ),
            const SizedBox(width: 10),
            IconPill(
              glyph: Glyph.undo,
              onPressed: _undo.isEmpty ? null : _undoStep,
              semanticLabel: l.koroUndo,
            ),
            const SizedBox(width: 10),
            Transform.flip(
              flipX: true,
              child: IconPill(
                glyph: Glyph.undo,
                onPressed: _redo.isEmpty ? null : _redoStep,
                semanticLabel: l.koroRedo,
              ),
            ),
            const Spacer(),
            IbashoButton(
              key: const ValueKey<String>('koro.play'),
              label: _playing ? l.koroStop : l.koroPlay,
              glyph: _playing ? Glyph.pause : Glyph.play,
              tone: ButtonTone.accent,
              minWidth: 128,
              onPressed: () => unawaited(_togglePlay()),
            ),
          ],
        ),
        const SizedBox(height: 14),
        IbashoSegmented<KoroScale>(
          options: [
            (KoroScale.major, l.koroScaleMajor),
            (KoroScale.minor, l.koroScaleMinor),
            (KoroScale.penta, l.koroScalePenta),
          ],
          value: _song.scale,
          onChanged: (scale) => _change(_song.copyWith(scale: scale)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(width: 92, child: Text(l.koroTempo(_song.tempo), style: Ty.caption)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => IbashoSlider(
                  value: tempoFraction,
                  width: box.maxWidth,
                  ticks: (koroMaxTempo - koroMinTempo) ~/ 10 + 1,
                  semanticLabel: l.koroTempo(_song.tempo),
                  onChanged: (v) {
                    final bpm = (koroMinTempo + v * (koroMaxTempo - koroMinTempo)) ~/ 10 * 10;
                    if (bpm != _song.tempo) _change(_song.copyWith(tempo: bpm));
                  },
                ),
              ),
            ),
          ],
        ),
        if (!layout.tall) ...[
          const SizedBox(height: 14),
          Text(l.koroEditorHint, style: Ty.micro),
        ],
      ],
    );
  }
}

Uint8List _renderJob((KoroSong, List<TamaVoice?>) job) => renderKoroSong(job.$1, job.$2);
