// Ibasho — barra de estado del panel superior.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../audio/audio_service.dart';
import '../../backend/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/system_status.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../canvas.dart';
import '../widgets/glyphs.dart';
import '../widgets/pressable.dart';

/// Bateria, conexion, sonido e idioma, con la estetica de los indicadores de
/// 3DS.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final skin = IbashoSkin.of(context);
    final preferences = ref.watch(preferencesProvider);
    final controller = ref.read(preferencesProvider.notifier);
    final coins = ref.watch(coinsProvider);
    // En vertical cada boton ocupa sus 48 dp de toque, que ya separan: los
    // huecos se estrechan y la bateria deja la cifra (el movil ya la enseña
    // arriba), para que todo quepa en 360 de ancho.
    final tall = CanvasSize.tallOf(context);
    final gap = tall ? 12.0 : (compact ? 16.0 : 22.0);

    final bars = switch (status.link) {
      LinkQuality.offline => 0,
      LinkQuality.weak => 1,
      LinkQuality.fair => 2,
      LinkQuality.strong => 3,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Las monedas van las primeras, antes de los indicadores del aparato:
        // son de la cuenta, no del cacharro. Hoy estan a cero para todo el
        // mundo y aun asi se enseñan, porque el sitio tiene que existir antes
        // de que haya algo que gastar.
        _CoinsReadout(coins: coins, accent: skin.accentDeep, compact: compact),
        SizedBox(width: gap),
        // Sin bateria no se dibuja nada ni se deja hueco.
        if (status.battery != null) ...[
          _BatteryReadout(battery: status.battery!, accent: skin.accent, showLevel: !tall),
          SizedBox(width: gap),
        ],
        SignalArcs(
          bars: bars,
          color: bars == 0 ? T.warn : skin.accentDeep,
          dim: skin.hairline,
          size: compact ? 16 : 18,
        ),
        SizedBox(width: tall ? 0 : (compact ? 12 : 16)),
        // Musica y sonidos (0.8.0): tocar silencia o devuelve; la rueda o
        // arrastrar arriba y abajo cambia el volumen sin ir a Ajustes.
        _VolumeButton(
          glyph: Glyph.note,
          offGlyph: Glyph.noteOff,
          label: L.of(context)!.statusMusic,
          level: preferences.musicLevel,
          current: () => ref.read(preferencesProvider).musicLevel,
          onToggle: controller.toggleMusicMuted,
          onChanged: controller.setMusicVolume,
        ),
        SizedBox(width: tall ? 0 : (compact ? 6 : 8)),
        _VolumeButton(
          glyph: Glyph.speaker,
          offGlyph: Glyph.speakerOff,
          label: L.of(context)!.statusEffects,
          level: preferences.effectsLevel,
          current: () => ref.read(preferencesProvider).effectsLevel,
          onToggle: () async {
            await controller.toggleEffectsMuted();
            // Al volver, un toque para oir que vuelve.
            AudioService.instance.play(Sfx.tick);
          },
          onChanged: (v) async {
            await controller.setEffectsVolume(v);
            AudioService.instance.play(Sfx.tick);
          },
        ),
        SizedBox(width: tall ? 0 : (compact ? 8 : 12)),
        _LocaleButton(
          code: preferences.localeCode,
          onPressed: () =>
              changeLanguage(ref, preferences.localeCode == 'es' ? 'en' : 'es'),
        ),
      ],
    );
  }
}

/// El monedero, con el mismo peso visual que la bateria: glifo y cifra.
class _CoinsReadout extends StatelessWidget {
  const _CoinsReadout({
    required this.coins,
    required this.accent,
    required this.compact,
  });

  final int coins;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Semantics(
      label: '$coins ${l.coinsLabel}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(
            Glyph.coin,
            size: compact ? 15 : 17,
            // El acento, no la tinta suave: es lo unico de la barra que crece
            // con lo que haces, y tiene que verse que esta vivo.
            color: accent,
            strokeWidth: 1.7,
          ),
          const SizedBox(width: 7),
          Text(
            // Con separador de millares: en cuanto haya algo que gastar, un
            // "1.250" se lee de un vistazo y un "1250" no.
            NumberFormat.decimalPattern(
              Localizations.localeOf(context).languageCode,
            ).format(coins),
            style: Ty.numeral(15, color: Ty.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _BatteryReadout extends StatelessWidget {
  const _BatteryReadout({required this.battery, required this.accent, this.showLevel = true});

  final BatteryInfo battery;
  final Color accent;
  final bool showLevel;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${battery.level}%',
        excludeSemantics: true,
        child: _row(),
      );

  Widget _row() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BatteryGauge(
            level: battery.level,
            charging: battery.charging,
            color: Ty.inkSoft,
            accent: accent,
            warn: T.warn,
          ),
          if (showLevel) ...[
            const SizedBox(width: 8),
            Text(
              '${battery.level}%',
              style: Ty.numeral(15, color: Ty.inkSoft),
            ),
          ],
        ],
      );
}

