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
  }) =>
      Preferences(
        musicVolume: musicVolume ?? this.musicVolume,
        effectsVolume: effectsVolume ?? this.effectsVolume,
        localeCode: localeCode ?? this.localeCode,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        lastUsername: lastUsername ?? this.lastUsername,
        credentialGenerations:
            credentialGenerations ?? this.credentialGenerations,
        accentHex: accentHex ?? this.accentHex,
        musicTrack: musicTrack ?? this.musicTrack,
        profileMusicMuted: profileMusicMuted ?? this.profileMusicMuted,
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
