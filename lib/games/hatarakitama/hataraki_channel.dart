// Ibasho — canal de Hatarakitama: el pueblo donde trabajan tus Tamas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/missions.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/hataraki.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_painter.dart';
import '../../ui/track_text.dart';
import '../../ui/tama/tama_text.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/slot_tile.dart';
import '../game_music.dart';
import '../game_stage.dart';
import 'hataraki_art.dart';
import 'hataraki_data.dart';
import 'hataraki_engine.dart';

/// Las cuatro partes del pueblo.
enum HTab { village, skills, bank, expedition }

/// Las canciones del pueblo: la mañana, el agua y el mercado al atardecer.
const List<MusicTrack> hatarakiTracks = [MusicTrack.asa, MusicTrack.mizuba, MusicTrack.yuyake];

/// El canal con su música: las tres por turnos, o la que se haya elegido.
class HatarakiScreen extends ConsumerWidget {
  const HatarakiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(preferencesProvider.select((p) => p.hatarakiTrack));
    final chosen = hatarakiTracks.where((t) => t.id == id).firstOrNull;
    return chosen == null
        ? GameMusic.cycle(cycle: hatarakiTracks, child: const HatarakiChannel())
        : GameMusic(track: chosen, child: const HatarakiChannel());
  }
}

// --- Textos -------------------------------------------------------------------

String hSkillName(L l, HSkill s) => l.hatarakiSkillName(s.name);

String hItemName(L l, String id) => l.hatarakiItemName(id);

/// Nombre de una tarea: lo que da (o el recorrido, en agilidad).
String hActionName(L l, HAction a) => a.skill == HSkill.agility
    ? l.hatarakiCourseName(a.id)
    : hItemName(l, a.outputs.keys.first);

String hZoneName(L l, String id) => l.hatarakiZoneName(id);

/// «1 h 05 min», «12 min» o «42 s».
String hDuration(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')} min';
  }
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

String _seconds(double s) =>
    s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);

/// Postura de un Tama trabajando en [skill], en el instante [t] (segundos).
TamaPose hWorkPose(
  HSkill skill,
  double t, {
  bool stalled = false,
  double joy = .5,
}) {
  if (stalled) return TamaPose(doze: .8, joy: -.3, breathe: math.sin(t * 1.4));
  final beat = math.sin(t * 5);
  return switch (skill) {
    HSkill.woodcutting || HSkill.mining || HSkill.smithing => TamaPose(
      tilt: .18 * math.max(0, beat),
      squash: .12 * math.max(0, -beat),
      joy: joy,
      armWave: math.max(0, beat),
    ),
    HSkill.fishing => TamaPose(
      sway: .2 * math.sin(t * 1.2),
      doze: .3,
      joy: joy,
      breathe: math.sin(t * 1.2),
    ),
    HSkill.farming || HSkill.foraging => TamaPose(
      lean: 4 * math.sin(t * 2),
      tilt: .08 * math.sin(t * 2),
      joy: joy,
    ),
    HSkill.agility => TamaPose(
      hop: 8 * math.max(0, math.sin(t * 4)),
      joy: joy,
      happyEyes: .4,
    ),
    HSkill.cooking || HSkill.tea => TamaPose(
      armWave: .5 + .5 * math.sin(t * 3),
      joy: joy,
      mouthOpen: .15,
    ),
    _ => TamaPose(
      tilt: .05 * math.sin(t * 3),
      breathe: math.sin(t * 2),
      joy: joy,
      blink: t % 3 < .12 ? 1 : 0,
    ),
  };
}

/// El canal de Hatarakitama.
///
/// Una sola escena, como el Yatai: a la izquierda el escenario con el Tama
/// elegido, el escaparate de lo que se ha tocado y su botón de acento; a la
/// derecha, las pestañas (pueblo, oficios, almacén, expedición) con su
/// rejilla paginada. El trabajo sigue aunque el canal esté cerrado: al volver
/// se enseña lo que ha pasado.
class HatarakiChannel extends ConsumerStatefulWidget {
  const HatarakiChannel({super.key});

  @override
  ConsumerState<HatarakiChannel> createState() => _HatarakiChannelState();
}

