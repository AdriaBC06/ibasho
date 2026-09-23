// Ibasho — canal de Nihongo: aprender kana con tu Tama de sensei.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../audio/tama_voice.dart';
import '../../backend/leaderboards.dart';
import '../../backend/missions.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/tama/tama_widgets.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/text_field.dart';
import '../game_music.dart';
import '../game_stage.dart';
import '../game_store.dart';
import 'kana.dart';
import 'nihongo_store.dart';
import 'nihongo_widgets.dart';

/// Semilla fija para los recorridos visuales. En la app es siempre `null`.
@visibleForTesting
int? debugNihongoSeed;

/// Las cuatro categorias. Kanji y palabras aun no estan.
enum _Category { hiragana, katakana, kanji, words }

enum _Phase { menu, quiz, results, chart }

/// El canal de Nihongo.
///
/// Una escena con tu Tama de sensei al lado. En el menu se elige categoria
/// (hiragana, katakana; kanji y palabras, proximamente), que grupos de kana
/// entran y si se responde eligiendo entre cuatro o escribiendo. Una ronda son
/// diez tarjetas: el kana grande en su tarjeta de papel, y al acertar cae el
/// sello rojo; al fallar se enseña la lectura buena y se espera a que la
/// mires. Al final, los fallos para repasar y, con un pleno, monedas. Desde
/// el menu se abre tambien la tabla, para leer los kana de cada grupo con su
/// lectura; al tocar uno, el Tama te dice cómo se lee.
class NihongoChannel extends ConsumerStatefulWidget {
  const NihongoChannel({super.key});

  @override
  ConsumerState<NihongoChannel> createState() => _NihongoChannelState();
}

class _NihongoChannelState extends ConsumerState<NihongoChannel> {
  _Phase _phase = _Phase.menu;
  _Category _category = _Category.hiragana;
  KanaRound? _round;
  KanaGroup _chartGroup = KanaGroup.basic;
  Kana? _chartPick;

  final math.Random _random = math.Random();
  String? _tamaId;
  final TamaViewController _tama = TamaViewController();
  double _joy = .4;
  String? _bubble;
  Timer? _bubbleTimer;
  bool _greeted = false;

  GameStore? _store;
  NihongoRecords _records = const NihongoRecords();
  bool _newBest = false;
  RewardOutcome? _reward;
  bool _rewardPending = false;
  Timer? _advance;

  final TextEditingController _typed = TextEditingController();
  final FocusNode _typeFocus = FocusNode(debugLabel: 'nihongo.write');
  final FocusNode _keys = FocusNode(debugLabel: 'nihongo');

