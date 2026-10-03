// Ibasho — canal de Tama Kōen: el parque donde juegan los Tamas de los amigos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
import '../../backend/koen.dart';
import '../../backend/koen_bonds.dart';
import '../../backend/koen_care.dart';
import '../../backend/koen_rewards.dart' show koenGame;
import '../../backend/missions.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../game_stage.dart' show DailyCoinsMeter;
import '../../state/koen.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/slot_tile.dart';
import 'koen_album.dart';
import 'koen_art.dart';
import 'koen_badge.dart';
import 'koen_care_ui.dart';
import 'koen_charm.dart';
import 'koen_friendship.dart';
import 'koen_house.dart';
import 'koen_mood.dart';

/// Lo que dura cada frase de una conversación, con su pausa.
const double _lineSeconds = 1.9;

/// Lo que se ve un bocadillo.
const double _bubbleSeconds = 1.6;

/// Velocidad al pasear, en fracciones de la escena por segundo (cerca; al
/// fondo, menos).
const double _walkSpeed = .028;

/// Al ir a encontrarse con otro, algo más deprisa.
const double _meetSpeed = .042;

/// Cada cuánto empieza el siguiente encuentro del día.
const double _showEvery = 12;

/// Un Tama en la escena: dónde está, adónde va y qué está haciendo.
class _Walker {
  _Walker(this.card, this.pos) : target = pos;

  KoenCard card;
  Offset pos;
  Offset target;
  double idleUntil = 0;
  bool facingLeft = false;
  bool held = false;

  /// El encuentro que está jugando, si hay alguno.
  _Show? show;

  /// Lo que siente en su bocadillo, desde cuándo y hasta cuándo.
  KoenMood? mood;
  double moodFrom = 0;
  double moodUntil = 0;

  /// Hasta cuándo se ve su nombre.
  double tagUntil = 0;

  final TamaViewController controller = TamaViewController();

  bool get arrived => (target - pos).distance < .004;
}

/// Un encuentro en marcha: los dos van juntos (a una zona o adonde estén) y
/// se dicen unas cuantas cosas por turnos.
class _Show {
  _Show(this.encounter, {required this.lines, required this.opener, this.forced = false, this.dance = false});

  final KoenEncounter encounter;
  final bool forced;

  /// Al acabar de hablar, su baile de pareja: dan media vuelta el uno
  /// alrededor del otro (desde «compis»).
  final bool dance;
  Offset? danceA;
  Offset? danceB;

  /// La conversación, y quién la empieza.
  final List<KoenLine> lines;
  final String opener;

  /// Cuándo empezaron (los dos ya juntos), o `null` si aún van.
  double? playFrom;
  int said = 0;

  double get talk => lines.length * _lineSeconds + .3;
  double get length => talk + .3 + (dance ? _danceSeconds + .4 : 0);
}

/// Lo que dura el baile de pareja.
const double _danceSeconds = 1.4;

/// El canal de Tama Kōen.
///
/// Arriba (o a la izquierda) el parque: los Tamas propios y los de los
/// amigos pasean con calma, y los encuentros del día se van representando
/// uno tras otro, en una zona o donde estén, con una pequeña conversación de
/// bocadillos. Se puede tocar un Tama (salta, saluda y dice su nombre),
/// arrastrarlo hasta otro para que hablen o hasta una zona, y tocar el
/// escenario. Las cosas altas del parque se ordenan con los Tamas según la
/// profundidad, para que pasen por delante o por detrás. Al lado, los tres
/// huecos propios y lo que ha pasado hoy.
class KoenChannel extends ConsumerStatefulWidget {
  const KoenChannel({super.key});

  @override
  ConsumerState<KoenChannel> createState() => _KoenChannelState();
}