/// Codigo de dos letras del idioma activo, pulsable para cambiarlo.
class _LocaleButton extends StatelessWidget {
  const _LocaleButton({required this.code, required this.onPressed});

  final String code;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: code,
      builder: (context, state) => FocusRing(
        visible: state.focus,
        radius: 9,
        inset: -3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            code.toUpperCase(),
            style: Ty.numeral(
              15,
              color: Color.lerp(Ty.inkSoft, skin.accentDeep, state.hover)!,
              weight: FontWeight.w700,
            ).copyWith(letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }
}

/// Musica o sonidos: el glifo tachado si no suenan y, al pasar por encima o
/// al cambiarlo, el volumen en cifra.
class _VolumeButton extends StatefulWidget {
  const _VolumeButton({
    required this.glyph,
    required this.offGlyph,
    required this.label,
    required this.level,
    required this.current,
    required this.onToggle,
    required this.onChanged,
  });

  final Glyph glyph;
  final Glyph offGlyph;
  final String label;

  /// Lo que suena ahora, de 0 a 1 (0 si esta silenciado).
  final double level;

  /// Lo mismo leido en el momento, sin esperar a reconstruir.
  final double Function() current;
  final Future<void> Function() onToggle;
  final Future<void> Function(double) onChanged;

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  /// Un paso de rueda o de flecha.
  static const double _step = .05;

  /// Pixeles de arrastre por paso.
  static const double _dragStep = 10;

  /// La cifra se queda un momento a la vista despues de cambiarlo.
  Timer? _shown;
  double _drag = 0;

  /// El volumen que se va pidiendo, por delante de las preferencias, para
  /// que una rueda rapida no pise pasos que aun no se han guardado.
  double? _pending;
  int _inFlight = 0;

  @override
  void dispose() {
    _shown?.cancel();
    super.dispose();
  }

  void _nudge(int steps) {
    if (steps == 0) return;
    final from = _inFlight > 0 ? _pending! : widget.current();
    final next = ((from + steps * _step) / _step).round() * _step;
    final v = next.clamp(0.0, 1.0);
    if (v == from) return;
    _pending = v;
    _inFlight++;
    _shown?.cancel();
    setState(() {});
    _shown = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _shown = null);
    });
    widget.onChanged(v).whenComplete(() {
      if (--_inFlight == 0 && mounted) setState(() => _pending = null);
    });
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Se lo queda este boton: que no pase la pagina ni desplace nada debajo.
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy.abs() < 1) return;
      _nudge(dy < 0 ? 1 : -1);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _nudge(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _nudge(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final level = _pending ?? widget.level;
    final off = level <= 0;
    final percent = (level * 100).round();
    String said(int p) => p <= 0 ? l.statusMuted : '$p %';
    return Semantics(
      value: off ? l.statusMuted : said(percent),
      increasedValue: said((percent + 5).clamp(0, 100)),
      decreasedValue: said((percent - 5).clamp(0, 100)),
      hint: l.statusVolumeHint,
      onIncrease: () => _nudge(1),
      onDecrease: () => _nudge(-1),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: _onWheel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => _drag = 0,
            onVerticalDragUpdate: (d) {
              _drag -= d.delta.dy;
              final steps = (_drag / _dragStep).truncate();
              if (steps == 0) return;
              _drag -= steps * _dragStep;
              _nudge(steps);
            },
            child: Pressable(
              onPressed: widget.onToggle,
              semanticLabel: widget.label,
              builder: (context, state) {
                final color = off
                    ? Color.lerp(
                        skin.hairline,
                        Ty.inkSoft,
                        .4 + .6 * state.hover,
                      )!
                    : Color.lerp(Ty.inkSoft, skin.accentDeep, state.hover)!;
                final showLevel =
                    _shown != null || state.hover > .5 || state.focus;
                return FocusRing(
                  visible: state.focus,
                  radius: 9,
                  inset: -3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlyphIcon(
                          off ? widget.offGlyph : widget.glyph,
                          size: 18,
                          color: color,
                          strokeWidth: 1.8,
                        ),
                        AnimatedSize(
                          duration: skin.motion(
                            const Duration(milliseconds: 160),
                          ),
                          curve: Curves.easeOut,
                          child: showLevel
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    '$percent',
                                    style: Ty.numeral(14, color: color),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
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
}
