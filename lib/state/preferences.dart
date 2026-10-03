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

  /// Mover el volumen quita el silencio: si se toca es para oirlo.
  Future<void> setMusicVolume(double value) async {
    final v = value.clamp(0.0, 1.0);
    await AudioService.instance.setMusicVolume(v);
    await _commit(state.copyWith(musicVolume: v, musicMuted: false));
  }

  Future<void> setEffectsVolume(double value) async {
    final v = value.clamp(0.0, 1.0);
    await AudioService.instance.setEffectsVolume(v);
    await _commit(state.copyWith(effectsVolume: v, effectsMuted: false));
  }

  /// Silencia o devuelve la musica sin perder su volumen. Si estaba a cero,
  /// al quitar el silencio vuelve al de serie: si no, el boton no haria nada.
  Future<void> toggleMusicMuted() async {
    final muted = !state.musicMuted && state.musicVolume > 0;
    final volume = !muted && state.musicVolume <= 0
        ? const Preferences().musicVolume
        : state.musicVolume;
    await AudioService.instance.setMusicVolume(muted ? 0 : volume);
    await _commit(state.copyWith(musicVolume: volume, musicMuted: muted));
  }

  /// Lo mismo para los efectos.
  Future<void> toggleEffectsMuted() async {
    final muted = !state.effectsMuted && state.effectsVolume > 0;
    final volume = !muted && state.effectsVolume <= 0
        ? const Preferences().effectsVolume
        : state.effectsVolume;
    await AudioService.instance.setEffectsVolume(muted ? 0 : volume);
    await _commit(state.copyWith(effectsVolume: volume, effectsMuted: muted));
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

  /// El canal de Tamakoro ya se ha desenvuelto.
  Future<void> openKoro() => state.koroOpened
      ? Future<void>.value()
      : _commit(state.copyWith(koroOpened: true));

  /// El canal de Odori ya se ha desenvuelto.
  Future<void> openOdori() => state.odoriOpened
      ? Future<void>.value()
      : _commit(state.copyWith(odoriOpened: true));

  /// El canal de Hatarakitama ya se ha desenvuelto.
  Future<void> openHataraki() => state.hatarakiOpened
      ? Future<void>.value()
      : _commit(state.copyWith(hatarakiOpened: true));

  /// El canal de Tama Kōen ya se ha desenvuelto.
  Future<void> openKoen() => state.koenOpened
      ? Future<void>.value()
      : _commit(state.copyWith(koenOpened: true));

  /// La ayuda de Hatarakitama ya ha salido sola.
  Future<void> seeHatarakiHelp() => state.hatarakiHelpSeen
      ? Future<void>.value()
      : _commit(state.copyWith(hatarakiHelpSeen: true));

  /// Elige la canción de Hatarakitama ('' = todas por turnos).
  Future<void> setHatarakiTrack(String id) => _commit(state.copyWith(hatarakiTrack: id));

  /// Vuelve a enseñar la ayuda de Hatarakitama (canal de depuración).
  Future<void> forgetHatarakiHelp() => _commit(state.copyWith(hatarakiHelpSeen: false));

  /// El canal secreto de Ohirune ya se ha desenvuelto.
  Future<void> openOhirune() => state.ohiruneOpened
      ? Future<void>.value()
      : _commit(state.copyWith(ohiruneOpened: true));

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

  /// El acento sigue al tema puesto (ver `Preferences.accentFollowsTheme`).
  Future<void> setAccentFollowsTheme(bool value) =>
      _commit(state.copyWith(accentFollowsTheme: value));

  /// El cristal de las pantallas del menu (ver `Preferences.glassLevel`).
  Future<void> setGlassLevel(double value) =>
      _commit(state.copyWith(glassLevel: value));

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