  KanaScript get _script => _category == _Category.katakana ? KanaScript.katakana : KanaScript.hiragana;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStore());
  }

  Future<void> _loadStore() async {
    final store = await GameStore.open('nihongo');
    final json = await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _records = NihongoRecords.fromJson(json);
    });
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _advance?.cancel();
    _typed.dispose();
    _typeFocus.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _save() => unawaited(_store?.save(_records.toJson()));

  // --- Tama ------------------------------------------------------------------

  void _pickTama() {
    final tamas = ref.read(tamasProvider).tamas;
    if (tamas.isEmpty) {
      _tamaId = null;
      return;
    }
    final pool = tamas.length > 1 ? tamas.where((t) => t.id != _tamaId).toList() : tamas;
    _tamaId = pool[_random.nextInt(pool.length)].id;
  }

  Tama? _currentTama() {
    final tamas = ref.watch(tamasProvider).tamas;
    if (tamas.isEmpty) return null;
    if (_tamaId == null || !tamas.any((t) => t.id == _tamaId)) {
      _tamaId = tamas[_random.nextInt(tamas.length)].id;
    }
    return tamas.firstWhere((t) => t.id == _tamaId);
  }

  void _say(String? text, {Duration hold = const Duration(milliseconds: 2000)}) {
    _bubbleTimer?.cancel();
    _bubble = text;
    if (text == null) return;
    _bubbleTimer = Timer(hold, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  // --- Menu --------------------------------------------------------------------

  void _choose(_Category c) {
    final l = L.of(context)!;
    if (c == _Category.kanji || c == _Category.words) {
      AudioService.instance.play(Sfx.error);
      setState(() => _say(l.nihongoBubbleSoon));
      _tama.hop();
      return;
    }
    setState(() => _category = c);
  }

  void _toggleGroup(KanaGroup g) {
    final groups = {..._records.groups};
    groups.contains(g) ? groups.remove(g) : groups.add(g);
    setState(() {
      _records = _records.copyWith(groups: groups);
      if (groups.isEmpty) _say(L.of(context)!.nihongoBubbleEmpty);
    });
    _save();
  }

  void _setMode(AnswerMode m) {
    setState(() => _records = _records.copyWith(mode: m));
    _save();
  }

  // --- Tabla ---------------------------------------------------------------------

  void _openChart() {
    AudioService.instance.play(Sfx.open);
    setState(() {
      _phase = _Phase.chart;
      _chartPick = null;
      _say(L.of(context)!.nihongoBubbleChart);
    });
    _tama.hop();
  }

  void _setChartScript(_Category c) {
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _category = c;
      _chartPick = null;
    });
  }

  void _setChartGroup(KanaGroup g) {
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _chartGroup = g;
      _chartPick = null;
    });
  }

  void _readKana(Kana k) {
    final l = L.of(context)!;
    final reading = k.also.isEmpty ? k.romaji : '${k.romaji} (${k.also.join(', ')})';
    setState(() {
      _chartPick = k;
      _joy = .7;
      _say(l.nihongoChartReads(k.char, reading), hold: const Duration(seconds: 3));
    });
    _tama
      ..hop()
      ..speak(ChirpKind.hello);
  }

  // --- Ronda ---------------------------------------------------------------------

  void _start({List<Kana>? only}) {
    final l = L.of(context)!;
    final pool = only ?? kanaOf(_script, _records.groups);
    if (pool.isEmpty) {
      AudioService.instance.play(Sfx.error);
      setState(() => _say(l.nihongoBubbleEmpty));
      return;
    }
    _advance?.cancel();
    AudioService.instance.play(Sfx.open);
    setState(() {
      _round = KanaRound(
        script: _script,
        mode: _records.mode,
        pool: pool,
        stats: _records.stats,
        length: only == null ? 10 : only.length,
        review: only != null,
        seed: debugNihongoSeed,
      );
      _phase = _Phase.quiz;
      _reward = null;
      _rewardPending = false;
      _newBest = false;
      _joy = .5;
      _typed.clear();
      _pickTama();
      _say(l.nihongoBubbleStart);
    });
    _tama.hop();
    _focusInput();
  }

  void _focusInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_records.mode == AnswerMode.write ? _typeFocus : _keys).requestFocus();
    });
  }

  void _answer(String text) {
    final round = _round;
    if (round == null || round.current.correct != null) return;
    if (text.trim().isEmpty) return;
    final l = L.of(context)!;
    final kana = round.current.kana;
    final ok = round.answer(text);
    _records = _records.answered(kana, ok);
    _save();
    if (ok) {
      AudioService.instance.play(Sfx.chime);
      _joy = .9;
      _tama.hop();
      if (round.streak >= 5 && round.streak % 5 == 0) {
        _say(l.nihongoBubbleStreak(round.streak));
        _tama.cuddle();
      } else if (_random.nextDouble() < .55) {
        _say([l.nihongoBubbleRight1, l.nihongoBubbleRight2, l.nihongoBubbleRight3][_random.nextInt(3)]);
      }
      // Acertar pasa sola; fallar espera a que se mire la buena.
      _advance = Timer(const Duration(milliseconds: 950), _next);
    } else {
      AudioService.instance.play(Sfx.error);
      _joy = -.5;
      _say(l.nihongoBubbleWrong, hold: const Duration(seconds: 3));
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _tama.speak(ChirpKind.sigh);
        }),
      );
      _keys.requestFocus();
    }
    setState(() {});
  }

  void _next() {
    _advance?.cancel();
    final round = _round;
    if (!mounted || round == null || round.current.correct == null) return;
    if (round.next()) {
      AudioService.instance.play(Sfx.tick);
      setState(() {
        _typed.clear();
        _joy = .4;
      });
      _focusInput();
    } else {
      _finish();
    }
  }

  void _finish() {
    final round = _round!;
    final l = L.of(context)!;
    final (records, newBest) = _records.finished(round);
    _records = records;
    _save();
    _newBest = newBest;
    _phase = _Phase.results;
    if (round.perfect && !round.review) {
      AudioService.instance.play(Sfx.chime);
      _joy = 1;
      _say(l.nihongoBubblePerfect, hold: const Duration(seconds: 5));
      _tama
        ..cuddle()
        ..hop()
        ..speak(ChirpKind.happy);
    } else {
      _joy = .6;
      _say(l.nihongoBubbleDone, hold: const Duration(seconds: 4));
      _tama.hop();
    }
    final coins = nihongoRewardFor(round);
    if (coins > 0) unawaited(_claim(coins));
    // Nihongo no tiene una sola puntuacion: `best` guarda la mejor ronda
    // (0-10) de cada combinacion de escritura y modo. La clasificacion usa la
    // suma de todas esas mejores rondas, que crece con lo que se domina en
    // conjunto (hiragana y katakana, a elegir y a escribir) en vez de premiar
    // solo el modo mas facil.
    unawaited(
      ref.read(leaderboardsProvider.notifier).submitScore(
            LeaderboardGame.nihongo,
            _records.best.values.fold(0, (a, b) => a + b),
          ),
    );
    unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.play));
    _keys.requestFocus();
    setState(() {});
  }

  Future<void> _claim(int coins) async {
    setState(() => _rewardPending = true);
    final outcome = await ref.read(rewardsProvider.notifier).claim(game: 'nihongo', amount: coins);
    if (!mounted) return;
    setState(() {
      _reward = outcome;
      _rewardPending = false;
    });
  }

  void _toMenu() {
    _advance?.cancel();
    AudioService.instance.play(Sfx.back);
    setState(() {
      _phase = _Phase.menu;
      _round = null;
      _chartPick = null;
      _joy = .4;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final round = _round;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (_phase == _Phase.quiz && round?.current.correct != null) {
        _next();
        return KeyEventResult.handled;
      }
      if (_phase == _Phase.results) {
        _start();
        return KeyEventResult.handled;
      }
    }
    if (_phase == _Phase.quiz && round != null && round.mode == AnswerMode.choices) {
      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ];
      final i = digits.indexOf(key);
      if (i >= 0 && i < round.current.choices.length) {
        _answer(round.current.choices[i]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // --- Composicion ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tama = _currentTama();
    if (!_greeted) {
      _greeted = true;
      _say(l.nihongoBubbleHello, hold: const Duration(seconds: 4));
    }
    // Sumi en el menu y en la tabla; Hanami durante la ronda y sus resultados.
    final playing = _phase == _Phase.quiz || _phase == _Phase.results;
    return GameMusic(
      track: playing ? MusicTrack.hanami : MusicTrack.sumi,
      child: ChannelScaffold(
        title: l.nihongoTitle,
        glyph: Glyph.kana,
        art: ArtIcon.nihongo,
        child: Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            child: layout.tall ? _tallLayout(context, tama) : _wideLayout(context, tama),
          ),
        ),
      ),
    );
  }

  Widget _stage(Tama? tama, double size) {
    final face = tama == null
        ? GlossyFace(joy: _joy, size: size)
        : TamaOnStand(tama: tama, size: size, joy: _joy, controller: _tama);
    return KeyedSubtree(key: ValueKey<String>('nihongo.tama.${tama?.id}'), child: face);
  }

  // Menu.

  Widget _categoryCard(L l, _Category c, double height, {bool compact = false}) {
    final (char, name) = switch (c) {
      _Category.hiragana => ('あ', l.nihongoHiragana),
      _Category.katakana => ('ア', l.nihongoKatakana),
      _Category.kanji => ('漢', l.nihongoKanji),
      _Category.words => ('言', l.nihongoWords),
    };
    final locked = c == _Category.kanji || c == _Category.words;
    final script = c == _Category.katakana ? KanaScript.katakana : KanaScript.hiragana;
    final total = kanaTable[script]!.length;
    final mastered = _records.mastered(script);
    return CategoryCard(
      key: ValueKey<String>('nihongo.category.${c.name}'),
      char: char,
      name: name,
      caption: locked ? l.nihongoSoon : (compact ? '$mastered/$total' : l.nihongoMastered(mastered, total)),
      compact: compact,
      progress: locked ? 0 : mastered / total,
      selected: c == _category,
      locked: locked,
      height: height,
      onPressed: () => _choose(c),
    );
  }

  Widget _categories(L l, {required double height, required double gap, bool compact = false}) => Column(
    children: [
      Row(
        children: [
          Expanded(child: _categoryCard(l, _Category.hiragana, height, compact: compact)),
          SizedBox(width: gap),
          Expanded(child: _categoryCard(l, _Category.katakana, height, compact: compact)),
        ],
      ),
      SizedBox(height: gap),
      Row(
        children: [
          Expanded(child: _categoryCard(l, _Category.kanji, height, compact: compact)),
          SizedBox(width: gap),
          Expanded(child: _categoryCard(l, _Category.words, height, compact: compact)),
        ],
      ),
    ],
  );

  Widget _setup(L l, {required bool tall}) {
    final small = tall && Layout.of(context).height < 700;
    String count(KanaGroup g) => '${kanaOf(_script, {g}).length}';
    final label = Ty.micro.copyWith(fontWeight: FontWeight.w600);
    final h = tall ? 48.0 : 50.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.nihongoGroups, style: label),
        const SizedBox(height: 6),
        SegmentRail(
          height: h,
          children: [
            for (final (g, name) in [
              (KanaGroup.basic, l.nihongoGroupBasic),
              (KanaGroup.dakuten, l.nihongoGroupDakuten),
              (KanaGroup.combo, l.nihongoGroupCombo),
            ])
              SegmentPill(
                key: ValueKey<String>('nihongo.group.${g.name}'),
                label: name,
                caption: count(g),
                height: h,
                selected: _records.groups.contains(g),
                onPressed: () => _toggleGroup(g),
              ),
          ],
        ),
        SizedBox(height: small ? 8 : (tall ? 10 : 14)),
        Text(l.nihongoMode, style: label),
        const SizedBox(height: 6),
        SegmentRail(
          height: 44,
          children: [
            SegmentPill(
              key: const ValueKey<String>('nihongo.mode.choices'),
              label: l.nihongoModeChoices,
              glyph: Glyph.slot,
              selected: _records.mode == AnswerMode.choices,
              onPressed: () => _setMode(AnswerMode.choices),
            ),
            SegmentPill(
              key: const ValueKey<String>('nihongo.mode.write'),
              label: l.nihongoModeWrite,
              glyph: Glyph.pencil,
              selected: _records.mode == AnswerMode.write,
              onPressed: () => _setMode(AnswerMode.write),
            ),
          ],
        ),
        SizedBox(height: small ? 8 : (tall ? 10 : 14)),
        DailyCoinsMeter(game: 'nihongo', height: small ? 38 : 44),
        // En un movil bajo no cabe todo con los botones a la vista: lo que se
        // gana se queda para los resultados.
        if (!small) ...[
          const SizedBox(height: 6),
          Text(l.nihongoRewardHint, textAlign: TextAlign.center, style: Ty.caption),
        ],
        SizedBox(height: small ? 8 : (tall ? 10 : 14)),
        Row(
          children: [
            Expanded(
              child: IbashoButton(
                key: const ValueKey<String>('nihongo.chart'),
                label: l.nihongoChart,
                glyph: Glyph.kana,
                expand: true,
                cue: null,
                onPressed: _openChart,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: IbashoButton(
                key: const ValueKey<String>('nihongo.start'),
                label: l.nihongoStart,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                cue: null,
                onPressed: _records.groups.isEmpty ? null : () => _start(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Tabla.

  Widget _chartPickers(L l, {required bool tall}) {
    final h = tall ? 44.0 : 46.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentRail(
          height: h,
          children: [
            for (final (c, name) in [(_Category.hiragana, l.nihongoHiragana), (_Category.katakana, l.nihongoKatakana)])
              SegmentPill(
                key: ValueKey<String>('nihongo.chart.script.${c.name}'),
                label: name,
                height: h,
                selected: _category == c,
                onPressed: () => _setChartScript(c),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentRail(
          height: h,
          children: [
            for (final (g, name) in [
              (KanaGroup.basic, l.nihongoGroupBasic),
              (KanaGroup.dakuten, l.nihongoGroupDakuten),
              (KanaGroup.combo, l.nihongoGroupCombo),
            ])
              SegmentPill(
                key: ValueKey<String>('nihongo.chart.group.${g.name}'),
                label: name,
                caption: '${kanaOf(_script, {g}).length}',
                height: h,
                selected: _chartGroup == g,
                onPressed: () => _setChartGroup(g),
              ),
          ],
        ),
      ],
    );
  }

  Widget _chart({double gap = 8}) => KanaChartView(
    key: ValueKey<String>('nihongo.chart.${_script.name}.${_chartGroup.name}'),
    rows: kanaChart(_script, _chartGroup),
    mastered: (k) => _records.stats[k.char]?.mastered ?? false,
    selected: _chartPick,
    onPressed: _readKana,
    gap: gap,
  );

  // Ronda.

  Widget _card(double size) {
    final round = _round!;
    final q = round.current;
    return AnimatedSwitcher(
      duration: IbashoSkin.of(context).motion(const Duration(milliseconds: 380)),
      switchInCurve: IbashoSkin.of(context).curve(Curves.easeOutBack),
      switchOutCurve: Curves.easeIn,
      // Cada tarjeta nueva entra dandose la vuelta.
      transitionBuilder: (child, a) => AnimatedBuilder(
        animation: a,
        child: child,
        builder: (context, child) => Opacity(
          opacity: a.value.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0015)
              ..rotateY((1 - a.value) * math.pi / 2),
            child: child,
          ),
        ),
      ),
      child: KanaCard(
        key: ValueKey<String>('nihongo.card.${round.index}'),
        char: q.kana.char,
        size: size,
        correct: q.correct,
        reading: q.kana.romaji,
      ),
    );
  }

  Widget _answers(L l, {required bool tall}) {
    final round = _round!;
    final q = round.current;
    final answered = q.correct != null;
    if (round.mode == AnswerMode.write) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IbashoTextField(
            key: const ValueKey<String>('nihongo.field'),
            controller: _typed,
            focusNode: _typeFocus,
            label: l.nihongoWriteHint,
            hint: 'a, ka, shi…',
            enabled: !answered,
            maxLength: 4,
            autofocus: true,
            onSubmitted: _answer,
            error: q.correct == false ? l.nihongoWrongWas(q.kana.romaji) : null,
          ),
          const SizedBox(height: 10),
          answered
              ? _nextButton(l)
              : IbashoButton(
                  key: const ValueKey<String>('nihongo.check'),
                  label: l.nihongoCheck,
                  glyph: Glyph.check,
                  tone: ButtonTone.accent,
                  expand: true,
                  cue: null,
                  onPressed: () => _answer(_typed.text),
                ),
        ],
      );
    }
    final h = tall ? 60.0 : 66.0;
    AnswerLook look(String c) {
      if (!answered) return AnswerLook.idle;
      if (q.kana.romaji == c) return AnswerLook.right;
      if (q.answer == c) return AnswerLook.wrong;
      return AnswerLook.dim;
    }

    Widget tile(int i) => AnswerTile(
      key: ValueKey<String>('nihongo.choice.$i'),
      label: q.choices[i],
      look: look(q.choices[i]),
      height: h,
      hint: tall ? null : '${i + 1}',
      onPressed: answered ? null : () => _answer(q.choices[i]),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: tile(0)),
            const SizedBox(width: 10),
            Expanded(child: tile(1)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: tile(2)),
            const SizedBox(width: 10),
            Expanded(child: tile(3)),
          ],
        ),
        // Solo tras fallar: acertar pasa sola.
        if (q.correct == false) ...[const SizedBox(height: 10), _nextButton(l)],
      ],
    );
  }

  Widget _nextButton(L l) => IbashoButton(
    key: const ValueKey<String>('nihongo.next'),
    label: l.nihongoNext,
    glyph: Glyph.arrowRight,
    tone: ButtonTone.accent,
    expand: true,
    onPressed: _next,
  );

  Widget _results() {
    final round = _round!;
    return NihongoResultsCard(
      round: round,
      newBest: _newBest,
      reward: _reward,
      rewardPending: _rewardPending,
      onAgain: () => _start(),
      onReview: round.missed.isEmpty ? null : () => _start(only: round.missed),
      onMenu: _toMenu,
    );
  }

  Widget _streakReadout(L l, double height) {
    final round = _round;
    return Readout(
      icon: GlyphIcon(Glyph.star, size: height * .5, color: IbashoSkin.of(context).accentDeep, strokeWidth: 2.2),
      value: '${round?.streak ?? 0}',
      label: l.nihongoStreakLabel,
      height: height,
    );
  }

  Widget _wideLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    final round = _round;
    Widget right;
    switch (_phase) {
      case _Phase.menu:
        right = Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _categories(l, height: 112, gap: 14),
                  const SizedBox(height: 22),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _setup(l, tall: false)),
                ],
              ),
            ),
          ),
        );
      case _Phase.quiz:
        right = LayoutBuilder(
          builder: (context, box) {
            final card = math.min(300.0, box.maxHeight - (round!.mode == AnswerMode.write ? 230 : 250));
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RoundDots(round: round),
                    const SizedBox(height: 18),
                    _card(card),
                    const SizedBox(height: 22),
                    _answers(l, tall: false),
                  ],
                ),
              ),
            );
          },
        );
      case _Phase.results:
        right = Center(child: SingleChildScrollView(child: _results()));
      case _Phase.chart:
        right = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                _chartPickers(l, tall: false),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(child: Center(child: _chart())),
                ),
              ],
            ),
          ),
        );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 330,
            child: Column(
              children: [
                Expanded(
                  child: StageLight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SpeechBubble(text: _bubble, maxWidth: 260),
                        const SizedBox(height: 6),
                        _stage(tama, 176),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                if (_phase == _Phase.quiz)
                  Row(
                    children: [
                      Expanded(
                        child: Readout(
                          icon: const ArtIconView(ArtIcon.nihongo, size: 30),
                          value: '${round!.index + 1}/${round.questions.length}',
                          label: _script == KanaScript.katakana ? l.nihongoKatakana : l.nihongoHiragana,
                          height: 58,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _streakReadout(l, 58)),
                    ],
                  )
                else
                  Readout(
                    icon: const ArtIconView(ArtIcon.medalGold, size: 30),
                    value: '${_records.perfects[_script.name] ?? 0}',
                    label: l.nihongoPerfectsLabel,
                    height: 58,
                  ),
                if (_phase == _Phase.quiz || _phase == _Phase.chart) ...[
                  const SizedBox(height: 12),
                  IbashoButton(
                    label: l.nihongoMenu,
                    glyph: Glyph.arrowLeft,
                    tone: ButtonTone.quiet,
                    expand: true,
                    cue: Sfx.back,
                    onPressed: _toMenu,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _tallLayout(BuildContext context, Tama? tama) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final small = layout.height < 700;
    final stageSize = small ? 64.0 : 92.0;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final round = _round;

    final strip = SizedBox(
      height: small ? 96 : 136,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: stageSize + 30,
            child: StageLight(
              child: Align(alignment: Alignment.bottomCenter, child: _stage(tama, stageSize)),
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
                    child: SpeechBubble(text: _bubble, maxWidth: 210),
                  ),
                ),
                if (_phase == _Phase.quiz && round != null) ...[
                  const SizedBox(height: 8),
                  FittedBox(child: RoundDots(round: round, dot: 12)),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    Widget body;
    switch (_phase) {
      case _Phase.menu:
        body = SingleChildScrollView(
          child: Column(
            children: [
              _categories(l, height: small ? 84 : 100, gap: 10, compact: layout.width < 400),
              SizedBox(height: small ? 12 : 18),
              _setup(l, tall: true),
            ],
          ),
        );
      case _Phase.quiz:
        body = LayoutBuilder(
          builder: (context, box) {
            final answersH = round!.mode == AnswerMode.write ? 150.0 : (round.current.correct == false ? 200.0 : 140.0);
            final card = math.max(90.0, math.min(300.0, box.maxHeight - answersH - 16));
            return Column(
              children: [
                Expanded(child: Center(child: _card(card))),
                const SizedBox(height: 12),
                _answers(l, tall: true),
              ],
            );
          },
        );
      case _Phase.results:
        body = Center(child: SingleChildScrollView(child: _results()));
      case _Phase.chart:
        body = Column(
          children: [
            _chartPickers(l, tall: true),
            SizedBox(height: small ? 8 : 12),
            Expanded(
              child: SingleChildScrollView(child: Center(child: _chart(gap: 6))),
            ),
            SizedBox(height: small ? 8 : 12),
            IbashoButton(
              key: const ValueKey<String>('nihongo.chart.back'),
              label: l.nihongoMenu,
              glyph: Glyph.arrowLeft,
              tone: ButtonTone.quiet,
              expand: true,
              cue: null,
              onPressed: _toMenu,
            ),
          ],
        );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Column(
        children: [
          SizedBox(height: small ? 6 : 12),
          if (keyboard == 0) strip,
          SizedBox(height: small ? 8 : 14),
          Expanded(child: body),
          SizedBox(height: small ? 10 : 16),
        ],
      ),
    );
  }
}
