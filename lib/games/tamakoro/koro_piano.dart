// Ibasho — el Tamapiano: una octava, de Do a Do', cantada por un Tama.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/glyphs.dart';
import 'koro_synth.dart';
import 'koro_widgets.dart';

/// Teclas blancas (MIDI) y la tecla del teclado del ordenador de cada una.
const List<(int, LogicalKeyboardKey)> _whites = [
  (60, LogicalKeyboardKey.keyA),
  (62, LogicalKeyboardKey.keyS),
  (64, LogicalKeyboardKey.keyD),
  (65, LogicalKeyboardKey.keyF),
  (67, LogicalKeyboardKey.keyG),
  (69, LogicalKeyboardKey.keyH),
  (71, LogicalKeyboardKey.keyJ),
  (72, LogicalKeyboardKey.keyK),
];

/// Teclas negras: la blanca tras la que asoman y su tecla del ordenador.
const List<(int, int, LogicalKeyboardKey)> _blacks = [
  (61, 0, LogicalKeyboardKey.keyW),
  (63, 1, LogicalKeyboardKey.keyE),
  (66, 3, LogicalKeyboardKey.keyT),
  (68, 4, LogicalKeyboardKey.keyY),
  (70, 5, LogicalKeyboardKey.keyU),
];

class KoroPiano extends StatefulWidget {
  const KoroPiano({super.key, required this.tamas, this.initialTamaId});

  final List<Tama> tamas;
  final String? initialTamaId;

  @override
  State<KoroPiano> createState() => _KoroPianoState();
}

class _KoroPianoState extends State<KoroPiano> {
  late String? _tamaId = widget.initialTamaId ?? widget.tamas.firstOrNull?.id;
  final TamaViewController _controller = TamaViewController();
  final Set<int> _down = <int>{};
  final FocusNode _focus = FocusNode();

  Tama? get _tama =>
      widget.tamas.where((t) => t.id == _tamaId).firstOrNull ?? widget.tamas.firstOrNull;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _play(int midi) {
    final voice = _tama?.voice ?? koroFallbackVoice;
    unawaited(AudioService.instance.playKoroNote(
      'p${voice.pitch}.${voice.tempo}.${voice.timbre.index}.$midi',
      () => renderKoroNote(voice: voice, midi: midi),
    ));
    _controller.hop();
    setState(() => _down.add(midi));
    Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _down.remove(midi));
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    for (final (midi, key) in _whites) {
      if (event.logicalKey == key) {
        _play(midi);
        return KeyEventResult.handled;
      }
    }
    for (final (midi, _, key) in _blacks) {
      if (event.logicalKey == key) {
        _play(midi);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _change() async {
    final l = L.of(context)!;
    final picked = await pickKoroTama(context, tamas: widget.tamas, title: l.koroPianoPick);
    if (picked != null && picked.isNotEmpty && mounted) setState(() => _tamaId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tama = _tama;
    final names = l.koroNoteNames.split(',');
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          final stand = layout.tall ? 120.0 : math.min(150.0, box.maxHeight * .34);
          final keysHeight = math.min(box.maxHeight - stand - 70, layout.tall ? 220.0 : 260.0);
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (tama != null)
                    TamaOnStand(tama: tama, size: stand, controller: _controller, joy: .7),
                  const SizedBox(width: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tama?.name ?? '', style: Ty.lead),
                      const SizedBox(height: 10),
                      IbashoButton(
                        label: l.koroPianoChange,
                        glyph: Glyph.tama,
                        onPressed: widget.tamas.length > 1 ? () => unawaited(_change()) : null,
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              _keyboard(context, names, math.min(box.maxWidth, 720), keysHeight),
              const SizedBox(height: 10),
              if (!layout.tall) Text(l.koroPianoHint, style: Ty.micro),
            ],
          );
        },
      ),
    );
  }

  Widget _keyboard(BuildContext context, List<String> names, double width, double height) {
    final skin = IbashoSkin.of(context);
    final ink = _tama?.look.bodyColor ?? skin.accent;
    return SizedBox(
      width: width,
      height: height,
      child: GlossSurface(
        radius: 22,
        elevation: 2,
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, box) {
            final white = box.maxWidth / _whites.length;
            return Stack(
              children: [
                for (var i = 0; i < _whites.length; i++)
                  Positioned(
                    left: i * white,
                    top: 0,
                    bottom: 0,
                    width: white,
                    child: _Key(
                      label: names.elementAtOrNull(i) ?? '',
                      down: _down.contains(_whites[i].$1),
                      black: false,
                      ink: ink,
                      onDown: () => _play(_whites[i].$1),
                    ),
                  ),
                for (final (midi, after, _) in _blacks)
                  Positioned(
                    left: (after + 1) * white - white * .32,
                    top: 0,
                    width: white * .64,
                    height: box.maxHeight * .6,
                    child: _Key(
                      label: '',
                      down: _down.contains(midi),
                      black: true,
                      ink: ink,
                      onDown: () => _play(midi),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Una tecla. Suena al apoyar el dedo, no al levantarlo: es un instrumento.
class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.down,
    required this.black,
    required this.ink,
    required this.onDown,
  });

  final String label;
  final bool down;
  final bool black;
  final Color ink;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final base = black ? T.ink : T.shellTop;
    final color = down ? Color.lerp(base, ink, black ? .55 : .45)! : base;
    return Listener(
      onPointerDown: (_) => onDown(),
      child: AnimatedContainer(
        duration: skin.motion(const Duration(milliseconds: 90)),
        margin: EdgeInsets.symmetric(horizontal: black ? 0 : 2),
        transform: Matrix4.translationValues(0, down ? 2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10), top: Radius.circular(4)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, Color.lerp(color, black ? T.letterbox : T.shellBottom, .6)!],
          ),
          border: Border.all(color: black ? T.letterbox : T.hairline),
          boxShadow: down ? null : const [BoxShadow(color: T.shadow, offset: Offset(0, 3), blurRadius: 3)],
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 10),
        child: black ? null : Text(label, style: Ty.caption.copyWith(color: T.ink)),
      ),
    );
  }
}
