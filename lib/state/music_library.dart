// Ibasho — musica del menu y canciones desbloqueadas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_service.dart';
import '../backend/ibasho_backend.dart';
import 'preferences.dart';
import 'session.dart';

@immutable
class MusicLibraryState {
  const MusicLibraryState({
    this.unlocked = const <String>{},
    this.menuTrack,
    this.loaded = false,
  });

  /// Canciones desbloqueadas al escucharlas en las apps. Las de serie no se
  /// guardan: estan siempre.
  final Set<String> unlocked;

  /// Pista elegida para el menu, tal como esta guardada en la cuenta.
  final String? menuTrack;

  final bool loaded;

  bool isUnlocked(MusicTrack track) =>
      track.unlockedByDefault || unlocked.contains(track.id);

  /// Lo que se puede elegir como musica del menu, en el orden de la casa.
  List<MusicTrack> get available =>
      MusicTrack.values.where(isUnlocked).toList(growable: false);

  /// Cuantas quedan por descubrir.
  int get pending => MusicTrack.values.length - available.length;

  MusicLibraryState copyWith({
    Set<String>? unlocked,
    String? menuTrack,
    bool? loaded,
  }) =>
      MusicLibraryState(
        unlocked: unlocked ?? this.unlocked,
        menuTrack: menuTrack ?? this.menuTrack,
        loaded: loaded ?? this.loaded,
      );
}

/// La biblioteca de musica de una cuenta.
///
/// Vive en `/users/{accountId}/music`, asi que las canciones desbloqueadas
/// siguen a la persona entre equipos. La pista elegida se copia ademas a las
/// preferencias locales, para que al arrancar suene antes de que llegue la red.
///
/// Las apps de los proximos checkpoints llamaran a [markHeard] la primera vez
/// que suene su cancion.
class MusicLibraryController extends StateNotifier<MusicLibraryState> {
  MusicLibraryController({
    required IbashoBackend backend,
    required SessionController session,
    required PreferencesController preferences,
  })  : _backend = backend,
        _session = session,
        _preferences = preferences,
        super(const MusicLibraryState()) {
    unawaited(_load());
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final PreferencesController _preferences;

  String get _path => '/users/${_session.state.accountId}/music';

  Future<void> _load() async {
    if (_session.state.accountId.isEmpty) return;
    try {
      final raw = await _backend.read(_path, idToken: await _session.freshToken());
      final unlocked = <String>{};
      String? menuTrack;
      if (raw is Map) {
        final stored = raw['unlocked'];
        if (stored is Map) {
          stored.forEach((id, value) {
            if (value == true) unlocked.add('$id');
          });
        }
        if (raw['menuTrack'] is String) menuTrack = raw['menuTrack'] as String;
      }
      if (!mounted) return;
      state = MusicLibraryState(unlocked: unlocked, menuTrack: menuTrack, loaded: true);

      // La eleccion de la cuenta manda sobre la cache local, siempre que siga
      // desbloqueada.
      final chosen = menuTrack == null ? null : MusicTrack.byId(menuTrack);
      if (chosen != null && chosen.id == menuTrack && state.isUnlocked(chosen)) {
        await _preferences.setMusicTrack(chosen.id);
      } else if (!state.isUnlocked(MusicTrack.byId(_preferences.state.musicTrack))) {
        await _preferences.setMusicTrack(MusicTrack.fallback.id);
      }
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer la musica de la cuenta ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  /// Elige la musica del menu. Solo acepta pistas desbloqueadas.
  Future<void> select(MusicTrack track) async {
    if (!state.isUnlocked(track)) return;
    state = state.copyWith(menuTrack: track.id);
    await _preferences.setMusicTrack(track.id);
    try {
      await _backend.write('$_path/menuTrack', track.id,
          idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar la musica del menu ($e)');
    }
  }

  /// Anade una cancion a la biblioteca la primera vez que se escucha.
  Future<void> markHeard(MusicTrack track) async {
    if (state.isUnlocked(track)) return;
    state = state.copyWith(unlocked: {...state.unlocked, track.id});
    try {
      await _backend.write('$_path/unlocked/${track.id}', true,
          idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido desbloquear ${track.id} ($e)');
    }
  }

  /// Solo para depuracion: vuelve a dejar unicamente las canciones de serie.
  Future<void> resetUnlocks() async {
    final current = MusicTrack.byId(state.menuTrack ?? MusicTrack.fallback.id);
    state = MusicLibraryState(loaded: true, menuTrack: state.menuTrack);
    try {
      await _backend.remove('$_path/unlocked', idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se han podido olvidar los desbloqueos ($e)');
    }
    if (!current.unlockedByDefault) await select(MusicTrack.fallback);
  }
}
