// Ibasho — el canal del gachapon: la maquina, la tirada animada y el
// deposito de bolas. El Catalogo vive en el pinball.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Es una escena, no un formulario (docs/UI.md §2): la maquina manda y ocupa
// todo el alto, con su foco y su sombra de contacto; a un lado, el escenario
// con los tickets y el deposito. Los tickets se compran en el
// Yatai, aqui solo se gastan.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/gacha.dart';
import '../../../backend/missions.dart';
import '../../../games/game_stage.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/gacha.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../widgets/channel_art.dart';
import '../../widgets/controls.dart';
import '../../widgets/gacha_art.dart';
import '../../widgets/gloss.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/overlays.dart';
import '../../widgets/pressable.dart';
import '../channel_route.dart';

String ticketName(L l, TicketKind kind) =>
    kind == TicketKind.kinken ? l.gachaTicketKinken : l.gachaTicketGachaken;

ArtIcon ticketArt(TicketKind kind) =>
    kind == TicketKind.kinken ? ArtIcon.ticketKinken : ArtIcon.ticketGachaken;

String categoryName(L l, GachaCategory category) => switch (category) {
      GachaCategory.hats => l.gachaCategoryHats,
      GachaCategory.accessories => l.gachaCategoryAccessories,
      GachaCategory.backdrops => l.gachaCategoryBackdrops,
      GachaCategory.music => l.gachaCategoryMusic,
    };

/// Cada rareza tiene su premio sonoro; de R para abajo basta el chasquido.
/// Lo usan la tirada y el premio del pinball.
Sfx? rarityFanfare(Rarity rarity) => switch (rarity) {
      Rarity.n || Rarity.r => null,
      Rarity.sr => Sfx.rare,
      Rarity.ur => Sfx.legend,
      Rarity.ssr => Sfx.epic,
      Rarity.mu => Sfx.infinity,
    };

