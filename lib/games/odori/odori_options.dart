// Ibasho — Odori: las opciones del juego (direccion, aspecto, velocidad,
// desfase con su calibracion, teclas de cada carril y tema propio).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/backdrops.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/screens/channels/settings_channel.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/panel.dart';
import '../../ui/widgets/pressable.dart';
import '../game_stage.dart';
import 'odori_board.dart';
import 'odori_butai.dart';
import 'odori_chart.dart';
import 'odori_hits.dart';
import 'odori_keys.dart';
import 'odori_store.dart';
import 'odori_widgets.dart';

/// Velocidad que se enseña: 1,0 = una nota tarda 1,2 s en llegar.
double speedOf(double approach) => 1.2 / approach;

class OdoriOptionsPage extends ConsumerStatefulWidget {
  const OdoriOptionsPage({super.key, required this.prefs, required this.onChanged});

  final OdoriPrefs prefs;
  final ValueChanged<OdoriPrefs> onChanged;

  @override
  ConsumerState<OdoriOptionsPage> createState() => _OdoriOptionsPageState();
}

class _OdoriOptionsPageState extends ConsumerState<OdoriOptionsPage> {
  late OdoriPrefs _prefs = widget.prefs;
  late int _mapKeys = _prefs.keys;

  /// Carril que espera su tecla nueva.
  int? _waiting;