class _KoenChannelState extends ConsumerState<KoenChannel> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  final KoenSceneFx _fx = KoenSceneFx();
  final math.Random _random = math.Random();
  final Map<String, _Walker> _walkers = <String, _Walker>{};
  final List<_Show> _shows = <_Show>[];

  List<KoenEncounter> _today = const [];
  int _nextShow = 0;
  double _nextShowAt = 3;
  double _last = 0;
  Size _size = Size.zero;

  /// Solo en depuración: la estación que se pinta en vez de la de hoy.
  KoenSeason? _debugSeason;

  double get _now => _clock.value;
  bool get _reduced => IbashoSkin.of(context).reducedMotion;
  String get _me => ref.read(sessionProvider).accountId;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final friends = ref.read(friendsProvider).friends.map((f) => f.accountId).toList();
    // Los que se cuidan a medias no se siguen en vivo: se releen al entrar.
    await ref.read(tamasProvider.notifier).refreshCared();
    if (!mounted) return;
    // Lo de los dúos va antes que el parque: las fichas llevan su pareja.
    await ref.read(koenDuosStateProvider.notifier).load(ref.read(koenDuosProvider));
    if (!mounted) return;
    final tamas = ref.read(tamasProvider).companions;
    await ref.read(koenProvider.notifier).refresh(friendIds: friends, tamas: tamas);
    for (final duo in ref.read(koenDuosProvider)) {
      if (!mounted) return;
      await tickKoenDuo(context, ref, duo);
    }
  }

  // --- La escena -------------------------------------------------------------

  /// Si [p] es un sitio donde se puede estar: en el césped y fuera del agua.
  bool _walkable(Offset p) => _size.isEmpty || !koenInPond(p, _size);

  Offset _clampGround(Offset p) => Offset(p.dx.clamp(.06, .94), p.dy.clamp(.46, .92));

  /// Un sitio no muy lejos de [from], para dar un paseo corto.
  Offset _strollFrom(Offset from) {
    for (var tries = 0; tries < 8; tries++) {
      final a = _random.nextDouble() * math.pi * 2;
      final d = .06 + _random.nextDouble() * .18;
      final p = _clampGround(from + Offset(math.cos(a) * d, math.sin(a) * d * .7));
      if (_walkable(p)) return p;
    }
    return from;
  }

  /// El otro Tama del dúo de [w], si está en el parque.
  _Walker? _mateOf(_Walker w) {
    for (final o in _walkers.values) {
      if (o != w && KoenCard.duoPair(w.card, o.card)) return o;
    }
    return null;
  }

  /// Pone al día los Tamas de la escena con lo que hay en el parque.
  void _sync(KoenState park) {
    final cards = park.all;
    final ids = {for (final c in cards) c.tamaId};
    _walkers.removeWhere((id, _) => !ids.contains(id));
    _shows.removeWhere((s) => !ids.contains(s.encounter.a.tamaId) || !ids.contains(s.encounter.b.tamaId));
    for (final c in cards) {
      final w = _walkers[c.tamaId];
      if (w != null) {
        w.card = c;
      } else {
        // Cada uno empieza en su sitio de siempre, para que al volver a entrar
        // no salgan todos amontonados.
        final h = koenHash(c.tamaId);
        var start = Offset(.08 + (h % 1000) / 1000 * .84, .5 + ((h >> 10) % 1000) / 1000 * .4);
        if (!_walkable(start)) start = Offset(start.dx, .5);
        _walkers[c.tamaId] = _Walker(c, start)..idleUntil = _now + 1 + (h % 60) / 10;
      }
    }
    _today = park.encounters(_me);
    if (_nextShow >= _today.length) _nextShow = 0;
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = math.min(.05, t - _last);
    _last = t;
    _fx.step(dt);
    _direct();
    for (final w in _walkers.values) {
      _move(w, dt);
    }
    _clock.value = t;
  }

  void _move(_Walker w, double dt) {
    if (w.held) return;
    if (!w.arrived) {
      final d = w.target - w.pos;
      if (_reduced) {
        w.pos = w.target;
      } else {
        // Al fondo se ve más pequeño, y también anda más corto.
        final speed = (w.show != null ? _meetSpeed : _walkSpeed) * koenDepthScale(w.pos.dy);
        final step = math.min(d.distance, speed * dt);
        w.pos += d / d.distance * step;
      }
      if (d.dx.abs() > .002) w.facingLeft = d.dx < 0;
      return;
    }
    if (w.show == null && _now >= w.idleUntil) {
      // Pasea un poco o se queda donde está, mirando a otro lado. Los de un
      // dúo van juntos: si se ha alejado, vuelve al lado del otro.
      final mate = _mateOf(w);
      if (mate != null && mate.show == null && (mate.pos - w.pos).distance > .1) {
        final side = w.pos.dx < mate.pos.dx ? -.05 : .05;
        final p = _clampGround(mate.pos + Offset(side, .01));
        w.target = _walkable(p) ? p : mate.pos;
      } else if (_random.nextInt(3) == 0) {
        w.facingLeft = mate != null ? mate.pos.dx < w.pos.dx : !w.facingLeft;
      } else {
        w.target = _strollFrom(w.pos);
      }
      w.idleUntil = _now + 4 + _random.nextDouble() * 8;
    }
  }

  /// Lleva los encuentros: arranca el siguiente del día de vez en cuando, uno
  /// cada vez, y hace hablar por turnos a los que ya están juntos.
  void _direct() {
    if (_today.isNotEmpty && _now >= _nextShowAt && !_shows.any((s) => !s.forced)) {
      for (var tries = 0; tries < _today.length; tries++) {
        final e = _today[_nextShow];
        _nextShow = (_nextShow + 1) % _today.length;
        if (_start(e)) break;
      }
      _nextShowAt = _now + _showEvery;
    }
    for (final s in [..._shows]) {
      final a = _walkers[s.encounter.a.tamaId];
      final b = _walkers[s.encounter.b.tamaId];
      if (a == null || b == null) {
        _shows.remove(s);
        continue;
      }
      if (s.playFrom == null) {
        if (a.arrived && b.arrived) {
          s.playFrom = _now;
          a.facingLeft = a.pos.dx > b.pos.dx;
          b.facingLeft = !a.facingLeft;
          if (!s.encounter.inPlace) _zoneFx(s.encounter.zone);
        }
        continue;
      }
      final playing = _now - s.playFrom!;
      final first = s.opener == a.card.tamaId ? a : b;
      final second = first == a ? b : a;
      if (s.said < s.lines.length && playing >= s.said * _lineSeconds + .3) {
        final line = s.lines[s.said];
        _say(line.first ? first : second, line.mood);
        s.said++;
      }
      if (s.dance && playing >= s.talk) _dance(s, a, b, (playing - s.talk) / _danceSeconds);
      if (playing >= s.length) _end(s);
    }
  }

  /// El baile de pareja, de 0 a 1: media vuelta del uno alrededor del otro,
  /// con un saltito al empezar y otro al acabar.
  void _dance(_Show s, _Walker a, _Walker b, double t) {
    if (s.danceA == null) {
      s.danceA = a.pos;
      s.danceB = b.pos;
      a.controller.hop();
      b.controller.hop();
      AudioService.instance.play(Sfx.pop);
    }
    final k = t.clamp(0.0, 1.0);
    final eased = k * k * (3 - 2 * k);
    final c = (s.danceA! + s.danceB!) / 2;
    final v = s.danceA! - c;
    final angle = math.pi * eased;
    // En perspectiva: la vuelta se aplasta en la «y».
    final r = Offset(v.dx * math.cos(angle) - v.dy * math.sin(angle), (v.dx * math.sin(angle) + v.dy * math.cos(angle)) * .5);
    a.pos = a.target = c + r;
    b.pos = b.target = c - r;
    if (k >= 1 && a.mood != KoenMood.love) {
      a.facingLeft = a.pos.dx > b.pos.dx;
      b.facingLeft = !a.facingLeft;
      _say(a, KoenMood.love);
      _say(b, KoenMood.love);
    }
  }

  /// Arranca un encuentro si los dos están libres. [opener] es quien habla
  /// primero (si no, el primero del encuentro).
  bool _start(KoenEncounter e, {bool forced = false, String? opener}) {
    final a = _walkers[e.a.tamaId];
    final b = _walkers[e.b.tamaId];
    if (a == null || b == null || a.show != null || b.show != null || a.held || b.held) return false;
    final first = opener == b.card.tamaId ? b : a;
    final second = first == a ? b : a;
    final level = ref.read(koenProvider).bondLevel(e.a.tamaId, e.b.tamaId) ?? 1;
    final show = _Show(
      e,
      forced: forced,
      dance: level >= koenBondDanceLevel && !_reduced,
      opener: first.card.tamaId,
      lines: koenChat(
        first: first.card.personality,
        second: second.card.personality,
        closeness: ref.read(koenProvider).closeness(e.a, e.b),
        random: _random,
      ),
    );
    // Donde estén (a medio camino) o en su zona.
    var spot = e.inPlace ? _clampGround((a.pos + b.pos) / 2) : koenZoneAt[e.zone]!;
    if (!_walkable(spot)) spot = Offset(spot.dx, koenZoneAt[KoenZone.pond]!.dy - .12);
    final aLeft = a.pos.dx <= b.pos.dx;
    a.show = show;
    b.show = show;
    a.target = spot + Offset(aLeft ? -.04 : .04, .005);
    b.target = spot + Offset(aLeft ? .04 : -.04, .005);
    _shows.add(show);
    return true;
  }

  /// Termina [show]: cada uno se queda un rato quieto antes de seguir.
  void _end(_Show show) {
    _shows.remove(show);
    for (final w in _walkers.values) {
      if (w.show != show) continue;
      w.show = null;
      w.idleUntil = _now + 2 + _random.nextDouble() * 3;
    }
  }

  /// Lo que se mueve en la zona al empezar a jugar allí.
  void _zoneFx(KoenZone zone) {
    switch (zone) {
      case KoenZone.swings:
        _fx.swingVel[0] += 1.6;
        _fx.swingVel[1] -= 1.6;
      case KoenZone.pond:
        _fx.duckTo = _random.nextDouble();
      case KoenZone.tree:
        _fx.treeShakeUntil = _now + .8;
      case KoenZone.sandbox:
        _fx.castle = math.min(3, _fx.castle + 1);
      case KoenZone.picnic:
        _fx.onigiriUntil = _now + .6;
      case KoenZone.slide:
        break;
    }
  }

  /// Que [w] sienta [mood]: le sale el bocadillo, lo dice con su voz y pone
  /// esa cara.
  void _say(_Walker w, KoenMood mood) {
    w.mood = mood;
    w.moodFrom = _now;
    w.moodUntil = _now + _bubbleSeconds;
    w.controller.speak(mood.chirp, w.card.voice);
    if (mood.hops && !_reduced) w.controller.hop();
  }

  void _tapTama(_Walker w) {
    w.controller.speak(ChirpKind.hello, w.card.voice);
    w.controller.hop();
    w.tagUntil = _now + 3;
  }

  void _tapScene(Offset local) {
    if (_size.isEmpty) return;
    final prop = koenPropAt(Offset(local.dx / _size.width, local.dy / _size.height), _size);
    if (prop == null) return;
    AudioService.instance.play(Sfx.tick);
    switch (prop) {
      case KoenProp.swingLeft:
        _fx.swingVel[0] += 2.6;
      case KoenProp.swingRight:
        _fx.swingVel[1] += 2.6;
      case KoenProp.pond:
        _fx.duckTo = _random.nextDouble();
      case KoenProp.tree:
        _fx.treeShakeUntil = _now + 1;
      case KoenProp.sandbox:
        _fx.castle = (_fx.castle + 1) % 4;
      case KoenProp.picnic:
        _fx.onigiriUntil = _now + .6;
      case KoenProp.lamp:
        _fx.lampUntil = _now + .8;
    }
  }

  // --- Arrastrar -------------------------------------------------------------

  void _dragStart(_Walker w) {
    if (w.show != null) _end(w.show!);
    w.held = true;
    w.controller.hop();
  }

  void _dragMove(_Walker w, Offset delta) {
    if (_size.isEmpty) return;
    w.pos = Offset(
      (w.pos.dx + delta.dx / _size.width).clamp(.04, .96),
      (w.pos.dy + delta.dy / _size.height).clamp(koenHorizon + .1, .97),
    );
    w.target = w.pos;
  }

  /// Al soltarlo junto a otro Tama, hablan allí mismo (si les quedan
  /// encuentros forzados hoy); en una zona, se queda jugando un rato. Si cae
  /// en el agua, sale a la orilla.
  void _dragEnd(_Walker w) {
    w.held = false;
    if (!_walkable(w.pos)) w.pos = Offset(w.pos.dx, koenZoneAt[KoenZone.pond]!.dy - .12);
    w.target = w.pos;
    final me = _me;
    final park = ref.read(koenProvider);
    _Walker? partner;
    var best = .14;
    for (final o in _walkers.values) {
      if (o == w || o.held) continue;
      final d = (o.pos - w.pos).distance;
      if (d < best && park.areFriends(me, w.card.holder, o.card.holder)) {
        best = d;
        partner = o;
      }
    }
    if (partner != null) {
      final key = koenPairKey(w.card.tamaId, partner.card.tamaId);
      if (park.dragsToday(key) < koenDragsPerPair) {
        final pair = [w.card, partner.card]..sort((x, y) => x.tamaId.compareTo(y.tamaId));
        if (partner.show != null) _end(partner.show!);
        final e = KoenEncounter(a: pair[0], b: pair[1], zone: KoenZone.tree, hour: 0, variant: 0, inPlace: true);
        if (_start(e, forced: true, opener: w.card.tamaId)) {
          unawaited(ref.read(koenProvider.notifier).drag(w.card, partner.card));
          AudioService.instance.play(Sfx.pop);
          return;
        }
      } else {
        _say(w, KoenMood.sleepy);
        w.idleUntil = _now + 3;
        return;
      }
    }
    final zone = _nearestZone(w.pos);
    if ((koenZoneAt[zone]! - w.pos).distance < .12) {
      w.target = koenZoneAt[zone]! + Offset((_random.nextDouble() - .5) * .08, .01);
      w.idleUntil = _now + 10;
      _say(w, _random.nextBool() ? KoenMood.happy : KoenMood.sing);
      _zoneFx(zone);
    } else {
      w.idleUntil = _now + 4;
    }
  }

  KoenZone _nearestZone(Offset p) => KoenZone.values.reduce(
    (a, b) => (koenZoneAt[a]! - p).distance <= (koenZoneAt[b]! - p).distance ? a : b,
  );

  // --- Huecos ------------------------------------------------------------------

  Future<void> _pickSlot() async {
    final l = L.of(context)!;
    final park = ref.read(koenProvider);
    if (park.mine.length >= koenSlots) {
      AudioService.instance.play(Sfx.error);
      return;
    }
    final tama = await showIbashoModal<Tama>(context, (_) => const _SendPicker());
    if (tama == null || !mounted) return;
    final ok = await ref.read(koenProvider.notifier).send(tama);
    if (!mounted) return;
    if (!ok) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.koenSendFailed);
      return;
    }
    AudioService.instance.play(Sfx.pop);
    unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.koen));
    _sync(ref.read(koenProvider));
  }

  /// Solo en depuración: el parque de prueba, con un Tama de un amigo
  /// inventado que ya se cuida a medias (ha comido hoy; falta el mimo) y una
  /// oferta de otro en el buzón. Con el primer Tama propio, Mochi hace un dúo
  /// que lleva 6 días de racha.
  void _demo() {
    final own = ref.read(tamasProvider).tamas;
    ref.read(koenProvider.notifier).debugDemo(own);
    final park = ref.read(koenProvider);
    final first = park.friends['demo-0']?.first;
    final second = park.friends['demo-1']?.last;
    if (first == null || second == null) return;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    ref.read(tamasProvider.notifier).debugCare(Tama(
      id: '-demoCare000000000a',
      creator: 'demo-0',
      keeper: 'demo-0',
      carer: _me,
      name: 'Mochi',
      personality: first.personality,
      voice: first.voice,
      look: first.look.withColor('#FFCF9A', TamaColorMode.hex),
      care: TamaCare(lastFed: DateTime.now()),
      createdAt: epoch,
      updatedAt: epoch,
    ));
    if (own.isNotEmpty) {
      ref.read(koenDuosStateProvider.notifier).debugDemo(mine: own.first.id, friend: 'demo-0');
      // Otra vez, para que las fichas lleven su pareja.
      ref.read(koenProvider.notifier).debugDemo(own);
    }
    ref.read(koenDemoOffersProvider.notifier).state = [
      KoenOffer(
        from: 'demo-1',
        card: KoenCard(
          holder: 'demo-1',
          slot: 0,
          tamaId: '-demoOffer00000000b',
          owner: 'demo-1',
          name: 'Kuri',
          personality: second.personality,
          voice: second.voice,
          look: second.look.withColor('#C9B6FF', TamaColorMode.hex),
          at: 1,
        ),
      ),
    ];
  }

  Future<void> _recall(KoenCard card) async {
    final l = L.of(context)!;
    final yes = await askConfirmation(
      context,
      title: l.koenRecallTitle(card.name),
      body: l.koenRecallBody(card.name),
      confirmLabel: l.koenRecall,
      cancelLabel: l.actionCancel,
      width: 460,
    );
    if (!yes || !mounted) return;
    final ok = await ref.read(koenProvider.notifier).recall(card.tamaId);
    if (!ok && mounted) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.koenSendFailed);
    }
  }

  // --- Lo que da el parque -------------------------------------------------

  /// Enseña lo que ha traído el parque: al entrar, en un cuadro; tras un
  /// encuentro forzado, en un aviso.
  void _showSummary(KoenSummary summary) {
    final l = L.of(context)!;
    ref.read(koenProvider.notifier).clearSummary();
    if (summary.quiet && !summary.big) {
      final parts = [
        if (summary.coins > 0) l.gameCoinsWon(summary.coins),
        for (final m in summary.memories) l.koenNewMemory(l.koenMemory(m.name)),
      ];
      if (parts.isEmpty) return;
      AudioService.instance.play(Sfx.chime);
      showIbashoToast(context, parts.join(' · '));
      return;
    }
    AudioService.instance.play(Sfx.chime);
    unawaited(showIbashoModal<void>(
      context,
      (_) => KoenSummaryDialog(summary: summary, season: _season(DateTime.now())),
    ));
  }

  // --- Interfaz ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final park = ref.watch(koenProvider);
    _sync(park);
    final layout = Layout.of(context);
    final scene = _sceneBox(park, l);
    ref.listen(koenProvider.select((k) => k.summary), (_, next) {
      if (next != null) _showSummary(next);
    });
    final side = _SidePanel(
      park: park,
      today: _today,
      me: ref.watch(sessionProvider.select((s) => s.accountId)),
      onAlbum: () => unawaited(
        showIbashoModal<void>(context, (_) => KoenAlbumDialog(season: _season(DateTime.now()))),
      ),
      onSlot: (i) {
        final card = park.slot(i);
        if (card == null) {
          unawaited(_pickSlot());
        } else {
          unawaited(_recall(card));
        }
      },
    );
    return ChannelScaffold(
      title: l.channelKoen,
      glyph: Glyph.park,
      art: ArtIcon.koen,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Solo en depuración: el parque lleno en local, para probarlo sin
          // amigos ni reglas desplegadas.
          if (kDebugMode) ...[
            IbashoButton(
              label: 'demo',
              tone: ButtonTone.quiet,
              height: layout.pill,
              onPressed: _demo,
            ),
            const SizedBox(width: 8),
            IbashoButton(
              label: _debugSeason?.name ?? 'auto',
              tone: ButtonTone.quiet,
              height: layout.pill,
              onPressed: () => setState(() {
                final next = (_debugSeason?.index ?? -1) + 1;
                _debugSeason = next < KoenSeason.values.length ? KoenSeason.values[next] : null;
              }),
            ),
            const SizedBox(width: 8),
          ],
          IbashoButton(
            label: l.koenRefresh,
            glyph: Glyph.refresh,
            tone: ButtonTone.quiet,
            height: layout.pill,
            onPressed: park.loading ? null : () => unawaited(_refresh()),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.gap),
        child: layout.tall
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 1.05, child: scene),
                  SizedBox(height: layout.gap),
                  Expanded(child: SingleChildScrollView(child: side)),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: scene),
                  SizedBox(width: layout.gap),
                  SizedBox(width: 300, child: SingleChildScrollView(child: side)),
                ],
              ),
      ),
    );
  }

  /// La estación de hoy según el hemisferio del país del dispositivo, o la
  /// elegida en depuración.
  KoenSeason _season(DateTime now) =>
      _debugSeason ??
      koenSeason(now, south: koenSouthern(WidgetsBinding.instance.platformDispatcher.locale.countryCode));

  KoenScenePainter _painter(KoenLayer layer, DateTime now) => KoenScenePainter(
    layer: layer,
    season: _season(now),
    daylight: koenDaylight(now),
    time: _clock,
    fx: _fx,
    reducedMotion: _reduced,
    repaint: _clock,
  );

  Widget _sceneBox(KoenState park, L l) {
    final now = DateTime.now();
    return GlossSurface(
      radius: 22,
      recessed: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: LayoutBuilder(
          builder: (context, box) {
            _size = box.biggest;
            final tamaSize = math.max(44.0, math.min(box.maxWidth, box.maxHeight * 1.6) * .11);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _tapScene(d.localPosition),
                    child: RepaintBoundary(child: CustomPaint(painter: _painter(KoenLayer.ground, now))),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _clock,
                    builder: (context, _) => _depthStack(box.biggest, tamaSize, now),
                  ),
                ),
                if (!park.loaded || (park.friends.isEmpty && park.loaded))
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Center(
                      child: _Hint(
                        text: !park.loaded
                            ? l.loading
                            : park.failed
                            ? l.koenFailed
                            : l.koenNoFriendsHere,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Los Tamas y las cosas altas del parque, de atrás adelante según la «y»
  /// de su base; encima, lo que cae del cielo, los bocadillos y los nombres.
  Widget _depthStack(Size size, double tamaSize, DateTime now) {
    final items = <(double, Widget)>[
      for (final e in koenLayerBase.entries)
        (
          e.value,
          Positioned.fill(
            key: ValueKey<String>('koen.layer.${e.key.name}'),
            child: IgnorePointer(child: CustomPaint(painter: _painter(e.key, now))),
          ),
        ),
      for (final w in _walkers.values) (w.held ? 9.0 : w.pos.dy, _tamaAt(w, size, tamaSize)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final (_, child) in items) child,
        ..._charmLinks(size, tamaSize),
        Positioned.fill(
          key: const ValueKey<String>('koen.layer.air'),
          child: IgnorePointer(child: CustomPaint(painter: _painter(KoenLayer.air, now))),
        ),
        for (final w in _walkers.values)
          if (w.mood != null && _now < w.moodUntil) _bubbleAt(w, size, tamaSize),
        for (final w in _walkers.values)
          if (_now < w.tagUntil) _tagAt(w, size, tamaSize),
      ],
    );
  }

  /// El accesorio de pareja de los dúos que están juntos, quietos y
  /// llevándolo los dos: el hilo de uno a otro o el corazón entre los dos.
  List<Widget> _charmLinks(Size size, double base) {
    final out = <Widget>[];
    for (final w in _walkers.values) {
      final mate = _mateOf(w);
      if (mate == null || w.card.tamaId.compareTo(mate.card.tamaId) > 0) continue;
      if (w.held || mate.held || !w.arrived || !mate.arrived) continue;
      if ((w.pos - mate.pos).distance > .12) continue;
      final (l, r) = w.pos.dx <= mate.pos.dx ? (w, mate) : (mate, w);
      final link = koenCharmLink(l.card.look, r.card.look);
      if (link == null) continue;
      Offset topLeft(_Walker x, double s) => Offset(x.pos.dx * size.width - s / 2, x.pos.dy * size.height - s * .92);
      final ls = base * koenDepthScale(l.pos.dy);
      final rs = base * koenDepthScale(r.pos.dy);
      out.add(Positioned.fill(
        key: ValueKey<String>('koen.charm.${w.card.tamaId}'),
        child: IgnorePointer(
          child: CustomPaint(
            painter: KoenCharmLinkPainter(
              charm: link,
              from: koenCharmAnchor(l.card.look, topLeft(l, ls), ls, towardRight: true),
              to: koenCharmAnchor(r.card.look, topLeft(r, rs), rs, towardRight: false),
              scale: (ls + rs) / 2,
            ),
          ),
        ),
      ));
    }
    return out;
  }

  Widget _tamaAt(_Walker w, Size size, double base) {
    final card = w.card;
    final s = base * koenDepthScale(w.pos.dy);
    final mine = card.holder == _me;
    final tama = mine ? ref.read(tamasProvider).find(card.tamaId) : null;
    final talking = w.mood != null && _now < w.moodUntil + .6;
    final joy = talking ? w.mood!.joy : (tama != null ? TamaMoodReading.of(tama, DateTime.now()).joy : .5);
    final x = w.pos.dx * size.width;
    final y = w.pos.dy * size.height;
    return Positioned(
      key: ValueKey<String>('koen.tama.${card.tamaId}'),
      left: x - s / 2,
      top: y - s * .92,
      width: s,
      height: s,
      child: GestureDetector(
        onPanStart: (_) => _dragStart(w),
        onPanUpdate: (d) => _dragMove(w, d.delta),
        onPanEnd: (_) => _dragEnd(w),
        onPanCancel: () => w.held = false,
        child: Transform.flip(
          flipX: w.facingLeft,
          child: TamaView(
            // En espejo, la mitad del accesorio de pareja cambia de lado para
            // seguir mirando al otro.
            look: w.facingLeft ? koenMirrorCharm(card.look) : card.look,
            personality: card.personality,
            name: card.name,
            voice: card.voice,
            seed: koenHash(card.tamaId),
            joy: joy,
            size: s,
            controller: w.controller,
            onTap: () => _tapTama(w),
            semanticLabel: card.name,
          ),
        ),
      ),
    );
  }

  /// El bocadillo de [w], sobre su cabeza y hacia el lado al que mira, sin
  /// salirse de la escena.
  Widget _bubbleAt(_Walker w, Size size, double base) {
    final s = base * koenDepthScale(w.pos.dy);
    final bw = math.max(46.0, base * 1.05);
    final bh = bw * .78;
    final x = w.pos.dx * size.width;
    final headTop = w.pos.dy * size.height - s * .92;
    // El pico apunta al Tama: el globo cae hacia donde mira.
    final toRight = !w.facingLeft;
    var left = toRight ? x - bw * .22 : x - bw * .78;
    left = left.clamp(4.0, math.max(4.0, size.width - bw - 4));
    final top = math.max(4.0, headTop - bh + s * .06);
    return Positioned(
      key: ValueKey<String>('koen.bubble.${w.card.tamaId}'),
      left: left,
      top: top,
      width: bw,
      height: bh,
      child: IgnorePointer(
        child: CustomPaint(
          painter: KoenBubblePainter(
            mood: w.mood!,
            tint: colorFromHex(w.card.look.color) ?? const Color(0xFF9FD4FF),
            age: _reduced ? 1 : _now - w.moodFrom,
            life: _bubbleSeconds,
            tailRight: !toRight,
          ),
        ),
      ),
    );
  }

  /// El nombre de [w] bajo sus pies, entero y dentro de la escena.
  Widget _tagAt(_Walker w, Size size, double base) {
    final s = base * koenDepthScale(w.pos.dy);
    final style = Ty.caption.copyWith(color: Ty.ink);
    final text = TextPainter(
      text: TextSpan(text: w.card.name, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final tw = text.width + 24;
    final th = text.height;
    text.dispose();
    final x = w.pos.dx * size.width;
    final y = w.pos.dy * size.height;
    final left = (x - tw / 2).clamp(4.0, math.max(4.0, size.width - tw - 4)).toDouble();
    final top = math.min(y + s * .1, size.height - th - 16);
    return Positioned(
      key: ValueKey<String>('koen.tag.${w.card.tamaId}'),
      left: left,
      top: top,
      child: IgnorePointer(child: _Tag(name: w.card.name, style: style)),
    );
  }
}


/// Un cartel pequeño sobre la escena.
class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => GlossSurface(
    radius: 16,
    elevation: 1.2,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text, textAlign: TextAlign.center, style: Ty.caption),
  );
}

/// El nombre de un Tama, entero.
class _Tag extends StatelessWidget {
  const _Tag({required this.name, required this.style});

  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => GlossSurface(
    radius: 12,
    elevation: 1,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Text(name, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: style),
  );
}

/// Los tres huecos propios y lo que ha pasado hoy.
class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.park,
    required this.today,
    required this.me,
    required this.onSlot,
    required this.onAlbum,
  });

  final KoenState park;
  final List<KoenEncounter> today;
  final String me;
  final void Function(int slot) onSlot;
  final VoidCallback onAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final mineIds = {for (final c in park.mine) c.tamaId};
    final ours = today.where((e) => mineIds.contains(e.a.tamaId) || mineIds.contains(e.b.tamaId)).toList();
    final friendTamas = park.friends.values.fold<int>(0, (n, c) => n + c.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.koenYourTamas, style: Ty.label),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < koenSlots; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _SlotView(card: park.slot(i), onPressed: () => onSlot(i))),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(l.koenSlotsHint, style: Ty.micro),
        const SizedBox(height: 14),
        DailyCoinsMeter(game: koenGame, earned: park.demo ? park.demoEarned : null),
        const SizedBox(height: 6),
        Text(l.koenCoinsHint, style: Ty.micro),
        const SizedBox(height: 10),
        KoenAlbumButton(onPressed: onAlbum),
        const SizedBox(height: 18),
        Text(l.koenToday, style: Ty.label),
        const SizedBox(height: 8),
        if (park.mine.isEmpty)
          Text(l.koenTodayNoTamas, style: Ty.caption)
        else if (ours.isEmpty)
          Text(l.koenTodayNone, style: Ty.caption)
        else
          for (final e in ours)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _EncounterRow(encounter: e, me: me),
            ),
        const SizedBox(height: 18),
        Text(l.koenFriendsTitle, style: Ty.label),
        const SizedBox(height: 4),
        Text(l.koenFriendsHint, style: Ty.micro),
        const SizedBox(height: 8),
        if (_mates(park).isEmpty)
          Text(l.koenFriendsNone, style: Ty.caption)
        else
          for (final friend in _mates(park))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _FriendRow(park: park, friend: friend),
            ),
        const SizedBox(height: 18),
        const KoenCareSection(),
        const SizedBox(height: 18),
        const KoenDuoSection(),
        const SizedBox(height: 18),
        Text(l.koenFriendsCount(friendTamas, park.friends.length), style: Ty.micro),
      ],
    );
  }
}

