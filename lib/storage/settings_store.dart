// Ibasho — preferencias locales, sin secretos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Lo que Ibasho recuerda de una sesion a otra y no es secreto.
@immutable
class Preferences {
  const Preferences({
    this.musicVolume = .55,
    this.effectsVolume = .8,
    this.localeCode = 'es',
    this.reducedMotion = false,
    this.lastUsername = '',
    this.credentialGenerations = const <String, int>{},
    this.accentHex = '',
    this.musicTrack = '',
    this.profileMusicMuted = false,
    this.hourFormat24 = true,
    this.gachaOpened = false,
    this.pinballOpened = false,
    this.pinballPlayed = false,
    this.pachinkoOpened = false,
    this.fullscreen = false,
    this.backdropId = '',
  });

  final double musicVolume;
  final double effectsVolume;

  /// `es` o `en`.
  final String localeCode;

  /// Preferencia del usuario. Se suma a la del sistema, no la sustituye.
  final bool reducedMotion;

  final String lastUsername;

  /// Ultima generacion de credencial que funciono para cada usuario en esta
  /// maquina. Es solo un atajo: sin esto el inicio de sesion tambien funciona,
  /// pero tarda algun viaje mas.
  final Map<String, int> credentialGenerations;

  /// Ultimo color de acento conocido (`#RRGGBB`). Se pinta desde el primer
  /// frame, antes de que el perfil llegue por red.
  final String accentHex;

  /// Pista de musica elegida en el canal de depuracion. Vacia: la de la casa.
  final String musicTrack;

  /// Silencia la musica de los perfiles ajenos: al abrirlos sigue sonando la
  /// de ambiente.
  final bool profileMusicMuted;

  /// Formato de reloj: `true` es 24 h, `false` es 12 h con AM/PM.
  final bool hourFormat24;

  /// El canal del gachapon ya se ha desenvuelto en esta maquina. El regalo es
  /// un gesto, no un dato de la cuenta: por eso se recuerda aqui y no en la
  /// base de datos.
  final bool gachaOpened;

  /// Lo mismo para el canal del pinball, que llega con la primera bola.
  final bool pinballOpened;

  /// Ya se ha jugado una bola en el pinball: es lo que trae el pachinko.
  final bool pinballPlayed;

  /// El canal del pachinko ya se ha desenvuelto.
  final bool pachinkoOpened;

  /// Solo en escritorio: la ventana estaba en pantalla completa al cerrar.
  final bool fullscreen;

  /// El fondo del menu de inicio que lleva puesto la cuenta en este
  /// aparato (el `id` de `Backdrop`, sin el prefijo `bg_`). Vacio es el
  /// aspecto de siempre, para quien no ha jugado al gacha.
  final String backdropId;

  Preferences copyWith({
    double? musicVolume,
    double? effectsVolume,
    String? localeCode,
    bool? reducedMotion,
    String? lastUsername,
    Map<String, int>? credentialGenerations,
    String? accentHex,
    String? musicTrack,
    bool? profileMusicMuted,
    bool? hourFormat24,
    bool? gachaOpened,
    bool? pinballOpened,
    bool? pinballPlayed,
    bool? pachinkoOpened,
    bool? fullscreen,
    String? backdropId,
  }) => Preferences(
    musicVolume: musicVolume ?? this.musicVolume,
    effectsVolume: effectsVolume ?? this.effectsVolume,
    localeCode: localeCode ?? this.localeCode,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    lastUsername: lastUsername ?? this.lastUsername,
    credentialGenerations: credentialGenerations ?? this.credentialGenerations,
    accentHex: accentHex ?? this.accentHex,
    musicTrack: musicTrack ?? this.musicTrack,
    profileMusicMuted: profileMusicMuted ?? this.profileMusicMuted,
    hourFormat24: hourFormat24 ?? this.hourFormat24,
    gachaOpened: gachaOpened ?? this.gachaOpened,
    pinballOpened: pinballOpened ?? this.pinballOpened,
    pinballPlayed: pinballPlayed ?? this.pinballPlayed,
    pachinkoOpened: pachinkoOpened ?? this.pachinkoOpened,
    fullscreen: fullscreen ?? this.fullscreen,
    backdropId: backdropId ?? this.backdropId,
  );

  Map<String, Object?> toJson() => {
    'musicVolume': musicVolume,
    'effectsVolume': effectsVolume,
    'localeCode': localeCode,
    'reducedMotion': reducedMotion,
    'lastUsername': lastUsername,
    'credentialGenerations': credentialGenerations,
    'accentHex': accentHex,
    'musicTrack': musicTrack,
    'profileMusicMuted': profileMusicMuted,
    'hourFormat24': hourFormat24,
    'gachaOpened': gachaOpened,
    'pinballOpened': pinballOpened,
    'pinballPlayed': pinballPlayed,
    'pachinkoOpened': pachinkoOpened,
    'fullscreen': fullscreen,
    'backdropId': backdropId,
  };

  static Preferences fromJson(Map<String, Object?> json) {
    final generations = json['credentialGenerations'];
    return Preferences(
      musicVolume: (json['musicVolume'] as num?)?.toDouble() ?? .55,
      effectsVolume: (json['effectsVolume'] as num?)?.toDouble() ?? .8,
      localeCode: (json['localeCode'] as String?) ?? 'es',
      reducedMotion: (json['reducedMotion'] as bool?) ?? false,
      lastUsername: (json['lastUsername'] as String?) ?? '',
      credentialGenerations: generations is Map
          ? generations.map((k, v) => MapEntry('$k', (v as num).toInt()))
          : const <String, int>{},
      accentHex: (json['accentHex'] as String?) ?? '',
      musicTrack: (json['musicTrack'] as String?) ?? '',
      profileMusicMuted: (json['profileMusicMuted'] as bool?) ?? false,
      hourFormat24: (json['hourFormat24'] as bool?) ?? true,
      gachaOpened: (json['gachaOpened'] as bool?) ?? false,
      pinballOpened: (json['pinballOpened'] as bool?) ?? false,
      pinballPlayed: (json['pinballPlayed'] as bool?) ?? false,
      pachinkoOpened: (json['pachinkoOpened'] as bool?) ?? false,
      fullscreen: (json['fullscreen'] as bool?) ?? false,
      backdropId: (json['backdropId'] as String?) ?? '',
    );
  }
}

/// Un archivo JSON en el directorio de datos de la aplicacion.
///
/// No se usa `shared_preferences` para no depender de otro plugin: esto es
/// medio kilobyte de estado y el mismo codigo sirve en las tres plataformas.
class SettingsStore {
  SettingsStore(this._file);

  final File _file;

  static Future<SettingsStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return SettingsStore(File('${dir.path}/preferences.json'));
  }

  Future<Preferences> load() async {
    try {
      if (!await _file.exists()) return const Preferences();
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, Object?>) return const Preferences();
      return Preferences.fromJson(decoded);
    } catch (e) {
      debugPrint('Ibasho: preferencias ilegibles ($e), se empieza de cero');
      return const Preferences();
    }
  }

  Future<void> save(Preferences preferences) async {
    try {
      await _file.writeAsString(jsonEncode(preferences.toJson()), flush: true);
    } catch (e) {
      debugPrint('Ibasho: no se han podido guardar las preferencias ($e)');
    }
  }
}
