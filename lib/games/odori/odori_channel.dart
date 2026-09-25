// Ibasho — canal de Odori: el selector de canciones, versiones, dificultad,
// teclas y modo, con los récords, el Tama que acompaña y el tema propio.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/shop.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/shop.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channel_route.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/widgets/backdrop_art.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/panel.dart';
import '../../ui/widgets/pressable.dart';
import '../game_stage.dart';
import 'odori_butai.dart';
import 'odori_catalog.dart';
import 'odori_chart.dart';
import 'odori_engine.dart';
import 'odori_keys.dart';
import 'odori_options.dart';
import 'odori_play.dart';
import 'odori_store.dart';
import 'odori_widgets.dart';

/// Lo que cuenta la cabecera de una partitura: pulsos por minuto y duracion.
typedef SongInfo = ({double bpm, double length});

final Map<String, SongInfo> _infoCache = <String, SongInfo>{};

/// Lee el bpm y la duracion de una version. Se guarda: son nueve archivos
/// pequeños y el selector los pide todos al abrir.
Future<SongInfo?> loadSongInfo(OdoriVersion v) async {
  final cached = _infoCache[v.id];
  if (cached != null) return cached;
  try {
    final raw = jsonDecode(await rootBundle.loadString(v.scoreAsset, cache: false)) as Map;
    return _infoCache[v.id] = (
      bpm: (raw['bpm'] as num).toDouble(),
      length: (raw['length'] as num?)?.toDouble() ?? 0,
    );
  } catch (e) {
    debugPrint('Ibasho: sin cabecera para ${v.id} ($e)');
    return null;
  }
}

/// La ayuda del Tama segun su personalidad.
OdoriAssist assistFor(TamaPersonality p) => switch (p) {
      TamaPersonality.calm => OdoriAssist.wide,
      TamaPersonality.playful => OdoriAssist.shield,
      TamaPersonality.shy => OdoriAssist.noEarly,
      TamaPersonality.cheeky => OdoriAssist.rescue,
      TamaPersonality.sleepy => OdoriAssist.lateWide,
    };

String assistText(L l, OdoriAssist a) => switch (a) {
      OdoriAssist.wide => l.odoriHelpCalm,
      OdoriAssist.shield => l.odoriHelpPlayful,
      OdoriAssist.noEarly => l.odoriHelpShy,
      OdoriAssist.rescue => l.odoriHelpCheeky,
      OdoriAssist.lateWide => l.odoriHelpSleepy,
    };

/// «JA · Kasane Teto», o «instrumental».
String versionLabel(L l, OdoriVersion v) =>
    v.instrumental
        ? l.odoriInstrumental
        : '${v.lang!.toUpperCase()} · ${v.singerName}${v.singer == 'sinsy_b' ? ' B' : ''}';

String _clockText(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// El tema propio de Odori: mientras el canal esta abierto, el fondo del
/// juego sustituye al del menu en toda la app (materiales, tinta y acento).
///
/// Como tiñe la app entera, cambia en cuanto empieza a abrirse el canal (con
/// el ultimo tema conocido, sin esperar a leer las preferencias) y se quita en
/// cuanto empieza a cerrarse, no al acabar la animacion.
mixin OdoriTheme<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// El tema de la ultima vez; `(false, _)` si aun no se ha leido nunca.
  static (bool, String?) _last = (false, null);

  StateController<String?>? _themeCtl;
  Animation<double>? _route;
  bool _closing = false;

  StateController<String?> get _ctl => _themeCtl ??= ref.read(gameThemeProvider.notifier)!;

  /// Pone el tema sin esperar si se puede; durante un build, al acabarlo.
  void _set(String? id) {
    final ctl = _ctl;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle ||
        SchedulerBinding.instance.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      if (ctl.mounted) ctl.state = id;
      return;
    }
    // Riverpod no deja cambiar un proveedor mientras se construye el arbol.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctl.mounted) ctl.state = id;
    });
  }

  @override
  void initState() {
    super.initState();
    final (known, id) = _last;
    if (known) _set(id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == _route) return;
    _route?.removeStatusListener(_onRoute);
    _route = route?..addStatusListener(_onRoute);
  }

  void _onRoute(AnimationStatus status) {
    if (status != AnimationStatus.reverse || _closing) return;
    _closing = true;
    _set(null);
  }

  void applyOdoriTheme(String? id) {
    _last = (true, id);
    if (!_closing) _set(id);
  }

  void dropOdoriTheme() {
    _route?.removeStatusListener(_onRoute);
    if (_themeCtl == null) return;
    _set(null);
  }
}

