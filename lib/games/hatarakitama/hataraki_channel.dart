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
import '../../state/people.dart' show cardOfProvider;
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/social/social_widgets.dart' show CardTama;
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
import 'hataraki_home.dart';
import 'hataraki_map.dart';
import 'hataraki_orders.dart';
import 'hataraki_town.dart';

part 'hataraki_channel_home.dart';
part 'hataraki_channel_orders.dart';
part 'hataraki_channel_town.dart';
part 'hataraki_channel_trip.dart';
part 'hataraki_channel_visit.dart';

/// Las cinco partes del canal: los Tamas trabajando, los edificios, los
/// oficios, el almacén y las expediciones.
enum HTab { village, town, skills, bank, expedition }

/// Las canciones del pueblo: la mañana, el agua y el mercado al atardecer.
const List<MusicTrack> hatarakiTracks = [
  MusicTrack.asa,
  MusicTrack.mizuba,
  MusicTrack.yuyake,
];

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

/// El primer material que le falta a [action] en el almacén, si falta alguno.
String? _firstMissing(HState game, HAction action) => action.inputs.entries
    .where((e) => game.count(e.key) < e.value)
    .firstOrNull
    ?.key;

/// Nombre de una tarea: lo que da (el recorrido, en agilidad; el libro, en
/// estudio).
String hActionName(L l, HAction a) => switch (a.skill) {
  HSkill.agility => l.hatarakiCourseName(a.id),
  HSkill.study => l.hatarakiRead(hItemName(l, a.inputs.keys.first)),
  _ => hItemName(l, a.outputs.keys.first),
};

