// Ibasho — preferencias en vivo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../audio/audio_service.dart';
import '../core/device.dart';
import '../storage/settings_store.dart';

/// Preferencias del usuario, aplicadas al instante y persistidas.
class PreferencesController extends StateNotifier<Preferences> {
  PreferencesController(this._store, Preferences initial) : super(initial);

  final SettingsStore _store;

  Future<void> _commit(Preferences next) async {
    state = next;
    await _store.save(next);
  }

  Future<void> setMusicVolume(double value) async {
    await AudioService.instance.setMusicVolume(value);
    await _commit(state.copyWith(musicVolume: value));
  }

  Future<void> setEffectsVolume(double value) async {
    await AudioService.instance.setEffectsVolume(value);
    await _commit(state.copyWith(effectsVolume: value));
  }

  Future<void> setLocale(String code) =>
      _commit(state.copyWith(localeCode: code));

  Future<void> setReducedMotion(bool value) =>
      _commit(state.copyWith(reducedMotion: value));

  /// El canal del gachapon ya se ha desenvuelto.
  Future<void> openGacha() => state.gachaOpened
      ? Future<void>.value()
      : _commit(state.copyWith(gachaOpened: true));

  /// El canal del pinball ya se ha desenvuelto.
  Future<void> openPinball() => state.pinballOpened
      ? Future<void>.value()
      : _commit(state.copyWith(pinballOpened: true));

  /// Se ha jugado la primera bola del pinball: llega el pachinko.
  Future<void> playedPinball() => state.pinballPlayed
      ? Future<void>.value()
      : _commit(state.copyWith(pinballPlayed: true));

  /// El canal del pachinko ya se ha desenvuelto.
  Future<void> openPachinko() => state.pachinkoOpened
      ? Future<void>.value()
      : _commit(state.copyWith(pachinkoOpened: true));

  Future<void> setHourFormat24(bool value) =>
      _commit(state.copyWith(hourFormat24: value));

  /// Solo en escritorio. Cambia la ventana de verdad y recuerda el estado
  /// para la proxima vez que se abra la app.
  Future<void> setFullscreen(bool value) async {
    if (Device.isDesktop) {
      await windowManager.setFullScreen(value);
    }
    await _commit(state.copyWith(fullscreen: value));
  }

  /// El fondo del menu de inicio puesto en este aparato. Vacio vuelve al
  /// aspecto de siempre.
  Future<void> setBackdrop(String id) =>
      _commit(state.copyWith(backdropId: id));

  Future<void> rememberAccent(String hex) async {
    if (hex == state.accentHex) return;
    await _commit(state.copyWith(accentHex: hex));
  }

  Future<void> setMusicTrack(String id) async {
    await AudioService.instance.setTrack(id);
    await _commit(state.copyWith(musicTrack: id));
  }

  Future<void> setProfileMusicMuted(bool value) =>
      _commit(state.copyWith(profileMusicMuted: value));

  Future<void> rememberUsername(String username) =>
      _commit(state.copyWith(lastUsername: username));

  Future<void> rememberCredential(String username, int generation) {
    final next = Map<String, int>.from(state.credentialGenerations)
      ..[username] = generation;
    return _commit(
      state.copyWith(lastUsername: username, credentialGenerations: next),
    );
  }
}