class OdoriChannel extends ConsumerStatefulWidget {
  const OdoriChannel({super.key});

  @override
  ConsumerState<OdoriChannel> createState() => _OdoriChannelState();
}

class _OdoriChannelState extends ConsumerState<OdoriChannel> with OdoriTheme {
  List<OdoriSong>? _songs;
  OdoriStore? _store;
  final Map<String, SongInfo> _info = <String, SongInfo>{};
  bool _failed = false;

  OdoriPrefs get _prefs => _store!.data.prefs;

  /// Mientras se juega o se miran las opciones, la instrumental calla.
  bool _away = false;

  @override
  void initState() {
    super.initState();
    unawaited(AudioService.instance.hushMusic());
    unawaited(_load());
  }

  @override
  void dispose() {
    dropOdoriTheme();
    unawaited(AudioService.instance.stopOdoriPreview());
    unawaited(AudioService.instance.unhushMusic());
    super.dispose();
  }

  /// En el menu suena en bucle la instrumental de la cancion elegida.
  void _preview() {
    if (_away || _songs == null) return;
    final song = _song;
    final inst = song.versions.where((v) => v.instrumental).firstOrNull ?? song.versions.first;
    unawaited(AudioService.instance.playOdoriPreview(inst.audioAsset));
  }

  /// Abre una pagina encima (partida u opciones) con la instrumental parada.
  Future<void> _awayFor(Future<void> Function() page) async {
    _away = true;
    await AudioService.instance.stopOdoriPreview();
    await page();
    _away = false;
    if (mounted) _preview();
  }

