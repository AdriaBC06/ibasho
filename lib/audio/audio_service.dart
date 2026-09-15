// Ibasho — musica de fondo y efectos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter/foundation.dart';

/// Los cinco efectos del entorno.
enum Sfx {
  /// Al desplazarse entre canales y al pulsar un control.
  tick('audio/sfx/tick.wav'),

  /// Confirmacion al abrir un canal.
  open('audio/sfx/open.wav'),

  /// Vuelta atras, mas grave.
  back('audio/sfx/back.wav'),

  /// Aviso de error.
  error('audio/sfx/error.wav'),

  /// Campanilla de arranque.
  chime('audio/sfx/chime.wav');

  const Sfx(this.asset);

  final String asset;
}

/// Pistas de musica de fondo.
///
/// Las de Ibasho son originales (CC0, `tool/gen_audio.py`). Las demas vienen
/// de OpenGameArt con licencia CC0 o CC BY, verificada en su pagina; autoria,
/// licencia y enlace estan en `CREDITS.md` y en la pantalla de creditos.
enum MusicTrack {
  // Con ritmo. Se desbloquean al escucharlas en las apps que las usan.
  plaza('plaza', 'audio/bgm/plaza.ogg', 'Adrià Bonnin Catalán', 'CC0'),
  bossa('bossa', 'audio/bgm/bossa.ogg', 'Joth', 'CC0'),

  // De ambiente. Las de la casa: disponibles desde el principio.
  calma('calma', 'audio/bgm/calma.ogg', 'Adrià Bonnin Catalán', 'CC0',
      unlockedByDefault: true),
  aurora('aurora', 'audio/bgm/aurora.ogg', 'Adrià Bonnin Catalán', 'CC0',
      unlockedByDefault: true),
  brisa('brisa', 'audio/bgm/brisa.ogg', 'Adrià Bonnin Catalán', 'CC0',
      unlockedByDefault: true),
  noche('noche', 'audio/bgm/noche.ogg', 'Adrià Bonnin Catalán', 'CC0',
      unlockedByDefault: true);

  const MusicTrack(
    this.id,
    this.asset,
    this.author,
    this.license, {
    this.unlockedByDefault = false,
  });

  final String id;
  final String asset;
  final String author;
  final String license;

  /// Si ya esta en la lista de musica del menu sin haberla escuchado antes en
  /// ninguna app.
  final bool unlockedByDefault;

  static const MusicTrack fallback = MusicTrack.calma;

  static MusicTrack byId(String id) =>
      values.firstWhere((t) => t.id == id, orElse: () => fallback);
}

