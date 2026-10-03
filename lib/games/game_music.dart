// Ibasho — la cancion de cada juego, que se desbloquea al oirla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_service.dart';
import '../backend/gacha_music.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/koro.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';
import '../ui/layout.dart';
import '../ui/track_text.dart';
import '../ui/widgets/controls.dart';
import '../ui/widgets/glyphs.dart';
import '../ui/widgets/overlays.dart';
import '../ui/widgets/track_tile.dart';
import 'tamakoro/koro_widgets.dart';

/// Pone [track] en lugar de la musica de ambiente mientras el juego esta
/// abierto, con el mismo fundido que la musica de un perfil, y la anade a la
/// biblioteca de la cuenta la primera vez: a partir de ahi se puede elegir
/// para el menu, para el perfil o para otro juego.
///
/// Si [track] cambia sin desmontarse (Nihongo tiene una para el menu y otra
/// para jugar), pasa a la nueva con el mismo fundido y la desbloquea tambien.
///
/// Con [GameMusic.cycle] suenan varias pistas por turnos (Hatarakitama): cada
/// una entera y luego la siguiente. Se desbloquea cada una al empezar a sonar.
///
/// Sin [track] ni ronda, el juego no trae cancion y sigue la del menu.
///
/// Desde la 0.9.0 la cuenta puede elegir otra para cada juego
/// (`music/games/{gameId}`): una pista de la biblioteca o una cancion de
/// Tamakoro. Manda sobre la de serie; el boton ♪ de la cabecera
/// ([ChannelScaffold]) abre el selector.
class GameMusic extends ConsumerStatefulWidget {
  const GameMusic({super.key, required this.gameId, this.track, required this.child})
      : cycle = const [];

  GameMusic.cycle({super.key, required this.gameId, required this.cycle, required this.child})
      : track = cycle.first;

  /// El mismo id que en `/users/{cuenta}/games` y en las clasificaciones.
  final String gameId;
  final MusicTrack? track;
  final List<MusicTrack> cycle;
  final Widget child;

  @override
  ConsumerState<GameMusic> createState() => _GameMusicState();
}

class _GameMusicState extends ConsumerState<GameMusic> {
  /// La eleccion de la cuenta para este juego, o `null` si suena la de serie.
  String? _choice;

  /// Sube con cada cambio: un render de Tamakoro que acaba tarde no pisa lo
  /// que se haya elegido despues.
  int _job = 0;

  @override
  void initState() {
    super.initState();
    AudioService.instance.guestTrack.addListener(_onGuest);
    _choice = ref.read(musicLibraryProvider).gameTracks[widget.gameId];
    ref.listenManual(musicLibraryProvider.select((m) => m.gameTracks[widget.gameId]), (_, next) {
      _choice = next;
      _apply();
    });
    // Una cancion de Tamakoro necesita las canciones y las voces del coro.
    ref.listenManual(koroProvider.select((k) => k.loaded), (_, _) => _applyKoroAgain());
    ref.listenManual(tamasProvider.select((t) => t.loaded), (_, _) => _applyKoroAgain());
    _apply();
  }

  /// Puede pasar de una ronda a una pista fija y al revés (en Hatarakitama
  /// se elige): sin desmontarse, con el mismo fundido.
  @override
  void didUpdateWidget(GameMusic old) {
    super.didUpdateWidget(old);
    if (_resolvedChoice() != null) return;
    if (widget.cycle.isNotEmpty) {
      if (!listEquals(old.cycle, widget.cycle)) _apply();
    } else if (old.track != widget.track || old.cycle.isNotEmpty) {
      _apply();
    }
  }

  /// La eleccion, si aun se puede usar: una pista que exista o un hueco de
  /// Tamakoro.
  String? _resolvedChoice() {
    final choice = _choice;
    if (choice == null) return null;
    if (koroSlotOfTrack(choice) != null) return choice;
    return MusicTrack.values.any((t) => t.id == choice) ? choice : null;
  }

