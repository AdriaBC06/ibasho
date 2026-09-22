// Ibasho — la pantalla del bono diario: el calendario del mes y el sello.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../audio/audio_service.dart';
import '../../games/nihongo/nihongo_widgets.dart' show MaruPainter;
import '../../l10n/gen/app_localizations.dart';
import '../../state/login_bonus.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../layout.dart';
import '../widgets/channel_art.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import '../widgets/overlays.dart';

/// Abre el bono diario. Con [preview] todo se ve y suena igual, pero no se
/// cobra nada: es lo que usa el canal de depuracion.
Future<void> showLoginBonus(BuildContext context, {bool preview = false}) =>
    showIbashoModal<void>(context, (_) => LoginBonusPanel(preview: preview));

/// El bono diario: el calendario del mes con lo que da cada dia, los dias
/// cobrados con el sello rojo y hoy encendido. Al cobrar, el sello cae sobre
/// hoy, las monedas saltan de la casilla a la cabecera y la cifra sube.
class LoginBonusPanel extends ConsumerStatefulWidget {
  const LoginBonusPanel({super.key, this.preview = false});

  final bool preview;

  @override
  ConsumerState<LoginBonusPanel> createState() => _LoginBonusPanelState();
}

enum _Step { ready, claiming, done, failed }

class _LoginBonusPanelState extends ConsumerState<LoginBonusPanel> with TickerProviderStateMixin {
  late final AnimationController _stamp;
  late final AnimationController _coins;
  late final AnimationController _glow;
  _Step _step = _Step.ready;

  final GlobalKey _stackKey = GlobalKey(debugLabel: 'bonus.stack');
  final GlobalKey _todayKey = GlobalKey(debugLabel: 'bonus.today');
  final GlobalKey _targetKey = GlobalKey(debugLabel: 'bonus.target');
  Offset? _from;
  Offset? _to;
  int _landed = 0;

  final int _today = bonusDay();

  int get _amount => loginBonusFor(_today);

  @override
  void initState() {
    super.initState();
    _stamp = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
    _coins = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..addListener(_countLanded);
    _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _stamp.dispose();
    _coins.dispose();
    _glow.dispose();
    super.dispose();
  }

  /// Cuantas monedas vuelan: una por moneda, hasta diez.
  int get _flying => math.min(_amount, 10);

  static const double _flight = .45;

  double _startOf(int i) => _flying <= 1 ? 0 : i / (_flying - 1) * (1 - _flight);

  void _countLanded() {
    var landed = 0;
    for (var i = 0; i < _flying; i++) {
      if (_coins.value >= _startOf(i) + _flight) landed++;
    }
    if (landed != _landed) {
      if (landed > _landed) AudioService.instance.play(Sfx.tick);
      setState(() => _landed = landed);
    }
  }