/// Un toque con vida para lo que no es un boton: realza al pasar por encima y
/// se hunde al pulsar.
class _Tap extends StatelessWidget {
  const _Tap({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduced = IbashoSkin.of(context).reducedMotion;
    return Pressable(
      onPressed: onPressed,
      enabled: onPressed != null,
      semanticLabel: semanticLabel,
      builder: (context, state) {
        final scale = reduced ? 1.0 : 1 + .03 * state.hover - .05 * state.press;
        return Opacity(
          opacity: state.enabled ? 1 : .55,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

// --- El canal -------------------------------------------------------------

/// En que punto de la tirada esta la maquina de la pantalla.
enum _Phase {
  /// Quieta, esperando.
  idle,

  /// La manivela gira mientras la tirada viaja.
  crank,

  /// Las capsulas salen por la boca, ya de su color, hasta la bandeja.
  drop,

  /// Todas fuera, esperando a que se guarden.
  done,
}

/// El gachapon entero: escenario a un lado y la maquina grande al otro.
///
/// La tirada **no** abre otra pantalla: pasa en esta maquina. La manivela
/// gira aqui, las capsulas salen por su boca a la bandeja de abajo y se abren
/// donde han caido.
class GachaChannel extends ConsumerStatefulWidget {
  const GachaChannel({super.key});

  @override
  ConsumerState<GachaChannel> createState() => _GachaChannelState();
}

class _GachaChannelState extends ConsumerState<GachaChannel>
    with TickerProviderStateMixin {
  TicketKind _kind = TicketKind.gachaken;

  /// La manivela dando vueltas mientras la tirada viaja.
  late final AnimationController _crank =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  /// Las capsulas cayendo por la boca a la bandeja.
  late final AnimationController _drop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  /// El golpe de cada bola al abrirse.
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  _Phase _phase = _Phase.idle;
  PullResult? _result;

  /// Cuantas bolas se han tirado (se sabe antes que el resultado) y cuantas
  /// se han destapado ya.
  int _balls = 0;
  int _shown = 0;

  /// Cuantas capsulas han tocado la bandeja: cada una suena al caer.
  int _fallen = 0;

  bool _skipped = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    // Se empieza con el ticket que se tiene: entrar y ver «sin tickets»
    // teniendo kinken era el peor recibimiento posible.
    final gacha = ref.read(gachaProvider);
    if (gacha.ticketsOf(TicketKind.gachaken) == 0 &&
        gacha.ticketsOf(TicketKind.kinken) > 0) {
      _kind = TicketKind.kinken;
    }
    _drop.addListener(_onDrop);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = IbashoSkin.of(context).reducedMotion;
  }

  @override
  void dispose() {
    _drop.removeListener(_onDrop);
    _crank.dispose();
    _drop.dispose();
    _pop.dispose();
    super.dispose();
  }

  bool get _busy => _phase != _Phase.idle;

  /// Cada vez que una capsula toca la bandeja: su golpe, su chasquido y, si
  /// es gorda, su fanfarria. Suena al caer, no despues.
  void _onDrop() {
    final result = _result;
    final landed = ballsLandedAt(_drop.value, _balls);
    if (landed <= _fallen) return;
    for (var i = _fallen; i < landed; i++) {
      AudioService.instance.play(Sfx.capsule);
      AudioService.instance.play(Sfx.pop);
      if (result != null && i < result.balls.length) {
        final fanfare = rarityFanfare(result.balls[i].rarity);
        if (fanfare != null) AudioService.instance.play(fanfare);
      }
    }
    _pop.forward(from: 0);
    setState(() {
      _fallen = landed;
      _shown = landed;
    });
  }

  Future<void> _wait(int ms) async {
    if (_skipped) return;
    await Future<void>.delayed(Duration(milliseconds: _reduced ? 0 : ms));
  }

  Future<void> _pull(int balls) async {
    final l = L.of(context)!;
    final gacha = ref.read(gachaProvider);
    if (gacha.busy || _busy) return;
    if (!gacha.canPull(_kind, balls)) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.gachaErrorNoTickets, isError: true);
      return;
    }

    // Los tickets cuestan monedas y una semana de espera: nunca se gastan de
    // un toque sin decir cuantos.
    final go = await showIbashoModal<bool>(
      context,
      (context) => _ConfirmPull(
        kind: _kind,
        balls: balls,
        cost: pullCost(balls),
        after: gacha.ticketsOf(_kind) - pullCost(balls),
      ),
    );
    if (!mounted || go != true) return;

    setState(() {
      _phase = _Phase.crank;
      _balls = balls;
      _result = null;
      _shown = 0;
      _fallen = 0;
      _skipped = false;
    });
    if (!_reduced) _crank.repeat();
    AudioService.instance.play(Sfx.crank);

    PullResult result;
    try {
      // La manivela suena entera aunque el servidor conteste antes.
      final both = await Future.wait(<Future<Object?>>[
        ref.read(gachaProvider.notifier).pull(_kind, balls: balls),
        Future<void>.delayed(Duration(milliseconds: _reduced ? 0 : 1100)),
      ]);
      result = both.first! as PullResult;
      unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.pull));
    } catch (e) {
      if (!mounted) return;
      _crank.stop();
      setState(() => _phase = _Phase.idle);
      AudioService.instance.play(Sfx.error);
      final failure = e is PullException ? e.failure : PullFailure.rejected;
      showIbashoToast(
        context,
        failure == PullFailure.noTickets ? l.gachaErrorNoTickets : l.gachaErrorPull,
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    _crank.stop();
    setState(() {
      _result = result;
      _phase = _Phase.drop;
    });

    // Cada bola se mira un rato: una sola tarda lo mismo que una de las
    // once, y once no son una ametralladora.
    _drop.duration = Duration(milliseconds: 1000 + 320 * result.balls.length);
    if (!_reduced) {
      await _drop.forward(from: 0);
    } else {
      setState(() => _shown = result.balls.length);
    }
    if (!mounted) return;
    // Un respiro con todo a la vista antes de poder guardarlo.
    await _wait(360);
    if (!mounted) return;
    setState(() {
      _shown = result.balls.length;
      _phase = _Phase.done;
    });
  }

  /// Tocar la bandeja se salta la ceremonia y ensena todo lo que ha salido.
  void _skip() {
    if (_result == null || _phase == _Phase.done || _phase == _Phase.idle) return;
    _drop.stop();
    setState(() {
      _skipped = true;
      _shown = _result!.balls.length;
      _phase = _Phase.done;
    });
  }

  /// Guardar el botin: las bolas ya estan en el deposito, aqui solo se
  /// recoge la bandeja.
  void _keep() {
    AudioService.instance.play(Sfx.back);
    setState(() {
      _phase = _Phase.idle;
      _result = null;
      _shown = 0;
      _balls = 0;
    });
  }

  void _openDeposit() => unawaited(showIbashoModal<void>(
        context,
        (context) => const _DepositDialog(),
      ));

  void _choose(TicketKind kind) {
    if (kind == _kind || _busy) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _kind = kind);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tall = layout.tall;
    final gacha = ref.watch(gachaProvider);
    final shop = ref.watch(shopProvider);

    final tickets = <Widget>[
      for (final kind in TicketKind.values)
        _TicketCard(
          kind: kind,
          count: gacha.ticketsOf(kind),
          left: shop.ticketsLeftThisWeek(kind),
          selected: _kind == kind,
          compact: tall,
          onPressed: () => _choose(kind),
        ),
    ];

    final deposit = _DepositCard(balls: gacha.totalBalls, onPressed: _openDeposit);

    final machine = _MachineStage(
      phase: _phase,
      crank: _crank,
      drop: _drop,
      pop: _pop,
      balls: _balls,
      result: _result,
      shown: _shown,
      tall: tall,
      busy: gacha.busy || _busy,
      onPull: () => unawaited(_pull(singlePullBalls)),
      onPullMulti: () => unawaited(_pull(multiPullBalls)),
      onSkip: _skip,
      onKeep: _keep,
    );

    return ChannelScaffold(
      title: l.channelGacha,
      glyph: Glyph.gift,
      art: ArtIcon.gacha,
      child: Padding(
        padding: EdgeInsets.fromLTRB(layout.gutter, 6, layout.gutter, tall ? 12 : 16),
        child: tall
            ? Column(
                children: [
                  Expanded(child: machine),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: tickets[0]),
                      const SizedBox(width: 10),
                      Expanded(child: tickets[1]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: deposit),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 330,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l.gachaChooseTicket,
                          style: Ty.micro.copyWith(color: Ty.inkSoft),
                        ),
                        const SizedBox(height: 6),
                        tickets[0],
                        const SizedBox(height: 8),
                        tickets[1],
                        const SizedBox(height: 14),
                        SizedBox(width: double.infinity, child: deposit),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: machine),
                ],
              ),
      ),
    );
  }
}