  void _applyKoroAgain() {
    if (koroSlotOfTrack(_choice) != null) _apply();
  }

  void _apply() {
    _job++;
    final choice = _resolvedChoice();
    final slot = koroSlotOfTrack(choice);
    if (slot != null) {
      unawaited(_playKoro(slot, _job));
    } else if (choice != null) {
      _play(MusicTrack.values.firstWhere((t) => t.id == choice));
    } else if (widget.cycle.isNotEmpty) {
      _playCycle(widget.cycle);
    } else if (widget.track case final track?) {
      _play(track);
    } else {
      unawaited(AudioService.instance.endProfileTrack());
    }
  }

  Future<void> _playKoro(int slot, int job) async {
    final koro = ref.read(koroProvider);
    final tamas = ref.read(tamasProvider);
    final song = koro.songs[slot];
    if (song == null) {
      // Aun sin cargar: se espera. Borrada: la de serie.
      if (!koro.loaded) return;
      _choice = null;
      _apply();
      return;
    }
    if (!tamas.loaded) return;
    final path = await renderKoroGameMusic(song, tamas.tamas);
    if (!mounted || job != _job || path == null) return;
    unawaited(AudioService.instance.playProfileFile(path));
  }

  void _playCycle(List<MusicTrack> cycle) {
    unawaited(AudioService.instance.playProfileCycle(cycle));
    _unlock(cycle.first);
  }

  /// En una ronda, cada pista se desbloquea cuando le toca sonar.
  void _onGuest() {
    final track = AudioService.instance.guestTrack.value;
    if (track != null && widget.cycle.contains(track)) _unlock(track);
  }

  void _play(MusicTrack track) {
    unawaited(AudioService.instance.playProfileTrack(track));
    _unlock(track);
  }

  void _unlock(MusicTrack track) {
    // Se lee despues del cuadro: tocar un provider durante el montaje o la
    // reconstruccion lo marca como sucio a mitad de construccion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(musicLibraryProvider).loaded) {
        unawaited(ref.read(musicLibraryProvider.notifier).markHeard(track));
      } else {
        // Sin la biblioteca cargada no se sabe si ya estaba: se espera a ella.
        // El controlador se lee al cargar: con la sesion cambia por otro.
        ref.listenManual(musicLibraryProvider.select((m) => m.loaded), (_, loaded) {
          if (loaded && mounted) unawaited(ref.read(musicLibraryProvider.notifier).markHeard(track));
        });
      }
    });
  }

  @override
  void dispose() {
    _job++;
    AudioService.instance.guestTrack.removeListener(_onGuest);
    unawaited(AudioService.instance.endProfileTrack());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GameMusicScope(
        gameId: widget.gameId,
        defaults: widget.cycle.isNotEmpty
            ? widget.cycle
            : [?widget.track],
        child: widget.child,
      );
}

/// Lo que [ChannelScaffold] necesita para poner el boton ♪ en la cabecera de
/// un juego.
class GameMusicScope extends InheritedWidget {
  const GameMusicScope({
    super.key,
    required this.gameId,
    required this.defaults,
    required super.child,
  });

  final String gameId;

  /// Lo que trae el juego de serie: vacio si sigue la musica del menu.
  final List<MusicTrack> defaults;

  static GameMusicScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameMusicScope>();

  @override
  bool updateShouldNotify(GameMusicScope old) =>
      gameId != old.gameId || !listEquals(defaults, old.defaults);
}

/// El boton ♪ de la cabecera de un juego.
class GameMusicButton extends StatelessWidget {
  const GameMusicButton({super.key, required this.scope});

  final GameMusicScope scope;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IconPill(
      key: const ValueKey<String>('game.music'),
      glyph: Glyph.note,
      semanticLabel: l.gameMusic,
      onPressed: () => unawaited(showIbashoModal<void>(
        context,
        (_) => GameMusicDialog(gameId: scope.gameId, defaults: scope.defaults),
      )),
    );
  }
}