  Future<void> _load() async {
    try {
      final (songs, store) = (await loadOdoriSongs(), await OdoriStore.open());
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _store = store;
      });
      applyOdoriTheme(store.data.prefs.themeId);
      _preview();
      for (final s in songs) {
        for (final v in s.versions) {
          final info = await loadSongInfo(v);
          if (!mounted) return;
          if (info != null) setState(() => _info[v.id] = info);
        }
      }
    } catch (e) {
      debugPrint('Ibasho: Odori no ha podido abrir ($e)');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _update(OdoriPrefs Function(OdoriPrefs p) change) {
    final store = _store;
    if (store == null) return;
    final before = store.data.prefs.themeId;
    setState(() => store.data.prefs = change(store.data.prefs));
    if (store.data.prefs.themeId != before) applyOdoriTheme(store.data.prefs.themeId);
    unawaited(store.save());
  }

  OdoriSong get _song {
    final songs = _songs!;
    return songs.where((s) => s.id == _prefs.songId).firstOrNull ?? songs.first;
  }

  OdoriVersion get _version {
    final song = _song;
    return song.versions.where((v) => v.id == _prefs.versionId).firstOrNull ?? song.versions.first;
  }

  Tama? _tama(List<Tama> tamas) {
    if (tamas.isEmpty) return null;
    return tamas.where((t) => t.id == _prefs.tamaId).firstOrNull ?? tamas.first;
  }

  void _pickSong(OdoriSong s) {
    if (s.id == _song.id) return;
    AudioService.instance.play(Sfx.tick);
    // Se queda con la misma voz si la cancion nueva la tiene.
    final same = s.versions.where((v) => v.lang == _version.lang && v.singer == _version.singer).firstOrNull;
    _update((p) => p.copyWith(songId: s.id, versionId: (same ?? s.versions.first).id));
    _preview();
  }

  /// Compra la cancion [s] en el Yatai sin salir de Odori, tras confirmar.
  Future<void> _buy(OdoriSong s) async {
    final l = L.of(context)!;
    final item = shopCatalog.where((i) => i.odoriSong == s.id).firstOrNull;
    if (item == null) return;
    final price = ref.read(shopProvider).prices[item.id];
    if (price == null) {
      showIbashoToast(context, l.yataiErrorNoPrice, isError: true);
      return;
    }
    final ok = await showIbashoModal<bool>(
      context,
      (context) => IbashoDialog(
        title: l.odoriBuyTitle(s.title),
        width: 360,
        body: Text(l.odoriBuyBody(price), style: Ty.body),
        actions: [
          IbashoButton(
            label: l.actionCancel,
            tone: ButtonTone.quiet,
            cue: Sfx.back,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IbashoButton(
            key: const ValueKey<String>('odori.buy.confirm'),
            label: l.yataiBuy,
            tone: ButtonTone.accent,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(shopProvider.notifier).buy(item, 1);
      if (!mounted) return;
      AudioService.instance.play(Sfx.chime);
      showIbashoToast(context, l.odoriBought(s.title));
    } on ShopException catch (e) {
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      showIbashoToast(
        context,
        e.failure == ShopFailure.insufficientCoins ? l.yataiErrorInsufficientCoins : l.yataiErrorRejected,
        isError: true,
      );
    }
  }

  Future<void> _play(Tama? tama) async {
    final assist = tama != null && _prefs.assist ? assistFor(tama.personality) : null;
    final p = _prefs;
    final keys = p.mode == OdoriMode.butai ? butaiKeys : p.keys;
    await _awayFor(() => pushChannelPage<void>(
      context,
      (_) => OdoriPlayScreen(
        store: _store,
        setup: OdoriSetup(
          song: _song,
          version: _version,
          keys: keys,
          difficulty: p.difficulty,
          mode: p.mode,
          butaiMark: p.butaiMark,
          butaiTouch: p.butaiTouch,
          hitVolume: p.hitVolume,
          flow: p.flow,
          look: p.look,
          approach: p.approach,
          offsetMs: p.offsetMs,
          keyMap: p.keysFor(keys),
          altKeys: p.mode == OdoriMode.butai && p.butaiDouble ? p.butaiAlt : null,
          tama: tama,
          assist: assist,
        ),
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _options() async {
    final store = _store;
    if (store == null) return;
    await _awayFor(() => pushChannelPage<void>(
      context,
      (_) => OdoriOptionsPage(
        prefs: store.data.prefs,
        onChanged: (p) => _update((_) => p),
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final backdrop = ref.watch(backdropIdProvider);
    final Widget body;
    if (_failed) {
      body = Center(child: Text(l.odoriLoadFailed, style: Ty.lead));
    } else if (_songs == null || _store == null) {
      body = Center(child: Text(l.odoriLoading, style: Ty.lead));
    } else if (layout.tall) {
      body = _tallLayout(context, layout, ref.watch(shopProvider));
    } else {
      body = _wideLayout(context, layout, ref.watch(shopProvider));
    }
    return Stack(
      children: [
        if (backdrop.isNotEmpty) Positioned.fill(child: RepaintBoundary(child: BackdropView(id: backdrop))),
        ChannelScaffold(
          title: l.channelOdori,
          glyph: Glyph.note,
          art: ArtIcon.odori,
          trailing: _store == null
              ? null
              : IconPill(
                  key: const ValueKey<String>('odori.options'),
                  glyph: Glyph.gear,
                  semanticLabel: l.odoriOptions,
                  onPressed: _options,
                ),
          child: body,
        ),
      ],
    );
  }

  Widget _wideLayout(BuildContext context, Layout layout, ShopState shop) => Padding(
        padding: EdgeInsets.fromLTRB(layout.gutter, 4, layout.gutter, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 340,
              child: Column(
                children: [
                  const DailyCoinsMeter(game: 'odori', height: 42),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GlossSurface(
                radius: 26,
                recessed: true,
                padding: const EdgeInsets.all(8),
                child: IbashoScroll(
                  child: Column(
                    children: [
                      for (final s in _songs!) ...[
                        _SongTile(
                          song: s,
                          owned: shop.hasOdoriSong(s.id),
                          info: _info[s.versions.first.id],
                          selected: s.id == _song.id,
                          played: {
                            for (final d in OdoriDifficulty.values)
                              if (_playedAny(s, d)) d,
                          },
                          onPressed: () => _pickSong(s),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),
                  ),
                ],
              ),
            ),
            SizedBox(width: layout.gap),
            Expanded(child: IbashoScroll(child: _detail(context, layout))),
          ],
        ),
      );

  Widget _tallLayout(BuildContext context, Layout layout, ShopState shop) => IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DailyCoinsMeter(game: 'odori', height: 40),
            const SizedBox(height: 10),
            SizedBox(
              height: 108,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in _songs!)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 220,
                        child: _SongTile(
                          song: s,
                          owned: shop.hasOdoriSong(s.id),
                          info: _info[s.versions.first.id],
                          selected: s.id == _song.id,
                          played: {
                            for (final d in OdoriDifficulty.values)
                              if (_playedAny(s, d)) d,
                          },
                          onPressed: () => _pickSong(s),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _detail(context, layout),
          ],
        ),
      );

  bool _playedAny(OdoriSong s, OdoriDifficulty d) {
    final records = _store!.data.records;
    for (final assisted in const [false, true]) {
      for (var k = odoriMinKeys; k <= odoriMaxKeys; k++) {
        if (records.containsKey(odoriRecordKey(s.id, d, k, assisted: assisted))) return true;
      }
      if (records.containsKey(odoriRecordKey(s.id, d, butaiKeys, assisted: assisted, mode: OdoriMode.butai))) {
        return true;
      }
    }
    return false;
  }

  static const List<String> _singerOrder = ['teto', 'kiritan', 'zundamon', 'merrow', 'sinsy'];

  /// Quien canta esta cancion: `null` es la instrumental, que va primero.
  List<String?> _singers(OdoriSong song) {
    final found = {for (final v in song.versions) v.singer};
    int rank(String? s) => s == null ? -1 : (_singerOrder.contains(s) ? _singerOrder.indexOf(s) : 99);
    return found.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  List<String> _langsOf(OdoriSong song, String? singer) => [
        for (final lang in const ['ja', 'es', 'en'])
          if (song.versions.any((v) => v.singer == singer && v.lang == lang)) lang,
      ];

  void _pickVersion(OdoriVersion v) {
    if (v.id == _version.id) return;
    _update((p) => p.copyWith(versionId: v.id));
  }

  /// Cambia de cantante y se queda con el idioma si lo canta.
  void _pickSinger(OdoriSong song, String? singer) {
    final options = song.versions.where((v) => v.singer == singer).toList();
    if (options.isEmpty) return;
    _pickVersion(options.where((v) => v.lang == _version.lang).firstOrNull ?? options.first);
  }

  Widget _detail(BuildContext context, Layout layout) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final song = _song;
    final version = _version;
    final p = _prefs;
    final info = _info[version.id];
    final tamas = ref.watch(tamasProvider).tamas;
    final tama = _tama(tamas);
    final assisted = tama != null && p.assist;
    final data = _store!.data;
    final butai = p.mode == OdoriMode.butai;
    final best = data.bestOf(version.songId, p.difficulty, p.keys, assisted: assisted, mode: p.mode);
    final shop = ref.watch(shopProvider);
    final owned = shop.hasOdoriSong(song.id);
    final price = shop.prices[ShopItem.idForOdoriSong(song.id)];

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
          child: Text(text, style: Ty.label.copyWith(color: Ty.inkSoft)),
        );

    return GlossSurface(
      radius: 28,
      padding: EdgeInsets.fromLTRB(layout.pick(26, 18), 20, layout.pick(26, 18), 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title, style: Ty.title.copyWith(color: skin.accentDeep)),
                    if (song.native.isNotEmpty) Text(song.native, style: Ty.lead.copyWith(color: Ty.inkSoft)),
                    const SizedBox(height: 4),
                    Text(song.authorOf(version), style: Ty.body.copyWith(fontWeight: FontWeight.w600)),
                    if (info != null)
                      Text('${info.bpm.round()} bpm · ${_clockText(info.length)}', style: Ty.caption),
                  ],
                ),
              ),
              _RecordBox(best: best),
            ],
          ),
          heading(l.odoriVersion),
          // Primero quien canta (o la instrumental) y, si canta, en que
          // idioma: solo lo que existe de esta cancion.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final singer in _singers(song))
                SizedBox(
                  width: 170,
                  child: SegmentPill(
                    key: ValueKey<String>('odori.singer.${singer ?? 'none'}'),
                    label: singer == null ? l.odoriInstrumental : (OdoriVersion.singerNames[singer] ?? singer),
                    selected: singer == version.singer,
                    height: 40,
                    onPressed: () => _pickSinger(song, singer),
                  ),
                ),
            ],
          ),
          if (!version.instrumental) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 90.0 * _langsOf(song, version.singer).length + 8,
              child: SegmentRail(
                height: 38,
                children: [
                  for (final lang in _langsOf(song, version.singer))
                    SegmentPill(
                      key: ValueKey<String>('odori.lang.$lang'),
                      label: lang.toUpperCase(),
                      height: 38,
                      selected: lang == version.lang,
                      onPressed: () => _pickVersion(
                        song.versions.firstWhere((v) => v.singer == version.singer && v.lang == lang),
                      ),
                    ),
                ],
              ),
            ),
          ],
          heading(l.odoriDifficulty),
          Row(
            children: [
              for (final d in OdoriDifficulty.values) ...[
                if (d.index > 0) const SizedBox(width: 6),
                Expanded(
                  child: _DifficultyPill(
                    difficulty: d,
                    selected: d == p.difficulty,
                    best: data.bestOf(version.songId, d, p.keys, assisted: assisted, mode: p.mode),
                    onPressed: () => _update((p) => p.copyWith(difficulty: d)),
                  ),
                ),
              ],
            ],
          ),
          heading(l.odoriMode),
          SegmentRail(
            children: [
              SegmentPill(
                key: const ValueKey<String>('odori.mode.taki'),
                label: l.odoriTaki,
                caption: l.odoriTakiHint,
                selected: !butai,
                onPressed: () => _update((p) => p.copyWith(mode: OdoriMode.taki)),
              ),
              SegmentPill(
                key: const ValueKey<String>('odori.mode.butai'),
                label: l.odoriButai,
                caption: l.odoriButaiHint,
                selected: butai,
                onPressed: () => _update((p) => p.copyWith(mode: OdoriMode.butai)),
              ),
            ],
          ),
          heading(l.odoriKeys),
          // Butai va siempre con cuatro: en vez de elegir, se ve que flecha
          // lleva cada tecla.
          if (butai)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentRail(
                  height: 36,
                  children: [
                    for (final m in ButaiMark.values)
                      SegmentPill(
                        key: ValueKey<String>('odori.mark.${m.name}'),
                        label: switch (m) {
                          ButaiMark.arrows => l.odoriMarkArrows,
                          ButaiMark.shapes => l.odoriMarkShapes,
                          ButaiMark.keys => l.odoriMarkKeys,
                        },
                        height: 36,
                        selected: m == p.butaiMark,
                        onPressed: () => _update((p) => p.copyWith(butaiMark: m)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Una o dos teclas por figura, como los mandos de Diva.
                SegmentRail(
                  height: 36,
                  children: [
                    for (final (two, label) in [(false, l.odoriButaiSingle), (true, l.odoriButaiDouble)])
                      SegmentPill(
                        key: ValueKey<String>('odori.double.$two'),
                        label: label,
                        height: 36,
                        selected: p.butaiDouble == two,
                        onPressed: () => _update((p) => p.copyWith(butaiDouble: two)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  runSpacing: 6,
                  children: [
                    for (var j = 0; j < butaiKeys; j++)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ButaiSymbol(
                              lane: j,
                              size: 34,
                              mark: p.butaiMark,
                              caps: [for (final k in p.keysFor(butaiKeys)) keyCap(k)],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              p.butaiDouble
                                  ? '${keyCap(p.keysFor(butaiKeys)[j])} · ${keyCap(p.butaiAlt[j])}'
                                  : keyCap(p.keysFor(butaiKeys)[j]),
                              key: ValueKey<String>('odori.butaiKey.$j'),
                              style: Ty.body.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(l.odoriButaiKeys, style: Ty.caption),
              ],
            )
          else
            SegmentRail(
              height: 40,
              children: [
                for (var k = odoriMinKeys; k <= odoriMaxKeys; k++)
                  SegmentPill(
                    key: ValueKey<String>('odori.keys.$k'),
                    label: '$k',
                    height: 40,
                    selected: k == p.keys,
                    onPressed: () => _update((p) => p.copyWith(keys: k)),
                  ),
              ],
            ),
          heading(l.odoriTama),
          _TamaRow(
            tamas: tamas,
            selected: tama,
            assist: p.assist,
            onPick: (t) => _update((p) => p.copyWith(tamaId: () => t.id)),
            onAssist: (v) => _update((p) => p.copyWith(assist: v)),
          ),
          const SizedBox(height: 18),
          if (owned)
            IbashoButton(
              key: const ValueKey<String>('odori.play'),
              label: l.odoriPlay,
              glyph: Glyph.play,
              tone: ButtonTone.accent,
              expand: true,
              height: 54,
              cue: null,
              onPressed: () => _play(tama),
            )
          else
            IbashoButton(
              key: const ValueKey<String>('odori.buy'),
              label: price == null ? l.yataiPriceNotAvailable : l.odoriBuy(price),
              glyph: Glyph.coin,
              tone: ButtonTone.accent,
              expand: true,
              height: 54,
              onPressed: price == null || shop.busy ? null : () => unawaited(_buy(song)),
            ),
        ],
      ),
    );
  }
}

/// Una cancion de la lista: titulo, en japones, bpm y un punto por
/// dificultad, lleno si ya se ha jugado.
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.owned,
    required this.info,
    required this.selected,
    required this.played,
    required this.onPressed,
  });

  final OdoriSong song;

  /// Gratis o comprada. Si no, lleva candado.
  final bool owned;
  final SongInfo? info;
  final bool selected;
  final Set<OdoriDifficulty> played;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final voices = song.versions.where((v) => !v.instrumental).length;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: song.title,
      builder: (context, state) => GlossSurface(
        key: ValueKey<String>('odori.song.${song.id}'),
        radius: 20,
        tint: selected ? skin.accentWash : null,
        borderColor: selected ? skin.accentDeep : null,
        borderWidth: selected ? 1.6 : 1,
        elevation: selected ? 1.4 : (state.hover > 0 ? .9 : .4),
        specular: selected || state.hover > 0 ? 1 : .4,
        sink: state.press,
        padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.lead.copyWith(color: selected ? skin.accentDeep : Ty.ink),
                  ),
                ),
                const SizedBox(width: 8),
                Text(song.native, maxLines: 1, style: Ty.caption),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (info != null) '${info!.bpm.round()} bpm',
                      if (voices > 0) '♪ $voices',
                    ].join(' · '),
                    style: Ty.caption,
                  ),
                ),
                if (!owned)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GlyphIcon(Glyph.lock, size: 14, color: Ty.inkSoft, strokeWidth: 2.2),
                  ),
                for (final d in OdoriDifficulty.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: played.contains(d) ? d.color : null,
                        border: Border.all(color: d.color, width: 1.6),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Una dificultad: su nombre en su color y el mejor rango debajo.
class _DifficultyPill extends StatelessWidget {
  const _DifficultyPill({
    required this.difficulty,
    required this.selected,
    required this.best,
    required this.onPressed,
  });

  final OdoriDifficulty difficulty;
  final bool selected;
  final OdoriBest? best;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = difficulty.color;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: difficulty.label,
      builder: (context, state) => GlossSurface(
        key: ValueKey<String>('odori.difficulty.${difficulty.name}'),
        radius: 18,
        tint: selected ? c : null,
        borderColor: c,
        borderWidth: selected ? 2 : 1.4,
        elevation: selected ? 1.6 : (state.hover > 0 ? .8 : .2),
        specular: 1,
        sink: state.press,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                difficulty.label,
                maxLines: 1,
                style: Ty.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFFFFFFFF) : Color.lerp(c, const Color(0xFF000000), .15),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              best?.rank.label ?? '—',
              style: Ty.numeral(
                16,
                color: selected
                    ? const Color(0xFFFFFFFF)
                    : best == null
                        ? Ty.inkSoft
                        : rankColor(best!.rank),
                weight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El récord de lo elegido: rango, puntos y precision.
class _RecordBox extends StatelessWidget {
  const _RecordBox({required this.best});

  final OdoriBest? best;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final b = best;
    return GlossSurface(
      key: const ValueKey<String>('odori.record'),
      radius: 20,
      recessed: true,
      padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
      child: b == null
          ? Text(l.odoriNoRecord, style: Ty.caption)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RankBadge(rank: b.rank, size: 46),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.odoriRecord, style: Ty.micro),
                    Text('${b.score}', style: Ty.numeral(22, color: Ty.ink, weight: FontWeight.w700)),
                    Text(
                      '${(b.accuracy * 100).toStringAsFixed(2)} %',
                      style: Ty.caption.copyWith(color: skin.accentDeep),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Los Tamas de la cuenta, para elegir quien acompaña, y el interruptor de
/// su ayuda con lo que hace segun su personalidad.
class _TamaRow extends StatelessWidget {
  const _TamaRow({
    required this.tamas,
    required this.selected,
    required this.assist,
    required this.onPick,
    required this.onAssist,
  });

  final List<Tama> tamas;
  final Tama? selected;
  final bool assist;
  final ValueChanged<Tama> onPick;
  final ValueChanged<bool> onAssist;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tama = selected;
    if (tama == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(l.odoriNoTamas, style: Ty.caption),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in tamas)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Pressable(
                    onPressed: () => onPick(t),
                    semanticLabel: t.name,
                    builder: (context, state) => GlossSurface(
                      key: ValueKey<String>('odori.tama.${t.id}'),
                      radius: 18,
                      tint: t.id == tama.id ? skin.accentWash : null,
                      borderColor: t.id == tama.id ? skin.accentDeep : null,
                      borderWidth: t.id == tama.id ? 1.6 : 1,
                      elevation: t.id == tama.id ? 1.2 : .3,
                      sink: state.press,
                      padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                      child: SizedBox(
                        width: 64,
                        child: Column(
                          children: [
                            TamaView(
                              look: t.look,
                              personality: t.personality,
                              name: t.name,
                              voice: t.voice,
                              seed: t.id.hashCode,
                              size: 50,
                              interactive: false,
                              shadow: false,
                            ),
                            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IbashoToggle(
              key: const ValueKey<String>('odori.assist'),
              value: assist,
              onChanged: onAssist,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.odoriAssist}: ${assistText(l, assistFor(tama.personality))}',
                    style: Ty.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(l.odoriAssistHint, style: Ty.caption),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
