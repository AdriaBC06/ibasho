// Ibasho — las canciones de Tamakoro de una cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../audio/audio_service.dart';
import '../backend/ibasho_backend.dart';
import '../backend/tama.dart';
import '../games/tamakoro/koro_song.dart';
import '../games/tamakoro/koro_synth.dart';
import 'session.dart';

/// Prefijo de `music/menuTrack` cuando la musica del menu es una cancion de
/// Tamakoro: `koro_{hueco}`.
const String koroTrackPrefix = 'koro_';

int? koroSlotOfTrack(String? id) => id != null && id.startsWith(koroTrackPrefix)
    ? int.tryParse(id.substring(koroTrackPrefix.length))
    : null;

@immutable
class KoroState {
  const KoroState({
    this.songs = const <int, KoroSong>{},
    this.slots = koroFreeSlots,
    this.loaded = false,
  });

  /// Las canciones guardadas, por hueco (0 a [slots] - 1).
  final Map<int, KoroSong> songs;

  /// Huecos que tiene la cuenta: 10 de serie, hasta 50 comprando.
  final int slots;

  final bool loaded;

  /// Numero para la proxima cancion: uno mas que la mas alta que haya.
  int get nextNumber =>
      songs.values.fold(0, (top, s) => s.number > top ? s.number : top) + 1;

  KoroState copyWith({Map<int, KoroSong>? songs, int? slots, bool? loaded}) => KoroState(
        songs: songs ?? this.songs,
        slots: slots ?? this.slots,
        loaded: loaded ?? this.loaded,
      );
}

/// `/users/{cuenta}/koro`: `{slots, songs: {hueco: cancion}}`. Solo la lee y
/// la escribe su dueña; los huecos de mas solo suben con un recibo del Yatai.
class KoroController extends StateNotifier<KoroState> {
  KoroController({required IbashoBackend backend, required SessionController session})
      : _backend = backend,
        _session = session,
        super(const KoroState()) {
    unawaited(_load());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  String get _path => '/users/${_session.state.accountId}/koro';

  Future<void> _load() async {
    if (_session.state.accountId.isEmpty) return;
    try {
      final raw = await _backend.read(_path, idToken: await _session.freshToken());
      final songs = <int, KoroSong>{};
      var slots = koroFreeSlots;
      if (raw is Map) {
        if (raw['slots'] is num) {
          slots = (raw['slots'] as num).toInt().clamp(koroFreeSlots, koroMaxSlots);
        }
        void take(Object? key, Object? value) {
          final slot = int.tryParse('$key');
          final song = KoroSong.fromJson(value);
          if (slot != null && song != null) songs[slot] = song;
        }

        final stored = raw['songs'];
        if (stored is Map) stored.forEach(take);
        if (stored is List) {
          for (var i = 0; i < stored.length; i++) {
            take(i, stored[i]);
          }
        }
      }
      if (mounted) state = KoroState(songs: songs, slots: slots, loaded: true);
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer las canciones ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  /// Guarda [song] en [slot]. Devuelve si ha llegado a la cuenta.
  Future<bool> save(int slot, KoroSong song) async {
    if (slot < 0 || slot >= state.slots) return false;
    state = state.copyWith(songs: {...state.songs, slot: song});
    try {
      await _backend.write('$_path/songs/$slot', song.toJson(),
          idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar la cancion ($e)');
      return false;
    }
  }

  Future<void> delete(int slot) async {
    state = state.copyWith(songs: {...state.songs}..remove(slot));
    try {
      await _backend.remove('$_path/songs/$slot', idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido borrar la cancion ($e)');
    }
  }

  /// Tras comprar un hueco en el Yatai (la escritura la hace la tienda).
  void boughtSlots(int slots) => state = state.copyWith(slots: slots);
}

/// Las voces del coro de [song]: la del Tama de cada asiento, o `null` si ya
/// no esta en la cuenta.
List<TamaVoice?> koroVoices(KoroSong song, List<Tama> tamas) => [
      for (final id in song.seats)
        tamas.where((t) => t.id == id).firstOrNull?.voice,
    ];

/// Donde se deja renderizada la cancion del menu, para que al arrancar suene
/// antes de que lleguen la red y los Tamas.
Future<File> koroMenuFile() async =>
    File('${(await getApplicationSupportDirectory()).path}/koro_menu.wav');

/// Al arrancar: si la musica del menu es una cancion de Tamakoro y ya se
/// renderizo otra vez, suena esa.
Future<void> restoreKoroMenuMusic(String musicTrack) async {
  if (koroSlotOfTrack(musicTrack) == null) return;
  try {
    final file = await koroMenuFile();
    if (await file.exists()) await AudioService.instance.setMenuFile(file.path);
  } catch (_) {}
}

/// Renderiza [song] como musica del menu y la pone. `null` vuelve a la pista
/// normal.
Future<void> applyKoroMenuMusic(KoroSong? song, List<Tama> tamas) async {
  if (song == null) {
    await AudioService.instance.setMenuFile(null);
    return;
  }
  try {
    final wav = await compute(_render, (song, koroVoices(song, tamas)));
    final file = await koroMenuFile();
    await file.writeAsBytes(wav, flush: true);
    await AudioService.instance.setMenuFile(file.path);
  } catch (e) {
    debugPrint('Ibasho: no se ha podido poner la cancion en el menu ($e)');
  }
}

Uint8List _render((KoroSong, List<TamaVoice?>) job) => renderKoroSong(job.$1, job.$2);
