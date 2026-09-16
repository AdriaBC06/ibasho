// Ibasho — musica de fondo y efectos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter/foundation.dart';

import '../backend/tama.dart';
import '../core/device.dart';
import 'android_audio.dart';
import 'tama_voice.dart';

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

  // --- Movil ------------------------------------------------------------
  //
  // En Android la app convive con otras: el foco de audio lo lleva el
  // servicio (no audioplayers), la musica calla si otra app se lo queda y baja
  // si alguien habla por encima. En segundo plano no suena nada y el motor de
  // efectos se apaga del todo.
  //
  // El modo silencio del telefono no se mira: musica, efectos y voces son
  // audio de medios, y el timbre en silencio calla el tono y las
  // notificaciones, no los medios. Mirarlo dejaba la app a medias —sonaba la
  // musica y no los toques— y sorprendia a quien lleva el movil en vibracion
  // todo el dia. Para callar Ibasho estan sus dos deslizadores y el volumen
  // de medios.

  AndroidAudio? _android;

  /// La app esta en segundo plano.
  bool _suspended = false;

  /// Otra app tiene el foco: la musica no suena.
  bool _focusLost = false;

  /// Otra app habla un momento por encima: la musica baja.
  bool _ducked = false;

  static const double _duckedVolume = .2;

  Future<void> init() async {
    if (_ready) return;
    if (Device.isAndroid) await _initAndroid();
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

  /// Pista de un perfil ajeno, que suena por encima de la de ambiente mientras
  /// ese perfil esta abierto.
  MusicTrack? _guest;

  /// Fundidos al cambiar de pista cuando algo ya sonaba: salida corta, entrada
  /// algo mas larga. Solo los usa la musica de perfil; el resto de cambios de
  /// pista siguen siendo inmediatos.
  static const Duration _fadeOut = Duration(milliseconds: 260);
  static const Duration _fadeIn = Duration(milliseconds: 900);
  bool _fadeNext = false;

  Future<void> _fade(AudioPlayer player, double from, double to, Duration duration) async {
    const steps = 18;
    for (var i = 1; i <= steps; i++) {
      await player.setVolume(from + (to - from) * i / steps);
      await Future<void>.delayed(duration ~/ steps);
    }
  }

  Future<void> _initAndroid() async {
    final android = _android = AndroidAudio();
    try {
      // El foco lo pide el servicio y no cada reproductor: asi sabe cuando
      // otra app se lo queda y puede decidir callar, bajar o volver.
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          audioFocus: AndroidAudioFocus.none,
          usageType: AndroidUsageType.game,
          contentType: AndroidContentType.music,
        ),
      ));
    } catch (e) {
      debugPrint('Ibasho: contexto de audio ($e)');
    }
    android.focusChanges.listen((change) {
      switch (change) {
        case AudioFocusChange.gain:
          _focusLost = false;
          _ducked = false;
        case AudioFocusChange.loss:
        case AudioFocusChange.lossTransient:
          _focusLost = true;
        case AudioFocusChange.duck:
          _ducked = true;
      }
      unawaited(_serial(_reconcileMusic));
    });
  }

  double get _effectiveMusicVolume => _ducked ? _musicVolume * _duckedVolume : _musicVolume;

  /// La app pasa a segundo plano: calla la musica, apaga el motor de efectos y
  /// suelta el foco. Solo en Android.
  Future<void> suspend() async {
    if (_suspended) return;
    _suspended = true;
    await _serial(_reconcileMusic);
    if (_sfxReady) {
      try {
        SoLoud.instance.deinit();
      } catch (_) {}
      _sfxSources.clear();
      _chirps.clear();
      _chirpVoice = null;
      for (final voices in _liveVoices.values) {
        voices.clear();
      }
      _sfxReady = false;
    }
    await _android?.abandonFocus();
  }

  /// Vuelve del segundo plano: se pide otra vez el foco (una perdida anterior
  /// se da por olvidada al volver a la app) y todo suena donde estaba.
  Future<void> resume() async {
    if (!_suspended) return;
    _suspended = false;
    _focusLost = false;
    _ducked = false;
    await _initEffects();
    await _serial(_reconcileMusic);
  }

  Future<void> _reconcileMusic() async {
    if (!_ready || _muteAll) return;
    final player = _music!;
    _reconciling = true;
    final fade = _fadeNext;
    _fadeNext = false;
    try {
      var shouldPlay = _musicWanted && _musicVolume > 0 && !_suspended && !_focusLost;
      if (shouldPlay && _android != null && !await _android!.requestFocus()) {
        shouldPlay = false;
      }
      if (!shouldPlay) {
        if (player.state == PlayerState.playing) await player.pause();
        if (_android != null && !_suspended && !_focusLost) await _android!.abandonFocus();
        return;
      }
      final wanted = (_guest ?? _track).asset;
      var fadeIn = false;
      if (_loadedAsset != wanted) {
        if (fade && player.state == PlayerState.playing) {
          await _fade(player, _effectiveMusicVolume, 0, _fadeOut);
        }
        await player.stop();
        await player.setSource(AssetSource(wanted));
        _loadedAsset = wanted;
        fadeIn = fade;
      }
      if (fadeIn) {
        await player.setVolume(0);
        await player.resume();
        await _fade(player, 0, _effectiveMusicVolume, _fadeIn);
        return;
      }
      await player.setVolume(_effectiveMusicVolume);
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
      if (_reconciling || !_musicWanted || _musicVolume <= 0 || _suspended || _focusLost) return;
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
      if (Device.isAndroid) {
        // En el movil el mezclador trabaja a la frecuencia nativa (48 kHz) y
        // con un periodo corto: con el de escritorio, 2048 muestras, un toque
        // se oye tarde. Si un aparato no admite esa combinacion, arranca con
        // la de serie antes que quedarse mudo.
        try {
          await soloud.init(sampleRate: 48000, bufferSize: _androidBufferSize);
        } catch (e) {
          debugPrint('Ibasho: el mezclador a 48 kHz no ha arrancado ($e), se prueba con el de serie');
          await soloud.init();
        }
      } else {
        await soloud.init();
      }
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

  /// Periodo del mezclador en Android, en muestras. Medido en el dispositivo
  /// de prueba (ver docs/ARCHITECTURE.md).
  static const int _androidBufferSize = 512;

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
  ///
  /// Elegir pista es pedir musica: en Android vuelve a pedir el foco aunque
  /// otra app se lo hubiera quedado.
  Future<void> setTrack(String id) {
    if (_track.id != id) _focusLost = false;
    _track = MusicTrack.byId(id);
    return _serial(_reconcileMusic);
  }

  /// Pone la pista de un perfil en lugar de la de ambiente, con un fundido
  /// corto.
  Future<void> playProfileTrack(MusicTrack track) {
    if (_guest == track) return _musicQueue;
    _guest = track;
    _fadeNext = true;
    return _serial(_reconcileMusic);
  }

  /// Vuelve a la musica de ambiente, con el mismo fundido.
  Future<void> endProfileTrack() {
    if (_guest == null) return _musicQueue;
    _guest = null;
    _fadeNext = true;
    return _serial(_reconcileMusic);
  }

  /// Pista de perfil que suena ahora, si hay.
  MusicTrack? get profileTrack => _guest;

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

  // --- Voces de Tama -------------------------------------------------------
  //
  // Los graznidos se sintetizan en `tama_voice.dart` y se cargan en SoLoud
  // desde memoria. Van por el mismo motor que los efectos, asi que obedecen al
  // volumen de efectos sin hacer nada mas: es el volumen global de SoLoud.

  /// Graznidos ya cargados, por clave. Se guardan unos pocos: cada Tama tiene
  /// cuatro frases y se repiten mucho.
  final Map<String, AudioSource> _chirps = <String, AudioSource>{};
  SoundHandle? _chirpVoice;
  DateTime _lastChirp = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _maxChirps = 16;

  /// Hace sonar un graznido. Devuelve los segundos que dura, o 0 si no suena
  /// (sin audio o con los efectos a cero).
  Future<double> chirp({
    required String name,
    required TamaVoice voice,
    ChirpKind kind = ChirpKind.hello,
  }) async {
    final pattern = chirpPattern(name, voice, kind);
    final seconds = chirpSeconds(pattern);
    if (!_sfxReady || _effectsVolume <= 0) return 0;
    final now = DateTime.now();
    if (now.difference(_lastChirp) < const Duration(milliseconds: 120)) return 0;
    _lastChirp = now;

    final key = '${voiceSeed(name)}-${voice.pitch}-${voice.tempo}-'
        '${voice.timbre.index}-${kind.index}';
    try {
      final soloud = SoLoud.instance;
      var source = _chirps.remove(key);
      if (source == null) {
        if (_chirps.length >= _maxChirps) {
          final oldest = _chirps.keys.first;
          await soloud.disposeSource(_chirps.remove(oldest)!);
        }
        source = await soloud.loadMem(
          'tama-$key.wav',
          synthesizeChirp(name: name, voice: voice, kind: kind),
        );
      }
      _chirps[key] = source;

      // Un Tama no habla encima de si mismo: la frase anterior se apaga.
      final previous = _chirpVoice;
      if (previous != null && soloud.getIsValidVoiceHandle(previous)) {
        soloud.fadeVolume(previous, 0, _voiceFade);
        soloud.scheduleStop(previous, _voiceFade);
      }
      _chirpVoice = soloud.play(source);
      return seconds;
    } catch (e) {
      debugPrint('Ibasho: graznido fallido ($e)');
      return 0;
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
      _chirps.clear();
      _liveVoices.clear();
      _sfxReady = false;
    }
    _ready = false;
  }
}