/// Los amigos con algo de amistad en el parque, de más a menos.
List<String> _mates(KoenState park) {
  int points(String f) => (park.mates[f]?.p ?? 0) + (park.theirs[f] ?? 0);
  return {...park.mates.keys, ...park.theirs.keys}.where((f) => points(f) > 0).toList()
    ..sort((a, b) => points(b).compareTo(points(a)));
}

/// La amistad con un amigo: su nombre, el nivel y lo que falta para el
/// siguiente.
class _FriendRow extends ConsumerWidget {
  const _FriendRow({required this.park, required this.friend});

  final KoenState park;
  final String friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final points = (park.mates[friend]?.p ?? 0) + (park.theirs[friend] ?? 0);
    final level = KoenFriendLevel.of(points);
    final next = level.index + 1 < KoenFriendLevel.values.length ? KoenFriendLevel.values[level.index + 1] : null;
    return SlotTile(
      key: ValueKey<String>('koen.friend.$friend'),
      width: double.infinity,
      height: 52,
      semanticLabel: l.koenFriendshipTitle(koenFriendName(ref, friend)),
      onPressed: () => unawaited(showKoenFriendship(context, friend)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            KoenFriendBadge(level: level, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(koenFriendName(ref, friend), maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.body),
                  Text(
                    next == null
                        ? l.koenFriendLevel(level.name)
                        : '${l.koenFriendLevel(level.name)} · ${l.koenFriendNext(points, next.points, l.koenFriendLevel(next.name))}',
                    style: Ty.micro,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotView extends StatelessWidget {
  const _SlotView({required this.card, required this.onPressed});

  final KoenCard? card;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final c = card;
    return SlotTile(
      width: double.infinity,
      height: 104,
      semanticLabel: c?.name ?? l.koenSlotEmpty,
      onPressed: onPressed,
      child: c == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlyphIcon(Glyph.plus, size: 26, color: Ty.inkSoft),
                const SizedBox(height: 4),
                Text(l.koenSlotEmpty, style: Ty.micro),
              ],
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Column(
                children: [
                  Expanded(
                    child: TamaView(
                      look: c.look,
                      personality: c.personality,
                      name: c.name,
                      voice: c.voice,
                      seed: koenHash(c.tamaId),
                      size: 64,
                      interactive: false,
                      shadow: false,
                    ),
                  ),
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(color: Ty.ink)),
                ],
              ),
            ),
    );
  }
}

class _EncounterRow extends ConsumerWidget {
  const _EncounterRow({required this.encounter, required this.me});