// --- La maquina y su bandeja ----------------------------------------------

/// Cuantas capsulas han terminado su caida en el instante [t].
int ballsLandedAt(double t, int count) {
  var landed = 0;
  for (var i = 0; i < count; i++) {
    if (ballDropProgress(t, i, count) >= 1) landed++;
  }
  return landed;
}

/// El avance de la capsula [i] dentro de la caida entera, de 0 a 1.
double ballDropProgress(double t, int i, int count) {
  final step = count <= 1 ? 0.0 : .58 / (count - 1);
  final span = count <= 1 ? 1.0 : .42;
  return ((t - i * step) / span).clamp(0.0, 1.0);
}

/// La maquina bajo su foco, con la bandeja debajo y los botones al pie.
///
/// Todo lo que pasa en una tirada pasa aqui dentro: no hay otra pantalla.
class _MachineStage extends StatefulWidget {
  const _MachineStage({
    required this.phase,
    required this.crank,
    required this.drop,
    required this.pop,
    required this.balls,
    required this.result,
    required this.shown,
    required this.tall,
    required this.busy,
    required this.onPull,
    required this.onPullMulti,
    required this.onSkip,
    required this.onKeep,
  });

  final _Phase phase;
  final AnimationController crank;
  final AnimationController drop;
  final AnimationController pop;

  /// Cuantas bolas se han tirado (antes incluso de saber cuales).
  final int balls;
  final PullResult? result;
  final int shown;
  final bool tall;
  final bool busy;
  final VoidCallback onPull;
  final VoidCallback onPullMulti;
  final VoidCallback onSkip;
  final VoidCallback onKeep;

  @override
  State<_MachineStage> createState() => _MachineStageState();
}