  /// Carril de Butai cuya segunda tecla se esta esperando.
  int? _waitingAlt;
  final FocusNode _focus = FocusNode(debugLabel: 'odori.options');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _set(OdoriPrefs p) {
    setState(() => _prefs = p);
    widget.onChanged(p);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_waitingAlt != null) return _onAltKey(event);
    final lane = _waiting;
    if (lane == null || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _waiting = null);
      return KeyEventResult.handled;
    }
    final keys = [..._prefs.keysFor(_mapKeys)];
    final key = event.physicalKey;
    // Si la tecla ya estaba en otro carril, se cambian de sitio.
    final other = keys.indexOf(key);
    if (other >= 0) keys[other] = keys[lane];
    keys[lane] = key;
    AudioService.instance.play(Sfx.tick);
    _waiting = null;
    _set(_prefs.copyWith(keyMaps: {..._prefs.keyMaps, _mapKeys: keys}));
    return KeyEventResult.handled;
  }

  /// La segunda tecla de una figura de Butai. Como con las principales, si
  /// ya era de otra figura se cambian de sitio.
  KeyEventResult _onAltKey(KeyEvent event) {
    final lane = _waitingAlt!;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.escape) {
      setState(() => _waitingAlt = null);
      return KeyEventResult.handled;
    }
    // Enter y P pausan la partida: no pueden ser teclas de juego.
    if (logical == LogicalKeyboardKey.enter || logical == LogicalKeyboardKey.keyP) return KeyEventResult.handled;
    final keys = [..._prefs.butaiAlt];
    final key = event.physicalKey;
    final other = keys.indexOf(key);
    if (other >= 0) keys[other] = keys[lane];
    keys[lane] = key;
    AudioService.instance.play(Sfx.tick);
    _waitingAlt = null;
    _set(_prefs.copyWith(butaiAlt: keys, butaiDouble: true));
    return KeyEventResult.handled;
  }

  Future<void> _calibrate() async {
    final ms = await pushChannelPage<int>(context, (_) => const OdoriCalibration());
    if (ms != null && mounted) _set(_prefs.copyWith(offsetMs: ms));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final p = _prefs;

    Widget section(String title, List<Widget> children, {String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: SectionCard(
            title: title,
            padding: EdgeInsets.fromLTRB(layout.pick(22, 16), 12, layout.pick(22, 16), 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(hint, style: Ty.caption),
                  ),
                ...children,
              ],
            ),
          ),
        );

    final speed = speedOf(p.approach);
    return ChannelScaffold(
      title: l.odoriOptions,
      glyph: Glyph.gear,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: IbashoScroll(
          padding: EdgeInsets.fromLTRB(layout.gutter, 4, layout.gutter, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section(l.odoriFlow, [
                    SegmentRail(
                      children: [
                        for (final f in TakiFlow.values)
                          SegmentPill(
                            key: ValueKey<String>('odori.flow.${f.name}'),
                            label: flowLabel(f),
                            selected: p.flow == f,
                            onPressed: () => _set(p.copyWith(flow: f)),
                          ),
                      ],
                    ),
                  ]),
                  section(l.odoriLook, [
                    SegmentRail(
                      children: [
                        for (final (look, label) in [
                          (NoteLook.circle, l.odoriLookCircle),
                          (NoteLook.bar, l.odoriLookBar),
                          (NoteLook.arrow, l.odoriLookArrow),
                        ])
                          SegmentPill(
                            key: ValueKey<String>('odori.look.${look.name}'),
                            label: label,
                            selected: p.look == look,
                            onPressed: () => _set(p.copyWith(look: look)),
                          ),
                      ],
                    ),
                  ]),
                  section(l.odoriHitSounds, hint: l.odoriHitSoundsHint, [
                    Row(
                      children: [
                        Expanded(
                          child: IbashoSlider(
                            key: const ValueKey<String>('odori.hits'),
                            width: double.infinity,
                            value: (p.hitVolume / odoriHitMax).clamp(0.0, 1.0),
                            ticks: 20,
                            onChanged: (v) {
                              final volume = (v * 20).round() / 20 * odoriHitMax;
                              if (volume == p.hitVolume) return;
                              _set(p.copyWith(hitVolume: volume));
                              // Suena a cada paso, para oir como queda.
                              unawaited(_hitPreview());
                            },
                          ),
                        ),
                        SizedBox(
                          width: 96,
                          child: Text(
                            p.hitVolume <= 0 ? l.odoriHitOff : '${(p.hitVolume / odoriHitMax * 100).round()} %',
                            textAlign: TextAlign.right,
                            style: Ty.numeral(16, color: Ty.inkSoft),
                          ),
                        ),
                      ],
                    ),
                  ]),
                  section(l.odoriButaiTouch, hint: l.odoriButaiTouchHint, [
                    SegmentRail(
                      children: [
                        for (final (t, label) in [
                          (ButaiTouch.targets, l.odoriButaiTouchTargets),
                          (ButaiTouch.pad, l.odoriButaiTouchPad),
                        ])
                          SegmentPill(
                            key: ValueKey<String>('odori.touch.${t.name}'),
                            label: label,
                            selected: p.butaiTouch == t,
                            onPressed: () => _set(p.copyWith(butaiTouch: t)),
                          ),
                      ],
                    ),
                  ]),
                  section(l.odoriSpeed, [
                    Row(
                      children: [
                        Expanded(
                          child: IbashoSlider(
                            width: double.infinity,
                            // De ×0,5 a ×2,4, en pasos de 0,1.
                            value: ((speed - .5) / 1.9).clamp(0.0, 1.0),
                            ticks: 19,
                            onChanged: (v) {
                              final sp = .5 + (v * 19).round() / 10;
                              _set(p.copyWith(
                                approach: (1.2 / sp).clamp(OdoriPrefs.minApproach, OdoriPrefs.maxApproach),
                              ));
                            },
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            '×${speed.toStringAsFixed(1)}',
                            textAlign: TextAlign.right,
                            style: Ty.numeral(18, color: Ty.inkSoft),
                          ),
                        ),
                      ],
                    ),
                  ]),
                  section(
                    l.odoriOffset,
                    hint: l.odoriOffsetHint,
                    [
                      Row(
                        children: [
                          IconPill(
                            glyph: Glyph.minus,
                            onPressed: () => _set(p.copyWith(offsetMs: math.max(-OdoriPrefs.maxOffset, p.offsetMs - 5))),
                          ),
                          Expanded(
                            child: Text(
                              '${p.offsetMs > 0 ? '+' : ''}${p.offsetMs} ms',
                              key: const ValueKey<String>('odori.offset'),
                              textAlign: TextAlign.center,
                              style: Ty.numeral(22, color: Ty.ink, weight: FontWeight.w700),
                            ),
                          ),
                          IconPill(
                            glyph: Glyph.plus,
                            onPressed: () => _set(p.copyWith(offsetMs: math.min(OdoriPrefs.maxOffset, p.offsetMs + 5))),
                          ),
                          const SizedBox(width: 14),
                          IbashoButton(
                            key: const ValueKey<String>('odori.calibrate'),
                            label: l.odoriCalibrate,
                            glyph: Glyph.clock,
                            onPressed: _calibrate,
                          ),
                        ],
                      ),
                    ],
                  ),
                  section(
                    l.odoriKeyMap,
                    hint: l.odoriKeyMapHint,
                    [
                      SegmentRail(
                        height: 38,
                        children: [
                          for (var k = odoriMinKeys; k <= odoriMaxKeys; k++)
                            SegmentPill(
                              label: '$k',
                              height: 38,
                              selected: k == _mapKeys,
                              onPressed: () => setState(() {
                                _mapKeys = k;
                                _waiting = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (var i = 0; i < _mapKeys; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: _KeyCap(
                                label: keyCap(p.keysFor(_mapKeys)[i]),
                                color: laneColor(i, _mapKeys, IbashoSkin.of(context).accent),
                                waiting: _waiting == i,
                                onPressed: () {
                                  _focus.requestFocus();
                                  setState(() {
                                    _waitingAlt = null;
                                    _waiting = _waiting == i ? null : i;
                                  });
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_waiting != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(l.odoriKeyWaiting, style: Ty.caption, textAlign: TextAlign.center),
                        ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IbashoButton(
                          label: l.odoriKeysDefault,
                          glyph: Glyph.refresh,
                          tone: ButtonTone.quiet,
                          height: 40,
                          onPressed: p.keyMaps.containsKey(_mapKeys)
                              ? () => _set(p.copyWith(keyMaps: {...p.keyMaps}..remove(_mapKeys)))
                              : null,
                        ),
                      ),
                    ],
                  ),
                  section(l.odoriButaiAlt, hint: l.odoriButaiAltHint, [
                    Row(
                      children: [
                        for (var i = 0; i < butaiKeys; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: _KeyCap(
                              key: ValueKey<String>('odori.alt.$i'),
                              label: keyCap(p.butaiAlt[i]),
                              color: butaiColors[i],
                              waiting: _waitingAlt == i,
                              onPressed: () {
                                _focus.requestFocus();
                                setState(() {
                                  _waiting = null;
                                  _waitingAlt = _waitingAlt == i ? null : i;
                                });
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_waitingAlt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(l.odoriKeyWaiting, style: Ty.caption, textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IbashoButton(
                        label: l.odoriKeysDefault,
                        glyph: Glyph.refresh,
                        tone: ButtonTone.quiet,
                        height: 40,
                        onPressed: listEquals(p.butaiAlt, butaiAltDefault)
                            ? null
                            : () => _set(p.copyWith(butaiAlt: butaiAltDefault)),
                      ),
                    ),
                  ]),
                  section(l.odoriTheme, hint: l.odoriThemeHint, [_themes(context, p)]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Hace sonar un brillo al volumen elegido, para oir como queda.
  Future<void> _hitPreview() async {
    final volume = _prefs.hitVolume;
    if (volume <= 0) return;
    await AudioService.instance.loadOdoriHits(
      [for (final h in OdoriHit.values) h.name],
      (key) => synthesizeHit(OdoriHit.values.byName(key)),
    );
    AudioService.instance.playOdoriHit(OdoriHit.perfect.name, volume);
  }

  Widget _themes(BuildContext context, OdoriPrefs p) {
    final l = L.of(context)!;
    final gacha = ref.watch(gachaProvider);
    final owned = [for (final b in backdrops) if (gacha.owns(b.key)) b];
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        BackdropChip(
          key: const ValueKey<String>('odori.theme.menu'),
          id: null,
          rarity: null,
          label: l.odoriThemeMenu,
          locked: false,
          selected: p.themeId == null,
          onPressed: () => _set(p.copyWith(themeId: () => null)),
        ),
        BackdropChip(
          key: const ValueKey<String>('odori.theme.none'),
          id: null,
          rarity: null,
          label: l.backdropNone,
          locked: false,
          selected: p.themeId == '',
          onPressed: () => _set(p.copyWith(themeId: () => '')),
        ),
        for (final b in owned)
          BackdropChip(
            key: ValueKey<String>('odori.theme.${b.id}'),
            id: b.id,
            rarity: b.rarity,
            label: l.backdropName(b.key),
            locked: false,
            selected: p.themeId == b.id,
            onPressed: () => _set(p.copyWith(themeId: () => b.id)),
          ),
      ],
    );
  }
}

/// La tecla de un carril, del color del carril. Esperando, parpadea.
class _KeyCap extends StatelessWidget {
  const _KeyCap({super.key, required this.label, required this.color, required this.waiting, required this.onPressed});

  final String label;
  final Color color;
  final bool waiting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlossSurface(
        radius: 14,
        tint: waiting ? skin.accentWash : null,
        borderColor: waiting ? skin.accentDeep : color,
        borderWidth: waiting ? 2.2 : 1.6,
        elevation: waiting ? 1.6 : .6,
        sink: state.press,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            waiting ? '…' : label,
            style: Ty.numeral(20, color: waiting ? skin.accentDeep : Ty.ink, weight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// La calibracion: un metronomo a 100 bpm y el jugador toca con cada golpe.
/// El desfase es la mediana de lo que se adelanta o se retrasa, y se
/// devuelve en milisegundos al pulsar «listo».
class OdoriCalibration extends StatefulWidget {
  const OdoriCalibration({super.key});

  @override
  State<OdoriCalibration> createState() => _OdoriCalibrationState();
}

class _OdoriCalibrationState extends State<OdoriCalibration> with SingleTickerProviderStateMixin {
  static const double _beat = .6;
  static const int _enough = 8;

  final Stopwatch _watch = Stopwatch();
  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'odori.calibration');
  int _beats = 0;
  final List<double> _deltas = <double>[];
  double _flash = -1;

  double get _now => _watch.elapsedMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _watch.start();
    AudioService.instance.hushMusic();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    AudioService.instance.unhushMusic();
    super.dispose();
  }

  void _onTick(Duration _) {
    // El primer golpe, un segundo despues de entrar.
    final next = 1 + _beats * _beat;
    if (_now >= next) {
      _beats++;
      AudioService.instance.play(Sfx.tick);
      setState(() => _flash = next);
    }
  }

  void _tap() {
    final t = _now - 1;
    if (t < -_beat / 2) return;
    final nearest = (t / _beat).round() * _beat;
    final d = t - nearest;
    setState(() {
      _deltas.add(d);
      if (_deltas.length > 16) _deltas.removeAt(0);
    });
  }

  int? get _offsetMs {
    if (_deltas.length < 4) return null;
    final sorted = [..._deltas]..sort();
    final median = sorted[sorted.length ~/ 2];
    return (median * 1000).round().clamp(-OdoriPrefs.maxOffset, OdoriPrefs.maxOffset);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final ms = _offsetMs;
    return ChannelScaffold(
      title: l.odoriCalibrate,
      glyph: Glyph.clock,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey != LogicalKeyboardKey.escape) {
            _tap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _tap(),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(l.odoriCalibrateHint, style: Ty.lead, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 28),
                TweenAnimationBuilder<double>(
                  key: ValueKey<double>(_flash),
                  tween: Tween<double>(begin: 1, end: 0),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, v, _) => Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(skin.accentWash, skin.accent, v),
                      border: Border.all(color: skin.accentDeep, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  ms == null ? '${_deltas.length}/$_enough' : '${ms > 0 ? '+' : ''}$ms ms',
                  style: Ty.numeral(30, color: Ty.ink, weight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                IbashoButton(
                  key: const ValueKey<String>('odori.calibrate.done'),
                  label: l.odoriCalibrateDone,
                  glyph: Glyph.check,
                  tone: ButtonTone.accent,
                  onPressed: _deltas.length >= _enough ? () => Navigator.of(context).pop(ms) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