/// Reproductor unico del entorno.
///
/// Se accede por `AudioService.instance` porque lo usan controles que no
/// tienen `WidgetRef` a mano; el ajuste de volumen sigue viviendo en Riverpod
/// y escribe aqui.
///
/// Si el backend de audio del sistema no arranca, el servicio se queda mudo en
/// lugar de tirar la app: el sonido es la mitad de la experiencia, pero no es
/// motivo para no poder entrar.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  // --- Efectos ------------------------------------------------------------
  //
  // Los efectos van por SoLoud, un motor de audio de juegos que mezcla en el
  // propio proceso. Antes iban por audioplayers, que en Linux monta una
  // tuberia completa de GStreamer por voz: cada disparo tenia una latencia
  // distinta y reiniciar con seek dejaba pasar restos del buffer anterior, asi
  // que al repetir un sonido rapido se oia distinto y a trompicones.

  /// Voces simultaneas como mucho por efecto.
  ///
  /// Todos son monofonicos: cada disparo sustituye al anterior del mismo
  /// efecto. Medido grabando la salida real, dejar solaparse dos ticks hacia
  /// que cada golpe sonara entre 0,7 y 1,44 veces el volumen de uno aislado y
  /// con otra forma, porque la cola del anterior se sumaba o se cancelaba con
  /// el nuevo. Con una sola voz todos los golpes suenan igual.
  static const Map<Sfx, int> _maxVoices = {
    Sfx.tick: 1,
    Sfx.open: 1,
    Sfx.back: 1,
    Sfx.error: 1,
    Sfx.chime: 1,
  };

  /// Separacion minima entre dos disparos del mismo efecto. Por debajo de
  /// esto el oido ya no los separa y solo suman ruido.
  static const Map<Sfx, Duration> _minGap = {
    Sfx.tick: Duration(milliseconds: 45),
    Sfx.open: Duration(milliseconds: 90),
    Sfx.back: Duration(milliseconds: 90),
    Sfx.error: Duration(milliseconds: 150),
    Sfx.chime: Duration(milliseconds: 500),
  };

  /// Lo que tarda en desvanecerse la voz sustituida. Suficiente para que no
  /// haga clic y tan corto que no se oye debajo del golpe nuevo.
  static const Duration _voiceFade = Duration(milliseconds: 10);

  final Map<Sfx, AudioSource> _sfxSources = <Sfx, AudioSource>{};
  final Map<Sfx, List<SoundHandle>> _liveVoices = <Sfx, List<SoundHandle>>{};
  bool _sfxReady = false;

  AudioPlayer? _music;
  bool _ready = false;
  bool _muteAll = false;

  MusicTrack _track = MusicTrack.fallback;

  MusicTrack get track => _track;

  double _musicVolume = .55;
  double _effectsVolume = .8;

  /// Ultima vez que sono cada efecto, para no encadenar diez ticks por frame.
  final Map<Sfx, DateTime> _lastPlayed = <Sfx, DateTime>{};

  Future<void> init() async {
    if (_ready) return;
    await _initEffects();
    try {
      _music = AudioPlayer(playerId: 'ibasho_bgm');
      await _music!.setReleaseMode(ReleaseMode.loop);
      await _music!.setVolume(_musicVolume);
      _watchMusic(_music!);
      _ready = true;
    } catch (e) {
      debugPrint('Ibasho: el audio no ha podido arrancar, se sigue en mudo ($e)');
      _muteAll = true;
    }
  }

  // --- Musica ------------------------------------------------------------
  //
  // La musica no se controla mirando el estado del reproductor, sino por
  // intencion: `_musicWanted` y `_track` dicen como deberia estar, y cada
  // operacion reconcilia el reproductor con eso. Las operaciones van en fila.
  //
  // Antes, cambiar de pista hacia stop() y luego play() "solo si sonaba": si
  // se pulsaban dos pistas seguidas, la segunda encontraba el reproductor ya
  // parado por la primera, concluia que no sonaba nada y se quedaba en
  // silencio para siempre.

  bool _musicWanted = false;
  String? _loadedAsset;
  Future<void> _musicQueue = Future<void>.value();
  DateTime _lastAutoRestart = DateTime.fromMillisecondsSinceEpoch(0);
  bool _reconciling = false;

  Future<void> _serial(Future<void> Function() op) {
    final next = _musicQueue.then((_) => op());
    _musicQueue = next.catchError((Object e) {
      debugPrint('Ibasho: operacion de musica fallida ($e)');
    });
    return _musicQueue;
  }

  Future<void> _reconcileMusic() async {
    if (!_ready || _muteAll) return;
    final player = _music!;
    _reconciling = true;
    try {
      final shouldPlay = _musicWanted && _musicVolume > 0;
      if (!shouldPlay) {
        if (player.state == PlayerState.playing) await player.pause();
        return;
      }
      final wanted = _track.asset;
      if (_loadedAsset != wanted) {
        await player.stop();
        await player.setSource(AssetSource(wanted));
        _loadedAsset = wanted;
      }
      await player.setVolume(_musicVolume);
      if (player.state != PlayerState.playing) await player.resume();
    } catch (e) {
      // La proxima operacion vuelve a cargar la fuente desde cero.
      _loadedAsset = null;
      debugPrint('Ibasho: no se ha podido poner la musica ($e)');
    } finally {
      _reconciling = false;
    }
  }

  /// Si el reproductor se para sin que nadie lo haya pedido, se vuelve a poner
  /// en marcha. Como mucho una vez cada dos segundos, para no entrar en bucle
  /// si el sistema de audio falla de verdad.
  void _watchMusic(AudioPlayer player) {
    player.onPlayerStateChanged.listen((state) {
      if (_reconciling || !_musicWanted || _musicVolume <= 0) return;
      if (state != PlayerState.stopped && state != PlayerState.completed) return;
      final now = DateTime.now();
      if (now.difference(_lastAutoRestart) < const Duration(seconds: 2)) return;
      _lastAutoRestart = now;
      debugPrint('Ibasho: la musica se ha parado sola ($state), se reanuda');
      _loadedAsset = null;
      unawaited(_serial(_reconcileMusic));
    });
    player.onLog.listen(
      (message) => debugPrint('Ibasho: audioplayers: $message'),
      onError: (Object e) => debugPrint('Ibasho: audioplayers error: $e'),
    );
  }

  Future<void> _initEffects() async {
    try {
      final soloud = SoLoud.instance;
      await soloud.init();
      for (final sfx in Sfx.values) {
        _sfxSources[sfx] = await soloud.loadAsset('assets/${sfx.asset}');
        _liveVoices[sfx] = <SoundHandle>[];
      }
      soloud.setGlobalVolume(_effectsVolume);
      _sfxReady = true;
    } catch (e) {
      // Sin efectos no se cae nada: la musica va por otro camino.
      debugPrint('Ibasho: los efectos no han podido arrancar ($e)');
      _sfxReady = false;
    }
  }

  Future<void> startMusic() {
    _musicWanted = true;
    return _serial(_reconcileMusic);
  }

  Future<void> stopMusic() {
    _musicWanted = false;
    return _serial(() async {
      if (!_ready || _muteAll) return;
      try {
        await _music!.stop();
      } catch (_) {}
    });
  }

  /// Cambia la pista. Si la musica debe sonar, empieza la nueva al momento;
  /// pulsaciones seguidas acaban siempre en la ultima pista, sonando.
  Future<void> setTrack(String id) {
    _track = MusicTrack.byId(id);
    return _serial(_reconcileMusic);
  }

  /// Dispara un efecto. Es inmediato y nunca bloquea la interfaz.
  void play(Sfx sfx) {
    if (!_sfxReady || _effectsVolume <= 0) return;
    final now = DateTime.now();
    final last = _lastPlayed[sfx];
    if (last != null && now.difference(last) < _minGap[sfx]!) return;
    _lastPlayed[sfx] = now;

    try {
      final soloud = SoLoud.instance;
      final live = _liveVoices[sfx]!
        ..removeWhere((h) => !soloud.getIsValidVoiceHandle(h));

      // La voz anterior se desvanece en vez de cortarse en seco.
      while (live.length >= _maxVoices[sfx]!) {
        final oldest = live.removeAt(0);
        soloud.fadeVolume(oldest, 0, _voiceFade);
        soloud.scheduleStop(oldest, _voiceFade);
      }

      final handle = soloud.play(_sfxSources[sfx]!);
      live.add(handle);
    } catch (e) {
      debugPrint('Ibasho: efecto ${sfx.name} fallido ($e)');
    }
  }

  double get musicVolume => _musicVolume;

  double get effectsVolume => _effectsVolume;

  /// A volumen cero la musica se pausa, para no dejar un decodificador
  /// girando en vano; al subirlo vuelve a sonar donde estaba.
  Future<void> setMusicVolume(double v) {
    _musicVolume = v.clamp(0, 1);
    return _serial(_reconcileMusic);
  }

  Future<void> setEffectsVolume(double v) async {
    _effectsVolume = v.clamp(0, 1);
    if (!_sfxReady) return;
    try {
      SoLoud.instance.setGlobalVolume(_effectsVolume);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _music?.dispose();
    _music = null;
    if (_sfxReady) {
      SoLoud.instance.deinit();
      _sfxSources.clear();
      _liveVoices.clear();
      _sfxReady = false;
    }
    _ready = false;
  }
}