class _HatarakiChannelState extends ConsumerState<HatarakiChannel>
    with SingleTickerProviderStateMixin {
  HTab _tab = HTab.village;

  String? _tamaId;
  HSkill? _skill;
  String? _action;
  String? _item;
  String _zone = hZones.first.id;
  List<String> _party = const [];
  String? _food;
  final Map<HTab, int> _pages = {};

  final TamaViewController _tama = TamaViewController();
  String? _bubble;
  Timer? _bubbleTimer;

  Timer? _tick;
  Timer? _minute;
  late final AppLifecycleListener _life;
  bool _foreground = true;
  bool _awayShown = false;
  bool _helpShown = false;

  late final Ticker _anim;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  late final HatarakiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(hatarakiProvider.notifier);
    _anim = createTicker((e) => _clock.value = e.inMicroseconds / 1e6);
    _life = AppLifecycleListener(
      onShow: () => _foreground = true,
      onResume: () => _foreground = true,
      onHide: _leave,
      onPause: _leave,
    );
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    // Una moneda por minuto con el canal delante, hasta el tope del día.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground && mounted) {
        unawaited(
          ref
              .read(rewardsProvider.notifier)
              .claim(game: hatarakiGame, amount: 1),
        );
      }
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onTick();
      _say(L.of(context)!.hatarakiBubbleHello);
      _tama.hop();
      unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.play));
    });
  }

  void _leave() {
    _foreground = false;
    unawaited(ref.read(hatarakiProvider.notifier).save());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = IbashoSkin.of(context).reducedMotion;
    if (reduced && _anim.isActive) _anim.stop();
    if (!reduced && !_anim.isActive) _anim.start();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _minute?.cancel();
    _bubbleTimer?.cancel();
    _life.dispose();
    _anim.dispose();
    _clock.dispose();
    // `ref` ya no se puede usar aquí: se guarda con el que se cogió al entrar.
    unawaited(_controller.save());
    super.dispose();
  }

  void _say(
    String? text, {
    Duration hold = const Duration(milliseconds: 2600),
  }) {
    _bubbleTimer?.cancel();
    setState(() => _bubble = text);
    if (text == null) return;
    _bubbleTimer = Timer(hold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _onTick() {
    if (!mounted) return;
    final report = ref.read(hatarakiProvider.notifier).tick();
    if (report == null) return;
    final l = L.of(context)!;
    final state = ref.read(hatarakiProvider);
    // Partida recién empezada: la ayuda sale sola una vez en la vida.
    if (!_helpShown &&
        !ref.read(preferencesProvider).hatarakiHelpSeen &&
        state.game != null &&
        state.game!.xp.isEmpty &&
        state.game!.workers.isEmpty) {
      _helpShown = true;
      unawaited(ref.read(preferencesProvider.notifier).seeHatarakiHelp());
      unawaited(_help());
      return;
    }
    if (state.away != null && !_awayShown) {
      _awayShown = true;
      unawaited(_showAway(state.away!));
      return;
    }
    // Con la ventana minimizada o la app detrás, el pueblo sigue trabajando
    // pero en silencio: ni campanitas ni la voz del Tama.
    final audible = _foreground &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (report.levelUps.isNotEmpty) {
      final up = report.levelUps.entries.first;
      if (audible) AudioService.instance.play(Sfx.chime);
      _say(l.hatarakiBubbleLevelUp(hSkillName(l, up.key), up.value));
      _tama.hop();
      if (audible) _tama.cuddle();
    } else if (report.expeditionZone != null) {
      if (audible) AudioService.instance.play(Sfx.chime);
      _say(
        report.prizes > 0 ? l.hatarakiTreasure : l.hatarakiBubbleBack,
        hold: const Duration(seconds: 4),
      );
      _tama.hop();
    } else if (report.stalledTamas.isNotEmpty) {
      _say(l.hatarakiBubbleStalled);
    }
  }

  /// La ayuda, abierta en [page] (`work`, `level`, `likes`…).
  Future<void> _help([String page = 'work']) =>
      showIbashoModal<void>(context, (_) => _HelpDialog(start: page));

  Future<void> _showAway(HReport report) async {
    await showIbashoModal<void>(context, (_) => _AwayDialog(report: report));
    if (mounted) ref.read(hatarakiProvider.notifier).dismissAway();
  }

  // --- Órdenes ------------------------------------------------------------------

  void _pickTab(HTab tab) {
    if (tab == _tab) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _tab = tab);
  }

  Future<void> _assign(HAction action) async {
    final l = L.of(context)!;
    final game = ref.read(hatarakiProvider).game;
    if (game == null) return;
    final picked = await showIbashoModal<String>(
      context,
      (_) => _TamaPicker(skill: action.skill, game: game),
    );
    if (picked == null || !mounted) return;
    final ok = ref.read(hatarakiProvider.notifier).assign(picked, action.id);
    AudioService.instance.play(ok ? Sfx.chime : Sfx.error);
    if (ok) {
      setState(() {
        _tamaId = picked;
        _tab = HTab.village;
      });
      _say(l.hatarakiBubbleHello);
      _tama.hop();
    }
  }

  void _release(String tamaId) {
    ref.read(hatarakiProvider.notifier).release(tamaId);
    AudioService.instance.play(Sfx.back);
    _say(L.of(context)!.hatarakiBubbleIdle);
  }

  /// Le da de comer la comida más sencilla del almacén: sube su ánimo, y el
  /// ánimo es velocidad.
  void _feed(String tamaId) {
    final l = L.of(context)!;
    final meal = ref.read(hatarakiProvider.notifier).takeMeal();
    if (meal == null) {
      AudioService.instance.play(Sfx.error);
      _say(l.hatarakiNoMeal);
      return;
    }
    unawaited(ref.read(tamasProvider.notifier).feedMeal(tamaId));
    AudioService.instance.play(Sfx.chime);
    // Cae a la boca el plato que se come, no una chuche cualquiera.
    _tama.feed(TamaFood.dango, (c, at, s) => paintHatarakiFood(c, meal, at, s));
    _say(l.hatarakiBubbleFed);
  }

  void _drink(String item) {
    if (ref.read(hatarakiProvider.notifier).drinkTea(item)) {
      AudioService.instance.play(Sfx.chime);
      _say(L.of(context)!.hatarakiBubbleTea);
      _tama.cuddle();
    }
  }

  void _equip(String item) {
    if (ref.read(hatarakiProvider.notifier).equip(item)) {
      AudioService.instance.play(Sfx.chime);
    }
  }

  /// Vende [n] de [item]; con más de uno, pregunta antes.
  Future<void> _sell(String item, int n) async {
    final l = L.of(context)!;
    if (n > 1) {
      final ok = await askConfirmation(
        context,
        title: l.hatarakiSellTitle,
        body: l.hatarakiSellBody(n, hItemName(l, item), n * hSellValue(item)),
        confirmLabel: l.hatarakiSellAll,
        cancelLabel: l.actionCancel,
        width: 440,
      );
      if (ok != true || !mounted) return;
    }
    final got = ref.read(hatarakiProvider.notifier).sell(item, n);
    AudioService.instance.play(got > 0 ? Sfx.pop : Sfx.error);
    if (got > 0) _say(l.hatarakiSold(got));
  }

  void _unequip(HGearSlot slot) {
    if (ref.read(hatarakiProvider.notifier).unequip(slot)) {
      AudioService.instance.play(Sfx.back);
    }
  }

  Future<void> _cancelTrip() async {
    final l = L.of(context)!;
    final ok = await askConfirmation(
      context,
      title: l.hatarakiTripCancelTitle,
      body: l.hatarakiTripCancelBody,
      confirmLabel: l.hatarakiTripCancel,
      cancelLabel: l.actionCancel,
      width: 440,
    );
    if (!ok || !mounted) return;
    if (ref.read(hatarakiProvider.notifier).cancelExpedition()) {
      AudioService.instance.play(Sfx.back);
      _say(l.hatarakiBubbleBack);
    }
  }

  Future<void> _addToParty() async {
    final game = ref.read(hatarakiProvider).game;
    if (game == null) return;
    final picked = await showIbashoModal<String>(
      context,
      (_) => _TamaPicker(
        skill: HSkill.expedition,
        game: game,
        exclude: _party.toSet(),
      ),
    );
    if (picked != null && mounted) setState(() => _party = [..._party, picked]);
  }

  void _go(HZone zone, String food) {
    final ok = ref
        .read(hatarakiProvider.notifier)
        .startExpedition(zone.id, _party, food);
    AudioService.instance.play(ok ? Sfx.chime : Sfx.error);
    if (ok) {
      setState(() => _party = const []);
      _say(L.of(context)!.hatarakiBubbleTrip);
      _tama.hop();
    }
  }

  // --- Composición --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final state = ref.watch(hatarakiProvider);
    final tamas = ref.watch(tamasProvider.select((t) => t.tamas));
    Widget body;
    if (!state.loaded) {
      body = const SizedBox.expand();
    } else if (state.game == null) {
      body = Center(child: _Notice(text: l.hatarakiLoadFailed));
    } else {
      body = layout.tall
          ? _tallLayout(context, state.game!, tamas)
          : _wideLayout(context, state.game!, tamas);
    }
    return ChannelScaffold(
      title: l.channelHataraki,
      glyph: Glyph.pick,
      art: ArtIcon.hataraki,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconPill(
            key: const ValueKey<String>('hataraki.music'),
            glyph: Glyph.note,
            semanticLabel: l.hatarakiMusic,
            onPressed: () => unawaited(
              showIbashoModal<void>(context, (_) => const _MusicDialog()),
            ),
          ),
          const SizedBox(width: 8),
          IconPill(
            key: const ValueKey<String>('hataraki.help'),
            glyph: Glyph.info,
            semanticLabel: l.hatarakiHelp,
            onPressed: () => unawaited(_help()),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: body,
      ),
    );
  }

  /// El Tama del escenario: el elegido, o el primero que trabaja, o cualquiera.
  Tama? _stageTama(HState game, List<Tama> tamas) {
    Tama? byId(String? id) => tamas.where((t) => t.id == id).firstOrNull;
    return byId(_tamaId) ??
        byId(game.workers.firstOrNull?.tamaId) ??
        tamas.firstOrNull;
  }

  Widget _stage(Tama? tama, double size, double joy) {
    if (tama == null) return GlossyFace(joy: joy, size: size);
    return KeyedSubtree(
      key: ValueKey<String>('hataraki.tama.${tama.id}'),
      child: TamaOnStand(
        tama: tama,
        size: size,
        joy: joy,
        controller: _tama,
        pettable: true,
        // Un mimo sube el ánimo, y el ánimo es velocidad.
        onPetted: () =>
            unawaited(ref.read(tamasProvider.notifier).pet(tama.id)),
      ),
    );
  }

  /// El té que está haciendo efecto y cuánto le queda; nada si no hay.
  Widget _teaChip(HState game) {
    final l = L.of(context)!;
    final left = game.teaUntil - DateTime.now().millisecondsSinceEpoch;
    if (game.tea == null || left <= 0) return const SizedBox.shrink();
    return Semantics(
      label: hItemName(l, game.tea!),
      child: GlossSurface(
        radius: 14,
        elevation: 1,
        padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HatarakiItemIcon(game.tea!, size: 24),
            const SizedBox(width: 2),
            Text(
              hDuration(Duration(milliseconds: left)),
              style: Ty.micro.copyWith(color: Ty.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs({required double height, required bool labels}) {
    final l = L.of(context)!;
    String label(HTab t) => switch (t) {
      HTab.village => l.hatarakiTabVillage,
      HTab.skills => l.hatarakiTabSkills,
      HTab.bank => l.hatarakiTabBank,
      HTab.expedition => l.hatarakiTabExpedition,
    };
    Glyph glyph(HTab t) => switch (t) {
      HTab.village => Glyph.tama,
      HTab.skills => Glyph.pick,
      HTab.bank => Glyph.gift,
      HTab.expedition => Glyph.flag,
    };
    return SegmentRail(
      height: height,
      children: [
        for (final t in HTab.values)
          SegmentPill(
            key: ValueKey<String>('hataraki.tab.${t.name}'),
            label: labels ? label(t) : '',
            glyph: glyph(t),
            height: height,
            selected: t == _tab,
            onPressed: () => _pickTab(t),
          ),
      ],
    );
  }

  /// En vertical, en vez de las ranuras (que ya se ven en el pueblo), las
  /// monedas del día: allí no hay otro sitio para ellas.
  Widget _readouts(HState game, {required double height, bool coins = false, bool money = false}) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final next = hSlotThresholds.where((t) => t > game.totalLevel).firstOrNull;
    return Row(
      children: [
        Expanded(
          // En vertical, en el almacén, los ginmon en lugar del nivel total.
          child: money
              ? _money(game, height)
              // Tocarlo explica qué es y para qué sirve.
              : Pressable(
            key: const ValueKey<String>('hataraki.totalLevel'),
            semanticLabel: l.hatarakiTotalLevel,
            onPressed: () => unawaited(_help('level')),
            builder: (context, _) => Readout(
              icon: GlyphIcon(
                Glyph.star,
                size: height * .5,
                color: skin.accentDeep,
                strokeWidth: 2.2,
              ),
              value: '${game.totalLevel}',
              label: l.hatarakiTotalLevel,
              height: height,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: coins
              ? DailyCoinsMeter(game: hatarakiGame, height: height)
              : Readout(
                  icon: GlyphIcon(
                    Glyph.tama,
                    size: height * .5,
                    color: skin.accentDeep,
                    strokeWidth: 2.2,
                  ),
                  value: '${game.workers.length}/${game.slots}',
                  label: next == null
                      ? l.hatarakiWorkers
                      : l.hatarakiNextSlot(next),
                  height: height,
                ),
        ),
      ],
    );
  }

  /// Los ginmon que hay: se ganan vendiendo lo del almacén.
  Widget _money(HState game, double height) => Readout(
    key: const ValueKey<String>('hataraki.money'),
    icon: ArtIconView(ArtIcon.ginmon, size: height * .56),
    value: '${game.money}',
    label: L.of(context)!.hatarakiMonLabel,
    height: height,
  );

  Widget _content(HState game, List<Tama> tamas, {required bool tall}) {
    final page = _pages[_tab] ?? 0;
    void onPage(int p) => setState(() => _pages[_tab] = p);
    return switch (_tab) {
      HTab.village => _VillageGrid(
        game: game,
        page: page,
        onPage: onPage,
        tamas: tamas,
        clock: _clock,
        selected: _tamaId,
        tall: tall,
        onPick: (id) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _tamaId = id);
          _tama.hop();
        },
        onFree: () => _pickTab(HTab.skills),
      ),
      HTab.skills => _SkillsGrid(
        game: game,
        skill: _skill,
        action: _action,
        tall: tall,
        page: page,
        onPage: onPage,
        onSkill: (s) {
          if (s == HSkill.expedition) return _pickTab(HTab.expedition);
          AudioService.instance.play(Sfx.tick);
          setState(() {
            _skill = s;
            _action = null;
            _pages[HTab.skills] = 0;
          });
        },
        onAction: (a) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _action = a);
        },
        onBack: () {
          AudioService.instance.play(Sfx.back);
          setState(() {
            _skill = null;
            _action = null;
            _pages[HTab.skills] = 0;
          });
        },
      ),
      HTab.bank => _BankGrid(
        game: game,
        selected: _item,
        tall: tall,
        page: page,
        onPage: onPage,
        onPick: (id) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _item = id);
        },
      ),
      HTab.expedition => _ZoneGrid(
        game: game,
        page: page,
        onPage: onPage,
        selected: _zone,
        tall: tall,
        onPick: (id) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _zone = id);
        },
      ),
    };
  }

  /// Escaparate y botón de acento de la pestaña: lo que se ha tocado.
  (Widget, Widget?) _showcase(
    HState game,
    List<Tama> tamas, {
    required bool tall,
  }) {
    final l = L.of(context)!;
    switch (_tab) {
      case HTab.village:
        final tama = _stageTama(game, tamas);
        final worker = game.workers
            .where((w) => w.tamaId == tama?.id)
            .firstOrNull;
        if (tama == null) return (_Notice(text: l.hatarakiNoTamas), null);
        final hTama = ref.read(hatarakiProvider.notifier).tamaNow(tama.id);
        if (worker == null) {
          return (
            _WorkerCard(
              game: game,
              tama: tama,
              worker: null,
              hTama: hTama,
              onChange: () => _pickTab(HTab.skills),
            ),
            IbashoButton(
              key: const ValueKey<String>('hataraki.goJobs'),
              label: l.hatarakiGoJobs,
              glyph: Glyph.pick,
              tone: ButtonTone.accent,
              expand: true,
              onPressed: () => _pickTab(HTab.skills),
            ),
          );
        }
        return (
          _WorkerCard(
            game: game,
            tama: tama,
            worker: worker,
            hTama: hTama,
            onChange: () {
              final action = hAction(worker.actionId);
              AudioService.instance.play(Sfx.tick);
              setState(() {
                _tab = HTab.skills;
                _skill = action?.skill;
                _action = action?.id;
                _pages[HTab.skills] = 0;
              });
            },
          ),
          Row(
            children: [
              Expanded(
                child: IbashoButton(
                  key: const ValueKey<String>('hataraki.feed'),
                  label: l.hatarakiFeed,
                  // En vertical no cabe el texto con el icono.
                  glyph: tall ? null : Glyph.treat,
                  expand: true,
                  cue: null,
                  onPressed: () => _feed(tama.id),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: IbashoButton(
                  key: const ValueKey<String>('hataraki.rest'),
                  label: l.hatarakiStop,
                  glyph: Glyph.pause,
                  expand: true,
                  onPressed: () => _release(tama.id),
                ),
              ),
            ],
          ),
        );
      case HTab.skills:
        final action = _action == null ? null : hAction(_action!);
        if (action == null) {
          return (_SkillCard(game: game, skill: _skill), null);
        }
        final open = game.levelOf(action.skill) >= action.level;
        return (
          _ActionCard(game: game, action: action, tamas: tamas),
          IbashoButton(
            key: const ValueKey<String>('hataraki.assign'),
            label: open ? l.hatarakiAssign : l.hatarakiNeedLevel(action.level),
            glyph: open ? Glyph.tama : Glyph.lock,
            tone: open ? ButtonTone.accent : ButtonTone.plain,
            expand: true,
            onPressed: open ? () => unawaited(_assign(action)) : null,
          ),
        );
      case HTab.bank:
        final item = _item == null || game.count(_item!) == 0
            ? null
            : hItem(_item!);
        if (item == null) {
          return (
            _Notice(
              text: game.bank.isEmpty ? l.hatarakiBankEmpty : l.hatarakiTabBank,
            ),
            null,
          );
        }
        Widget? button;
        if (item.kind == HItemKind.tea) {
          button = IbashoButton(
            key: const ValueKey<String>('hataraki.drink'),
            label: l.hatarakiDrink,
            glyph: Glyph.heart,
            tone: ButtonTone.accent,
            expand: true,
            onPressed: () => _drink(item.id),
          );
        } else if (item.kind == HItemKind.gear) {
          final worn = game.kit[item.slot] == item.id;
          button = IbashoButton(
            key: const ValueKey<String>('hataraki.equip'),
            label: worn ? l.hatarakiUnequip : l.hatarakiEquip,
            glyph: worn ? Glyph.cross : Glyph.check,
            tone: worn ? ButtonTone.plain : ButtonTone.accent,
            expand: true,
            onPressed: () => worn ? _unequip(item.slot!) : _equip(item.id),
          );
        }
        // Beber o ponerse (si hay) y vender, en una fila; con otro botón al
        // lado, los de vender van sin dibujo para que quepan.
        final count = game.count(item.id);
        final plain = button != null;
        return (
          _ItemCard(game: game, item: item),
          Row(
            children: [
              if (button != null) ...[
                Expanded(child: button),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: IbashoButton(
                  key: const ValueKey<String>('hataraki.sell.one'),
                  label: l.hatarakiSellOne(hSellValue(item.id)),
                  icon: plain ? null : ArtIconView(ArtIcon.ginmon, size: IbashoButton.iconSize(48)),
                  expand: true,
                  onPressed: () => unawaited(_sell(item.id, 1)),
                ),
              ),
              if (count > 1) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: IbashoButton(
                    key: const ValueKey<String>('hataraki.sell.all'),
                    label: l.hatarakiSellMany(count, count * hSellValue(item.id)),
                    icon: plain ? null : ArtIconView(ArtIcon.ginmon, size: IbashoButton.iconSize(48)),
                    expand: true,
                    onPressed: () => unawaited(_sell(item.id, count)),
                  ),
                ),
              ],
            ],
          ),
        );
      case HTab.expedition:
        final exp = game.expedition;
        if (exp != null) {
          return (
            _TripCard(game: game, expedition: exp, tamas: tamas),
            IbashoButton(
              key: const ValueKey<String>('hataraki.tripCancel'),
              label: l.hatarakiTripCancel,
              glyph: Glyph.undo,
              expand: true,
              onPressed: () => unawaited(_cancelTrip()),
            ),
          );
        }
        final zone = hZoneById[_zone]!;
        final foods =
            game.bank.keys
                .where((id) => hItem(id)?.kind == HItemKind.food)
                .toList()
              ..sort((a, b) => hItem(a)!.food.compareTo(hItem(b)!.food));
        final food = foods.contains(_food) ? _food : foods.lastOrNull;
        final party = [
          for (final id in _party)
            if (tamas.any((t) => t.id == id) && !game.isBusy(id)) id,
        ];
        final hParty = [
          for (final t in tamas)
            if (party.contains(t.id)) HTama(t.id, t.personality, .5),
        ];
        final units = food == null || party.isEmpty
            ? 0
            : (HState.foodNeeded(zone, party.length) / hItem(food)!.food)
                  .ceil();
        final open = game.levelOf(HSkill.expedition) >= zone.level;
        final fed = food != null && game.count(food) >= units;
        final ready = party.isNotEmpty && fed && open;
        // El botón dice qué falta, en vez de apagarse sin más.
        final goLabel = !open
            ? l.hatarakiNeedLevel(zone.level)
            : party.isEmpty
            ? l.hatarakiPickParty
            : !fed
            ? l.hatarakiNeedFood
            : l.hatarakiGo;
        return (
          _ZoneCard(
            game: game,
            zone: zone,
            party: party,
            tamas: tamas,
            power: game.partyPower(hParty),
            food: food,
            units: units,
            onAdd: party.length < hMaxParty
                ? () => unawaited(_addToParty())
                : null,
            onRemove: (id) => setState(() => _party = [..._party]..remove(id)),
            onFood: foods.length < 2
                ? null
                : () {
                    AudioService.instance.play(Sfx.tick);
                    final i = food == null
                        ? 0
                        : (foods.indexOf(food) + 1) % foods.length;
                    setState(() => _food = foods[i]);
                  },
          ),
          IbashoButton(
            key: const ValueKey<String>('hataraki.go'),
            label: goLabel,
            glyph: open ? Glyph.flag : Glyph.lock,
            tone: ready ? ButtonTone.accent : ButtonTone.plain,
            expand: true,
            onPressed: ready
                ? () => _go(zone, food)
                : (open && party.isEmpty
                      ? () => unawaited(_addToParty())
                      : null),
          ),
        );
    }
  }

  Widget _wideLayout(BuildContext context, HState game, List<Tama> tamas) {
    final tama = _stageTama(game, tamas);
    final joy = tama == null
        ? .4
        : TamaMoodReading.of(tama, ref.watch(moodClockProvider)).joy;
    final (card, button) = _showcase(game, tamas, tall: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 352,
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: StageLight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: SpeechBubble(
                                  text: _bubble,
                                  maxWidth: 260,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _stage(tama, 104, joy),
                            ],
                          ),
                        ),
                      ),
                      Positioned(left: 0, top: 0, child: _teaChip(game)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(child: card),
                const SizedBox(height: 10),
                _readouts(game, height: 50),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: DailyCoinsMeter(game: hatarakiGame, height: 40),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _money(game, 40)),
                  ],
                ),
                if (button != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: button),
                ],
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              children: [
                _tabs(height: 46, labels: true),
                const SizedBox(height: 14),
                Expanded(child: _content(game, tamas, tall: false)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tallLayout(BuildContext context, HState game, List<Tama> tamas) {
    final layout = Layout.of(context);
    final small = layout.height < 700;
    final tama = _stageTama(game, tamas);
    final joy = tama == null
        ? .4
        : TamaMoodReading.of(tama, ref.watch(moodClockProvider)).joy;
    final (card, button) = _showcase(game, tamas, tall: true);
    final stageSize = small ? 64.0 : 84.0;
    return Column(
      children: [
        SizedBox(height: small ? 6 : 10),
        SizedBox(
          height: small ? 92 : 124,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: stageSize + 30,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: StageLight(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _stage(tama, stageSize, joy),
                        ),
                      ),
                    ),
                    Positioned(left: 0, top: 0, child: _teaChip(game)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: SpeechBubble(text: _bubble, maxWidth: 200),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _readouts(
                      game,
                      height: small ? 44 : 48,
                      coins: true,
                      money: _tab == HTab.bank,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: small ? 8 : 12),
        _tabs(height: 48, labels: false),
        SizedBox(height: small ? 8 : 12),
        Expanded(child: _content(game, tamas, tall: true)),
        SizedBox(height: small ? 6 : 10),
        SizedBox(
          // Preparar una expedición pide más sitio que el resto.
          height: _tab == HTab.expedition
              ? (small ? 206 : (layout.height > 840 ? 300 : 244))
              : (small ? 104 : (layout.height > 840 ? 210 : 150)),
          child: card,
        ),
        if (button != null) ...[
          SizedBox(height: small ? 6 : 10),
          SizedBox(width: double.infinity, child: button),
        ],
        SizedBox(height: small ? 10 : 16),
      ],
    );
  }
}

// --- Paginador ----------------------------------------------------------------

/// Una rejilla de ranuras por páginas, con flechas y puntos debajo y deslizar
/// con el dedo. Las ranuras que sobran en la última página van hundidas.
/// Si no caben [rows] filas de al menos [minTile] de alto, pone menos.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.count,
    required this.columns,
    required this.rows,
    required this.page,
    required this.onPage,
    required this.builder,
    this.gap = 14,
    this.minTile = 84,
  });

  final int count;
  final int columns;
  final int rows;
  final int page;
  final ValueChanged<int> onPage;
  final Widget Function(int index, double width, double height) builder;
  final double gap;
  final double minTile;

  /// Lo que ocupan las flechas y los puntos.
  static const double _nav = 58;

  int _rowsFor(double height) =>
      math.max(1, math.min(rows, ((height + gap) / (minTile + gap)).floor()));

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        // Primero sin flechas; si no cabe todo en una página, con ellas.
        var rows = _rowsFor(box.maxHeight);
        final paged = count > columns * rows;
        if (paged) rows = _rowsFor(box.maxHeight - _nav);
        final perPage = columns * rows;
        final pages = math.max(1, (count / perPage).ceil());
        final current = page.clamp(0, pages - 1);
        void go(int p) {
          if (p < 0 || p >= pages || p == current) return;
          AudioService.instance.play(Sfx.tick);
          onPage(p);
        }

        final gridH = box.maxHeight - (pages > 1 ? _nav : 0);
        final w = (box.maxWidth - gap * (columns - 1)) / columns;
        final h = (gridH - gap * (rows - 1)) / rows;
        return Column(
          children: [
            SizedBox(
              height: gridH,
              child: PageSwipe(
                onPrevious: () => go(current - 1),
                onNext: () => go(current + 1),
                child: AnimatedSwitcher(
                  duration: skin.motion(const Duration(milliseconds: 260)),
                  switchInCurve: skin.curve(Curves.easeOutCubic),
                  child: Column(
                    key: ValueKey<int>(current),
                    children: [
                      for (var r = 0; r < rows; r++) ...[
                        if (r > 0) SizedBox(height: gap),
                        Row(
                          children: [
                            for (var c = 0; c < columns; c++) ...[
                              if (c > 0) SizedBox(width: gap),
                              () {
                                final i = current * perPage + r * columns + c;
                                return i < count
                                    ? builder(i, w, h)
                                    : EmptySlot(width: w, height: h);
                              }(),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (pages > 1)
              SizedBox(
                height: _nav,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconPill(
                      glyph: Glyph.arrowLeft,
                      diameter: 36,
                      semanticLabel: '←',
                      onPressed: current > 0 ? () => go(current - 1) : null,
                    ),
                    const SizedBox(width: 14),
                    for (var p = 0; p < pages; p++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: AnimatedContainer(
                          duration: skin.motion(
                            const Duration(milliseconds: 200),
                          ),
                          width: p == current ? 18 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: p == current ? skin.accent : skin.hairline,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    const SizedBox(width: 14),
                    IconPill(
                      key: const ValueKey<String>('hataraki.page.next'),
                      glyph: Glyph.arrowRight,
                      diameter: 36,
                      semanticLabel: '→',
                      onPressed: current < pages - 1
                          ? () => go(current + 1)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// --- Piezas comunes -----------------------------------------------------------

/// Un aviso suelto sobre plástico.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: GlossSurface(
      radius: 22,
      elevation: 1.2,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Ty.body.copyWith(color: Ty.inkSoft),
      ),
    ),
  );
}

/// Barra de progreso de cristal con el acento.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, this.height = 8, this.color});

  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: skin.hairline),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Art.light(color ?? skin.accent, .35),
                      color ?? skin.accent,
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
}

/// Progreso hacia el siguiente nivel de un oficio.
double _levelProgress(int xp) {
  final level = hLevelForXp(xp);
  if (level >= hMaxLevel) return 1;
  final from = hXpForLevel(level), to = hXpForLevel(level + 1);
  return (xp - from) / (to - from);
}

/// Un Tama pintado con la postura de su oficio, que se mueve con [clock].
class _WorkingTama extends StatelessWidget {
  const _WorkingTama({
    required this.tama,
    required this.skill,
    required this.clock,
    this.stalled = false,
  });

  final Tama tama;
  final HSkill? skill;
  final ValueListenable<double> clock;
  final bool stalled;

  @override
  Widget build(BuildContext context) {
    final joy = TamaMoodReading.of(tama, DateTime.now()).joy;
    return SizedBox.expand(
      child: ValueListenableBuilder<double>(
        valueListenable: clock,
        builder: (context, t, _) => CustomPaint(
          painter: TamaPainter(
            look: tama.look,
            pose: skill == null
                ? TamaPose(joy: joy, breathe: math.sin(t * 1.6), doze: .2)
                : hWorkPose(
                    skill!,
                    t + tama.id.hashCode % 7,
                    stalled: stalled,
                    joy: joy,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Una fila «icono + ×n» de objetos, para entradas, salidas y botín.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.items,
    this.have,
    this.size = 30,
    this.counts = false,
  });

  final Map<String, int> items;

  /// Si está, pinta en rojo lo que falta.
  final HState? have;
  final double size;

  /// Con [have]: «tienes/pide» en vez de «×pide».
  final bool counts;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final e in items.entries)
          _Labelled(
            label: hItemName(l, e.key),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HatarakiItemIcon(e.key, size: size),
                const SizedBox(width: 2),
                Text(
                  counts && have != null
                      ? '${_compact(have!.count(e.key))}/${e.value}'
                      : '×${e.value}',
                  style: Ty.numeral(
                    size * .42,
                    weight: FontWeight.w700,
                    color: have != null && have!.count(e.key) < e.value
                        ? T.warn
                        : Ty.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Solo pone la etiqueta para lectores de pantalla.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(label: label, child: child);
}

/// El escaparate: una tarjeta de plástico con la cabecera y lo de dentro.
class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlossSurface(
      radius: 24,
      elevation: 1.2,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: box.maxHeight.isFinite ? box.maxHeight - 24 : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.lead,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ty.caption,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Text(text, style: Ty.label),
  );
}

/// Una ranura con un globito de «n Tamas aquí» en la esquina.
class _Badged extends StatelessWidget {
  const _Badged({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return child;
    final skin = IbashoSkin.of(context);
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          right: 6,
          top: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: skin.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlyphIcon(
                    Glyph.tama,
                    size: 12,
                    color: T.shellTop,
                    strokeWidth: 2.2,
                  ),
                  if (count > 1) ...[
                    const SizedBox(width: 2),
                    Text(
                      '$count',
                      style: Ty.micro.copyWith(
                        color: T.shellTop,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Pueblo -------------------------------------------------------------------

class _VillageGrid extends StatelessWidget {
  const _VillageGrid({
    required this.game,
    required this.page,
    required this.onPage,
    required this.tamas,
    required this.clock,
    required this.selected,
    required this.tall,
    required this.onPick,
    required this.onFree,
  });

  final HState game;
  final int page;
  final ValueChanged<int> onPage;
  final List<Tama> tamas;
  final ValueListenable<double> clock;
  final String? selected;
  final bool tall;
  final ValueChanged<String> onPick;
  final VoidCallback onFree;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return _Pager(
      count: hSlotThresholds.length,
      columns: tall ? 2 : 3,
      rows: tall ? 3 : 2,
      minTile: 120,
      page: page,
      onPage: onPage,
      builder: (i, w, h) {
        if (i >= game.slots) {
          return SizedBox(
            key: ValueKey<String>('hataraki.slot.$i'),
            width: w,
            height: h,
            child: GlossSurface(
              radius: T.tileRadius,
              recessed: true,
              elevation: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlyphIcon(Glyph.lock, size: 22, color: Ty.inkSoft),
                    const SizedBox(height: 4),
                    Text(
                      l.hatarakiSlotLocked(hSlotThresholds[i]),
                      style: Ty.caption,
                    ),
                    Text(l.hatarakiSlotHave(game.totalLevel), style: Ty.micro),
                  ],
                ),
              ),
            ),
          );
        }
        final worker = i < game.workers.length ? game.workers[i] : null;
        final tama = worker == null
            ? null
            : tamas.where((t) => t.id == worker.tamaId).firstOrNull;
        if (worker == null || tama == null) {
          return SlotTile(
            key: ValueKey<String>('hataraki.slot.$i'),
            width: w,
            height: h,
            semanticLabel: l.hatarakiSlotFree,
            onPressed: onFree,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlyphIcon(
                  Glyph.plus,
                  size: 26,
                  color: skin.accentDeep,
                  strokeWidth: 2.4,
                ),
                const SizedBox(height: 6),
                Text(
                  l.hatarakiSlotFree,
                  style: Ty.caption.copyWith(color: Ty.ink),
                ),
                Text(
                  l.hatarakiSlotFreeHint,
                  textAlign: TextAlign.center,
                  style: Ty.micro,
                ),
              ],
            ),
          );
        }
        final action = hAction(worker.actionId)!;
        return SlotTile(
          key: ValueKey<String>('hataraki.slot.$i'),
          width: w,
          height: h,
          selected: tama.id == selected,
          semanticLabel: tama.name,
          onPressed: () => onPick(tama.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _WorkingTama(
                            tama: tama,
                            skill: action.skill,
                            clock: clock,
                            stalled: worker.stalled,
                          ),
                        ),
                      ),
                      HatarakiItemIcon(
                        action.outputs.keys.firstOrNull ?? 'gear_scarf',
                        size: math.min(34, h * .22),
                      ),
                    ],
                  ),
                ),
                Text(
                  tama.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  worker.stalled ? l.hatarakiStalled : hActionName(l, action),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.micro.copyWith(
                    color: worker.stalled ? T.warn : Ty.inkSoft,
                  ),
                ),
                const SizedBox(height: 4),
                _Bar(value: worker.progress, height: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.game,
    required this.tama,
    required this.worker,
    required this.hTama,
    required this.onChange,
  });

  final HState game;
  final Tama tama;
  final HWorker? worker;

  /// Personalidad y ánimo de ahora, para el ritmo.
  final HTama? hTama;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final action = worker == null ? null : hAction(worker!.actionId);
    final likes = hAffinities[tama.personality] ?? const <HSkill>{};
    final missing = action == null
        ? const <String, int>{}
        : {
            for (final e in action.inputs.entries)
              if (game.count(e.key) < e.value) e.key: e.value,
          };
    final mood = hTama == null ? null : 0.8 + 0.4 * hTama!.mood.clamp(0, 1);
    return _Card(
      icon: action == null
          ? HatarakiSkillIcon(likes.first, size: 40)
          : HatarakiSkillIcon(action.skill, size: 40),
      title: tama.name,
      subtitle: action == null ? l.hatarakiBubbleIdle : hActionName(l, action),
      children: [
        if (action != null) ...[
          Text(
            '${hSkillName(l, action.skill)} · ${l.hatarakiLevel(game.levelOf(action.skill))} · ${l.hatarakiMastery(game.masteryOf(action.id))}',
            style: Ty.caption,
          ),
          const SizedBox(height: 6),
          _Bar(value: _levelProgress(game.xp[action.skill] ?? 0)),
          if (hTama != null && missing.isEmpty) ...[
            const SizedBox(height: 6),
            Text(_pace(l, game, action, hTama!), style: Ty.caption),
          ],
          if (missing.isNotEmpty) ...[
            _Label(l.hatarakiMissing),
            _ItemRow(items: missing, have: game, counts: true),
            _Sources(items: missing.keys),
          ],
          const SizedBox(height: 8),
          _LinkChip(
            key: const ValueKey<String>('hataraki.change'),
            glyph: Glyph.refresh,
            text: l.hatarakiChange,
            onPressed: onChange,
          ),
        ],
        _Label(
          l.hatarakiPersonalityLikes(personalityLabel(l, tama.personality)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in likes)
              ResultChip(
                text: hSkillName(l, s),
                icon: HatarakiSkillIcon(s, size: 16),
              ),
          ],
        ),
        if (mood != null) ...[
          _Label(l.hatarakiMood(mood.toStringAsFixed(2))),
          Text(l.hatarakiMoodHint, style: Ty.micro),
        ],
      ],
    );
  }
}

/// «4,2 s cada vez · ≈ 850 por hora» para una tarea hecha por [tama].
String _pace(L l, HState game, HAction action, HTama tama) {
  final secs = game.secondsFor(
    action,
    tama,
    DateTime.now().millisecondsSinceEpoch,
  );
  final perHour = 3600 / secs;
  final amount = action.outputs.isEmpty
      ? '${(perHour * action.xp).round()} xp'
      : _compact((perHour * action.outputs.values.first).round());
  return '${l.hatarakiEach(_seconds(secs))} · ${l.hatarakiPerHour(amount)}';
}

/// Oficios y sitios de donde salen [items]: para saber qué hacer cuando
/// falta algo.
class _Sources extends StatelessWidget {
  const _Sources({required this.items, this.label});

  final Iterable<String> items;

  /// Lo que va delante; por defecto, «se consigue con».
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skills = <HSkill>{};
    final zones = <String>{};
    for (final id in items) {
      for (final a in hActions) {
        if (a.outputs.containsKey(id) || a.drops.any((d) => d.item == id)) {
          skills.add(a.skill);
        }
      }
      for (final z in hZones) {
        if (z.loot.any((x) => x.item == id)) zones.add(z.id);
      }
    }
    if (skills.isEmpty && zones.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label ?? l.hatarakiGetWith, style: Ty.micro),
          for (final s in skills)
            ResultChip(
              text: hSkillName(l, s),
              icon: HatarakiSkillIcon(s, size: 16),
            ),
          for (final z in zones)
            ResultChip(
              text: hZoneName(l, z),
              icon: HatarakiZoneIcon(z, size: 16),
            ),
        ],
      ),
    );
  }
}

/// Un enlace pequeño en forma de píldora: para acciones secundarias dentro
/// del escaparate, sin quitarle el sitio al botón de acento.
class _LinkChip extends StatelessWidget {
  const _LinkChip({
    super.key,
    required this.glyph,
    required this.text,
    required this.onPressed,
  });

  final Glyph glyph;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: text,
      builder: (context, state) => GlossSurface(
        radius: 16,
        sink: state.press,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(
              glyph,
              size: 14,
              color: skin.accentDeep,
              strokeWidth: 2.2,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: Ty.caption.copyWith(
                color: skin.accentDeep,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Oficios ------------------------------------------------------------------

class _SkillsGrid extends StatelessWidget {
  const _SkillsGrid({
    required this.game,
    required this.skill,
    required this.action,
    required this.tall,
    required this.page,
    required this.onPage,
    required this.onSkill,
    required this.onAction,
    required this.onBack,
  });

  final HState game;
  final HSkill? skill;
  final String? action;
  final bool tall;
  final int page;
  final ValueChanged<int> onPage;
  final ValueChanged<HSkill> onSkill;
  final ValueChanged<String> onAction;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final s = skill;
    if (s == null) {
      const skills = HSkill.values;
      return _Pager(
        count: skills.length,
        columns: tall ? 3 : 5,
        rows: 3,
        page: page,
        onPage: onPage,
        builder: (i, w, h) {
          final sk = skills[i];
          final xp = game.xp[sk] ?? 0;
          final busy = sk == HSkill.expedition
              ? (game.expedition?.tamaIds.length ?? 0)
              : game.workers
                    .where((wk) => hAction(wk.actionId)?.skill == sk)
                    .length;
          return SlotTile(
            key: ValueKey<String>('hataraki.skill.${sk.name}'),
            width: w,
            height: h,
            semanticLabel: hSkillName(l, sk),
            onPressed: () => onSkill(sk),
            child: _Badged(
              count: busy,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  children: [
                    Expanded(
                      child: FittedBox(child: HatarakiSkillIcon(sk, size: 48)),
                    ),
                    // Nombre y nivel en una sola línea: en vertical no
                    // hay alto para dos.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hSkillName(l, sk),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.caption.copyWith(color: Ty.ink),
                          ),
                        ),
                        Text(
                          '${hLevelForXp(xp)}',
                          style: Ty.numeral(
                            16,
                            color: skin.accentDeep,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    _Bar(value: _levelProgress(xp), height: 5),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    final actions = hActionsOf(s);
    final level = game.levelOf(s);
    return Column(
      children: [
        Row(
          children: [
            IconPill(
              key: const ValueKey<String>('hataraki.skills.back'),
              glyph: Glyph.arrowLeft,
              diameter: 36,
              semanticLabel: l.hatarakiTabSkills,
              cue: null,
              onPressed: onBack,
            ),
            const SizedBox(width: 10),
            HatarakiSkillIcon(s, size: 30),
            const SizedBox(width: 6),
            Expanded(child: Text(hSkillName(l, s), style: Ty.lead)),
            Text(
              l.hatarakiLevel(level),
              style: Ty.numeral(
                18,
                color: skin.accentDeep,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _Pager(
            count: actions.length,
            columns: tall ? 2 : 4,
            rows: tall ? 3 : 2,
            page: page,
            onPage: onPage,
            builder: (i, w, h) {
              final a = actions[i];
              final open = level >= a.level;
              final short = a.inputs.entries.any(
                (e) => game.count(e.key) < e.value,
              );
              final busy = game.workers.where((wk) => wk.actionId == a.id);
              return SlotTile(
                key: ValueKey<String>('hataraki.action.${a.id}'),
                width: w,
                height: h,
                selected: a.id == action,
                semanticLabel: hActionName(l, a),
                onPressed: () => onAction(a.id),
                child: _Badged(
                  count: busy.length,
                  child: Opacity(
                    opacity: open ? 1 : .55,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Column(
                        children: [
                          Expanded(
                            child: FittedBox(
                              child: a.outputs.isEmpty
                                  ? HatarakiSkillIcon(s, size: 48)
                                  : HatarakiItemIcon(
                                      a.outputs.keys.first,
                                      size: 48,
                                    ),
                            ),
                          ),
                          Text(
                            hActionName(l, a),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.caption.copyWith(color: Ty.ink),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!open) ...[
                                GlyphIcon(
                                  Glyph.lock,
                                  size: 12,
                                  color: Ty.inkSoft,
                                ),
                                const SizedBox(width: 3),
                              ],
                              Flexible(
                                child: Text(
                                  !open
                                      ? l.hatarakiLevel(a.level)
                                      : short
                                      ? l.hatarakiMissing
                                      : l.hatarakiMastery(game.masteryOf(a.id)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Ty.micro.copyWith(
                                    color: open && short ? T.warn : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({required this.game, required this.skill});

  final HState game;
  final HSkill? skill;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final s = skill;
    if (s == null) {
      return _Card(
        icon: const ArtIconView(ArtIcon.hataraki, size: 40),
        title: l.hatarakiTabSkills,
        subtitle: '${l.hatarakiTotalLevel} ${game.totalLevel}',
        children: [Text(l.hatarakiSkillsIntro, style: Ty.caption)],
      );
    }
    final xp = game.xp[s] ?? 0;
    final level = hLevelForXp(xp);
    return _Card(
      icon: HatarakiSkillIcon(s, size: 40),
      title: hSkillName(l, s),
      subtitle: l.hatarakiLevel(level),
      children: [
        _Bar(value: _levelProgress(xp)),
        const SizedBox(height: 6),
        Text(
          level >= hMaxLevel
              ? l.hatarakiMaxed
              : l.hatarakiXpToNext('${hXpForLevel(level + 1) - xp}'),
          style: Ty.caption,
        ),
        const SizedBox(height: 6),
        Text(l.hatarakiSkillAbout(s.name), style: Ty.caption),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.game, required this.action, this.tamas});

  final HState game;
  final HAction action;
  final List<Tama>? tamas;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final a = action;
    final level = game.levelOf(a.skill);
    final missing = [
      for (final e in a.inputs.entries)
        if (game.count(e.key) < e.value) e.key,
    ];
    final doing = [
      for (final w in game.workers)
        if (w.actionId == a.id)
          tamas?.where((t) => t.id == w.tamaId).firstOrNull?.name,
    ].whereType<String>().toList();
    return _Card(
      icon: a.outputs.isEmpty
          ? HatarakiSkillIcon(a.skill, size: 40)
          : HatarakiItemIcon(a.outputs.keys.first, size: 40),
      title: hActionName(l, a),
      subtitle:
          '${l.hatarakiSeconds(_seconds(a.seconds))} · ${l.hatarakiXp(a.xp)} · ${l.hatarakiMastery(game.masteryOf(a.id))}',
      children: [
        if (level < a.level)
          Text(
            l.hatarakiNeedSkillLevel(hSkillName(l, a.skill), a.level, level),
            style: Ty.caption.copyWith(color: T.warn),
          ),
        if (doing.isNotEmpty)
          Text('${l.hatarakiDoing}: ${doing.join(', ')}', style: Ty.caption),
        if (a.inputs.isNotEmpty) ...[
          _Label(l.hatarakiUses),
          _ItemRow(items: a.inputs, have: game, counts: true),
          if (missing.isNotEmpty) _Sources(items: missing),
        ],
        if (a.outputs.isNotEmpty) ...[
          _Label(l.hatarakiMakes),
          _ItemRow(items: a.outputs),
        ],
        if (a.drops.isNotEmpty) ...[
          _Label(l.hatarakiSometimes),
          _ItemRow(items: {for (final d in a.drops) d.item: 1}, size: 24),
        ],
        const SizedBox(height: 8),
        Text(l.hatarakiMasteryHint, style: Ty.micro),
      ],
    );
  }
}

// --- Almacén ------------------------------------------------------------------

class _BankGrid extends StatelessWidget {
  const _BankGrid({
    required this.game,
    required this.selected,
    required this.tall,
    required this.page,
    required this.onPage,
    required this.onPick,
  });

  final HState game;
  final String? selected;
  final bool tall;
  final int page;
  final ValueChanged<int> onPage;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    // En el orden del catálogo: madera, pescado, minerales… y el equipo al final.
    final items = [
      for (final i in hItems)
        if (game.count(i.id) > 0) i.id,
    ];
    if (items.isEmpty) return _Notice(text: l.hatarakiBankEmpty);
    return _Pager(
      count: items.length,
      columns: tall ? 4 : 6,
      rows: tall ? 3 : 3,
      page: page,
      onPage: onPage,
      gap: 12,
      builder: (i, w, h) {
        final id = items[i];
        final equipped = game.kit.values.contains(id);
        return SlotTile(
          key: ValueKey<String>('hataraki.item.$id'),
          width: w,
          height: h,
          selected: id == selected,
          semanticLabel: hItemName(l, id),
          onPressed: () => onPick(id),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: Column(
                  children: [
                    Expanded(
                      child: FittedBox(child: HatarakiItemIcon(id, size: 48)),
                    ),
                    Text(
                      hItemName(l, id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.micro.copyWith(color: Ty.ink),
                    ),
                    Text(
                      _compact(game.count(id)),
                      style: Ty.numeral(
                        15,
                        color: skin.accentDeep,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (equipped)
                Positioned(
                  right: 6,
                  top: 6,
                  child: GlyphIcon(
                    Glyph.check,
                    size: 16,
                    color: skin.accentDeep,
                    strokeWidth: 2.6,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 12 345 → «12,3k».
String _compact(int n) {
  if (n < 10000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 100000 ? 1 : 0)}k';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.game, required this.item});

  final HState game;
  final HItem item;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final lines = <Widget>[];
    switch (item.kind) {
      case HItemKind.food:
        lines.add(
          Text(
            '${l.hatarakiFoodValue(item.food)} · ${l.hatarakiFoodHint}',
            style: Ty.caption,
          ),
        );
      case HItemKind.seed:
        lines.add(Text(l.hatarakiSeedHint, style: Ty.caption));
      case HItemKind.tea:
        final pct = (item.teaBoost * 100).round();
        lines.add(
          Text(
            item.teaSkill == null
                ? l.hatarakiTeaAll(pct)
                : l.hatarakiTeaFor(pct, hSkillName(l, item.teaSkill!)),
            style: Ty.caption,
          ),
        );
      case HItemKind.gear:
        lines
          ..add(
            Text(
              '${l.hatarakiGearSlot(item.slot!.name)} · ${l.hatarakiPower(item.power)}',
              style: Ty.caption,
            ),
          )
          ..add(Text(l.hatarakiGearHint, style: Ty.micro));
        if (game.kit[item.slot] == item.id) {
          lines
            ..add(const SizedBox(height: 6))
            ..add(ResultChip(text: l.hatarakiEquipped, accent: true));
        }
      default:
        break;
    }
    // Dónde se usa: las tareas que lo gastan.
    final uses = [
      for (final a in hActions)
        if (a.inputs.containsKey(item.id)) a,
    ];
    return _Card(
      icon: HatarakiItemIcon(item.id, size: 44),
      title: hItemName(l, item.id),
      subtitle: '×${game.count(item.id)} · ${l.hatarakiPrice(hSellValue(item.id))}',
      children: [
        ...lines,
        _Sources(items: [item.id], label: l.hatarakiComesFrom),
        if (uses.isNotEmpty) ...[
          _Label(l.hatarakiUsedIn),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final a in uses.take(8))
                ResultChip(
                  text: hActionName(l, a),
                  icon: HatarakiSkillIcon(a.skill, size: 16),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// --- Expediciones -------------------------------------------------------------

class _ZoneGrid extends StatelessWidget {
  const _ZoneGrid({
    required this.game,
    required this.page,
    required this.onPage,
    required this.selected,
    required this.tall,
    required this.onPick,
  });

  final HState game;
  final int page;
  final ValueChanged<int> onPage;
  final String selected;
  final bool tall;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final level = game.levelOf(HSkill.expedition);
    return _Pager(
      count: hZones.length,
      columns: tall ? 2 : 4,
      rows: tall ? 4 : 2,
      page: page,
      onPage: onPage,
      builder: (i, w, h) {
        final z = hZones[i];
        final open = level >= z.level;
        final away = game.expedition?.zone == z.id;
        return SlotTile(
          key: ValueKey<String>('hataraki.zone.${z.id}'),
          width: w,
          height: h,
          selected: z.id == selected,
          semanticLabel: hZoneName(l, z.id),
          onPressed: () => onPick(z.id),
          child: _Badged(
            count: away ? game.expedition!.tamaIds.length : 0,
            child: Opacity(
              opacity: open ? 1 : .55,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  children: [
                    Expanded(
                      child: FittedBox(child: HatarakiZoneIcon(z.id, size: 48)),
                    ),
                    Text(
                      hZoneName(l, z.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.caption.copyWith(color: Ty.ink),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GlyphIcon(
                          open ? Glyph.clock : Glyph.lock,
                          size: 12,
                          color: Ty.inkSoft,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          open
                              ? l.hatarakiTripTime(z.minutes)
                              : l.hatarakiLevel(z.level),
                          style: Ty.micro,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.game,
    required this.zone,
    required this.party,
    required this.tamas,
    required this.power,
    required this.food,
    required this.units,
    required this.onAdd,
    required this.onRemove,
    required this.onFood,
  });

  final HState game;
  final HZone zone;
  final List<String> party;
  final List<Tama> tamas;
  final int power;
  final String? food;
  final int units;
  final VoidCallback? onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback? onFood;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final open = game.levelOf(HSkill.expedition) >= zone.level;
    final success = (HState.successFor(zone, power) * 100).round();
    final kitPower = game.kit.values
        .where((item) => game.count(item) > 0)
        .fold(0, (sum, item) => sum + (hItem(item)?.power ?? 0));
    return _Card(
      icon: HatarakiZoneIcon(zone.id, size: 40),
      title: hZoneName(l, zone.id),
      subtitle: open
          ? '${l.hatarakiTripTime(zone.minutes)} · ${party.isEmpty ? l.hatarakiStrength(power, zone.difficulty) : l.hatarakiSuccess(success)}'
          : l.hatarakiNeedSkillLevel(
              hSkillName(l, HSkill.expedition),
              zone.level,
              game.levelOf(HSkill.expedition),
            ),
      children: [
        _Bar(
          value: power / zone.difficulty,
          color: power >= zone.difficulty ? T.correct : null,
        ),
        const SizedBox(height: 4),
        Text(l.hatarakiStrength(power, zone.difficulty), style: Ty.micro),
        _Label(l.hatarakiParty),
        Row(
          children: [
            for (var i = 0; i < hMaxParty; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              if (i < party.length)
                Pressable(
                  onPressed: () => onRemove(party[i]),
                  semanticLabel: tamas
                      .where((t) => t.id == party[i])
                      .firstOrNull
                      ?.name,
                  builder: (context, state) => SizedBox.square(
                    dimension: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: GlossSurface(
                            radius: 14,
                            sink: state.press,
                            child: CustomPaint(
                              painter: TamaPainter(
                                look: tamas
                                    .firstWhere((t) => t.id == party[i])
                                    .look,
                              ),
                            ),
                          ),
                        ),
                        // Se saca del grupo tocándolo: la cruz lo dice.
                        Positioned(
                          right: -4,
                          top: -4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: T.shellTop,
                              shape: BoxShape.circle,
                              border: Border.all(color: skin.hairline),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: GlyphIcon(
                                Glyph.cross,
                                size: 10,
                                color: Ty.inkSoft,
                                strokeWidth: 2.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Pressable(
                  key: ValueKey<String>('hataraki.party.add.$i'),
                  onPressed: i == party.length ? onAdd : null,
                  semanticLabel: l.hatarakiAddTama,
                  builder: (context, state) => SizedBox.square(
                    dimension: 48,
                    child: GlossSurface(
                      radius: 14,
                      recessed: true,
                      child: i == party.length
                          ? Center(
                              child: GlyphIcon(
                                Glyph.plus,
                                size: 20,
                                color: skin.accentDeep,
                                strokeWidth: 2.4,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ],
        ),
        _Label(l.hatarakiFood),
        if (food == null)
          Text(l.hatarakiNoFood, style: Ty.caption.copyWith(color: T.warn))
        else
          Pressable(
            key: const ValueKey<String>('hataraki.food'),
            onPressed: onFood,
            semanticLabel: hItemName(l, food!),
            builder: (context, state) => GlossSurface(
              radius: 16,
              sink: state.press,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HatarakiItemIcon(food!, size: 30),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l.hatarakiFoodUnits(units, hItemName(l, food!)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.caption.copyWith(
                        color: game.count(food!) < units ? T.warn : Ty.ink,
                      ),
                    ),
                  ),
                  if (onFood != null) ...[
                    const SizedBox(width: 6),
                    GlyphIcon(Glyph.refresh, size: 14, color: Ty.inkSoft),
                  ],
                ],
              ),
            ),
          ),
        // El equipo, en una línea: lo que suma y desde dónde se cambia.
        _Label(l.hatarakiKit),
        Row(
          children: [
            for (final item in game.kit.values)
              if (game.count(item) > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _Labelled(
                    label: hItemName(l, item),
                    child: HatarakiItemIcon(item, size: 26),
                  ),
                ),
            Flexible(
              child: Text(
                kitPower > 0 ? l.hatarakiPower(kitPower) : l.hatarakiKitNone,
                maxLines: 2,
                style: Ty.micro,
              ),
            ),
          ],
        ),
        _Label(l.hatarakiLoot),
        _ItemRow(
          items: {for (final loot in zone.loot) loot.item: loot.max},
          size: 26,
        ),
        // Sin grupo aún, la probabilidad del sitio con éxito completo.
        _TreasureLine(
          chance: zone.prizeChance * (party.isEmpty ? 1 : HState.successFor(zone, power)),
        ),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.game,
    required this.expedition,
    required this.tamas,
  });

  final HState game;
  final HExpedition expedition;
  final List<Tama> tamas;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final total = expedition.endsAt - expedition.startedAt;
    final left = Duration(milliseconds: math.max(0, expedition.endsAt - now));
    final zone = hZoneById[expedition.zone]!;
    return _Card(
      icon: HatarakiZoneIcon(zone.id, size: 40),
      title: hZoneName(l, zone.id),
      subtitle: l.hatarakiBackIn(hDuration(left)),
      children: [
        _Bar(value: total <= 0 ? 1 : 1 - left.inMilliseconds / total),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final id in expedition.tamaIds)
              if (tamas.where((t) => t.id == id).firstOrNull case final tama?)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox.square(
                    dimension: 48,
                    child: CustomPaint(
                      painter: TamaPainter(
                        look: tama.look,
                        pose: const TamaPose(hop: 4, joy: .8),
                      ),
                    ),
                  ),
                ),
          ],
        ),
        _Label(l.hatarakiLoot),
        _ItemRow(
          items: {for (final loot in zone.loot) loot.item: loot.max},
          size: 26,
        ),
        _TreasureLine(
          chance: zone.prizeChance * HState.successFor(zone, expedition.power),
        ),
      ],
    );
  }
}

/// El tesoro que puede traer una expedición (un ticket gachaken) y con qué
/// probabilidad; se canjea solo, como mucho uno por hora.
class _TreasureLine extends StatelessWidget {
  const _TreasureLine({required this.chance});

  final double chance;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          ArtIconView(ArtIcon.ticketGachaken, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.hatarakiTreasureChance(chance * 100),
              maxLines: 2,
              style: Ty.micro,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Diálogos -----------------------------------------------------------------

/// Elegir quién trabaja: los Tamas de la cuenta, con los ocupados apagados y
/// una estrella en los que tienen maña para este oficio.
class _TamaPicker extends ConsumerStatefulWidget {
  const _TamaPicker({
    required this.skill,
    required this.game,
    this.exclude = const {},
  });

  final HSkill skill;
  final HState game;
  final Set<String> exclude;

  @override
  ConsumerState<_TamaPicker> createState() => _TamaPickerState();
}

class _TamaPickerState extends ConsumerState<_TamaPicker> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tamas = ref.watch(tamasProvider.select((t) => t.tamas));
    final tall = Layout.of(context).tall;
    final affinity = [
      for (final t in tamas)
        if (hAffinities[t.personality]?.contains(widget.skill) ?? false) t,
    ];
    // Primero los que tienen maña; después, el resto.
    final sorted = [...affinity, ...tamas.where((t) => !affinity.contains(t))];
    final job = widget.skill != HSkill.expedition;
    final full = job && widget.game.workers.length >= widget.game.slots;
    return IbashoDialog(
      title: l.hatarakiPickTama,
      width: tall ? 340 : 560,
      body: SizedBox(
        height: tall ? 360 : 300,
        child: Column(
          children: [
            if (full)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  l.hatarakiSlotsFull,
                  textAlign: TextAlign.center,
                  style: Ty.caption.copyWith(color: T.warn),
                ),
              ),
            Expanded(child: _pickerGrid(l, skin, tall, sorted, affinity, full)),
          ],
        ),
      ),
      actions: [
        IbashoButton(
          label: l.actionCancel,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _pickerGrid(
    L l,
    IbashoSkin skin,
    bool tall,
    List<Tama> sorted,
    List<Tama> affinity,
    bool full,
  ) {
    return sorted.isEmpty
        ? _Notice(text: l.hatarakiNoTamas)
        : _Pager(
            count: sorted.length,
            columns: tall ? 2 : 4,
            rows: 2,
            page: _page,
            onPage: (p) => setState(() => _page = p),
            builder: (i, w, h) {
              final t = sorted[i];
              final job = widget.game.workers
                  .where((x) => x.tamaId == t.id)
                  .firstOrNull;
              final working = job != null;
              final away =
                  widget.game.expedition?.tamaIds.contains(t.id) ?? false;
              final blocked =
                  away ||
                  widget.exclude.contains(t.id) ||
                  (widget.skill == HSkill.expedition && working) ||
                  (full && !working);
              final likes = affinity.contains(t);
              return SlotTile(
                key: ValueKey<String>('hataraki.pick.${t.id}'),
                width: w,
                height: h,
                semanticLabel: t.name,
                onPressed: blocked
                    ? null
                    : () => Navigator.of(context).pop(t.id),
                child: Opacity(
                  opacity: blocked ? .5 : 1,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: CustomPaint(
                              painter: TamaPainter(look: t.look),
                            ),
                          ),
                        ),
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.caption.copyWith(color: Ty.ink),
                        ),
                        if (working && widget.skill != HSkill.expedition)
                          Text(
                            l.hatarakiDoingNow(
                              hActionName(l, hAction(job.actionId)!),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.micro,
                          )
                        else if (full && !working && !away)
                          Text(
                            l.hatarakiNoSlot,
                            style: Ty.micro.copyWith(color: T.warn),
                          )
                        else if (likes)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GlyphIcon(
                                Glyph.star,
                                size: 12,
                                color: skin.accentDeep,
                                strokeWidth: 2.4,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  l.hatarakiLikes,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Ty.micro,
                                ),
                              ),
                            ],
                          )
                        else if (working || away)
                          Text(l.hatarakiBusy, style: Ty.micro),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
  }
}

/// Lo que ha pasado mientras no había nadie: tiempo, lo ganado, los niveles
/// y la expedición que ha vuelto.
class _AwayDialog extends StatelessWidget {
  const _AwayDialog({required this.report});

  final HReport report;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final gained = report.gained.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return IbashoDialog(
      title: l.hatarakiAwayTitle,
      width: 440,
      body: PopIn(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.hatarakiAwayTime(
                hDuration(Duration(seconds: report.seconds.round())),
              ),
              textAlign: TextAlign.center,
              style: Ty.caption,
            ),
            const SizedBox(height: 10),
            if (gained.isNotEmpty)
              _ItemRow(
                items: {for (final e in gained.take(10)) e.key: e.value},
                size: 34,
              ),
            if (report.levelUps.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final e in report.levelUps.entries)
                    ResultChip(
                      text: '${hSkillName(l, e.key)} ${e.value}',
                      accent: true,
                      icon: HatarakiSkillIcon(e.key, size: 16),
                    ),
                ],
              ),
            ],
            if (report.expeditionZone != null) ...[
              const SizedBox(height: 10),
              Text(
                l.hatarakiAwayTrip(hZoneName(l, report.expeditionZone!)),
                textAlign: TextAlign.center,
                style: Ty.body.copyWith(color: skin.accentDeep),
              ),
            ],
            if (report.prizes > 0) ...[
              const SizedBox(height: 6),
              Text(
                l.hatarakiTreasure,
                textAlign: TextAlign.center,
                style: Ty.body.copyWith(color: Art.goldDark),
              ),
            ],
            if (report.stalledTamas.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l.hatarakiBubbleStalled,
                textAlign: TextAlign.center,
                style: Ty.caption.copyWith(color: T.warn),
              ),
            ],
          ],
        ),
      ),
      actions: [
        IbashoButton(
          key: const ValueKey<String>('hataraki.away.ok'),
          label: l.hatarakiAwayOk,
          tone: ButtonTone.accent,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Qué suena en el pueblo: las tres por turnos o una fija. Las que aún no
/// han sonado nunca salen con candado (se descubren por turnos).
class _MusicDialog extends ConsumerWidget {
  const _MusicDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final chosen = ref.watch(preferencesProvider.select((p) => p.hatarakiTrack));
    final library = ref.watch(musicLibraryProvider);
    final prefs = ref.read(preferencesProvider.notifier);
    Widget option(String id, String label, {bool locked = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IbashoButton(
        key: ValueKey<String>('hataraki.music.${id.isEmpty ? 'cycle' : id}'),
        label: locked ? l.hatarakiMusicLocked : label,
        glyph: locked ? Glyph.lock : (chosen == id ? Glyph.check : Glyph.note),
        tone: chosen == id ? ButtonTone.accent : ButtonTone.plain,
        expand: true,
        onPressed: locked
            ? null
            : () {
                AudioService.instance.play(Sfx.tick);
                unawaited(prefs.setHatarakiTrack(id));
              },
      ),
    );
    return IbashoDialog(
      title: l.hatarakiMusic,
      width: 400,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          option('', l.hatarakiMusicCycle),
          for (final t in hatarakiTracks)
            option(t.id, describeTrack(l, t), locked: !library.isUnlocked(t)),
        ],
      ),
      actions: [
        IbashoButton(
          key: const ValueKey<String>('hataraki.music.ok'),
          label: l.hatarakiAwayOk,
          tone: ButtonTone.accent,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// «Cómo se juega»: seis páginas cortas, con flechas, que se abren solas la
/// primera vez y desde el botón de información (o tocando el nivel total).
class _HelpDialog extends StatefulWidget {
  const _HelpDialog({required this.start});

  final String start;

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog> {
  static const List<(String, HSkill)> _pages = [
    ('work', HSkill.woodcutting),
    ('level', HSkill.agility),
    ('likes', HSkill.farming),
    ('stuff', HSkill.smithing),
    ('trip', HSkill.expedition),
    ('coins', HSkill.jewelry),
  ];

  late int _page = math.max(0, _pages.indexWhere((p) => p.$1 == widget.start));

  void _go(int p) {
    if (p < 0 || p >= _pages.length) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _page = p);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    final (id, skill) = _pages[_page];
    final last = _page == _pages.length - 1;
    return IbashoDialog(
      title: l.hatarakiHelp,
      width: tall ? 340 : 520,
      body: SizedBox(
        height: tall ? 380 : 300,
        child: PageSwipe(
          onPrevious: () => _go(_page - 1),
          onNext: () => _go(_page + 1),
          child: Column(
            children: [
              HatarakiSkillIcon(skill, size: tall ? 64 : 72),
              const SizedBox(height: 8),
              Text(
                l.hatarakiHelpTitle(id),
                textAlign: TextAlign.center,
                style: Ty.lead,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    l.hatarakiHelpBody(id),
                    textAlign: TextAlign.center,
                    style: Ty.body.copyWith(color: Ty.inkSoft),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconPill(
                    glyph: Glyph.arrowLeft,
                    diameter: 36,
                    semanticLabel: '←',
                    onPressed: _page > 0 ? () => _go(_page - 1) : null,
                  ),
                  const SizedBox(width: 14),
                  for (var p = 0; p < _pages.length; p++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AnimatedContainer(
                        duration: skin.motion(
                          const Duration(milliseconds: 200),
                        ),
                        width: p == _page ? 18 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: p == _page ? skin.accent : skin.hairline,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  const SizedBox(width: 14),
                  IconPill(
                    key: const ValueKey<String>('hataraki.help.next'),
                    glyph: Glyph.arrowRight,
                    diameter: 36,
                    semanticLabel: '→',
                    onPressed: last ? null : () => _go(_page + 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        IbashoButton(
          key: const ValueKey<String>('hataraki.help.ok'),
          label: last ? l.hatarakiAwayOk : l.actionClose,
          tone: last ? ButtonTone.accent : ButtonTone.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