  Future<void> _claim() async {
    final skin = IbashoSkin.of(context);
    setState(() => _step = _Step.claiming);
    final int? got;
    if (widget.preview) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      got = _amount;
    } else {
      got = await ref.read(loginBonusProvider.notifier).claim();
    }
    if (!mounted) return;
    if (got == null) {
      AudioService.instance.play(Sfx.error);
      setState(() => _step = _Step.failed);
      return;
    }
    _measure();
    setState(() => _step = _Step.done);
    AudioService.instance.play(Sfx.chime);
    await _stamp.animateTo(1, duration: skin.motion(_stamp.duration!));
    if (!mounted) return;
    _measure();
    await _coins.animateTo(1, duration: skin.motion(_coins.duration!));
  }

  /// Donde esta la casilla de hoy y la moneda de la cabecera, en el sistema
  /// del [Stack] de las monedas voladoras.
  void _measure() {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    Offset? centerOf(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || stack == null || !box.attached) return null;
      return stack.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
    }

    _from = centerOf(_todayKey);
    _to = centerOf(_targetKey);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final skin = IbashoSkin.of(context);
    final bonus = ref.watch(loginBonusProvider);
    final already = !widget.preview && bonus.claimedOn(_today) && _step == _Step.ready;
    final width = math.min(560.0, layout.width - layout.gutter * 2);
    final date = bonusDate(_today);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final month = DateFormat.MMMM(locale).format(date);

    final shown = switch (_step) {
      _Step.done => (_amount * _landed / math.max(1, _flying)).round(),
      _ => 0,
    };

    return SizedBox(
      width: width,
      child: GlossSurface(
        key: const ValueKey<String>('bonus.panel'),
        radius: 28,
        elevation: 2.4,
        padding: layout.pick(const EdgeInsets.fromLTRB(28, 24, 28, 22), const EdgeInsets.fromLTRB(16, 18, 16, 16)),
        child: Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.bonusTitle,
                            style: layout.pick(Ty.title, Ty.lead.copyWith(fontWeight: FontWeight.w500)),
                          ),
                          Text(
                            widget.preview ? '$month · ${l.bonusPreview}' : month,
                            style: Ty.caption.copyWith(color: skin.accentDeep),
                          ),
                        ],
                      ),
                    ),
                    _Counter(coinKey: _targetKey, value: shown, pop: _landed, done: _step == _Step.done),
                  ],
                ),
                SizedBox(height: layout.pick(16, 12)),
                _Weekdays(labels: l.bonusWeekdays.split(',')),
                const SizedBox(height: 6),
                _Month(
                  today: _today,
                  claimed: (d) =>
                      (widget.preview ? d < _today && bonus.claimedOn(d) : bonus.claimedOn(d)) ||
                      (d == _today && _step == _Step.done),
                  todayKey: _todayKey,
                  stamp: _stamp,
                  glow: _glow,
                ),
                SizedBox(height: layout.pick(14, 10)),
                Text(
                  switch (_step) {
                    _ when already => l.bonusAlready,
                    _Step.failed => l.bonusFailed,
                    _Step.done => l.bonusDone(_amount),
                    _ => l.bonusHint,
                  },
                  textAlign: TextAlign.center,
                  style: Ty.caption.copyWith(color: _step == _Step.failed ? T.wrong : T.inkSoft),
                ),
                SizedBox(height: layout.pick(14, 10)),
                if (_step == _Step.done || already || _step == _Step.failed)
                  IbashoButton(
                    key: const ValueKey<String>('bonus.close'),
                    label: _step == _Step.failed ? l.actionClose : l.bonusSeeYou,
                    glyph: _step == _Step.failed ? null : Glyph.check,
                    tone: _step == _Step.failed ? ButtonTone.quiet : ButtonTone.accent,
                    expand: true,
                    cue: Sfx.back,
                    onPressed: () => Navigator.of(context).pop(),
                  )
                else
                  IbashoButton(
                    key: const ValueKey<String>('bonus.claim'),
                    label: l.bonusClaim(_amount),
                    glyph: Glyph.coin,
                    tone: ButtonTone.accent,
                    expand: true,
                    cue: null,
                    onPressed: _step == _Step.ready && (bonus.loaded || widget.preview) ? _claim : null,
                  ),
              ],
            ),
            // Las monedas voladoras, por encima de todo.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _coins,
                  builder: (context, _) => CustomMultiChildLayout(
                    delegate: _FlightLayout(
                      from: _from,
                      to: _to,
                      progress: [
                        for (var i = 0; i < _flying; i++) ((_coins.value - _startOf(i)) / _flight).clamp(0.0, 1.0),
                      ],
                    ),
                    children: [
                      for (var i = 0; i < _flying; i++)
                        LayoutId(
                          id: i,
                          child: Opacity(opacity: _coinOpacity(i), child: const ArtIconView(ArtIcon.coin, size: 26)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _coinOpacity(int i) {
    if (_from == null || _to == null || !_coins.isAnimating && _coins.value == 0) return 0;
    final t = ((_coins.value - _startOf(i)) / _flight);
    if (t <= 0 || t >= .999) return 0;
    return 1;
  }
}

/// Coloca cada moneda en su arco: sale de hoy, sube y cae en la cabecera.
class _FlightLayout extends MultiChildLayoutDelegate {
  _FlightLayout({required this.from, required this.to, required this.progress});

  final Offset? from;
  final Offset? to;
  final List<double> progress;

  @override
  void performLayout(Size size) {
    for (var i = 0; i < progress.length; i++) {
      final s = layoutChild(i, const BoxConstraints());
      final a = from ?? Offset.zero;
      final b = to ?? Offset.zero;
      final t = Curves.easeInOutCubic.transform(progress[i]);
      // Un poco de abanico para que no vayan todas por el mismo sitio.
      final spread = (i.isEven ? 1 : -1) * (12.0 + i * 3);
      final mid = Offset((a.dx + b.dx) / 2 + spread, math.min(a.dy, b.dy) - 70);
      final p = Offset(
        (1 - t) * (1 - t) * a.dx + 2 * (1 - t) * t * mid.dx + t * t * b.dx,
        (1 - t) * (1 - t) * a.dy + 2 * (1 - t) * t * mid.dy + t * t * b.dy,
      );
      positionChild(i, p - s.center(Offset.zero));
    }
  }

  @override
  bool shouldRelayout(_FlightLayout old) => true;
}

/// La moneda de la cabecera con lo cobrado hoy, que salta con cada moneda
/// que le llega.
class _Counter extends StatelessWidget {
  const _Counter({required this.coinKey, required this.value, required this.pop, required this.done});

  /// La moneda a la que llegan las que vuelan.
  final GlobalKey coinKey;

  final int value;
  final int pop;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(pop),
      tween: Tween<double>(begin: pop == 0 ? 1 : 1.25, end: 1),
      duration: skin.motion(const Duration(milliseconds: 260)),
      curve: skin.curve(Curves.easeOutBack),
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: GlossSurface(
        radius: 22,
        recessed: true,
        padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtIconView(ArtIcon.coin, key: coinKey, size: 30),
            const SizedBox(width: 6),
            Text(
              '+$value',
              key: const ValueKey<String>('bonus.counter'),
              style: Ty.numeral(24, color: done ? Art.goldDark : T.inkSoft, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _Weekdays extends StatelessWidget {
  const _Weekdays({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, d) in labels.indexed)
        Expanded(
          child: Text(
            d,
            textAlign: TextAlign.center,
            style: Ty.micro.copyWith(fontWeight: FontWeight.w600, color: i >= 4 ? Art.goldDark : T.inkSoft),
          ),
        ),
    ],
  );
}

/// El mes de hoy (UTC), en semanas de lunes a domingo.
class _Month extends StatelessWidget {
  const _Month({
    required this.today,
    required this.claimed,
    required this.todayKey,
    required this.stamp,
    required this.glow,
  });

  final int today;
  final bool Function(int day) claimed;
  final GlobalKey todayKey;
  final Animation<double> stamp;
  final Animation<double> glow;

  @override
  Widget build(BuildContext context) {
    final date = bonusDate(today);
    final first = bonusDay(DateTime.utc(date.year, date.month));
    final length = DateTime.utc(date.year, date.month + 1, 0).day;
    final lead = (first + 3) % 7; // huecos antes del dia 1, con el lunes primero
    final cells = <int?>[for (var i = 0; i < lead; i++) null, for (var d = 0; d < length; d++) first + d];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 6.0;
        final w = (box.maxWidth - gap * 6) / 7;
        final h = math.min(w * 1.02, 62.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < cells.length ~/ 7; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              Row(
                children: [
                  for (var c = 0; c < 7; c++) ...[
                    if (c > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: w,
                      height: h,
                      child: switch (cells[r * 7 + c]) {
                        null => null,
                        final d => _DayCell(
                          key: d == today ? todayKey : ValueKey<String>('bonus.day.$d'),
                          dayOfMonth: d - first + 1,
                          amount: loginBonusFor(d),
                          isToday: d == today,
                          past: d < today,
                          claimed: claimed(d),
                          stamp: d == today ? stamp : null,
                          glow: glow,
                          size: Size(w, h),
                        ),
                      },
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.dayOfMonth,
    required this.amount,
    required this.isToday,
    required this.past,
    required this.claimed,
    required this.stamp,
    required this.glow,
    required this.size,
  });

  final int dayOfMonth;
  final int amount;
  final bool isToday;
  final bool past;
  final bool claimed;
  final Animation<double>? stamp;
  final Animation<double> glow;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final big = amount >= 10;
    final missed = past && !claimed;
    final u = size.width;
    Widget cell = GlossSurface(
      radius: u * .22,
      tint: isToday ? skin.accentWash : (big ? const Color(0xFFFFF4D6) : null),
      elevation: missed ? .4 : (isToday ? 2 : 1),
      borderColor: isToday ? skin.accentDeep : null,
      borderWidth: isToday ? 2 : 1,
      child: Padding(
        padding: EdgeInsets.all(u * .08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$dayOfMonth', style: Ty.micro.copyWith(height: 1, fontSize: math.max(9, u * .2))),
            Expanded(
              child: Center(
                child: FittedBox(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArtIconView(ArtIcon.coin, size: u * (big ? .3 : .24)),
                      SizedBox(width: u * .03),
                      Text(
                        '$amount',
                        style: Ty.numeral(
                          u * (big ? .3 : .26),
                          color: big ? Art.goldDark : T.ink,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (missed) cell = Opacity(opacity: .45, child: cell);
    // Cobrado, el sello manda: lo de debajo se aparta un poco.
    if (claimed) cell = Opacity(opacity: .7, child: cell);
    if (isToday && !claimed) {
      // Hoy late, llamando a cobrar.
      cell = AnimatedBuilder(
        animation: glow,
        child: cell,
        builder: (context, child) => Transform.scale(scale: 1 + .05 * glow.value, child: child),
      );
    }
    final seal = SizedBox.square(
      dimension: u * .92,
      child: const CustomPaint(painter: MaruPainter()),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: cell),
        if (claimed)
          Positioned.fill(
            top: u * .1,
            child: OverflowBox(
              maxWidth: u,
              maxHeight: u,
              child: stamp == null
                  ? seal
                  : AnimatedBuilder(
                      animation: stamp!,
                      child: seal,
                      // El sello cae desde grande y girado, como un hanko.
                      builder: (context, child) {
                        final t = Curves.easeOutBack.transform(stamp!.value);
                        return Opacity(
                          opacity: stamp!.value.clamp(0.0, 1.0),
                          child: Transform.rotate(
                            angle: (1 - t) * .7 - .15,
                            child: Transform.scale(scale: 2.4 - 1.4 * t, child: child),
                          ),
                        );
                      },
                    ),
            ),
          ),
      ],
    );
  }
}