  final KoenEncounter encounter;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final e = encounter;
    final h = e.hour.floor();
    final m = ((e.hour - h) * 60).floor();
    final time = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    return GlossSurface(
      radius: 14,
      elevation: .8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(time, style: Ty.caption),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.koenPair(e.a.name, e.b.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body,
                ),
                Row(
                  children: [
                    Flexible(child: Text(l.koenZoneName(e.inPlace ? 'path' : e.zone.name), style: Ty.micro)),
                    const SizedBox(width: 8),
                    KoenHearts(level: ref.watch(koenProvider).bondLevel(e.a.tamaId, e.b.tamaId) ?? 1, size: 10),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Elige qué Tama propio va al parque.
class _SendPicker extends ConsumerWidget {
  const _SendPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final park = ref.watch(koenProvider);
    // Los propios y los que se cuidan a medias, menos los que ya están en el
    // parque (también si lo ha traído el otro).
    final inPark = {for (final c in park.all) c.tamaId};
    final tamas = ref.watch(tamasProvider.select((t) => t.companions)).where((t) => !inPark.contains(t.id)).toList();
    return IbashoDialog(
      title: l.koenPickTitle,
      width: 460,
      body: tamas.isEmpty
          ? Text(l.koenPickNone, style: Ty.body)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tamas)
                      SlotTile(
                        key: ValueKey<String>('koen.pick.${t.id}'),
                        width: 96,
                        height: 112,
                        semanticLabel: t.name,
                        onPressed: () => Navigator.of(context).pop(t),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                          child: Column(
                            children: [
                              Expanded(
                                child: TamaView(
                                  look: t.look,
                                  personality: t.personality,
                                  name: t.name,
                                  voice: t.voice,
                                  seed: koenHash(t.id),
                                  size: 70,
                                  interactive: false,
                                  shadow: false,
                                ),
                              ),
                              Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(color: Ty.ink)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      actions: [
        IbashoButton(
          label: l.actionClose,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