/// Elegir lo que suena en un juego: la de serie, una cancion de Tamakoro o
/// cualquier pista de la biblioteca. Cambia al momento, sin cerrar.
class GameMusicDialog extends ConsumerWidget {
  const GameMusicDialog({super.key, required this.gameId, required this.defaults});

  final String gameId;
  final List<MusicTrack> defaults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final library = ref.watch(musicLibraryProvider);
    final gacha = ref.watch(gachaProvider);
    final koro = ref.watch(koroProvider);
    final profile = ref.watch(profileProvider.select((p) => p.profile));
    final owner = profile == null
        ? ''
        : profile.displayName.isNotEmpty
            ? profile.displayName
            : profile.username;
    final notifier = ref.read(musicLibraryProvider.notifier);
    final current = library.gameTracks[gameId];

    // Como en el menu: tambien cuentan los premios del gacha ya ganados.
    bool unlocked(MusicTrack track) {
      if (library.isUnlocked(track)) return true;
      final prize = gachaMusicById(track.id);
      return prize != null && gacha.owns(prize.key);
    }

    final tracks = MusicTrack.values.where(unlocked).toList(growable: false);
    final songs = koro.songs.entries.where((e) => !e.value.isBlank).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final playing = Text(
      l.musicPlaying,
      style: Ty.caption.copyWith(color: T.onAccent, fontWeight: FontWeight.w500),
    );

    void choose(String? id) {
      AudioService.instance.play(Sfx.tick);
      unawaited(notifier.selectGameTrack(gameId, id));
    }

    final String defaultsText;
    if (defaults.isEmpty) {
      defaultsText = l.gameMusicDefaultMenu;
    } else if (defaults.length > 1) {
      defaultsText = l.hatarakiMusicCycle;
    } else {
      defaultsText = describeTrack(l, defaults.first);
    }

    return IbashoDialog(
      title: l.gameMusic,
      width: 480,
      body: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: layout.height * .55),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 10),
                child: Text(l.gameMusicHint, style: Ty.caption),
              ),
              TrackTile(
                key: const ValueKey<String>('game.music.default'),
                title: l.gameMusicDefault,
                subtitle: defaultsText,
                selected: current == null,
                onPressed: () => choose(null),
                trailing: current == null ? playing : null,
              ),
              if (songs.isNotEmpty) const SizedBox(height: 12),
              for (final entry in songs)
                TrackTile(
                  key: ValueKey<String>('game.music.$koroTrackPrefix${entry.key}'),
                  title: koroTitle(l, entry.value, owner),
                  subtitle: l.koroSongFacts(entry.value.tempo, koroScaleName(l, entry.value.scale)),
                  selected: current == '$koroTrackPrefix${entry.key}',
                  onPressed: () => choose('$koroTrackPrefix${entry.key}'),
                  trailing: current == '$koroTrackPrefix${entry.key}' ? playing : null,
                ),
              const SizedBox(height: 12),
              for (final track in tracks)
                TrackTile(
                  key: ValueKey<String>('game.music.${track.id}'),
                  title: track.id,
                  subtitle: describeTrack(l, track),
                  selected: current == track.id,
                  onPressed: () async {
                    // Ganada en el gacha y nunca escuchada: se marca antes.
                    if (!library.isUnlocked(track)) await notifier.markHeard(track);
                    choose(track.id);
                  },
                  trailing: current == track.id ? playing : null,
                ),
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 10),
                child: Text(
                  l.settingsMenuMusicPending(MusicTrack.values.length - tracks.length),
                  style: Ty.micro,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IbashoButton(
          key: const ValueKey<String>('game.music.ok'),
          label: l.hatarakiAwayOk,
          tone: ButtonTone.accent,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