class _MachineStageState extends State<_MachineStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Con movimiento reducido la maquina se queda quieta; si no, nunca
    // dejaria de haber fotogramas pendientes (y los tests no acabarian).
    if (IbashoSkin.of(context).reducedMotion) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat();
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final reduced = IbashoSkin.of(context).reducedMotion;
    final phase = widget.phase;
    final working = phase == _Phase.crank || phase == _Phase.drop;

    return StageLight(
      child: LayoutBuilder(builder: (context, box) {
        final buttons = widget.tall ? 50.0 : 56.0;
        // La bandeja siempre ocupa su sitio, llena o vacia: asi la maquina no
        // pega un salto al empezar la tirada.
        final tray = widget.tall ? 74.0 : 92.0;
        final size = math.max(
          140.0,
          math.min(box.maxWidth * .78, box.maxHeight - buttons - tray - 22),
        );
        final count = widget.result?.balls.length ?? widget.balls;
        final ball = count <= 1
            ? 54.0
            : math.min(42.0, (box.maxWidth - 24) / count - 6).clamp(18.0, 42.0);

        final scene = SizedBox(
          width: box.maxWidth,
          height: size + tray,
          child: AnimatedBuilder(
            animation: Listenable.merge(
                <Listenable>[_idle, widget.crank, widget.drop, widget.pop]),
            builder: (context, _) {
              final t = widget.drop.value;
              // En reposo la manivela esta quieta y la maquina solo respira.
              final double crank;
              final double stir;
              switch (phase) {
                case _Phase.idle:
                  crank = 0;
                  stir = reduced ? 0 : .12;
                case _Phase.crank:
                  crank = Curves.easeInOut.transform(widget.crank.value) * 2;
                  stir = 1;
                case _Phase.drop:
                  crank = t * 2;
                  stir = (1 - t).clamp(0.0, 1.0);
                case _Phase.done:
                  crank = 0;
                  stir = 0;
              }
              final breath = reduced || working
                  ? 0.0
                  : math.sin(_idle.value * math.pi * 2) * .006;

              return Stack(
                children: [
                  // Las bolas se pintan DETRAS de la maquina: dentro no se
                  // ven, y aparecen justo al asomar por la boca.
                  ..._balls(box.maxWidth, size, tray, ball, count, t),
                  Positioned(
                    left: (box.maxWidth - size) / 2,
                    top: 0,
                    child: Transform.rotate(
                      angle: breath,
                      child: GachaMachineView(
                        size: size,
                        crank: crank,
                        stir: stir,
                        tremble: phase == _Phase.crank ? .8 : 0,
                        lit: working,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );

        final Widget foot;
        if (phase == _Phase.done) {
          foot = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IbashoButton(
                key: const ValueKey<String>('gacha.keep'),
                label: l.gachaKeep,
                tone: ButtonTone.accent,
                cue: null,
                height: buttons - 8,
                minWidth: 200,
                onPressed: widget.onKeep,
              ),
            ],
          );
        } else if (working) {
          foot = Center(
            child: Text(
              phase == _Phase.crank ? l.gachaRolling : l.gachaSkip,
              style: Ty.body.copyWith(color: Ty.inkSoft),
            ),
          );
        } else {
          foot = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IbashoButton(
                key: const ValueKey<String>('gacha.pull'),
                label: l.gachaPull,
                glyph: Glyph.gift,
                tone: ButtonTone.accent,
                cue: null,
                height: buttons - 8,
                minWidth: widget.tall ? 130 : 170,
                onPressed: widget.busy ? null : widget.onPull,
              ),
              const SizedBox(width: 12),
              IbashoButton(
                key: const ValueKey<String>('gacha.pull11'),
                label: l.gachaPullMulti,
                cue: null,
                height: buttons - 8,
                minWidth: widget.tall ? 120 : 150,
                onPressed: widget.busy ? null : widget.onPullMulti,
              ),
            ],
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          // Durante la ceremonia, tocar la escena la salta.
          onTap: phase == _Phase.drop ? widget.onSkip : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  // Trabajando, la maquina no es un boton: se queda a todo
                  // color en vez de apagarse como algo deshabilitado.
                  child: widget.busy
                      ? KeyedSubtree(
                          key: const ValueKey<String>('gacha.machine'),
                          child: scene,
                        )
                      : _Tap(
                          key: const ValueKey<String>('gacha.machine'),
                          onPressed: widget.onPull,
                          semanticLabel: l.gachaPull,
                          child: scene,
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(height: buttons, child: Center(child: foot)),
            ],
          ),
        );
      }),
    );
  }

  /// Las capsulas: saliendo por la boca, esperando en la bandeja o abiertas.
  List<Widget> _balls(
    double width,
    double size,
    double tray,
    double ball,
    int count,
    double dropT,
  ) {
    // Mientras gira la manivela no hay nada que ensenar: las capsulas siguen
    // dentro. Pintarlas aqui era lo que hacia asomar una bola gris en la
    // bandeja justo al dar a tirar.
    if (count == 0 || widget.phase == _Phase.idle) return const <Widget>[];
    final result = widget.result;
    // Mientras gira la manivela solo se prepara la bandeja: las capsulas
    // siguen dentro.
    final waiting = result == null || widget.phase == _Phase.crank;
    final reduced = IbashoSkin.of(context).reducedMotion;

    // La boca de la maquina y la fila de la bandeja, en pixeles.
    final mouth = Offset(
      (width - size) / 2 + GachaMachineView.mouth.dx / 100 * size - ball / 2,
      GachaMachineView.mouth.dy / 100 * size - ball / 2,
    );
    final row = count * (ball + 6) - 6;
    final trayTop = size + (tray - ball) / 2 - 6;

    // La bandeja donde caen: un hueco de cristal, como los del entorno.
    final out = <Widget>[
      Positioned(
        left: (width - row - 26) / 2,
        top: trayTop - 9,
        child: GlossSurface(
          radius: (ball + 18) / 2,
          recessed: true,
          elevation: 0,
          child: SizedBox(width: row + 26, height: ball + 18),
        ),
      ),
    ];
    if (waiting) return out;
    for (var i = 0; i < count; i++) {
      // Solo al terminar estan todas puestas; durante la caida cada una va
      // por donde le toca.
      final p = widget.phase == _Phase.done
          ? 1.0
          : ballDropProgress(dropT, i, count);
      if (p <= 0) continue;
      final target = Offset((width - row) / 2 + i * (ball + 6), trayTop);
      final x = mouth.dx + (target.dx - mouth.dx) * Curves.easeOut.transform(p);
      final y = mouth.dy + (target.dy - mouth.dy) * Curves.bounceOut.transform(p);

      // Sale ya de su color: lo que se ve es lo que ha tocado.
      final rarity = i < result.balls.length ? result.balls[i].rarity : Rarity.n;
      // La ultima en tocar la bandeja da su golpe.
      final opening = i == widget.shown - 1 && widget.phase == _Phase.drop;
      final t = reduced ? 1.0 : widget.pop.value;
      final scale = opening ? 1 + .55 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0)) : 1.0;

      out.add(Positioned(
        left: x,
        top: y,
        child: Transform.rotate(
          angle: p < 1 ? p * math.pi * (i.isEven ? 1.2 : -1.2) : 0,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: ball,
              height: ball,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (opening && RarityArt.shines(rarity))
                    Positioned(
                      left: -ball,
                      top: -ball,
                      width: ball * 3,
                      height: ball * 3,
                      child: CustomPaint(
                        painter: _BurstPainter(rarity: rarity, t: t),
                      ),
                    ),
                  GachaBallView(rarity, size: ball, shadow: false),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    // Debajo de la bandeja, la cinta de lo mejor que ha salido.
    if (widget.phase == _Phase.done) {
      final best = result.balls
          .map((b) => b.rarity)
          .reduce((a, b) => a.index >= b.index ? a : b);
      out.add(Positioned(
        left: 0,
        right: 0,
        top: trayTop + ball + 4,
        child: Center(
          child: RarityBadge(best, height: 22),
        ),
      ));
    }
    return out;
  }
}

// --- El escenario ---------------------------------------------------------

/// Un ticket de la cartera: cuantos hay y cuantos quedan por comprar esta
/// semana en el Yatai. Tocarlo lo elige.
class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.kind,
    required this.count,
    required this.left,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final TicketKind kind;
  final int count;
  final int left;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final total = weeklyTicketLimit[kind] ?? 0;

    final title = Text(
      ticketName(l, kind),
      style: Ty.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final counter = Text(
      '$count',
      style: Ty.numeral(compact ? 22 : 28, weight: FontWeight.w700)
          .copyWith(color: selected ? skin.accentDeep : Ty.ink),
    );
    // En vertical los puntitos se quedan fuera: la frase sola ya dice
    // cuantos quedan, y en 360 px no cabe todo en una linea.
    final weekly = Row(
      children: [
        if (!compact) ...[
          _WeeklyPips(left: left, total: total),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            l.gachaWeeklyLeft(left),
            style: Ty.micro.copyWith(color: Ty.inkSoft),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return _Tap(
      onPressed: onPressed,
      semanticLabel: '${ticketName(l, kind)} · ${l.gachaTicketsLeft(count)}',
      child: GlossSurface(
        key: ValueKey<String>('gacha.kind.${kind.name}'),
        radius: 18,
        tint: selected ? skin.accent : null,
        elevation: selected ? 2 : 1,
        padding: EdgeInsets.fromLTRB(12, compact ? 8 : 11, 12, compact ? 8 : 11),
        child: Row(
          children: [
            ArtIconView(ticketArt(kind), size: compact ? 34 : 46),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  const SizedBox(height: 2),
                  weekly,
                ],
              ),
            ),
            const SizedBox(width: 6),
            counter,
          ],
        ),
      ),
    );
  }
}

/// Los puntitos de lo que queda por comprar esta semana.
class _WeeklyPips extends StatelessWidget {
  const _WeeklyPips({required this.left, required this.total});

  final int left;
  final int total;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final shown = math.min(total, 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2.5),
            child: SizedBox(
              width: 5,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < left ? skin.accent : skin.hairline,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// El deposito: cuantas bolas esperan al pinball.
class _DepositCard extends StatelessWidget {
  const _DepositCard({required this.balls, required this.onPressed});

  final int balls;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return _Tap(
      key: const ValueKey<String>('gacha.deposit'),
      onPressed: onPressed,
      semanticLabel: l.gachaDeposit,
      child: GlossSurface(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GachaBallView(Rarity.sr, size: 28, shadow: false),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.gachaDeposit, style: Ty.micro.copyWith(color: Ty.inkSoft)),
                Text('$balls', style: Ty.numeral(18, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que se va a gastar, antes de gastarlo: tickets a la izquierda, bolas a
/// la derecha y lo que queda debajo.
class _ConfirmPull extends StatelessWidget {
  const _ConfirmPull({
    required this.kind,
    required this.balls,
    required this.cost,
    required this.after,
  });

  final TicketKind kind;
  final int balls;
  final int cost;
  final int after;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tall = Layout.of(context).tall;

    return IbashoDialog(
      title: l.gachaConfirmTitle,
      width: tall ? 340 : 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArtIconView(ticketArt(kind), size: 52),
                  const SizedBox(height: 4),
                  Text(l.gachaTicketsLeft(cost), style: Ty.label),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('→', style: Ty.title.copyWith(color: Ty.inkSoft)),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GachaBallView(Rarity.sr, size: 52, shadow: false),
                  const SizedBox(height: 4),
                  Text(l.gachaBalls(balls), style: Ty.label),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l.gachaLeftAfter(after), style: Ty.body.copyWith(color: Ty.inkSoft)),
        ],
      ),
      actions: [
        IbashoButton(
          key: const ValueKey<String>('gacha.confirm.no'),
          label: l.actionCancelPull,
          tone: ButtonTone.quiet,
          expand: tall,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        IbashoButton(
          key: const ValueKey<String>('gacha.confirm.yes'),
          label: l.gachaPull,
          tone: ButtonTone.accent,
          expand: tall,
          minWidth: tall ? 0 : 140,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// El estallido de rayos detras de una bola rara.
class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.rarity, required this.t});

  final Rarity rarity;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final color = RarityArt.of(rarity);
    final reach = size.shortestSide * (.32 + .18 * t);

    canvas.drawCircle(
      c,
      reach,
      Paint()
        ..color = color.withValues(alpha: .30 * (1 - t * .4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );

    final rays = Paint()..color = color.withValues(alpha: .34);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * .5);
    for (var i = 0; i < 12; i++) {
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(reach * 1.5, -reach * .10)
        ..lineTo(reach * 1.5, reach * .10)
        ..close();
      canvas.drawPath(path, rays);
      canvas.rotate(math.pi * 2 / 12);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.rarity != rarity;
}

// --- El deposito ----------------------------------------------------------

/// Lo guardado, por rareza, a la espera del pinball.
class _DepositDialog extends ConsumerWidget {
  const _DepositDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final gacha = ref.watch(gachaProvider);

    return IbashoDialog(
      title: l.gachaDeposit,
      width: 460,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.gachaDepositBody(gacha.totalBalls), style: Ty.body.copyWith(color: Ty.inkSoft)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final rarity in Rarity.values)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GachaBallView(rarity, size: 42, shadow: false),
                    const SizedBox(height: 3),
                    Text(
                      '${gacha.ballsOf(rarity)}',
                      style: Ty.numeral(15, weight: FontWeight.w700),
                    ),
                    RarityBadge(rarity, height: 18, faded: gacha.ballsOf(rarity) == 0),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(l.gachaDepositSoon, style: Ty.micro.copyWith(color: Ty.inkSoft)),
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionClose,
          tone: ButtonTone.accent,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
