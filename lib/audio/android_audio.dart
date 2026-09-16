// Ibasho — foco de audio en Android.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lo que el sistema dice del foco de audio.
enum AudioFocusChange {
  /// Vuelve a ser nuestro.
  gain,

  /// Otra app se lo ha quedado (Spotify, un video): la musica calla.
  loss,

  /// Una interrupcion corta (una llamada, una nota de voz): calla y vuelve.
  lossTransient,

  /// Otra app habla un momento por encima (navegacion): se baja el volumen.
  duck,
}

/// Puente con `MainActivity.kt`. Fuera de Android no se crea.
class AndroidAudio {
  AndroidAudio() {
    _subscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) => debugPrint('Ibasho: eventos del sistema ($e)'),
    );
  }

  static const MethodChannel _methods = MethodChannel('top.ibasho.app/system');
  static const EventChannel _events = EventChannel('top.ibasho.app/system/events');

  final StreamController<AudioFocusChange> _focus = StreamController<AudioFocusChange>.broadcast();
  StreamSubscription<Object?>? _subscription;

  /// Cambios del foco de audio.
  Stream<AudioFocusChange> get focusChanges => _focus.stream;

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final focus = event['focus'];
    if (focus is String) {
      final change = AudioFocusChange.values.where((c) => c.name == focus);
      if (change.isNotEmpty) _focus.add(change.first);
    }
  }

  /// Pide el foco para la musica. `false` si el sistema lo niega (por ejemplo,
  /// durante una llamada).
  Future<bool> requestFocus() async {
    try {
      return await _methods.invokeMethod<bool>('requestAudioFocus') ?? false;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido pedir el foco de audio ($e)');
      return true;
    }
  }

  Future<void> abandonFocus() async {
    try {
      await _methods.invokeMethod<void>('abandonAudioFocus');
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _focus.close();
  }
}