/// El objeto con el que se dibuja una tarea: lo que da, o el libro que se
/// lee. Null en agilidad, que va con el icono del oficio.
String? hActionItem(HAction a) =>
    a.outputs.keys.firstOrNull ??
    (a.skill == HSkill.study ? a.inputs.keys.firstOrNull : null);

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

  /// Sitio cuyo mapa se ve (en lugar de la rejilla de sitios).
  String? _mapZone;

  /// La ruta elegida en cada sitio (para el mapa de hoy).
  final Map<String, List<int>> _routes = {};
  String? _supply;
  String? _rune;
  bool _porter = false;
  bool _cart = false;
  HBuilding _building = HBuilding.workshop;

  /// Dentro de la tienda o la lonja (en lugar de ver los edificios).
  HBuilding? _inside;
  String? _offer;
  int _order = 0;
  bool _tomorrow = false;

  /// Las habitaciones de la posada: dentro de la lista, el Tama elegido y,
  /// dentro de su habitación, el mueble por poner o el puesto elegido.
  bool _inHomes = false;
  String? _homeTamaId;
  bool _inRoom = false;
  String? _piece;
  int? _placed;
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
    final audible =
        _foreground &&
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
    } else if (report.nodes.isNotEmpty) {
      if (audible) AudioService.instance.play(Sfx.tick);
      _say(l.hatarakiNodeDone(_nodeWhat(report.nodes.last)));
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

  /// Lo que se paga hoy por [item], con la lonja.
  int _price(String item) =>
      ref.read(hatarakiProvider).game?.priceOf(item, _controller.today) ??
      hSellValue(item);

  /// Vende [n] de [item]; con más de uno, pregunta antes.
  Future<void> _sell(String item, int n) async {
    final l = L.of(context)!;
    if (n > 1) {
      final ok = await askConfirmation(
        context,
        title: l.hatarakiSellTitle,
        body: l.hatarakiSellBody(n, hItemName(l, item), n * _price(item)),
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

  void _build(HBuilding b) {
    final l = L.of(context)!;
    final ok = ref.read(hatarakiProvider.notifier).build(b);
    AudioService.instance.play(ok ? Sfx.chime : Sfx.error);
    if (!ok) return;
    final level = ref.read(hatarakiProvider).game?.townLevel(b) ?? 1;
    _say(l.hatarakiBuilt(l.hatarakiBuildingName(b.name), level));
    _tama.hop();
  }

  void _buy(String item, int n) {
    final l = L.of(context)!;
    final plan =
        ref.read(hatarakiProvider).game?.plans.contains(item) == false &&
        hFurniture[item]?.plan == true;
    final got = ref.read(hatarakiProvider.notifier).buy(item, n);
    AudioService.instance.play(got > 0 ? Sfx.pop : Sfx.error);
    if (got > 0) {
      _say(
        l.hatarakiBought(
          got,
          plan ? l.hatarakiPlanOf(hItemName(l, item)) : hItemName(l, item),
        ),
      );
    }
  }

  void _deliver(int i) {
    final l = L.of(context)!;
    final game = ref.read(hatarakiProvider).game;
    final big = game != null && i < game.orders.length && game.orders[i].big;
    if (!ref.read(hatarakiProvider.notifier).deliver(i)) {
      AudioService.instance.play(Sfx.error);
      return;
    }
    AudioService.instance.play(Sfx.pop);
    _say(big ? l.hatarakiOrderThanksBig : l.hatarakiOrderThanks);
  }

  void _swapOrder(int i) {
    final l = L.of(context)!;
    if (ref.read(hatarakiProvider.notifier).swapOrder(i)) {
      AudioService.instance.play(Sfx.tick);
      _say(l.hatarakiOrderSwapped);
    } else {
      AudioService.instance.play(Sfx.error);
    }
  }

  // --- Casas ------------------------------------------------------------------

  void _buildHouse(Tama tama) {
    final ok = ref.read(hatarakiProvider.notifier).buildHouse(tama.id);
    AudioService.instance.play(ok ? Sfx.chime : Sfx.error);
    if (!ok) return;
    _say(L.of(context)!.hatarakiBuiltHouse(tama.name));
    _tama.hop();
    setState(() {
      _tamaId = tama.id;
      _enterRoom();
    });
  }

  void _enterRoom() {
    _inRoom = true;
    _piece = null;
    _placed = null;
  }

  /// Tocar una casilla de la habitación: poner lo elegido, mover lo puesto
  /// o elegir lo que hay.
  void _roomCell(int x, int y) {
    final id = _homeTamaId;
    final game = ref.read(hatarakiProvider).game;
    final house = id == null ? null : game?.houses[id];
    if (house == null) return;
    final hit = house.at(x, y);
    final notifier = ref.read(hatarakiProvider.notifier);
    // La esquina que deja [item] (con giro [r]) tocando la casilla, si cabe
    // de alguna forma.
    (int, int)? corner(String item, int r, {int? skip}) {
      final (w, h) = hFurniture[item]!.size(r);
      for (final (cx, cy) in [
        (x, y),
        (x - w + 1, y),
        (x, y - h + 1),
        (x - w + 1, y - h + 1),
      ]) {
        if (house.fits(item, cx, cy, r, skip: skip)) return (cx, cy);
      }
      return null;
    }

    if (_piece != null) {
      final at = hit == null ? corner(_piece!, 0) : null;
      if (at != null && notifier.placeFurniture(id!, _piece!, at.$1, at.$2)) {
        AudioService.instance.play(Sfx.pop);
        setState(() {
          if (game!.count(_piece!) == 0) _piece = null;
        });
      } else if (hit != null) {
        AudioService.instance.play(Sfx.tick);
        setState(() {
          _piece = null;
          _placed = hit;
        });
      } else {
        AudioService.instance.play(Sfx.error);
      }
      return;
    }
    if (_placed != null && hit != _placed) {
      if (hit != null) {
        AudioService.instance.play(Sfx.tick);
        setState(() => _placed = hit);
        return;
      }
      final p = house.items[_placed!];
      final at = corner(p.id, p.r, skip: _placed);
      final ok =
          at != null && notifier.moveFurniture(id!, _placed!, at.$1, at.$2);
      AudioService.instance.play(ok ? Sfx.pop : Sfx.error);
      return;
    }
    AudioService.instance.play(Sfx.tick);
    setState(() => _placed = hit == _placed ? null : hit);
  }

  void _pickPiece(String item) {
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _piece = _piece == item ? null : item;
      _placed = null;
    });
  }

  void _rotatePiece() {
    final ok = ref
        .read(hatarakiProvider.notifier)
        .rotateFurniture(_homeTamaId!, _placed!);
    AudioService.instance.play(ok ? Sfx.tick : Sfx.error);
  }

  void _storePiece() {
    if (ref
        .read(hatarakiProvider.notifier)
        .storeFurniture(_homeTamaId!, _placed!)) {
      AudioService.instance.play(Sfx.back);
      setState(() => _placed = null);
    }
  }

  /// El siguiente suelo o la siguiente pared.
  void _decorate({bool floor = false}) {
    final house = ref.read(hatarakiProvider).game?.houses[_homeTamaId];
    if (house == null) return;
    HStyle next(HStyle s) =>
        HStyle.values[(s.index + 1) % HStyle.values.length];
    ref
        .read(hatarakiProvider.notifier)
        .decorate(
          _homeTamaId!,
          floor: floor ? next(house.floor) : null,
          wall: floor ? null : next(house.wall),
        );
    AudioService.instance.play(Sfx.tick);
  }

  void _unequip(HGearSlot slot) {
    if (ref.read(hatarakiProvider.notifier).unequip(slot)) {
      AudioService.instance.play(Sfx.back);
    }
  }

  Future<void> _cancelTrip(String zone) async {
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
    if (ref.read(hatarakiProvider.notifier).cancelExpedition(zone)) {
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

  void _go(HTripPlan plan) {
    final ok = ref
        .read(hatarakiProvider.notifier)
        .startExpedition(plan, _party);
    AudioService.instance.play(ok ? Sfx.chime : Sfx.error);
    if (ok) {
      setState(() {
        _party = const [];
        _supply = null;
        _rune = null;
        _porter = false;
        _cart = false;
        _mapZone = plan.zone;
      });
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
      HTab.town => l.hatarakiTabTown,
      HTab.skills => l.hatarakiTabSkills,
      HTab.bank => l.hatarakiTabBank,
      HTab.expedition => l.hatarakiTabExpedition,
    };
    Glyph glyph(HTab t) => switch (t) {
      HTab.village => Glyph.tama,
      HTab.town => Glyph.house,
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
  Widget _readouts(
    HState game, {
    required double height,
    bool coins = false,
    bool money = false,
  }) {
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
      HTab.town when _inRoom && _roomTama(game, tamas) != null => _RoomView(
        game: game,
        tama: _roomTama(game, tamas)!,
        clock: _clock,
        piece: _piece,
        placed: _placed,
        onCell: _roomCell,
        onPiece: _pickPiece,
        onBack: () {
          AudioService.instance.play(Sfx.back);
          setState(() => _inRoom = false);
        },
      ),
      HTab.town when _inHomes => _HomesGrid(
        game: game,
        tamas: tamas,
        selected: _homeTamaId,
        tall: tall,
        page: page,
        onPage: onPage,
        onPick: (id) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _homeTamaId = id);
        },
        onBack: () {
          AudioService.instance.play(Sfx.back);
          setState(() {
            _inHomes = false;
            _pages[HTab.town] = 0;
          });
        },
      ),
      HTab.town => _TownGrid(
        game: game,
        today: _controller.today,
        selected: _building,
        rooms: tamas.where((t) => game.houses.containsKey(t.id)).length,
        inside: _inside,
        offer: _offer,
        order: _order,
        tomorrow: _tomorrow,
        tall: tall,
        page: page,
        onPage: onPage,
        onPick: (b) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _building = b);
        },
        onOffer: (item) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _offer = item);
        },
        onOrder: (i) {
          AudioService.instance.play(Sfx.tick);
          setState(() => _order = i);
        },
        onBack: () {
          AudioService.instance.play(Sfx.back);
          setState(() {
            _inside = null;
            _pages[HTab.town] = 0;
          });
        },
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
      HTab.expedition when _mapZone != null => _zoneMap(game, tamas),
      HTab.expedition => _ZoneGrid(
        game: game,
        page: page,
        onPage: onPage,
        selected: _zone,
        tall: tall,
        onPick: (id) {
          AudioService.instance.play(Sfx.tick);
          setState(() {
            _zone = id;
            _mapZone = id;
          });
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
            onBoost: (item) {
              AudioService.instance.play(Sfx.tick);
              ref.read(hatarakiProvider.notifier).setBoost(tama.id, item);
            },
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
      case HTab.town:
        return _townShowcase(game, tamas);
      case HTab.skills:
        final action = _action == null ? null : hAction(_action!);
        if (action == null) {
          return (_SkillCard(game: game, skill: _skill), null);
        }
        final open = game.canDo(action);
        final gate = game.missingGate(action);
        return (
          _ActionCard(game: game, action: action, tamas: tamas),
          IbashoButton(
            key: const ValueKey<String>('hataraki.assign'),
            label: open
                ? l.hatarakiAssign
                : game.levelOf(action.skill) < action.level
                ? l.hatarakiNeedLevel(action.level)
                : gate == null
                ? l.hatarakiNeedPlan
                : l.hatarakiNeedBuilding(
                    l.hatarakiBuildingName(gate.$1.name),
                    gate.$2,
                  ),
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
          _ItemCard(game: game, item: item, today: _controller.today),
          Row(
            children: [
              if (button != null) ...[
                Expanded(child: button),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: IbashoButton(
                  key: const ValueKey<String>('hataraki.sell.one'),
                  label: l.hatarakiSellOne(_price(item.id)),
                  icon: plain
                      ? null
                      : ArtIconView(
                          ArtIcon.ginmon,
                          size: IbashoButton.iconSize(48),
                        ),
                  expand: true,
                  onPressed: () => unawaited(_sell(item.id, 1)),
                ),
              ),
              if (count > 1) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: IbashoButton(
                    key: const ValueKey<String>('hataraki.sell.all'),
                    label: l.hatarakiSellMany(count, count * _price(item.id)),
                    icon: plain
                        ? null
                        : ArtIconView(
                            ArtIcon.ginmon,
                            size: IbashoButton.iconSize(48),
                          ),
                    expand: true,
                    onPressed: () => unawaited(_sell(item.id, count)),
                  ),
                ),
              ],
            ],
          ),
        );
      case HTab.expedition:
        return _tripShowcase(game, tamas);
    }
  }

  /// La ruta elegida en [zone] para el mapa de hoy.
  List<int> _routeFor(String zone) {
    final map = hZoneMap(zone, _controller.today);
    final route = _routes[zone];
    return route != null && map.isValid(route) ? route : map.defaultRoute;
  }

  /// Lo elegido para salir a [zone] y lo que falta.
  _TripDraft _draft(HState game, List<Tama> tamas, String zone) {
    final today = _controller.today;
    List<String> owned(bool Function(HItem i) test) =>
        game.bank.keys.where((id) => test(hItem(id)!)).toList()
          ..sort((a, b) => hSellValue(a).compareTo(hSellValue(b)));
    final foods = owned((i) => i.kind == HItemKind.food)
      ..sort((a, b) => hItem(a)!.food.compareTo(hItem(b)!.food));
    final supplies = owned(
      (i) => i.kind == HItemKind.potion || i.kind == HItemKind.map,
    );
    final runes = owned((i) => i.kind == HItemKind.rune);
    final food = foods.contains(_food) ? _food : foods.lastOrNull;
    final party = [
      for (final id in _party)
        if (tamas.any((t) => t.id == id) && !game.isBusy(id)) id,
    ];
    final hParty = _controller.partyOf(party);
    final plan = food == null
        ? null
        : HTripPlan(
            zone: zone,
            route: _routeFor(zone),
            food: food,
            supply: supplies.contains(_supply) ? _supply : null,
            rune: runes.contains(_rune) ? _rune : null,
            porter: _porter,
            cart: _cart,
          );
    return _TripDraft(
      plan: plan,
      party: party,
      hParty: hParty,
      foods: foods,
      supplies: supplies,
      runes: runes,
      revealed: game.guided(zone, today) || (plan?.reveals ?? false),
      problem: plan == null ? 'food' : game.tripProblem(plan, hParty, today),
    );
  }

  /// El siguiente de [options] tras [current], pasando por «nada».
  String? _cycle(List<String> options, String? current) {
    if (current == null) return options.firstOrNull;
    final i = options.indexOf(current);
    return i < 0 || i + 1 >= options.length ? null : options[i + 1];
  }

  Widget _zoneMap(HState game, List<Tama> tamas) {
    final zone = _mapZone!;
    final trip = game.tripTo(zone);
    final map = trip?.map ?? hZoneMap(zone, _controller.today);
    final draft = trip == null ? _draft(game, tamas, zone) : null;
    final l = L.of(context)!;
    return _ZoneMap(
      game: game,
      map: map,
      route: trip?.route ?? _routeFor(zone),
      revealed: trip != null || draft!.revealed,
      trip: trip,
      tamas: tamas,
      clock: _clock,
      onNode: trip != null
          ? null
          : (n) {
              AudioService.instance.play(Sfx.tick);
              final shown = _nodeKindName(n, revealed: draft!.revealed);
              _say(l.hatarakiNodeAbout(shown, n.threat));
              setState(
                () => _routes[zone] = map.routeThrough(
                  _routeFor(zone),
                  n.col,
                  n.row,
                ),
              );
            },
      onBack: () {
        AudioService.instance.play(Sfx.back);
        setState(() => _mapZone = null);
      },
    );
  }

  (Widget, Widget?) _tripShowcase(HState game, List<Tama> tamas) {
    final l = L.of(context)!;
    final zone = hZoneById[_zone]!;
    final trip = game.tripTo(zone.id);
    if (trip != null) {
      return (
        _TripCard(expedition: trip, tamas: tamas),
        IbashoButton(
          key: const ValueKey<String>('hataraki.tripCancel'),
          label: l.hatarakiTripCancel,
          glyph: Glyph.undo,
          expand: true,
          onPressed: () => unawaited(_cancelTrip(zone.id)),
        ),
      );
    }
    final draft = _draft(game, tamas, zone.id);
    final plan = draft.plan;
    final problem = draft.problem;
    // El botón dice qué falta, en vez de apagarse sin más.
    final goLabel = switch (problem) {
      null => l.hatarakiGo,
      'level' => l.hatarakiNeedLevel(zone.level),
      'trips' => l.hatarakiTripsFull,
      'party' || 'busy' => l.hatarakiPickParty,
      'money' => l.hatarakiNeedMoney(plan!.price - game.money),
      _ => l.hatarakiNeedFood,
    };
    final open = problem != 'level';
    return (
      _ZoneCard(
        game: game,
        zone: zone,
        draft: draft,
        today: _controller.today,
        tamas: tamas,
        porter: _porter,
        cart: _cart,
        onAdd: draft.party.length < game.maxParty
            ? () => unawaited(_addToParty())
            : null,
        onRemove: (id) => setState(() => _party = [..._party]..remove(id)),
        onFood: draft.foods.length < 2
            ? null
            : () {
                AudioService.instance.play(Sfx.tick);
                final foods = draft.foods;
                final i = plan == null
                    ? 0
                    : (foods.indexOf(plan.food) + 1) % foods.length;
                setState(() => _food = foods[i]);
              },
        onSupply: () {
          AudioService.instance.play(Sfx.tick);
          setState(() => _supply = _cycle(draft.supplies, plan?.supply));
        },
        onRune: () {
          AudioService.instance.play(Sfx.tick);
          setState(() => _rune = _cycle(draft.runes, plan?.rune));
        },
        onService: (what) {
          _say(l.hatarakiServiceAbout(what));
          if (what == 'guide') {
            if (game.guided(zone.id, _controller.today)) return;
            final ok = _controller.hireGuide(zone.id);
            AudioService.instance.play(ok ? Sfx.chime : Sfx.error);
            if (ok) setState(() => _mapZone = zone.id);
            return;
          }
          AudioService.instance.play(Sfx.tick);
          setState(() {
            if (what == 'porter') _porter = !_porter;
            if (what == 'cart') _cart = !_cart;
          });
        },
      ),
      IbashoButton(
        key: const ValueKey<String>('hataraki.go'),
        label: goLabel,
        glyph: open ? Glyph.flag : Glyph.lock,
        tone: problem == null ? ButtonTone.accent : ButtonTone.plain,
        expand: true,
        onPressed: problem == null
            ? () => _go(plan!)
            : (problem == 'party' && draft.party.isEmpty
                  ? () => unawaited(_addToParty())
                  : null),
      ),
    );
  }

  /// Escaparate del pueblo: el edificio elegido o, dentro, lo de la tienda
  /// o la lonja.
  /// El Tama de la habitación abierta, si sigue teniendo casa.
  Tama? _roomTama(HState game, List<Tama> tamas) => tamas
      .where((t) => t.id == _homeTamaId && game.houses.containsKey(t.id))
      .firstOrNull;

  (Widget, Widget?) _townShowcase(HState game, List<Tama> tamas) {
    final l = L.of(context)!;
    final today = _controller.today;
    final tama = _inRoom ? _roomTama(game, tamas) : null;
    if (tama != null) {
      final house = game.houses[tama.id]!;
      final placed = _placed != null && _placed! < house.items.length
          ? _placed
          : null;
      final style = l.hatarakiStyleName;
      return (
        _RoomCard(game: game, tama: tama, piece: _piece, placed: placed),
        placed != null
            ? Row(
                children: [
                  Expanded(
                    child: IbashoButton(
                      key: const ValueKey<String>('hataraki.room.rotate'),
                      label: l.hatarakiRotate,
                      glyph: Glyph.refresh,
                      tone: ButtonTone.accent,
                      expand: true,
                      cue: null,
                      onPressed: _rotatePiece,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IbashoButton(
                      key: const ValueKey<String>('hataraki.room.store'),
                      label: l.hatarakiStore,
                      glyph: Glyph.arrowLeft,
                      expand: true,
                      cue: null,
                      onPressed: _storePiece,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: IbashoButton(
                      key: const ValueKey<String>('hataraki.room.floor'),
                      label: '${l.hatarakiFloor}: ${style(house.floor.name)}',
                      expand: true,
                      cue: null,
                      onPressed: () => _decorate(floor: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IbashoButton(
                      key: const ValueKey<String>('hataraki.room.wall'),
                      label: '${l.hatarakiWall}: ${style(house.wall.name)}',
                      expand: true,
                      cue: null,
                      onPressed: _decorate,
                    ),
                  ),
                ],
              ),
      );
    }
    if (_inHomes) {
      final tama =
          tamas.where((t) => t.id == _homeTamaId).firstOrNull ??
          tamas.firstOrNull;
      if (tama == null) return (_Notice(text: l.hatarakiNoTamas), null);
      final has = game.houses.containsKey(tama.id);
      final can = game.canBuildHouse(tama.id);
      return (
        _HomeCard(game: game, tama: tama),
        IbashoButton(
          key: const ValueKey<String>('hataraki.home.go'),
          label: has ? l.hatarakiEnter : l.hatarakiBuildHouse,
          glyph: has ? Glyph.arrowRight : (can ? Glyph.house : Glyph.lock),
          tone: has || can ? ButtonTone.accent : ButtonTone.plain,
          expand: true,
          onPressed: has
              ? () => setState(() {
                  _homeTamaId = tama.id;
                  _enterRoom();
                })
              : can
              ? () => _buildHouse(tama)
              : null,
        ),
      );
    }
    if (_inside == HBuilding.shop) {
      final offers = game.shop(today);
      final offer =
          offers.where((o) => o.item == _offer).firstOrNull ??
          offers.firstOrNull;
      if (offer == null) return (_Notice(text: l.hatarakiShopHint), null);
      final left = game.stockLeft(offer, today);
      final most = math.min(left, game.money ~/ offer.price);
      Widget buy(int n, String key) => IbashoButton(
        key: ValueKey<String>(key),
        label: l.hatarakiBuy(n, n * offer.price),
        tone: ButtonTone.accent,
        expand: true,
        onPressed: most >= n ? () => _buy(offer.item, n) : null,
      );
      return (
        _OfferCard(game: game, offer: offer, left: left),
        left <= 0
            ? IbashoButton(
                label: l.hatarakiSoldOut,
                glyph: Glyph.lock,
                expand: true,
              )
            : Row(
                children: [
                  Expanded(child: buy(1, 'hataraki.buy.one')),
                  if (most > 1) ...[
                    const SizedBox(width: 8),
                    Expanded(child: buy(most, 'hataraki.buy.all')),
                  ],
                ],
              ),
      );
    }
    if (_inside == HBuilding.board) {
      final orders = game.orders;
      if (orders.isEmpty) return (_Notice(text: l.hatarakiOrderHint), null);
      final i = _order.clamp(0, orders.length - 1);
      final o = orders[i];
      final swappable = i > 0 && !o.done && game.swapDay != today;
      // Con los dos botones en fila, sin dibujo para que quepan.
      final deliver = IbashoButton(
        key: const ValueKey<String>('hataraki.deliver'),
        label: o.done ? l.hatarakiOrderDone : l.hatarakiDeliver,
        glyph: swappable
            ? null
            : o.done
            ? Glyph.check
            : game.canDeliver(i)
            ? Glyph.gift
            : Glyph.lock,
        tone: game.canDeliver(i) ? ButtonTone.accent : ButtonTone.plain,
        expand: true,
        onPressed: game.canDeliver(i) ? () => _deliver(i) : null,
      );
      return (
        _OrderCard(game: game, order: o, ticketToday: game.orderDay >= today),
        swappable
            ? Row(
                children: [
                  Expanded(child: deliver),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IbashoButton(
                      key: const ValueKey<String>('hataraki.swap'),
                      label: l.hatarakiSwap(o.swapPrice),
                      expand: true,
                      onPressed: game.canSwap(i, today)
                          ? () => _swapOrder(i)
                          : null,
                    ),
                  ),
                ],
              )
            : deliver,
      );
    }
    if (_inside == HBuilding.market) {
      final level = game.townLevel(HBuilding.market);
      return (
        _MarketCard(game: game, today: today, tomorrow: _tomorrow),
        level < hMarketTomorrow
            ? null
            : IbashoButton(
                key: const ValueKey<String>('hataraki.market.when'),
                label: l.hatarakiMarketWhen(_tomorrow ? 'today' : 'tomorrow'),
                glyph: Glyph.clock,
                expand: true,
                onPressed: () => setState(() => _tomorrow = !_tomorrow),
              ),
      );
    }
    final b = _building;
    final level = game.townLevel(b);
    final cost = game.nextBuildCost(b);
    final upgrade = IbashoButton(
      key: const ValueKey<String>('hataraki.build'),
      label: cost == null
          ? l.hatarakiTownMax
          : level == 0
          ? l.hatarakiBuild
          : l.hatarakiUpgrade(level + 1),
      glyph: cost == null
          ? Glyph.star
          : game.canBuild(b)
          ? Glyph.house
          : Glyph.lock,
      tone: game.canBuild(b) ? ButtonTone.accent : ButtonTone.plain,
      expand: true,
      onPressed: game.canBuild(b) ? () => _build(b) : null,
    );
    // A las habitaciones de la posada se entra aunque aún no esté hecha.
    final enter =
        b == HBuilding.inn ||
        (level > 0 &&
            (b == HBuilding.shop ||
                b == HBuilding.market ||
                b == HBuilding.board));
    return (
      _BuildingCard(game: game, building: b, tamas: tamas),
      enter
          ? Row(
              children: [
                Expanded(
                  child: IbashoButton(
                    key: const ValueKey<String>('hataraki.enter'),
                    label: l.hatarakiEnter,
                    glyph: Glyph.arrowRight,
                    tone: ButtonTone.accent,
                    expand: true,
                    onPressed: () => setState(() {
                      if (b == HBuilding.inn) {
                        _inHomes = true;
                        _homeTamaId ??= tamas.firstOrNull?.id;
                      } else {
                        _inside = b;
                        _tomorrow = false;
                      }
                      _pages[HTab.town] = 0;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: upgrade),
              ],
            )
          : upgrade,
    );
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
    // En la habitación, el Tama ya sale dentro: sin escenario, cabe más.
    final room = _tab == HTab.town && _inRoom && _roomTama(game, tamas) != null;
    return Column(
      children: [
        SizedBox(height: small ? 6 : 10),
        if (!room)
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
        if (!room) SizedBox(height: small ? 8 : 12),
        _tabs(height: 48, labels: false),
        SizedBox(height: small ? 8 : 12),
        Expanded(child: _content(game, tamas, tall: true)),
        SizedBox(height: small ? 6 : 10),
        SizedBox(
          // Preparar una expedición pide más sitio que el resto.
          // Con el mapa abierto, el mapa se queda con algo más.
          height: _tab == HTab.expedition
              ? (small
                    ? (_mapZone == null ? 206 : 160)
                    : (layout.height > 840 ? 300 : 244))
              : room
              ? (small ? 96 : 150)
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
                      if (hActionItem(action) case final item?)
                        HatarakiItemIcon(item, size: math.min(34, h * .22))
                      else
                        HatarakiSkillIcon(
                          action.skill,
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
                  worker.stalled
                      ? l.hatarakiStalled(
                          hItemName(l, _firstMissing(game, action) ?? ''),
                        )
                      : hActionName(l, action),
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
    this.onBoost,
  });

  final HState game;
  final Tama tama;
  final HWorker? worker;

  /// Personalidad y ánimo de ahora, para el ritmo.
  final HTama? hTama;
  final VoidCallback onChange;

  /// Le pone (o quita, con null) un cebo, abono o mecha.
  final ValueChanged<String?>? onBoost;

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
    // El ánimo con el que trabaja aquí: el suyo o el descanso de su casa.
    final mood = hTama == null ? null : 0.8 + 0.4 * game.moodFor(hTama!);
    final comfort = hTama == null ? null : game.comfortOf(hTama!);
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
            const SizedBox(height: 4),
            Text(l.hatarakiResumes, style: Ty.caption),
          ],
          if (onBoost != null)
            if (hItems.where((i) => i.boostSkill == action.skill).toList()
                case final boosts when boosts.isNotEmpty) ...[
              _Label(l.hatarakiBoostTitle(action.skill.name)),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _BoostChip(
                    key: const ValueKey<String>('hataraki.boost.none'),
                    text: l.hatarakiBoostNone,
                    on: worker!.boost == null,
                    onPressed: () => onBoost!(null),
                  ),
                  for (final b in boosts)
                    _BoostChip(
                      key: ValueKey<String>('hataraki.boost.${b.id}'),
                      item: b.id,
                      text: '${hItemName(l, b.id)} · ${game.count(b.id)}',
                      on: worker!.boost == b.id,
                      onPressed: game.count(b.id) > 0 || worker!.boost == b.id
                          ? () => onBoost!(b.id)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                worker!.boost != null && game.count(worker!.boost!) == 0
                    ? l.hatarakiBoostOut
                    : l.hatarakiBoostHint,
                style: Ty.micro,
              ),
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
          if (comfort != null)
            Text(
              l.hatarakiRestMood((hRestMood(comfort.value) * 100).round()),
              style: Ty.micro,
            ),
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

/// Un cebo, abono o mecha para elegir: el puesto va con el acento.
class _BoostChip extends StatelessWidget {
  const _BoostChip({
    super.key,
    required this.text,
    required this.on,
    required this.onPressed,
    this.item,
  });

  final String text;
  final bool on;
  final VoidCallback? onPressed;
  final String? item;

  @override
  Widget build(BuildContext context) {
    final icon = item == null ? null : HatarakiItemIcon(item!, size: 16);
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Pressable(
        onPressed: on ? null : onPressed,
        semanticLabel: text,
        builder: (context, state) => Transform.scale(
          scale: 1 - .04 * state.press,
          child: ResultChip(text: text, accent: on, icon: icon),
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
              ? game.expeditions.fold(0, (n, e) => n + e.tamaIds.length)
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
              final open = game.canDo(a);
              final gate = game.missingGate(a);
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
                              child: hActionItem(a) == null
                                  ? HatarakiSkillIcon(s, size: 48)
                                  : HatarakiItemIcon(hActionItem(a)!, size: 48),
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
                                      ? (level < a.level
                                            ? l.hatarakiLevel(a.level)
                                            : gate == null
                                            ? l.hatarakiNeedPlan
                                            : l.hatarakiNeedBuilding(
                                                l.hatarakiBuildingName(
                                                  gate.$1.name,
                                                ),
                                                gate.$2,
                                              ))
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
      icon: hActionItem(a) == null
          ? HatarakiSkillIcon(a.skill, size: 40)
          : HatarakiItemIcon(hActionItem(a)!, size: 40),
      title: hActionName(l, a),
      subtitle:
          '${l.hatarakiSeconds(_seconds(a.seconds))} · ${l.hatarakiXp(a.xp)} · ${l.hatarakiMastery(game.masteryOf(a.id))}',
      children: [
        if (level < a.level)
          Text(
            l.hatarakiNeedSkillLevel(hSkillName(l, a.skill), a.level, level),
            style: Ty.caption.copyWith(color: T.warn),
          ),
        if (game.missingGate(a) case (final b, final n))
          Text(
            l.hatarakiNeedBuilding(l.hatarakiBuildingName(b.name), n),
            style: Ty.caption.copyWith(color: T.warn),
          ),
        if (game.missingPlan(a) != null)
          Text(
            '${l.hatarakiNeedPlan} · ${l.hatarakiPlanHint}',
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
  const _ItemCard({
    required this.game,
    required this.item,
    required this.today,
  });

  final HState game;
  final HItem item;
  final int today;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final base = hSellValue(item.id);
    final price = game.priceOf(item.id, today);
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
                ? l.hatarakiTeaAll(pct, game.teaDuration.inMinutes)
                : l.hatarakiTeaFor(
                    pct,
                    hSkillName(l, item.teaSkill!),
                    game.teaDuration.inMinutes,
                  ),
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
        if (item.zones.isNotEmpty) {
          lines.add(
            Text(
              l.hatarakiZoneBonus(
                item.zonePower,
                item.zones.map((z) => hZoneName(l, z)).join(', '),
              ),
              style: Ty.caption,
            ),
          );
        }
        if (game.kit[item.slot] == item.id) {
          lines
            ..add(const SizedBox(height: 6))
            ..add(ResultChip(text: l.hatarakiEquipped, accent: true));
        }
      case HItemKind.boost:
        lines
          ..add(
            Text(
              l.hatarakiBoostEffect(
                item.boostSkill!.name,
                item.boostSkill == HSkill.fishing
                    ? (item.boost * 100).round()
                    : item.boostSkill == HSkill.mining
                    ? (item.boost + 1).round()
                    : item.boost.round(),
              ),
              style: Ty.caption,
            ),
          )
          ..add(Text(l.hatarakiBoostHint, style: Ty.micro));
      case HItemKind.potion || HItemKind.rune || HItemKind.map:
        lines.add(
          Text(
            [
              if (item.power > 0) l.hatarakiPower(item.power),
              if (item.effect != null) l.hatarakiTripEffect(item.effect!),
            ].join(' · '),
            style: Ty.caption,
          ),
        );
      case HItemKind.furniture:
        lines
          ..add(Text(_furnitureInfo(l, item.id), style: Ty.caption))
          ..add(Text(l.hatarakiFurnitureUse, style: Ty.micro));
      default:
        if (item.id == 'pot_teapot') {
          lines.add(Text(l.hatarakiTeapotHint, style: Ty.caption));
        }
    }
    // Dónde se usa: las tareas que lo gastan.
    final uses = [
      for (final a in hActions)
        if (a.inputs.containsKey(item.id)) a,
    ];
    return _Card(
      icon: HatarakiItemIcon(item.id, size: 44),
      title: hItemName(l, item.id),
      subtitle:
          '×${game.count(item.id)} · ${price == base ? l.hatarakiPrice(base) : '${l.hatarakiPriceToday(price)} ${price > base ? '▲' : '▼'}'}',
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
              final away = widget.game.isTraveling(t.id);
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
    final chosen = ref.watch(
      preferencesProvider.select((p) => p.hatarakiTrack),
    );
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

/// Lo que se le da bien a cada personalidad, con los dibujos de sus oficios:
/// una fila por personalidad.
class HatarakiLikesTable extends StatelessWidget {
  const HatarakiLikesTable({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Column(
      children: [
        for (final p in TamaPersonality.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    personalityLabel(l, p),
                    style: Ty.caption.copyWith(
                      color: Ty.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(child: HatarakiLikes(personality: p)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Los oficios en los que [personality] va más rápido: dibujo y nombre.
class HatarakiLikes extends StatelessWidget {
  const HatarakiLikes({super.key, required this.personality, this.icon = 22});

  final TamaPersonality personality;
  final double icon;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      children: [
        for (final s in hAffinities[personality] ?? const <HSkill>{})
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HatarakiSkillIcon(s, size: icon),
              const SizedBox(width: 2),
              Text(hSkillName(l, s), style: Ty.micro.copyWith(color: Ty.ink)),
            ],
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
    ('map', HSkill.writing),
    ('orders', HSkill.study),
    ('town', HSkill.construction),
    ('market', HSkill.dyeing),
    ('homes', HSkill.carpentry),
    ('visit', HSkill.foraging),
    ('coins', HSkill.jewelry),
  ];

  /// Las páginas que van con un edificio en vez de un oficio.
  static const Map<String, HBuilding> _buildings = {
    'market': HBuilding.market,
    'homes': HBuilding.inn,
    'visit': HBuilding.board,
  };

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
              // En la de la maña manda la tabla: sin dibujo grande.
              if (id != 'likes') ...[
                if (_buildings[id] case final b?)
                  HatarakiBuildingIcon(b, size: tall ? 64 : 72)
                else
                  HatarakiSkillIcon(skill, size: tall ? 64 : 72),
                const SizedBox(height: 8),
              ],
              Text(
                l.hatarakiHelpTitle(id),
                textAlign: TextAlign.center,
                style: Ty.lead,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        l.hatarakiHelpBody(id),
                        textAlign: TextAlign.center,
                        style: Ty.body.copyWith(color: Ty.inkSoft),
                      ),
                      if (id == 'likes') ...[
                        const SizedBox(height: 10),
                        const HatarakiLikesTable(),
                      ],
                    ],
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
                  const SizedBox(width: 10),
                  // Con muchas páginas, los puntos se encogen para caber.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        children: [
                          for (var p = 0; p < _pages.length; p++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: AnimatedContainer(
                                duration: skin.motion(
                                  const Duration(milliseconds: 200),
                                ),
                                width: p == _page ? 18 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: p == _page
                                      ? skin.accent
                                      : skin.hairline,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
